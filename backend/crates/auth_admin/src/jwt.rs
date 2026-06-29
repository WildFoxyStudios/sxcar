//! JWT issue/verify con aud=admin.
//!
//! Implementado en T6. Spec AD1 SS1: HS256, claim `aud = "admin"`.
//! Cross-audience (`aud = "app"`) rechazado en verify -- el handler en
//! `api::admin::extractors::StaffAuth` lo convierte a 401 (no 403).

use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use time::OffsetDateTime;
use uuid::Uuid;

use crate::AuthError;

/// Claims del JWT de staff.
#[derive(Debug, Serialize, Deserialize)]
pub struct StaffClaims {
    /// staff_id (uuid).
    pub sub: String,
    /// "admin" para tokens de staff.
    pub aud: String,
    /// support | moderator | admin | superadmin.
    pub staff_role: String,
    /// Permisos especificos del rol.
    pub permissions: Vec<String>,
    /// Issued at (Unix timestamp).
    pub iat: usize,
    /// Expiration (Unix timestamp, default 8h).
    pub exp: usize,
    /// UUID v4 unico por token (session_id para tokens de staff).
    pub jti: String,
}

/// Emite un JWT de staff. Retorna el token firmado (String).
///
/// `jti` es el token ID, usado como session_id para staff tokens.
///
/// # Errors
///
/// Retorna `AuthError::JwtInvalid` si el proceso de firma falla (p. ej. clave
/// vacia o claims invalidos).
pub fn issue(
    secret: &str,
    staff_id: Uuid,
    role: &str,
    permissions: &[String],
    ttl_secs: i64,
    jti: &str,
) -> Result<String, AuthError> {
    let now = OffsetDateTime::now_utc();
    let exp = now + time::Duration::seconds(ttl_secs);

    let claims = StaffClaims {
        sub: staff_id.to_string(),
        aud: "admin".to_string(),
        staff_role: role.to_string(),
        permissions: permissions.to_vec(),
        iat: now.unix_timestamp() as usize,
        exp: exp.unix_timestamp() as usize,
        jti: jti.to_string(),
    };

    let key = EncodingKey::from_secret(secret.as_bytes());
    encode(&Header::default(), &claims, &key)
        .map_err(|e| AuthError::JwtInvalid(e.to_string()))
}

/// Verifica un JWT de staff. Retorna `StaffClaims` si valido;
/// `Err(AuthError::JwtInvalid)` si no.
///
/// Valida:
/// - Firma HMAC-SHA256 (`secret` compartido).
/// - `aud == "admin"`.
/// - Token no expirado (con 30 s de leeway por clock skew).
pub fn verify(secret: &str, token: &str) -> Result<StaffClaims, AuthError> {
    let mut validation = Validation::new(jsonwebtoken::Algorithm::HS256);
    validation.set_audience(&["admin"]);
    validation.validate_exp = true;
    validation.leeway = 30;

    let key = DecodingKey::from_secret(secret.as_bytes());
    let token_data = decode::<StaffClaims>(token, &key, &validation)
        .map_err(|e| AuthError::JwtInvalid(e.to_string()))?;

    Ok(token_data.claims)
}

#[cfg(test)]
mod unit {
    use super::*;

    fn secret() -> &'static str {
        "test-hs256-secret-key-must-be-long-enough"
    }

    fn perms() -> Vec<String> {
        vec!["read:users".into(), "write:users".into()]
    }

    #[test]
    fn issue_returns_ok_with_valid_input() {
        let token = issue(secret(), Uuid::new_v4(), "moderator", &perms(), 3600, &Uuid::new_v4().to_string());
        assert!(token.is_ok());
        assert!(!token.unwrap().is_empty());
    }

    #[test]
    fn issue_sets_correct_aud() {
        let jti = Uuid::new_v4().to_string();
        let token = issue(secret(), Uuid::new_v4(), "admin", &perms(), 3600, &jti).unwrap();
        let claims = verify(secret(), &token).unwrap();
        assert_eq!(claims.aud, "admin");
    }
}
