//! Chat message broker — Redis Pub/Sub or in-memory broadcast.
//!
//! When `REDIS_URL` is set, messages are published to a Redis channel so that
//! multiple API server instances can share real-time chat.  Otherwise falls
//! back to a `tokio::sync::broadcast` channel suitable for single-node dev.

use std::pin::Pin;
use std::sync::Arc;

use futures_util::stream::StreamExt;
use futures_util::Stream;
use tokio::sync::broadcast;

// ---------------------------------------------------------------------------
// RedisChatBroker
// ---------------------------------------------------------------------------

/// Broadcasts and subscribes to chat messages through Redis Pub/Sub.
#[derive(Clone)]
pub struct RedisChatBroker {
    client: redis::Client,
}

impl RedisChatBroker {
    /// Try to create a broker using `REDIS_URL`.
    pub fn from_env() -> Option<Self> {
        let url = std::env::var("REDIS_URL").ok()?;
        let client = redis::Client::open(url).ok()?;
        Some(Self { client })
    }

    /// Publish a message to a Redis channel.
    pub async fn publish(&self, channel: &str, message: &str) {
        if let Ok(mut conn) = self.client.get_multiplexed_async_connection().await {
            let _: Result<i64, _> = redis::cmd("PUBLISH")
                .arg(channel)
                .arg(message)
                .query_async(&mut conn)
                .await;
        }
    }

    /// Subscribe to a Redis channel and return a stream of messages.
    pub async fn subscribe(
        &self,
        channel: &str,
    ) -> Result<Pin<Box<dyn Stream<Item = String> + Send>>, String> {
        let mut pubsub = self
            .client
            .get_async_pubsub()
            .await
            .map_err(|e| format!("Redis PubSub connect: {e}"))?;
        pubsub
            .subscribe(channel)
            .await
            .map_err(|e| format!("Redis subscribe: {e}"))?;

        // Bridge via mpsc to own the pubsub handle
        let (tx, mut rx) = tokio::sync::mpsc::channel::<String>(256);
        tokio::spawn(async move {
            let mut stream = pubsub.on_message();
            loop {
                match stream.next().await {
                    Some(msg) => {
                        let payload: String = msg.get_payload().unwrap_or_default();
                        if tx.send(payload).await.is_err() {
                            break;
                        }
                    }
                    None => break,
                }
            }
        });

        let stream = futures_util::stream::poll_fn(move |cx| rx.poll_recv(cx));
        Ok(Box::pin(stream))
    }
}

// ---------------------------------------------------------------------------
// ChatBroker — unified enum
// ---------------------------------------------------------------------------

/// Combined chat broker that uses Redis when available and falls back to an
/// in-memory broadcast channel for local development.
#[derive(Clone)]
pub enum ChatBroker {
    Redis(Arc<RedisChatBroker>),
    InMemory(Arc<broadcast::Sender<String>>),
}

impl ChatBroker {
    /// Create a broker by probing `REDIS_URL`; if unset fall back to a
    /// broadcast channel with the given capacity.
    pub fn from_env_or(capacity: usize) -> Self {
        match RedisChatBroker::from_env() {
            Some(redis) => {
                tracing::info!("ChatBroker: using Redis Pub/Sub backend");
                ChatBroker::Redis(Arc::new(redis))
            }
            None => {
                tracing::info!(
                    "ChatBroker: using in-memory broadcast backend (no REDIS_URL)"
                );
                let (tx, _) = broadcast::channel(capacity);
                ChatBroker::InMemory(Arc::new(tx))
            }
        }
    }

    /// Publish a message to all subscribers.
    pub fn publish(&self, channel: &str, message: &str) {
        match self {
            ChatBroker::Redis(broker) => {
                let broker = Arc::clone(broker);
                let ch = channel.to_owned();
                let msg = message.to_owned();
                tokio::spawn(async move {
                    broker.publish(&ch, &msg).await;
                });
            }
            ChatBroker::InMemory(tx) => {
                let _ = tx.send(message.to_owned());
            }
        }
    }

    /// Subscribe and return a boxed stream of messages.
    pub async fn subscribe(
        &self,
    ) -> Pin<Box<dyn Stream<Item = String> + Send>> {
        match self {
            ChatBroker::Redis(broker) => match broker.subscribe("chat").await {
                Ok(stream) => stream,
                Err(e) => {
                    tracing::error!("ChatBroker: Redis subscribe failed: {e}");
                    Box::pin(futures_util::stream::empty())
                }
            },
            ChatBroker::InMemory(tx) => {
                let rx = tx.subscribe();
                let stream = futures_util::stream::unfold(rx, |mut rx| async {
                    match rx.recv().await {
                        Ok(msg) => Some((msg, rx)),
                        Err(broadcast::error::RecvError::Closed) => None,
                        Err(broadcast::error::RecvError::Lagged(n)) => {
                            tracing::warn!("ChatBroker: receiver lagged by {n} messages");
                            Some((String::new(), rx))
                        }
                    }
                })
                .filter(|msg| {
                    let not_empty = !msg.is_empty();
                    async move { not_empty }
                });
                Box::pin(stream)
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redis_chat_broker_from_env_returns_none_by_default() {
        std::env::remove_var("REDIS_URL");
        assert!(RedisChatBroker::from_env().is_none());
    }

    #[test]
    fn chat_broker_from_env_creates_in_memory_when_no_redis() {
        std::env::remove_var("REDIS_URL");
        let broker = ChatBroker::from_env_or(64);
        assert!(matches!(broker, ChatBroker::InMemory(_)));
    }

    #[tokio::test]
    async fn in_memory_publish_and_subscribe_roundtrip() {
        let broker = ChatBroker::from_env_or(16);
        let mut stream = broker.subscribe().await;

        broker.publish("chat", "hello");
        broker.publish("chat", "world");

        // Give the broadcast channel a moment
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;

        use futures_util::StreamExt;
        let first = stream.next().await;
        let second = stream.next().await;

        assert_eq!(first.as_deref(), Some("hello"));
        assert_eq!(second.as_deref(), Some("world"));
    }
}
