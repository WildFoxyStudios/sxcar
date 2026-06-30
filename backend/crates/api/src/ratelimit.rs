use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Mutex;
use std::time::Instant;

// ---------------------------------------------------------------------------
// InMemoryRateLimiter — token bucket, single-node only
// ---------------------------------------------------------------------------

/// Token bucket per IP. Used as fallback when Redis is not configured.
pub struct InMemoryRateLimiter {
    capacity: f64,
    refill_per_sec: f64,
    buckets: Mutex<HashMap<IpAddr, (f64, Instant)>>,
}

impl InMemoryRateLimiter {
    pub fn new(capacity: f64, refill_per_sec: f64) -> Self {
        Self {
            capacity,
            refill_per_sec,
            buckets: Mutex::new(HashMap::new()),
        }
    }

    /// Returns `true` if the request is allowed (consumes 1 token).
    pub fn check(&self, ip: IpAddr, now: Instant) -> bool {
        let mut map = self.buckets.lock().unwrap();
        let entry = map.entry(ip).or_insert((self.capacity, now));
        let elapsed = now.saturating_duration_since(entry.1).as_secs_f64();
        entry.0 = (entry.0 + elapsed * self.refill_per_sec).min(self.capacity);
        entry.1 = now;
        if entry.0 >= 1.0 {
            entry.0 -= 1.0;
            true
        } else {
            false
        }
    }
}

// ---------------------------------------------------------------------------
// RedisRateLimiter — sliding-window via Redis INCR/EXPIRE
// ---------------------------------------------------------------------------

/// Redis-backed rate limiter using a sliding-window counter.
///
/// Creates keys of the form `ratelimit:{key}:{window_secs}` and increments
/// them atomically via `INCR`. The first increment sets an `EXPIRE` so the
/// key auto-evicts after the window. This is eventually consistent (no
/// sliding-window precision guarantee) but is sufficient for global rate
/// limiting across multiple API server instances.
pub struct RedisRateLimiter {
    client: redis::Client,
}

impl RedisRateLimiter {
    /// Attempt to connect using the `REDIS_URL` environment variable.
    pub fn from_env() -> Option<Self> {
        let url = std::env::var("REDIS_URL").ok()?;
        let client = redis::Client::open(url).ok()?;
        Some(Self { client })
    }

    /// Create a new `RedisRateLimiter` from an already-opened client.
    pub fn new(client: redis::Client) -> Self {
        Self { client }
    }

    /// Check whether `key` has exceeded `max_requests` per `window_secs`.
    ///
    /// Returns `true` if the request is allowed. On Redis failure the check
    /// fails open (allows the request) so transient outages don't block traffic.
    pub async fn check(&self, key: &str, max_requests: u32, window_secs: u32) -> bool {
        let mut conn = match self.client.get_multiplexed_async_connection().await {
            Ok(c) => c,
            Err(e) => {
                tracing::warn!("RedisRateLimiter: connection failed: {e}");
                return true; // fail open
            }
        };

        let redis_key = format!("ratelimit:{}:{}", key, window_secs);

        let count: u32 = match redis::cmd("INCR").arg(&redis_key).query_async(&mut conn).await {
            Ok(c) => c,
            Err(e) => {
                tracing::warn!("RedisRateLimiter: INCR failed: {e}");
                return true; // fail open
            }
        };

        if count == 1 {
            let _: Result<i64, _> = redis::cmd("EXPIRE")
                .arg(&redis_key)
                .arg(window_secs)
                .query_async(&mut conn)
                .await;
        }

        count <= max_requests
    }
}

// ---------------------------------------------------------------------------
// Limiter — unified enum with automatic fallback
// ---------------------------------------------------------------------------

/// Combined rate limiter that uses Redis when available and falls back to an
/// in-memory token bucket for local development.
pub enum Limiter {
    Redis(RedisRateLimiter),
    InMemory(InMemoryRateLimiter),
}

impl Limiter {
    /// Create a limiter using `REDIS_URL` if set, otherwise an in-memory
    /// token bucket with the given capacity and refill rate.
    pub fn from_env_or(capacity: f64, refill_per_sec: f64) -> Self {
        match RedisRateLimiter::from_env() {
            Some(redis) => {
                tracing::info!("RateLimiter: using Redis backend");
                Limiter::Redis(redis)
            }
            None => {
                tracing::info!("RateLimiter: using in-memory backend (no REDIS_URL)");
                Limiter::InMemory(InMemoryRateLimiter::new(capacity, refill_per_sec))
            }
        }
    }

    /// Check whether the given IP is allowed through.
    ///
    /// For the Redis backend the check uses a 10-request / 1-second window.
    pub async fn check(&self, ip: IpAddr) -> bool {
        match self {
            Limiter::Redis(r) => r.check(&ip.to_string(), 10, 1).await,
            Limiter::InMemory(m) => m.check(ip, Instant::now()),
        }
    }
}

// ---------------------------------------------------------------------------
// Axum middleware
// ---------------------------------------------------------------------------

use axum::{
    extract::{ConnectInfo, State},
    http::StatusCode,
    middleware::Next,
    response::Response,
};
use std::net::SocketAddr;

use crate::AppState;

pub async fn auth_limiter(
    State(state): State<AppState>,
    req: axum::extract::Request,
    next: Next,
) -> Result<Response, StatusCode> {
    let ip = req
        .extensions()
        .get::<ConnectInfo<SocketAddr>>()
        .map(|ci| ci.0.ip());
    match ip {
        Some(ip) if !state.limiter.check(ip).await => Err(StatusCode::TOO_MANY_REQUESTS),
        _ => Ok(next.run(req).await),
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
#[cfg(test)]
mod tests {
    use super::*;

    // --- InMemoryRateLimiter ---

    #[test]
    fn in_memory_blocks_after_capacity() {
        let rl = InMemoryRateLimiter::new(3.0, 0.0);
        let ip: IpAddr = "1.2.3.4".parse().unwrap();
        let now = Instant::now();
        assert!(rl.check(ip, now));
        assert!(rl.check(ip, now));
        assert!(rl.check(ip, now));
        assert!(!rl.check(ip, now)); // 4th blocked
    }

    #[test]
    fn in_memory_allows_different_ips_independently() {
        let rl = InMemoryRateLimiter::new(2.0, 0.0);
        let ip_a: IpAddr = "10.0.0.1".parse().unwrap();
        let ip_b: IpAddr = "10.0.0.2".parse().unwrap();
        let now = Instant::now();
        assert!(rl.check(ip_a, now));
        assert!(rl.check(ip_b, now));
        assert!(rl.check(ip_a, now)); // 2nd for A
        assert!(!rl.check(ip_a, now)); // 3rd for A blocked
        assert!(rl.check(ip_b, now)); // B still has capacity
    }

    #[test]
    fn in_memory_refills_over_time() {
        let rl = InMemoryRateLimiter::new(1.0, 2.0); // 1 token, 2/sec refill
        let ip: IpAddr = "1.2.3.4".parse().unwrap();
        let start = Instant::now();
        assert!(rl.check(ip, start));
        assert!(!rl.check(ip, start)); // used up

        // After ~1 second, 2 tokens should have refilled, but capped at capacity (1)
        let later = start + std::time::Duration::from_secs(1);
        assert!(rl.check(ip, later));
    }

    // --- RedisRateLimiter (unit-level, no Redis required) ---

    #[test]
    fn redis_rate_limiter_from_env_returns_none_by_default() {
        // When REDIS_URL is not set, from_env returns None.
        // We can't unset env in parallel tests easily, so just verify the
        // function signature compiles and handles absence gracefully.
        std::env::remove_var("REDIS_URL");
        assert!(RedisRateLimiter::from_env().is_none());
    }

    // --- Limiter enum ---

    #[test]
    fn limiter_from_env_creates_in_memory_when_no_redis() {
        std::env::remove_var("REDIS_URL");
        let limiter = Limiter::from_env_or(5.0, 1.0);
        assert!(matches!(limiter, Limiter::InMemory(_)));
    }
}
