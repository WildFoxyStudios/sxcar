use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Mutex;
use std::time::Instant;

/// Token bucket simple por clave (IP). Para F0.3 (single-node); Redis distribuido más adelante.
pub struct RateLimiter {
    capacity: f64,
    refill_per_sec: f64,
    buckets: Mutex<HashMap<IpAddr, (f64, Instant)>>,
}

impl RateLimiter {
    pub fn new(capacity: f64, refill_per_sec: f64) -> Self {
        Self {
            capacity,
            refill_per_sec,
            buckets: Mutex::new(HashMap::new()),
        }
    }

    /// Devuelve true si se permite la petición (consume 1 token).
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
        Some(ip) if !state.limiter.check(ip, Instant::now()) => Err(StatusCode::TOO_MANY_REQUESTS),
        _ => Ok(next.run(req).await), // sin ConnectInfo (p.ej. tests oneshot) → permitir
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bucket_blocks_after_capacity() {
        let rl = RateLimiter::new(3.0, 0.0); // sin refill
        let ip: IpAddr = "1.2.3.4".parse().unwrap();
        let now = Instant::now();
        assert!(rl.check(ip, now));
        assert!(rl.check(ip, now));
        assert!(rl.check(ip, now));
        assert!(!rl.check(ip, now)); // 4ª bloqueada
    }
}
