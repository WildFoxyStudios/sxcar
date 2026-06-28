//! Tests for [`crate::password`].
//!
//! Spec AD1 §1: argon2id m=64MB t=3 p=1. Tests verifican:
//! - Salt aleatorio: dos hashes del mismo password son distintos pero ambos verifican.
//! - Password correcto verifica.
//! - Password incorrecto retorna false (NO error — "wrong password" es bool, no error tipado).
//! - Hash malformado retorna error (NO se intenta verificar con texto basura).

use argon2::password_hash::PasswordHash;

use auth_admin::password::{hash, verify};
use auth_admin::AuthError;

#[test]
fn hash_deterministic_per_instance_but_unique_per_password() {
    // Dos hashes del MISMO password deben diferir (salt aleatorio).
    let h1 = hash("correct horse battery staple").expect("first hash");
    let h2 = hash("correct horse battery staple").expect("second hash");
    assert_ne!(h1, h2, "salt debe ser aleatorio");

    // Pero ambos verifican el mismo password.
    assert!(verify("correct horse battery staple", &h1).expect("verify h1"));
    assert!(verify("correct horse battery staple", &h2).expect("verify h2"));
}

#[test]
fn hash_starts_with_argon2id_marker() {
    let h = hash("anything").expect("hash");
    // El prefijo identifica el algoritmo + version + params.
    assert!(
        h.starts_with("$argon2id$v=19$m=65536,t=3,p=1$"),
        "hash no respeta el formato argon2id esperado: {h}"
    );
}

#[test]
fn verify_correct_password_returns_true() {
    let h = hash("hunter2").expect("hash");
    assert!(verify("hunter2", &h).expect("verify correct"));
}

#[test]
fn verify_wrong_password_returns_false_not_error() {
    let h = hash("hunter2").expect("hash");
    let result = verify("hunter3", &h).expect("verify no debe panic en wrong password");
    assert!(!result, "wrong password debe retornar false, no error");
}

#[test]
fn verify_empty_password_against_real_hash() {
    // Caso borde: empty password es valido per se (no es la funcion la que
    // rechaza vacios — eso es policy del handler). La funcion solo verifica
    // lo que le pasan.
    let h = hash("nonempty").expect("hash");
    assert!(!verify("", &h).expect("verify empty"));
}

#[test]
fn verify_malformed_hash_returns_error() {
    // Hashes que NO son argon2id valido deben producir AuthError::PasswordHash,
    // NO panic ni false silencioso.
    for malformed in [
        "",
        "not-a-hash",
        "$argon2id$v=19$m=65536,t=3,p=1$short$short",       // salt demasiado corto
        "$argon2id$v=19$m=65536,t=3,p=1$xxx$yyyyyyyyy",     // base64 invalido en salt
        "$argon2i$v=19$m=65536,t=3,p=1$xxx$yyyyyyyyyyy",    // argon2i (NO argon2id)
        "$argon2id$v=18$m=65536,t=3,p=1$xxx$yyyyyyyyyyy",    // version incorrecta
        "$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$",  // separadores vacios
    ] {
        let result = verify("any-password", malformed);
        assert!(
            matches!(result, Err(AuthError::PasswordHash(_))),
            "hash malformado '{malformed}' debio retornar PasswordHash, got {result:?}"
        );
    }
}

#[test]
fn password_hash_can_be_parsed_by_argon2_crate_directly() {
    // Test de interoperabilidad: el hash que emitimos debe ser parseable
    // por argon2::PasswordHash::new() sin trucos. Si esto rompe, algun
    // dia no podemos migrar a otra lib argon2-compatible.
    let h = hash("interop").expect("hash");
    let _parsed = PasswordHash::new(&h).expect("PasswordHash::new debe parsear nuestro output");
}
