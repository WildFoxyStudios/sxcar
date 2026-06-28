//! argon2id password hashing.
//!
//! Spec AD1 §1: argon2id con `m=64 MiB`, `t=3`, `p=1` y salt aleatorio
//! cryptographically-secure (`OsRng`). El hash resultante sigue el formato
//! PHC standard (`$argon2id$v=19$m=65536,t=3,p=1$<salt>$<hash>`) y es
//! portable entre implementaciones argon2id-compatibles.
//!
//! ## Por qué m=64 MiB, t=3, p=1
//!
//! OWASP Password Storage Cheat Sheet (2024) recomienda argon2id con
//! `m >= 19 MiB, t >= 2, p = 1`. Usamos `m=64 MiB, t=3` para margen contra
//! GPUs modernas. `p=1` (single-threaded) — el handler corre en un worker
//! async dedicado, no queremos contention entre threads de argon2 y el
//! resto del request.
//!
//! ## Lo que NO hace este modulo
//!
//! - No valida strength del password (eso es policy del handler; el spec
//!   AD1 no entra en password policy — vive en F0.3 user-side).
//! - No rate-limitea intentos (eso es el rate limiter en `api::admin`,
//!   tarea T16).
//! - No aplica pepper. Pepper es un secret del server adicional al
//!   password del user; no lo usamos en AD1. Si se agrega en el futuro,
//!   va como campo opcional en [`hash`] / [`verify`].

use argon2::password_hash::rand_core::OsRng;
use argon2::password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use argon2::{Algorithm, Argon2, Params, Version};

use crate::AuthError;

/// Parametros argon2id (m=64 MiB, t=3, p=1, output 32 bytes).
///
/// Computado una sola vez al cargar el modulo — argon2 recomienda Params
/// como constante reutilizable para no pagar el costo de validacion en cada
/// hash.
const ARGON2_PARAMS: Params = match Params::new(64 * 1024, 3, 1, Some(32)) {
    Ok(p) => p,
    Err(_) => panic!("argon2id m=64MiB t=3 p=1 output=32 son parametros validos; revise el codigo"),
};

/// argon2id configurado con los parametros del spec.
///
/// Instanciado una vez por llamada a [`hash`] / [`verify`] — `Argon2::new`
/// es zero-cost (es solo un enum tag), no vale cachear.
fn argon2() -> Argon2<'static> {
    Argon2::new(Algorithm::Argon2id, Version::V0x13, ARGON2_PARAMS)
}

/// Hashea un password con argon2id + salt aleatorio.
///
/// El output es un string PHC-formatted (`$argon2id$v=19$m=65536,t=3,p=1$<salt_b64>$<hash_b64>`)
/// listo para almacenar en `staff.password_hash` (columna `text`).
///
/// Cada llamada genera un salt nuevo via `OsRng`, asi que dos llamadas con
/// el mismo password producen hashes distintos pero ambos verificables.
pub fn hash(password: &str) -> Result<String, AuthError> {
    let salt = SaltString::generate(&mut OsRng);
    argon2()
        .hash_password(password.as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|e| AuthError::PasswordHash(e.to_string()))
}

/// Verifica un password contra un hash argon2id previamente emitido.
///
/// Retorna:
/// - `Ok(true)` si el password es correcto.
/// - `Ok(false)` si el password NO es correcto (no error — "wrong password"
///   es resultado de verificacion, no un fallo del sistema).
/// - `Err(AuthError::PasswordHash)` si el hash de entrada esta malformado
///   (no se puede parsear) — eso SI es un error del caller / DB corrupta.
///
/// `verify` es constant-time respecto al tamano del hash (argon2 internamente).
/// El handler NO debe usar el resultado para timing-attack enumeration: la
/// policy de AD1 es responder 401 generico para cualquier fallo de auth.
pub fn verify(password: &str, hash: &str) -> Result<bool, AuthError> {
    let parsed = PasswordHash::new(hash).map_err(|e| AuthError::PasswordHash(e.to_string()))?;
    match argon2().verify_password(password.as_bytes(), &parsed) {
        Ok(()) => Ok(true),
        Err(argon2::password_hash::Error::Password) => Ok(false),
        Err(e) => Err(AuthError::PasswordHash(e.to_string())),
    }
}

#[cfg(test)]
mod inline_tests {
    //! Tests inline rapidos (los exhaustivos viven en `tests/password.rs`).
    //! Estos cubren los caminos obvios sin pagar el costo de compilacion
    //! de un crate de tests separado.

    use super::*;

    #[test]
    fn hash_then_verify_roundtrip() {
        let h = hash("s3cr3t").unwrap();
        assert!(verify("s3cr3t", &h).unwrap());
    }

    #[test]
    fn constant_time_property_is_handled_by_argon2_crate() {
        // No testeamos timing real (eso seria flaky en CI). Solo documentamos
        // que argon2 hace compare constant-time internamente — el caller no
        // debe hacer su propio compare ni retornar antes de tiempo.
        let h = hash("x").unwrap();
        let ok = verify("x", &h).unwrap();
        assert!(ok);
    }
}
