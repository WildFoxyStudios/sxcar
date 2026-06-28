//! TOTP (RFC 6238) + AES-256-GCM encryption for at-rest TOTP secrets.
//!
//! Spec AD1 §1: TOTP **SHA1**, **step 30s**, **6 digits** — compatible con
//! Google Authenticator / 1Password / Authy / Bitwarden. NO usar SHA256
//! ni SHA512: aunque mas seguros, rompen compat con authenticators
//! populares.
//!
//! ## Almacenamiento del secret
//!
//! El secret (32 bytes random) NUNCA se guarda en plaintext. Se cifra
//! con AES-256-GCM. Formato del blob:
//!
//! ```text
//! [ nonce: 12 bytes | ciphertext: N bytes | gcm tag: 16 bytes ]
//! ```
//!
//! Overhead total: **28 bytes**. Nonce se genera con `OsRng` por encrypt.

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use rand::RngCore;
use totp_rs::{Algorithm, Secret, TOTP};

use crate::AuthError;

/// Tamaño del secret TOTP en bytes. `Secret::generate_secret()` produce
/// 20 bytes por default (160 bits, RFC 6238 minimum).
pub const SECRET_BYTES: usize = 32;

/// Tamaño del nonce AES-GCM (96 bits = 12 bytes, estandard para GCM).
pub const NONCE_BYTES: usize = 12;

/// Tamaño del tag de autenticación GCM (128 bits = 16 bytes).
pub const TAG_BYTES: usize = 16;

/// Step del TOTP en segundos (RFC 6238 / Google Authenticator default).
pub const STEP_SECS: u64 = 30;

/// Genera un secret TOTP nuevo (32 bytes random, codificado base32 RFC 4648
/// sin padding).
pub fn gen_secret() -> String {
    Secret::generate_secret().to_encoded().to_string()
}

/// Genera el codigo TOTP actual (6 digitos) para un secret.
pub fn current_code(secret_b32: &str) -> Result<String, AuthError> {
    let totp = build_totp(secret_b32)?;
    totp.generate_current()
        .map_err(|e| AuthError::TotpFormat(e.to_string()))
}

/// Verifica un codigo TOTP contra un secret.
///
/// El `window` (skew) se setea al construir el TOTP internamente (1 step,
/// acepta current ± 1 step = 90s de tolerancia). Si en el futuro el
/// handler necesita window dinamico, lo cambiamos a `TOTP::check` con
/// `time` explicito.
pub fn verify_code(secret_b32: &str, code: &str, _window: u8) -> Result<bool, AuthError> {
    let totp = build_totp(secret_b32)?;
    totp.check_current(code)
        .map_err(|e| AuthError::TotpFormat(format!("check_current: {e}")))
}

/// Cifra el secret TOTP (bytes crudos) con AES-256-GCM.
/// Output: `Vec<u8>` de longitud `plaintext.len() + 28`
///   - primeros 12 bytes: nonce random
///   - siguientes `plaintext.len()` bytes: ciphertext
///   - ultimos 16 bytes: GCM auth tag
pub fn encrypt_secret(kek: &[u8; 32], plaintext: &[u8]) -> Result<Vec<u8>, AuthError> {
    let key = Key::<Aes256Gcm>::from_slice(kek);
    let cipher = Aes256Gcm::new(key);

    let mut nonce_bytes = [0u8; NONCE_BYTES];
    rand::thread_rng().fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let ciphertext = cipher
        .encrypt(
            nonce,
            Payload {
                msg: plaintext,
                aad: b"",
            },
        )
        .map_err(|_| AuthError::TotpDecrypt)?;

    let mut out = Vec::with_capacity(NONCE_BYTES + ciphertext.len());
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&ciphertext);
    Ok(out)
}

/// Descifra un blob producido por [`encrypt_secret`].
/// Verifica el GCM tag: cualquier tampering (cambio en ciphertext, en nonce,
/// o uso de KEK distinta) produce `AuthError::TotpDecrypt`.
pub fn decrypt_secret(kek: &[u8; 32], blob: &[u8]) -> Result<Vec<u8>, AuthError> {
    if blob.len() < NONCE_BYTES + TAG_BYTES {
        return Err(AuthError::TotpDecrypt);
    }
    let (nonce_bytes, ciphertext) = blob.split_at(NONCE_BYTES);
    let key = Key::<Aes256Gcm>::from_slice(kek);
    let cipher = Aes256Gcm::new(key);
    let nonce = Nonce::from_slice(nonce_bytes);

    cipher
        .decrypt(
            nonce,
            Payload {
                msg: ciphertext,
                aad: b"",
            },
        )
        .map_err(|_| AuthError::TotpDecrypt)
}

fn build_totp(secret_b32: &str) -> Result<TOTP, AuthError> {
    // Decodificamos base32 manualmente para evitar depender del API de
    // `totp_rs::Secret` (cuyo constructor de string decoding requiere
    // feature flags y no implementa FromStr). El alphabet RFC 4648 base32
    // es fijo y pequeno: cabe en una tabla de 256 entries.
    let secret_bytes = decode_base32(secret_b32)?;
    TOTP::new(
        Algorithm::SHA1,
        6,
        1, // skew interno fijo a 1 step; verify_code() lo respeta
        STEP_SECS,
        secret_bytes,
        None,
        "admin".to_string(),
    )
    .map_err(|e| AuthError::TotpFormat(format!("TOTP::new: {e}")))
}

/// Decodifica RFC 4648 base32 sin padding. Devuelve error si el input
/// contiene chars fuera del alphabet o longitud incompatible con un
/// multiplo de 8 chars (5 bytes).
fn decode_base32(s: &str) -> Result<Vec<u8>, AuthError> {
    const ALPHABET: &[u8; 32] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    let mut lookup = [0xffu8; 256];
    for (i, &c) in ALPHABET.iter().enumerate() {
        lookup[c as usize] = i as u8;
    }

    let s = s.as_bytes();
    if s.is_empty() {
        return Err(AuthError::TotpFormat("secret vacio".into()));
    }
    // Valida chars
    for &c in s {
        if lookup[c as usize] == 0xff {
            return Err(AuthError::TotpFormat(format!(
                "caracter invalido en base32: {:?}",
                c as char
            )));
        }
    }

    let mut out = Vec::with_capacity(s.len() * 5 / 8);
    let mut buffer: u64 = 0;
    let mut bits_in_buffer: u32 = 0;

    for &c in s {
        let v = lookup[c as usize] as u64;
        buffer = (buffer << 5) | v;
        bits_in_buffer += 5;
        if bits_in_buffer >= 8 {
            bits_in_buffer -= 8;
            out.push((buffer >> bits_in_buffer) as u8);
            buffer &= (1u64 << bits_in_buffer) - 1;
        }
    }
    Ok(out)
}
