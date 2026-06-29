//! KEK (key encryption key) loader desde env.
//!
//! Carga la KEK desde `STAFF_TOTP_KEK` (base64, 32 bytes = AES-256)
//! y opcionalmente `STAFF_TOTP_KEK_VERSION` (u8, default 1).
//!
//! Versionado para permitir rotacion sin re-cifrar todos los ciphertexts
//! de golpe: lazy re-wrap on next login. Cada fila guarda su `kek_version`
//! y se re-cifra cuando el staff hace login con la nueva KEK.

use crate::AuthError;
use base64::{engine::general_purpose::STANDARD, Engine};

/// Key encryption key para cifrar TOTP secrets.
#[derive(Clone, Debug)]
pub struct Kek {
    /// Clave AES-256 de 32 bytes (cargada de STAFF_TOTP_KEK en base64).
    pub key: [u8; 32],
    /// Version de la KEK (STAFF_TOTP_KEK_VERSION, default 1).
    pub version: u8,
}

impl Kek {
    /// Carga la KEK desde variables de entorno.
    ///
    /// - `STAFF_TOTP_KEK` (obligatorio): 32 bytes en base64.
    /// - `STAFF_TOTP_KEK_VERSION` (opcional, default 1): u8.
    ///
    /// # Errors
    ///
    /// - [`AuthError::KekMissing`] si `STAFF_TOTP_KEK` no esta definida.
    /// - [`AuthError::KekMalformed`] si el base64 es invalido, la longitud
    ///   es distinta de 32 bytes, o la version no esta en 1..=255.
    pub fn from_env() -> Result<Self, AuthError> {
        let encoded = std::env::var("STAFF_TOTP_KEK")
            .map_err(|_| AuthError::KekMissing)?;

        let decoded = STANDARD
            .decode(encoded.as_bytes())
            .map_err(|e| AuthError::KekMalformed(format!("base64 decode error: {e}")))?;

        if decoded.len() != 32 {
            return Err(AuthError::KekMalformed(format!(
                "key length {} != expected 32 bytes",
                decoded.len()
            )));
        }

        let mut key = [0u8; 32];
        key.copy_from_slice(&decoded);

        let version_raw = std::env::var("STAFF_TOTP_KEK_VERSION")
            .unwrap_or_else(|_| "1".to_string());

        let version: u8 = version_raw
            .parse()
            .map_err(|e| {
                AuthError::KekMalformed(format!(
                    "STAFF_TOTP_KEK_VERSION '{version_raw}' is not a valid u8: {e}"
                ))
            })?;

        if version == 0 {
            return Err(AuthError::KekMalformed(
                "STAFF_TOTP_KEK_VERSION must be in 1..=255, got 0".to_string(),
            ));
        }

        Ok(Kek { key, version })
    }

    /// Constructor directo (para tests, no usa env).
    pub fn new(key: [u8; 32], version: u8) -> Self {
        Kek { key, version }
    }
}
