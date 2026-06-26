use async_trait::async_trait;

use crate::error::AuthError;

#[async_trait]
pub trait Notifier: Send + Sync {
    async fn send_email(&self, to: &str, subject: &str, body: &str) -> Result<(), AuthError>;
    async fn send_sms(&self, to: &str, body: &str) -> Result<(), AuthError>;
}

/// Notifier de DESARROLLO: registra el mensaje en el log (no envía nada real).
pub struct DevNotifier;

#[async_trait]
impl Notifier for DevNotifier {
    async fn send_email(&self, to: &str, subject: &str, body: &str) -> Result<(), AuthError> {
        tracing::info!(target: "auth::notify", to, subject, body, "DEV email");
        Ok(())
    }
    async fn send_sms(&self, to: &str, body: &str) -> Result<(), AuthError> {
        tracing::info!(target: "auth::notify", to, body, "DEV sms");
        Ok(())
    }
}
