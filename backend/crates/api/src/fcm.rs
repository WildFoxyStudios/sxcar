//! Firebase Cloud Messaging (FCM) HTTP v1 API client.
//!
//! Uses a Firebase service account to obtain OAuth2 tokens and send push
//! notifications via `https://fcm.googleapis.com/v1/projects/{project_id}/messages:send`.
//!
//! # Configuration
//!
//! The service account credentials are loaded from one of:
//! - `FIREBASE_SERVICE_ACCOUNT_JSON` env var — the full JSON content as a string
//! - `firebase/foxy-85ecb-firebase-adminsdk-fbsvc-686e30c5f3.json` file relative to the project root
//!
//! If neither is set, `FcmClient::from_env()` returns `None` (push disabled).

use std::collections::HashMap;
use std::sync::Arc;

use jsonwebtoken::{encode, EncodingKey, Header};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::sync::Mutex;

use db::Pool;

/// Firebase Cloud Messaging client.
pub struct FcmClient {
    project_id: String,
    client_email: String,
    private_key: String,
    /// Cached access token with its expiry timestamp (unix seconds).
    token_cache: Arc<Mutex<Option<(String, i64)>>>,
}

#[derive(Serialize)]
struct JwtClaims {
    iss: String,
    scope: String,
    aud: String,
    exp: i64,
    iat: i64,
}

#[derive(Deserialize)]
struct TokenResponse {
    access_token: String,
    expires_in: i64,
}

impl FcmClient {
    /// Attempt to load Firebase credentials from the environment.
    ///
    /// Reads `FIREBASE_SERVICE_ACCOUNT_JSON` (preferred) or falls back to the
    /// well-known file path in the `firebase/` directory.
    pub fn from_env() -> Option<Self> {
        // Try env var first (full JSON content)
        let json_str = std::env::var("FIREBASE_SERVICE_ACCOUNT_JSON")
            .ok()
            .or_else(|| {
                // Fallback: try reading the file
                let path = std::env::var("FIREBASE_SERVICE_ACCOUNT")
                    .unwrap_or_else(|_| {
                        "firebase/foxy-85ecb-firebase-adminsdk-fbsvc-686e30c5f3.json".into()
                    });
                std::fs::read_to_string(&path).ok()
            })?;

        let v: Value = serde_json::from_str(&json_str).ok()?;
        let project_id = v["project_id"].as_str()?.to_string();
        let client_email = v["client_email"].as_str()?.to_string();
        let private_key = v["private_key"].as_str()?.to_string();

        Some(Self {
            project_id,
            client_email,
            private_key,
            token_cache: Arc::new(Mutex::new(None)),
        })
    }

    /// Get a valid OAuth2 access token, refreshing if expired.
    async fn get_access_token(&self) -> Result<String, String> {
        let mut cache = self.token_cache.lock().await;
        if let Some((token, expiry)) = cache.as_ref() {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs() as i64;
            // Use token if it has more than 60 seconds of life left
            if now < *expiry - 60 {
                return Ok(token.clone());
            }
        }

        let (token, expires_in) = self.fetch_new_token().await?;
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;

        *cache = Some((token.clone(), now + expires_in));
        Ok(token)
    }

    /// Exchange a signed JWT assertion for an OAuth2 access token.
    async fn fetch_new_token(&self) -> Result<(String, i64), String> {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;

        let claims = JwtClaims {
            iss: self.client_email.clone(),
            scope: "https://www.googleapis.com/auth/firebase.messaging".into(),
            aud: "https://oauth2.googleapis.com/token".into(),
            exp: now + 3600,
            iat: now,
        };

        // Sign the JWT with the private key (RS256)
        let assertion = encode(
            &Header::new(jsonwebtoken::Algorithm::RS256),
            &claims,
            &EncodingKey::from_rsa_pem(self.private_key.as_bytes())
                .map_err(|e| format!("invalid private key: {e}"))?,
        )
        .map_err(|e| format!("jwt encode: {e}"))?;

        let client = reqwest::Client::new();
        let res = client
            .post("https://oauth2.googleapis.com/token")
            .form(&[
                ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
                ("assertion", &assertion),
            ])
            .send()
            .await
            .map_err(|e| format!("token request failed: {e}"))?;

        if !res.status().is_success() {
            let status = res.status();
            let text = res.text().await.unwrap_or_default();
            return Err(format!("token API error {}: {}", status, text));
        }

        let tr: TokenResponse = res
            .json()
            .await
            .map_err(|e| format!("token parse: {e}"))?;

        Ok((tr.access_token, tr.expires_in))
    }

    /// Send a push notification to a single device token.
    pub async fn send(
        &self,
        device_token: &str,
        title: &str,
        body: &str,
        data: Option<HashMap<String, String>>,
    ) -> Result<(), String> {
        let access_token = self.get_access_token().await?;

        let mut message = serde_json::json!({
            "token": device_token,
            "notification": {
                "title": title,
                "body": body,
            },
        });

        if let Some(data_map) = data {
            message["data"] = serde_json::json!(data_map);
        }

        let payload = serde_json::json!({
            "message": message,
        });

        let url = format!(
            "https://fcm.googleapis.com/v1/projects/{}/messages:send",
            self.project_id
        );

        let client = reqwest::Client::new();
        let res = client
            .post(&url)
            .bearer_auth(&access_token)
            .json(&payload)
            .send()
            .await
            .map_err(|e| format!("fcm send failed: {e}"))?;

        let status = res.status();
        if !status.is_success() {
            let text = res.text().await.unwrap_or_default();
            // If 401/403, cached token may be invalid — clear it
            if status.as_u16() == 401 || status.as_u16() == 403 {
                let mut cache = self.token_cache.lock().await;
                *cache = None;
            }
            return Err(format!("FCM API error {}: {}", status, text));
        }

        Ok(())
    }

    /// Send a push notification to all devices registered for a user.
    ///
    /// Loads device tokens from the database and sends to each. Invalid tokens
    /// are logged but do not abort the batch.
    pub async fn send_to_user(
        &self,
        pool: &Pool,
        user_id: uuid::Uuid,
        title: &str,
        body: &str,
    ) -> Result<(), String> {
        let devices = db::notifications::list_user_devices(pool, user_id)
            .await
            .map_err(|e| format!("loading devices: {e}"))?;

        if devices.is_empty() {
            tracing::info!(%user_id, "no devices registered for push");
            return Ok(());
        }

        for device in &devices {
            let token = match &device.push_token {
                Some(t) if !t.is_empty() => t.clone(),
                _ => continue,
            };

            match self.send(&token, title, body, None).await {
                Ok(_) => {
                    // Update last_seen_at for successful sends
                    let _ = sqlx::query!(
                        "UPDATE devices SET last_seen_at = now() WHERE id = $1",
                        device.id
                    )
                    .execute(pool)
                    .await;
                }
                Err(e) => {
                    tracing::warn!(device_id = %device.id, error = %e, "push send failed");
                    // If FCM returns 404/Unregistered, remove the device token
                    if e.contains("NOT_FOUND") || e.contains("UNREGISTERED") {
                        let _ = sqlx::query!("DELETE FROM devices WHERE id = $1", device.id)
                            .execute(pool)
                            .await;
                        tracing::info!(device_id = %device.id, "removed unregistered device");
                    }
                }
            }
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn from_env_none_when_unset() {
        let prev = std::env::var("FIREBASE_SERVICE_ACCOUNT_JSON").ok();
        let prev_file = std::env::var("FIREBASE_SERVICE_ACCOUNT").ok();
        std::env::remove_var("FIREBASE_SERVICE_ACCOUNT_JSON");
        std::env::remove_var("FIREBASE_SERVICE_ACCOUNT");
        assert!(FcmClient::from_env().is_none());
        if let Some(v) = prev {
            std::env::set_var("FIREBASE_SERVICE_ACCOUNT_JSON", v);
        }
        if let Some(v) = prev_file {
            std::env::set_var("FIREBASE_SERVICE_ACCOUNT", v);
        }
    }

    #[test]
    fn from_env_parses_json() {
        let prev = std::env::var("FIREBASE_SERVICE_ACCOUNT_JSON").ok();
        let json = r#"{
            "project_id": "test-project",
            "client_email": "test@test.iam.gserviceaccount.com",
            "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCX\n-----END PRIVATE KEY-----\n"
        }"#;
        std::env::set_var("FIREBASE_SERVICE_ACCOUNT_JSON", json);
        let client = FcmClient::from_env().unwrap();
        assert_eq!(client.project_id, "test-project");
        assert_eq!(
            client.client_email,
            "test@test.iam.gserviceaccount.com"
        );
        assert!(client.private_key.contains("BEGIN PRIVATE KEY"));
        if let Some(v) = prev {
            std::env::set_var("FIREBASE_SERVICE_ACCOUNT_JSON", v);
        } else {
            std::env::remove_var("FIREBASE_SERVICE_ACCOUNT_JSON");
        }
    }

    #[test]
    fn from_env_invalid_json_returns_none() {
        let prev = std::env::var("FIREBASE_SERVICE_ACCOUNT_JSON").ok();
        std::env::set_var("FIREBASE_SERVICE_ACCOUNT_JSON", "not-json");
        assert!(FcmClient::from_env().is_none());
        if let Some(v) = prev {
            std::env::set_var("FIREBASE_SERVICE_ACCOUNT_JSON", v);
        } else {
            std::env::remove_var("FIREBASE_SERVICE_ACCOUNT_JSON");
        }
    }

    #[test]
    fn send_without_token_returns_error() {
        // A send attempt without a valid token should fail with an FCM API error
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            let client = FcmClient {
                project_id: "test-project".into(),
                client_email: "test@test.com".into(),
                private_key: "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCX\n-----END PRIVATE KEY-----\n".into(),
                token_cache: Arc::new(Mutex::new(None)),
            };
            let result = client
                .send("fake-device-token", "title", "body", None)
                .await;
            // Will fail because we can't get a valid access token with a bogus key
            assert!(result.is_err());
        });
    }
}
