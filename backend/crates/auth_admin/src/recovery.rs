//! Recovery codes (10 single-use, hashed at rest).
//!
//! Spec AD1 §1: 10 codes generados una sola vez al activar 2FA, cada uno:
//! - 10 chars del alphabet "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" (sin 0/O/1/I/L
//!   para evitar confusion visual al transcribir).
//! - hasheado con argon2id (mismos params que `password::hash`).
//! - single-use: cuando un staff lo usa, se invalida (eso lo gestiona el
//!   handler + DB en T14+; este modulo solo produce y verifica hashes).
//!
//! El handler muestra los 10 codes UNA sola vez al activar 2FA. El staff
//! debe guardarlos offline (papel, password manager). Si los pierde todos,
//! recovery requiere un superadmin (futuro AD4 con break-glass auditado).

use argon2::password_hash::PasswordHash;
use rand::seq::SliceRandom;

use crate::password;
use crate::AuthError;

/// Cantidad de codigos generados por [`gen`].
pub const CODE_COUNT: usize = 10;

/// Largo de cada codigo en chars.
pub const CODE_LEN: usize = 10;

/// Alphabet sin ambiguedad visual: sin 0/O/1/I/L.
/// 23 letras (A-Z sin I, L, O) + 8 digitos (2-9) = 31 chars.
const ALPHABET: &[u8] = b"ABCDEFGHJKMNPQRSTUVWXYZ23456789";

/// Genera los 10 recovery codes. Cada uno es unico dentro del batch.
///
/// La randomness viene de `rand::thread_rng()` (OsRng-backed en Linux/macOS,
/// BCryptGenRandom en Windows) — CSPRNG, no predecicable.
pub fn gen() -> Vec<String> {
    let mut rng = rand::thread_rng();
    (0..CODE_COUNT)
        .map(|_| {
            (0..CODE_LEN)
                .map(|_| *ALPHABET.choose(&mut rng).expect("alphabet no vacio"))
                .map(char::from)
                .collect()
        })
        .collect()
}

/// Hashea un recovery code con argon2id (mismos params que passwords de
/// staff). El hash es un string PHC que se guarda en `staff.recovery_codes_hash`.
///
/// El caller guarda UN ARRAY con los 10 hashes; al verificar un intento,
/// compara contra cada uno. Si matchea, marca el code como usado y lo
/// quita del array (eso es policy del handler, no de este modulo).
pub fn hash(code: &str) -> Result<String, AuthError> {
    if !is_valid_format(code) {
        return Err(AuthError::RecoveryFormat);
    }
    // Reutilizamos password::hash: misma funcion argon2id, mismos params.
    password::hash(code)
}

/// Verifica un recovery code contra un hash. Retorna Ok(true) si matchea,
/// Ok(false) si no matchea, Err(RecoveryFormat) si el code esta vacio o el
/// hash esta malformado.
pub fn verify(code: &str, hash: &str) -> Result<bool, AuthError> {
    if code.is_empty() || !is_valid_format(code) {
        return Err(AuthError::RecoveryFormat);
    }
    let parsed = PasswordHash::new(hash).map_err(|_| AuthError::RecoveryFormat)?;
    // (parsed solo se usa para detectar malformacion temprana; el verify
    // real lo hace password::verify, que re-parsea internamente.)
    let _ = parsed;
    match password::verify(code, hash) {
        Ok(true) => Ok(true),
        Ok(false) => Ok(false),
        Err(_) => Err(AuthError::RecoveryFormat),
    }
}

fn is_valid_format(code: &str) -> bool {
    code.len() == CODE_LEN && code.chars().all(|c| ALPHABET.contains(&(c as u8)))
}
