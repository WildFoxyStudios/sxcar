//! Tests for [`crate::recovery`].
//!
//! Spec AD1 §1: 10 codes single-use, hashed at rest con argon2id (mismo
//! modulo que `password`). Charset sin ambiguedad visual (sin 0/O, 1/I/L)
//! para que un usuario pueda transcribir el codigo sin equivocarse.

use auth_admin::recovery::{gen, hash as rec_hash, verify as rec_verify};
use auth_admin::AuthError;

#[test]
fn gen_returns_ten_codes_of_ten_chars() {
    let codes = gen();
    assert_eq!(codes.len(), 10);
    for code in &codes {
        assert_eq!(code.len(), 10, "cada codigo = 10 chars, got '{code}'");
    }
}

#[test]
fn gen_codes_use_unambiguous_alphabet() {
    // Excluye 0 O 1 I L para evitar confusion al transcribir.
    let forbidden = "0O1IL";
    for code in gen() {
        for c in code.chars() {
            assert!(
                !forbidden.contains(c),
                "code '{code}' contiene char ambiguo '{c}'"
            );
        }
    }
}

#[test]
fn gen_codes_are_unique_within_one_batch() {
    let codes = gen();
    let unique: std::collections::HashSet<_> = codes.iter().collect();
    assert_eq!(unique.len(), 10, "los 10 codigos de un batch deben ser unicos");
}

#[test]
fn gen_produces_different_codes_across_calls() {
    // Probabilistic — prob de colision astronomicamente baja. Si rompe,
    // alguien cambio el RNG a deterministico.
    let a = gen();
    let b = gen();
    assert_ne!(a, b, "dos llamadas a gen() deben producir batches distintos");
}

#[test]
fn hash_and_verify_roundtrip() {
    for code in gen() {
        let h = rec_hash(&code).expect("hash");
        assert!(rec_verify(&code, &h).expect("verify correct"));
    }
}

#[test]
fn verify_wrong_code_returns_false_not_error() {
    let h = rec_hash("ABCDEFGHJK").expect("hash");
    // Codigo distinto pero con formato valido (10 chars del alphabet).
    assert!(!rec_verify("QRSTVWXYZ23", &h).expect("verify wrong"));
}

#[test]
fn verify_with_empty_code_returns_error() {
    let h = rec_hash("ABCDEFGHJK").expect("hash");
    let result = rec_verify("", &h);
    assert!(
        matches!(result, Err(AuthError::RecoveryFormat)),
        "empty code debe retornar AuthError::RecoveryFormat, got {result:?}"
    );
}

#[test]
fn verify_with_malformed_hash_returns_error() {
    let result = rec_verify("ABCDEFGHJK", "not-a-real-argon2id-hash");
    assert!(matches!(result, Err(AuthError::RecoveryFormat)));
}

#[test]
fn hash_output_is_argon2id_standard_format() {
    let h = rec_hash("ABCDEFGHJK").expect("hash");
    assert!(
        h.starts_with("$argon2id$"),
        "hash debe tener prefijo argon2id, got '{h}'"
    );
}
