use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use time::OffsetDateTime;

use crate::error::AuthError;

#[derive(Clone)]
pub struct JwtConfig {
    pub secret: String,
    pub access_ttl_secs: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AccessClaims {
    pub sub: String,
    pub exp: i64,
    pub iat: i64,
}

pub fn issue_access(user_id: &str, cfg: &JwtConfig) -> Result<String, AuthError> {
    let now = OffsetDateTime::now_utc().unix_timestamp();
    let claims = AccessClaims {
        sub: user_id.to_string(),
        iat: now,
        exp: now + cfg.access_ttl_secs,
    };
    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(cfg.secret.as_bytes()),
    )
    .map_err(|_| AuthError::InvalidToken)
}

pub fn verify_access(token: &str, cfg: &JwtConfig) -> Result<AccessClaims, AuthError> {
    let mut validation = Validation::default();
    validation.leeway = 0;
    let data = decode::<AccessClaims>(
        token,
        &DecodingKey::from_secret(cfg.secret.as_bytes()),
        &validation,
    )
    .map_err(|_| AuthError::InvalidToken)?;
    Ok(data.claims)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cfg(ttl: i64) -> JwtConfig {
        JwtConfig {
            secret: "test-secret".into(),
            access_ttl_secs: ttl,
        }
    }

    #[test]
    fn issue_and_verify() {
        let c = cfg(900);
        let t = issue_access("user-123", &c).unwrap();
        let claims = verify_access(&t, &c).unwrap();
        assert_eq!(claims.sub, "user-123");
    }

    #[test]
    fn wrong_secret_fails() {
        let t = issue_access("u", &cfg(900)).unwrap();
        let other = JwtConfig {
            secret: "other".into(),
            access_ttl_secs: 900,
        };
        assert!(verify_access(&t, &other).is_err());
    }

    #[test]
    fn expired_fails() {
        let t = issue_access("u", &cfg(-10)).unwrap(); // ya expirado
        assert!(verify_access(&t, &cfg(-10)).is_err());
    }
}
