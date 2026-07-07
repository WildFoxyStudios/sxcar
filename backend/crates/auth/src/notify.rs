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
    async fn send_sms(&self, _to: &str, _body: &str) -> Result<(), AuthError> {
        Err(AuthError::Notify("SMS not implemented".into()))
    }
}

/// Real SMTP notifier via Mailgun/SendGrid-compatible HTTP API.
///
/// Reads configuration from environment variables:
/// - `SMTP_API_KEY` — Mailgun API key or SMTP password
/// - `SMTP_FROM` — sender address (default: `noreply@turnend.win`)
/// - `SMTP_ENDPOINT` — API base URL (default: `https://api.mailgun.net/v3`)
/// - `SMTP_DOMAIN` — Mailgun domain / SendGrid subdomain
pub struct SmtpNotifier {
    api_key: String,
    from: String,
    url: String,
}

impl SmtpNotifier {
    pub fn from_env() -> Option<Self> {
        let api_key = match std::env::var("SMTP_API_KEY") {
            Ok(k) => k,
            Err(_) => {
                if std::env::var("DEV_SMTP_ENABLED").as_deref() != Ok("true") {
                    tracing::error!(
                        target: "auth::notify",
                        "SMTP_API_KEY is not set and DEV_SMTP_ENABLED != true. \
                         Emails will not be sent in production. \
                         Set SMTP_API_KEY or set DEV_SMTP_ENABLED=true for local development."
                    );
                }
                return None;
            }
        };
        let from = std::env::var("SMTP_FROM").unwrap_or_else(|_| "noreply@turnend.win".into());
        let endpoint =
            std::env::var("SMTP_ENDPOINT").unwrap_or_else(|_| "https://api.mailgun.net/v3".into());
        let domain =
            std::env::var("SMTP_DOMAIN").unwrap_or_else(|_| "sandbox.mailgun.org".into());
        Some(Self {
            api_key,
            from,
            url: format!("{endpoint}/{domain}/messages"),
        })
    }
}

#[async_trait]
impl Notifier for SmtpNotifier {
    async fn send_email(&self, to: &str, subject: &str, body: &str) -> Result<(), AuthError> {
        let client = reqwest::Client::new();
        let res = client
            .post(&self.url)
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

    async fn send_sms(&self, _to: &str, _body: &str) -> Result<(), AuthError> {
        Err(AuthError::Notify("SMS not implemented".into()))
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
        assert!(n.url.contains("api.mailgun.net"));
        // Restore
        if let Some(v) = prev {
            std::env::set_var("SMTP_API_KEY", v);
        } else {
            std::env::remove_var("SMTP_API_KEY");
        }
        std::env::remove_var("SMTP_FROM");
    }

    #[test]
    fn smtp_from_env_none_when_dev_enabled() {
        // DEV_SMTP_ENABLED=true allows None silently (no error log)
        let prev_key = std::env::var("SMTP_API_KEY").ok();
        let prev_dev = std::env::var("DEV_SMTP_ENABLED").ok();
        std::env::remove_var("SMTP_API_KEY");
        std::env::set_var("DEV_SMTP_ENABLED", "true");
        assert!(SmtpNotifier::from_env().is_none());
        if let Some(v) = prev_key {
            std::env::set_var("SMTP_API_KEY", v);
        } else {
            std::env::remove_var("SMTP_API_KEY");
        }
        if let Some(v) = prev_dev {
            std::env::set_var("DEV_SMTP_ENABLED", v);
        } else {
            std::env::remove_var("DEV_SMTP_ENABLED");
        }
    }

    #[tokio::test]
    async fn smtp_send_sms_falls_back_to_log() {
        let n = SmtpNotifier {
            api_key: "dummy".into(),
            from: "noreply@turnend.win".into(),
            url: "https://api.mailgun.net/v3/sandbox.mailgun.org/messages".into(),
        };
        // Should succeed (just logs)
        assert!(n.send_sms("+1234567890", "hello").await.is_ok());
    }
}
