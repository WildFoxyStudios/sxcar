//! mfa_token opaco pre-2FA (15 min TTL).
//!
//! Implementado en T7. Spec AD1 §3.1: el flujo de login es email+password
//! -> mfa_token -> TOTP -> JWT. El mfa_token es opaco (no JWT) porque
//! NO debe ser usable como access token — solo prueba que el password
//! paso y habilita la ventana de 15 min para que el usuario ingrese el
//! codigo TOTP. HMAC-SHA256 firmado, base64url.
//!
//! Formato interno del payload (antes de firmar): `"{staff_id}|{expires_at_unix}"`.
//! Formato wire del token: `base64url(payload_bytes || hmac_tag_32_bytes)`, sin padding.

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use hmac::{Hmac, Mac};
use sha2::Sha256;
use time::OffsetDateTime;

use crate::AuthError;

type HmacSha256 = Hmac<Sha256>;

/// TTL del mfa_token: 15 minutos (900 segundos).
const TTL_SECONDS: i64 = 900;

/// Emite un mfa_token opaco.
///
/// Construye el payload `"{staff_id}|{expires_at_unix}"` con `expires_at = now + 15 min`,
/// lo firma con HMAC-SHA256, y codifica `payload_bytes || hmac_tag_32_bytes` en
/// base64url sin padding.
pub fn issue(secret: &[u8], staff_id: &str) -> String {
    let expires_at = OffsetDateTime::now_utc().unix_timestamp() + TTL_SECONDS;
    let payload = format!("{}|{}", staff_id, expires_at);

    let mut mac = HmacSha256::new_from_slice(secret).expect("HMAC accepts any key length");
    mac.update(payload.as_bytes());
    let tag = mac.finalize().into_bytes();

    let mut wire = Vec::with_capacity(payload.len() + 32);
    wire.extend_from_slice(payload.as_bytes());
    wire.extend_from_slice(&tag);

    URL_SAFE_NO_PAD.encode(&wire)
}

/// Verifica un mfa_token.
///
/// Decodifica el base64url, separa `payload` de `hmac_tag`, verifica la firma
/// en tiempo constante, parsea `expires_at` del payload, y comprueba que el
/// token no haya expirado.
///
/// # Errors
///
/// Retorna `AuthError::MfaTokenInvalid` si:
/// - El token esta vacio.
/// - El base64url es invalido.
/// - El token es demasiado corto (menos de 33 bytes en total).
/// - La firma HMAC no coincide (payload alterado o clave incorrecta).
/// - El payload no es UTF-8 valido o no tiene el formato esperado.
/// - El timestamp de expiracion es invalido.
/// - El token ha expirado.
pub fn verify(secret: &[u8], token: &str) -> Result<String, AuthError> {
    if token.is_empty() {
        return Err(AuthError::MfaTokenInvalid("token is empty".into()));
    }

    let decoded = URL_SAFE_NO_PAD
        .decode(token)
        .map_err(|e| AuthError::MfaTokenInvalid(format!("base64 decode failed: {e}")))?;

    // Necesitamos al menos 1 byte de payload + 32 bytes de tag HMAC-SHA256.
    if decoded.len() < 33 {
        return Err(AuthError::MfaTokenInvalid("token too short".into()));
    }

    let payload_end = decoded.len() - 32;
    let payload = &decoded[..payload_end];
    let tag = &decoded[payload_end..];

    // Verificar HMAC en tiempo constante (via `subtle` internamente en la crate `hmac`).
    let mut mac = HmacSha256::new_from_slice(secret).expect("HMAC accepts any key length");
    mac.update(payload);
    mac.verify_slice(tag)
        .map_err(|_| AuthError::MfaTokenInvalid("HMAC mismatch".into()))?;

    // Parsear payload como UTF-8.
    let payload_str = std::str::from_utf8(payload)
        .map_err(|_| AuthError::MfaTokenInvalid("payload not valid UTF-8".into()))?;

    // El payload tiene formato "{staff_id}|{expires_at_unix}".
    // Usamos rfind para encontrar el ultimo '|', asumiendo que staff_id
    // (un UUID) no contiene '|'.
    let separator = payload_str
        .rfind('|')
        .ok_or_else(|| AuthError::MfaTokenInvalid("missing '|' separator in payload".into()))?;

    let staff_id = &payload_str[..separator];
    let expires_at_str = &payload_str[separator + 1..];

    let expires_at: i64 = expires_at_str
        .parse()
        .map_err(|_| AuthError::MfaTokenInvalid("invalid expiration timestamp".into()))?;

    let now = OffsetDateTime::now_utc().unix_timestamp();
    if now > expires_at {
        return Err(AuthError::MfaTokenInvalid("token has expired".into()));
    }

    Ok(staff_id.to_string())
}
