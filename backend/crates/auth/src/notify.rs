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

/// Real SMTP notifier via Mailgun/SendGrid-compatible HTTP API.
///
/// Reads configuration from environment variables:
/// - `SMTP_API_KEY` — Mailgun API key or SMTP password
/// - `SMTP_FROM` — sender address (default: `noreply@turnend.win`)
/// - `SMTP_ENDPOINT` — API endpoint URL (default: `https://api.mailgun.net/v3`)
pub struct SmtpNotifier {
    api_key: String,
    from: String,
    endpoint: String,
}

impl SmtpNotifier {
    pub fn from_env() -> Option<Self> {
        let api_key = std::env::var("SMTP_API_KEY").ok()?;
        let from = std::env::var("SMTP_FROM").unwrap_or_else(|_| "noreply@turnend.win".into());
        let endpoint =
            std::env::var("SMTP_ENDPOINT").unwrap_or_else(|_| "https://api.mailgun.net/v3".into());
        Some(Self {
            api_key,
            from,
            endpoint,
        })
    }
}

#[async_trait]
impl Notifier for SmtpNotifier {
    async fn send_email(&self, to: &str, subject: &str, body: &str) -> Result<(), AuthError> {
        let client = reqwest::Client::new();
        let res = client
            .post(format!("{}/messages", self.endpoint))
            .basic_auth("api", Some(&self.api_key))
            .form(&[
                ("from", self.from.as_str()),
                ("to", to),
                ("subject", subject),
                ("text", body),
            ])
            .send()
            .await
            .map_err(|e| AuthError::Notify(format!("send failed: {e}")))?;
        if res.status().is_success() {
            Ok(())
        } else {
            let status = res.status();
            let text = res.text().await.unwrap_or_default();
            Err(AuthError::Notify(format!("API error {status}: {text}")))
        }
    }

    async fn send_sms(&self, to: &str, body: &str) -> Result<(), AuthError> {
        tracing::info!(target: "auth::notify", to, body, "SMS not yet implemented via SMTP");
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn smtp_from_env_none_when_unset() {
        // No env vars set -> None
        let prev = std::env::var("SMTP_API_KEY").ok();
        std::env::remove_var("SMTP_API_KEY");
        assert!(SmtpNotifier::from_env().is_none());
        if let Some(v) = prev {
            std::env::set_var("SMTP_API_KEY", v);
        }
    }

    #[test]
    fn smtp_from_env_some_when_set() {
        let prev = std::env::var("SMTP_API_KEY").ok();
        std::env::set_var("SMTP_API_KEY", "test-key");
        std::env::set_var("SMTP_FROM", "test@example.com");
        let n = SmtpNotifier::from_env().unwrap();
        assert_eq!(n.api_key, "test-key");
        assert_eq!(n.from, "test@example.com");
        assert_eq!(n.endpoint, "https://api.mailgun.net/v3");
        // Restore
        if let Some(v) = prev {
            std::env::set_var("SMTP_API_KEY", v);
        } else {
            std::env::remove_var("SMTP_API_KEY");
        }
        std::env::remove_var("SMTP_FROM");
    }

    #[tokio::test]
    async fn smtp_send_sms_falls_back_to_log() {
        let n = SmtpNotifier {
            api_key: "dummy".into(),
            from: "noreply@turnend.win".into(),
            endpoint: "https://api.mailgun.net/v3".into(),
        };
        // Should succeed (just logs)
        assert!(n.send_sms("+1234567890", "hello").await.is_ok());
    }
}
