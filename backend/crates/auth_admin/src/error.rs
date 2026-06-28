//! Error type unificado para el crate `auth_admin`.
//!
//! Cada modulo define su variante especifica via `#[error("...")]`. La API
//! publica solo expone [`AuthError`] — los handlers en `api` lo mapean a
//! HTTP status codes segun la guia de errores del spec AD1 §1 (errores
//! genericos para evitar enumeracion de usuarios/staff).

use thiserror::Error;

/// Errores del crate `auth_admin`.
#[derive(Debug, Error)]
pub enum AuthError {
    /// Password hash/verify fallo (formato de hash invalido, parametros
    /// argon2id desconocidos, etc.). NO es "password incorrecto" — ese es
    /// un bool retornado por [`crate::password::verify`].
    #[error("password hash operation failed: {0}")]
    PasswordHash(String),

    /// Codigo TOTP malformado (no son 6 digitos, contiene caracteres no
    /// numericos, etc.). Distinto de "TOTP incorrecto" (que es bool).
    #[error("invalid TOTP code format: {0}")]
    TotpFormat(String),

    /// Ciphertext AES-256-GCM invalido (longitud incorrecta, tag mismatch,
    /// nonce corrupto, KEK incorrecto). NUNCA loggear el ciphertext.
    #[error("TOTP secret decryption failed")]
    TotpDecrypt,

    /// JWT mal firmado, expirado, `aud` incorrecto, o claims invalidos.
    #[error("admin JWT invalid: {0}")]
    JwtInvalid(String),

    /// `mfa_token` expirado, mal firmado, o con payload corrupto.
    #[error("mfa_token invalid: {0}")]
    MfaTokenInvalid(String),

    /// KEK (key encryption key) no esta configurado. El handler debe
    /// retornar 500 con este error y un mensaje claro para ops.
    #[error(
        "KEK not configured: set STAFF_TOTP_KEK (and optionally STAFF_TOTP_KEK_VERSION) in env"
    )]
    KekMissing,

    /// KEK presente pero malformado (no es base64 valido, longitud != 32 bytes).
    #[error("KEK malformed: {0}")]
    KekMalformed(String),

    /// Codigo de recovery malformado (longitud incorrecta, charset invalido).
    #[error("invalid recovery code format")]
    RecoveryFormat,
}
