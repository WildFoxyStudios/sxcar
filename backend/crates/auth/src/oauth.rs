use async_trait::async_trait;

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
}
