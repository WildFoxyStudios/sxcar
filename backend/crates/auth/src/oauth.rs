use async_trait::async_trait;
use jsonwebtoken::{decode, decode_header, Algorithm, DecodingKey, Validation};

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

/// Enum wrapper that selects the appropriate OAuth verifier based on environment config.
///
/// - `Real` — production Google/Apple token verification (requires `OAUTH_GOOGLE_CLIENT_ID`)
/// - `Dev` — development-only forged token verifier (requires `DEV_OAUTH_ENABLED=true`)
pub enum OAuthVerifierChoice {
    Real(RealOAuthVerifier),
    Dev(DevOAuthVerifier),
}

impl OAuthVerifierChoice {
    /// Construct the appropriate verifier from environment variables.
    ///
    /// Returns `None` and logs an error when neither `OAUTH_GOOGLE_CLIENT_ID` nor
    /// `DEV_OAUTH_ENABLED=true` is set. This prevents silent fallback to the dev
    /// verifier in production.
    pub fn from_env() -> Option<Self> {
        let google_client_id = std::env::var("OAUTH_GOOGLE_CLIENT_ID").ok();
        match google_client_id {
            Some(id) => {
                let apple = std::env::var("OAUTH_APPLE_CLIENT_ID").unwrap_or_default();
                Some(Self::Real(RealOAuthVerifier {
                    google_client_id: id,
                    apple_client_id: apple,
                }))
            }
            None => {
                // Only allow DevOAuthVerifier when explicitly opted in.
                if std::env::var("DEV_OAUTH_ENABLED").map_or(false, |v| v == "true") {
                    tracing::warn!(
                        "DEV MODE: OAuth accepts forged dev:<uid>:<email> tokens. \
                         DO NOT USE IN PRODUCTION."
                    );
                    Some(Self::Dev(DevOAuthVerifier))
                } else {
                    tracing::error!(
                        "OAUTH_GOOGLE_CLIENT_ID is not set and DEV_OAUTH_ENABLED \
                         is not 'true'. Refusing to start with no OAuth verifier."
                    );
                    None
                }
            }
        }
    }
}

#[async_trait]
impl OAuthVerifier for OAuthVerifierChoice {
    async fn verify(&self, provider: &str, id_token: &str) -> Result<OAuthIdentity, AuthError> {
        match self {
            Self::Real(r) => r.verify(provider, id_token).await,
            Self::Dev(d) => d.verify(provider, id_token).await,
        }
    }
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
    // P0-2: valida el `aud` del token contra el/los client_id configurados.
    // tokeninfo confirma que el token es genuino de Google, pero SIN comprobar
    // `aud` cualquier id_token de Google (emitido para OTRA app) sería aceptado.
    // `client_id` puede contener una allow-list separada por comas para soportar
    // los OAuth clients auto-generados de Firebase (Android/iOS/web).
    let aud = payload["aud"]
        .as_str()
        .ok_or(AuthError::OAuth("no aud".into()))?;
    let allowed = client_id
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty());
    if !allowed.clone().any(|c| c == aud) {
        return Err(AuthError::OAuth("aud mismatch".into()));
    }
    Ok(OAuthIdentity {
        provider_uid: sub.into(),
        email: Some(email.into()),
    })
}

/// Verify an Apple id_token by fetching Apple's public JWKS and validating the
/// RSA-256 signature on the JWT.
async fn verify_apple_token(token: &str, client_id: &str) -> Result<OAuthIdentity, AuthError> {
    let jwks: serde_json::Value = reqwest::get("https://appleid.apple.com/auth/keys")
        .await
        .map_err(|e| AuthError::OAuth(format!("jwks fetch: {e}")))?
        .json()
        .await
        .map_err(|e| AuthError::OAuth(format!("jwks parse: {e}")))?;

    verify_apple_token_with_jwks(token, client_id, &jwks)
}

/// Verify an Apple id_token using a pre-fetched JWKS value (factored out for
/// testability).
fn verify_apple_token_with_jwks(
    token: &str,
    client_id: &str,
    jwks: &serde_json::Value,
) -> Result<OAuthIdentity, AuthError> {
    let header = decode_header(token).map_err(|e| AuthError::OAuth(format!("jwt header: {e}")))?;
    let kid = header
        .kid
        .ok_or_else(|| AuthError::OAuth("no kid in header".into()))?;

    let keys = jwks["keys"]
        .as_array()
        .ok_or_else(|| AuthError::OAuth("jwks has no keys array".into()))?;
    let key = keys
        .iter()
        .find(|k| k["kid"].as_str() == Some(kid.as_str()))
        .ok_or_else(|| AuthError::OAuth(format!("key not found for kid {kid}")))?;

    let n = key["n"]
        .as_str()
        .ok_or_else(|| AuthError::OAuth("key missing n".into()))?;
    let e = key["e"]
        .as_str()
        .ok_or_else(|| AuthError::OAuth("key missing e".into()))?;

    let decoding_key =
        DecodingKey::from_rsa_components(n, e).map_err(|e| AuthError::OAuth(format!("decoding key: {e}")))?;

    let mut validation = Validation::new(Algorithm::RS256);
    validation.set_audience(&[client_id]);

    let token_data = decode::<serde_json::Value>(token, &decoding_key, &validation)
        .map_err(|e| AuthError::OAuth(format!("apple jwt verify: {e}")))?;

    let claims = token_data.claims;
    let sub = claims["sub"]
        .as_str()
        .ok_or_else(|| AuthError::OAuth("no sub in claims".into()))?;
    let email = claims["email"].as_str().unwrap_or("");

    Ok(OAuthIdentity {
        provider_uid: sub.into(),
        email: Some(email.into()),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};

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

    // ------------------------------------------------------------------
    // Apple JWT signature verification (verify_apple_token_with_jwks)
    // ------------------------------------------------------------------

    /// A valid-looking modulus (base64url-encoded) for test JWKs.
    /// These bytes decode to a large integer > 1 so `RsaPublicKey::new` won't
    /// reject them. Combined with the standard exponent 65537 ("AQAB") this
    /// forms a syntactically-valid RSA public key that will pass
    /// `DecodingKey::from_rsa_components` but cause any real JWT signature
    /// check to fail (since no corresponding private key exists).
    static TEST_MODULUS: &str = "nzXmY7q8w9e0r1t2y3u4i5o6p7a8s9d0f1g2h3j4k5l6z7x8c9v0b1n2m3";

    /// A syntactically-valid header for an RS256 JWT with a known kid.
    fn make_rs256_header_b64(kid: &str) -> String {
        let header_json = serde_json::json!({"alg": "RS256", "kid": kid});
        URL_SAFE_NO_PAD.encode(serde_json::to_string(&header_json).unwrap())
    }

    fn make_jwks_with_key(kid: &str) -> serde_json::Value {
        serde_json::json!({
            "keys": [{
                "kty": "RSA",
                "kid": kid,
                "use": "sig",
                "alg": "RS256",
                "n": TEST_MODULUS,
                "e": "AQAB"
            }]
        })
    }

    #[test]
    fn apple_verify_rejects_malformed_jwt() {
        // 2 parts — decode_header should fail
        let jwks = make_jwks_with_key("k1");
        let result = verify_apple_token_with_jwks("not.a.jwt", "client-id", &jwks);
        assert!(result.is_err());
    }

    #[test]
    fn apple_verify_rejects_unsigned_token() {
        let jwks = make_jwks_with_key("test-key");
        let header_b64 = make_rs256_header_b64("test-key");
        let payload = serde_json::json!({
            "sub": "user123",
            "aud": "com.example.app",
            "email": "user@privaterelay.apple.com"
        });
        let payload_b64 = URL_SAFE_NO_PAD.encode(serde_json::to_string(&payload).unwrap());
        let token = format!("{header_b64}.{payload_b64}.forgedsignature");

        let result = verify_apple_token_with_jwks(&token, "com.example.app", &jwks);
        assert!(
            result.is_err(),
            "unsigned/forged token must be rejected by RSA signature verification"
        );
    }

    #[test]
    fn apple_verify_rejects_missing_kid() {
        // Token header without kid
        let header_b64 = URL_SAFE_NO_PAD.encode(br#"{"alg":"RS256"}"#);
        let payload = serde_json::json!({"sub": "u1", "aud": "app"});
        let payload_b64 = URL_SAFE_NO_PAD.encode(serde_json::to_string(&payload).unwrap());
        let token = format!("{header_b64}.{payload_b64}.sig");

        let jwks = make_jwks_with_key("any-key");
        let result = verify_apple_token_with_jwks(&token, "app", &jwks);
        assert!(result.is_err(), "token without kid must be rejected");
    }

    #[test]
    fn apple_verify_rejects_unknown_kid() {
        let header_b64 = make_rs256_header_b64("unknown-kid");
        let payload = serde_json::json!({"sub": "u1", "aud": "app"});
        let payload_b64 = URL_SAFE_NO_PAD.encode(serde_json::to_string(&payload).unwrap());
        let token = format!("{header_b64}.{payload_b64}.sig");

        let jwks = make_jwks_with_key("known-key");
        let result = verify_apple_token_with_jwks(&token, "app", &jwks);
        assert!(result.is_err(), "token with non-matching kid must be rejected");
    }

    #[test]
    fn apple_verify_rejects_empty_jwks() {
        let header_b64 = make_rs256_header_b64("k1");
        let payload = serde_json::json!({"sub": "u1", "aud": "app"});
        let payload_b64 = URL_SAFE_NO_PAD.encode(serde_json::to_string(&payload).unwrap());
        let token = format!("{header_b64}.{payload_b64}.sig");

        let jwks = serde_json::json!({"keys": []});
        let result = verify_apple_token_with_jwks(&token, "app", &jwks);
        assert!(result.is_err(), "empty JWKS keys must be rejected");
    }

    #[test]
    fn apple_verify_rejects_missing_keys_field() {
        let header_b64 = make_rs256_header_b64("k1");
        let payload = serde_json::json!({"sub": "u1", "aud": "app"});
        let payload_b64 = URL_SAFE_NO_PAD.encode(serde_json::to_string(&payload).unwrap());
        let token = format!("{header_b64}.{payload_b64}.sig");

        let jwks = serde_json::json!({"not_keys": []});
        let result = verify_apple_token_with_jwks(&token, "app", &jwks);
        assert!(result.is_err(), "JWKS without keys array must be rejected");
    }
}
