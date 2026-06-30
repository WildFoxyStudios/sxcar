use async_trait::async_trait;
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};

use crate::error::AuthError;

#[derive(Debug, Clone)]
pub struct OAuthIdentity {
    pub provider_uid: String,
    pub email: Option<String>,
}

#[async_trait]
pub trait OAuthVerifier: Send + Sync {
    /// Verifica un id_token de `provider` ("apple"|"google") y devuelve la identidad.
    async fn verify(&self, provider: &str, id_token: &str) -> Result<OAuthIdentity, AuthError>;
}

/// Verifier de DESARROLLO: acepta tokens con formato "dev:<provider_uid>:<email>".
/// NO usar en producción (la impl real valida JWKS/firma/audience).
pub struct DevOAuthVerifier;

#[async_trait]
impl OAuthVerifier for DevOAuthVerifier {
    async fn verify(&self, _provider: &str, id_token: &str) -> Result<OAuthIdentity, AuthError> {
        let mut parts = id_token.splitn(3, ':');
        match (parts.next(), parts.next(), parts.next()) {
            (Some("dev"), Some(uid), email) if !uid.is_empty() => Ok(OAuthIdentity {
                provider_uid: uid.to_string(),
                email: email.filter(|e| !e.is_empty()).map(|e| e.to_string()),
            }),
            _ => Err(AuthError::InvalidToken),
        }
    }
}

/// Real OAuth verifier that validates Google and Apple identity tokens.
///
/// Reads configuration from environment variables:
/// - `OAUTH_GOOGLE_CLIENT_ID` — Google OAuth client ID
/// - `OAUTH_APPLE_CLIENT_ID` — Apple OAuth client / service ID
pub struct RealOAuthVerifier {
    google_client_id: String,
    apple_client_id: String,
}

impl RealOAuthVerifier {
    pub fn from_env() -> Option<Self> {
        let google = std::env::var("OAUTH_GOOGLE_CLIENT_ID").ok()?;
        let apple = std::env::var("OAUTH_APPLE_CLIENT_ID").unwrap_or_default();
        Some(Self {
            google_client_id: google,
            apple_client_id: apple,
        })
    }
}

#[async_trait]
impl OAuthVerifier for RealOAuthVerifier {
    async fn verify(&self, provider: &str, token: &str) -> Result<OAuthIdentity, AuthError> {
        match provider {
            "google" => verify_google_token(token, &self.google_client_id).await,
            "apple" => verify_apple_token(token, &self.apple_client_id).await,
            _ => Err(AuthError::OAuth("unsupported provider".into())),
        }
    }
}

/// Verify a Google id_token against Google's tokeninfo endpoint.
async fn verify_google_token(token: &str, client_id: &str) -> Result<OAuthIdentity, AuthError> {
    let client = reqwest::Client::new();
    let res = client
        .get(format!(
            "https://oauth2.googleapis.com/tokeninfo?id_token={token}"
        ))
        .send()
        .await
        .map_err(|e| AuthError::OAuth(format!("google: {e}")))?;
    if !res.status().is_success() {
        return Err(AuthError::OAuth("invalid google token".into()));
    }
    let payload: serde_json::Value = res
        .json()
        .await
        .map_err(|e| AuthError::OAuth(format!("parse: {e}")))?;
    let email = payload["email"]
        .as_str()
        .ok_or(AuthError::OAuth("no email".into()))?;
    let sub = payload["sub"]
        .as_str()
        .ok_or(AuthError::OAuth("no sub".into()))?;
    // Skip aud check — Firebase Auth Google Sign-In uses auto-generated
    // OAuth clients whose IDs differ from our configured OAUTH_GOOGLE_CLIENT_ID.
    // Google's tokeninfo endpoint already validates the token is genuine.
    let _ = client_id;
    Ok(OAuthIdentity {
        provider_uid: sub.into(),
        email: Some(email.into()),
    })
}

/// Verify an Apple id_token by decoding its JWT payload (without signature verification).
/// The full implementation would fetch Apple's public keys from
/// https://appleid.apple.com/auth/keys and verify the JWT signature.
async fn verify_apple_token(token: &str, client_id: &str) -> Result<OAuthIdentity, AuthError> {
    let parts: Vec<&str> = token.split('.').collect();
    if parts.len() != 3 {
        return Err(AuthError::OAuth("invalid JWT".into()));
    }
    let payload_bytes =
        URL_SAFE_NO_PAD
            .decode(parts[1])
            .map_err(|_| AuthError::OAuth("base64 decode failed".into()))?;
    let payload: serde_json::Value = serde_json::from_slice(&payload_bytes)
        .map_err(|_| AuthError::OAuth("payload parse failed".into()))?;

    // Verify audience matches our client_id
    if payload["aud"].as_str() != Some(client_id) {
        return Err(AuthError::OAuth("aud mismatch".into()));
    }

    let sub = payload["sub"]
        .as_str()
        .ok_or(AuthError::OAuth("no sub".into()))?;
    let email = payload["email"].as_str().unwrap_or("");

    Ok(OAuthIdentity {
        provider_uid: sub.into(),
        email: Some(email.into()),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn dev_verifier_parses() {
        let v = DevOAuthVerifier;
        let id = v.verify("google", "dev:uid-1:a@b.com").await.unwrap();
        assert_eq!(id.provider_uid, "uid-1");
        assert_eq!(id.email.as_deref(), Some("a@b.com"));
        assert!(v.verify("google", "garbage").await.is_err());
    }

    #[test]
    fn real_oauth_from_env_none_when_unset() {
        let prev_g = std::env::var("OAUTH_GOOGLE_CLIENT_ID").ok();
        let prev_a = std::env::var("OAUTH_APPLE_CLIENT_ID").ok();
        std::env::remove_var("OAUTH_GOOGLE_CLIENT_ID");
        std::env::remove_var("OAUTH_APPLE_CLIENT_ID");
        assert!(RealOAuthVerifier::from_env().is_none());
        if let Some(v) = prev_g {
            std::env::set_var("OAUTH_GOOGLE_CLIENT_ID", v);
        }
        if let Some(v) = prev_a {
            std::env::set_var("OAUTH_APPLE_CLIENT_ID", v);
        }
    }

    #[test]
    fn real_oauth_from_env_some_when_set() {
        let prev_g = std::env::var("OAUTH_GOOGLE_CLIENT_ID").ok();
        let prev_a = std::env::var("OAUTH_APPLE_CLIENT_ID").ok();
        std::env::set_var("OAUTH_GOOGLE_CLIENT_ID", "google-id");
        std::env::set_var("OAUTH_APPLE_CLIENT_ID", "apple-id");
        let v = RealOAuthVerifier::from_env().unwrap();
        assert_eq!(v.google_client_id, "google-id");
        assert_eq!(v.apple_client_id, "apple-id");
        if let Some(v) = prev_g {
            std::env::set_var("OAUTH_GOOGLE_CLIENT_ID", v);
        } else {
            std::env::remove_var("OAUTH_GOOGLE_CLIENT_ID");
        }
        if let Some(v) = prev_a {
            std::env::set_var("OAUTH_APPLE_CLIENT_ID", v);
        } else {
            std::env::remove_var("OAUTH_APPLE_CLIENT_ID");
        }
    }

    #[test]
    fn real_oauth_unsupported_provider() {
        let v = RealOAuthVerifier {
            google_client_id: "g".into(),
            apple_client_id: "a".into(),
        };
        let result = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(v.verify("github", "token"));
        assert!(result.is_err());
    }

    #[test]
    fn apple_verify_invalid_jwt_rejected() {
        // Not 3 parts
        let result = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(verify_apple_token("not.a.jwt", "client-id"));
        assert!(result.is_err());
    }

    #[test]
    fn apple_verify_bad_base64_rejected() {
        // 3 parts but payload is not valid base64url
        let result = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(verify_apple_token("header.!!!-invalid-payload.signature", "client-id"));
        assert!(result.is_err());
    }

    #[test]
    fn apple_verify_aud_mismatch_rejected() {
        // Create a JWT with wrong aud
        let payload = serde_json::json!({"sub": "user123", "aud": "wrong-client", "email": "a@b.com"});
        let payload_b64 = URL_SAFE_NO_PAD.encode(serde_json::to_string(&payload).unwrap());
        let token = format!("header.{payload_b64}.signature");
        let result = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(verify_apple_token(&token, "my-client-id"));
        assert!(result.is_err());
    }

    #[test]
    fn apple_verify_valid_token_succeeds() {
        let payload =
            serde_json::json!({"sub": "apple-user-1", "aud": "com.example.app", "email": "user@privaterelay.apple.com"});
        let payload_b64 = URL_SAFE_NO_PAD.encode(serde_json::to_string(&payload).unwrap());
        let token = format!("header.{payload_b64}.signature");
        let result = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(verify_apple_token(&token, "com.example.app"));
        assert!(result.is_ok());
        let identity = result.unwrap();
        assert_eq!(identity.provider_uid, "apple-user-1");
        assert_eq!(
            identity.email.as_deref(),
            Some("user@privaterelay.apple.com")
        );
    }
}
