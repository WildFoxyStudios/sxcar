//! Tests for [`crate::mfa_token`].
//!
//! Spec AD1 §3.1 / T7: el mfa_token es opaco (no JWT), firmado con HMAC-SHA256,
//! base64url sin padding, TTL 15 minutos.
//!
//! Formato interno: payload = "{staff_id}|{expires_at_unix}" (UTF-8).
//! Formato wire: base64url(payload_bytes || hmac_tag_32_bytes), sin padding.

use auth_admin::mfa_token;
use auth_admin::AuthError;
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use hmac::{Hmac, Mac};
use sha2::Sha256;

type HmacSha256 = Hmac<Sha256>;

/// Clave de test: 32 bytes para HMAC-SHA256 (misma longitud que una key real).
const TEST_SECRET: &[u8] = b"0123456789abcdef0123456789abcdef";

#[test]
fn issue_returns_base64url_no_padding() {
    let token = mfa_token::issue(TEST_SECRET, "test-user");

    // URL_SAFE_NO_PAD no produce '='.
    assert!(!token.contains('='), "token must not contain padding '=': {token}");
    // URL-safe alphabet usa '-' y '_', nunca '/' ni '+'.
    assert!(!token.contains('/'), "token must not contain url-unsafe '/': {token}");
    assert!(!token.contains('+'), "token must not contain url-unsafe '+': {token}");
    // Token no debe ser vacio.
    assert!(!token.is_empty(), "token must not be empty");
}

#[test]
fn verify_accepts_within_15min() {
    let staff_id = "test-uuid-550e8400-e29b-41d4-a716-446655440000";
    let token = mfa_token::issue(TEST_SECRET, staff_id);

    let result = mfa_token::verify(TEST_SECRET, &token);
    assert!(
        result.is_ok(),
        "verify deberia aceptar token recien emitido: {:?}",
        result.err()
    );
    assert_eq!(
        result.unwrap(),
        staff_id,
        "verify debe retornar el staff_id exacto"
    );
}

#[test]
fn verify_rejects_expired() {
    // Forjamos un token con expires_at = 1 (epoch 1 = 1970-01-01 00:00:01 UTC).
    let payload = b"test-user|1";
    let mut mac = HmacSha256::new_from_slice(TEST_SECRET).expect("HMAC key");
    mac.update(payload);
    let tag = mac.finalize().into_bytes();

    let mut wire = Vec::with_capacity(payload.len() + 32);
    wire.extend_from_slice(payload);
    wire.extend_from_slice(&tag);
    let token = URL_SAFE_NO_PAD.encode(&wire);

    let result = mfa_token::verify(TEST_SECRET, &token);
    assert!(result.is_err(), "token con exp=1 debe ser rechazado");
    match result.unwrap_err() {
        AuthError::MfaTokenInvalid(msg) => {
            assert!(
                msg.contains("expired"),
                "mensaje debe mencionar expiracion, got: {msg}"
            );
        }
        e => panic!("expected MfaTokenInvalid, got {e:?}"),
    }
}

#[test]
fn verify_rejects_tampered() {
    let token = mfa_token::issue(TEST_SECRET, "test-user");

    // Decodificar, mutar un byte del payload, re-codificar.
    let mut decoded = URL_SAFE_NO_PAD
        .decode(&token)
        .expect("token from issue debe ser base64 valido");
    let payload_end = decoded.len() - 32;
    decoded[payload_end - 1] ^= 0x01; // flip bit en el ultimo byte del payload

    let tampered = URL_SAFE_NO_PAD.encode(&decoded);

    let result = mfa_token::verify(TEST_SECRET, &tampered);
    assert!(
        result.is_err(),
        "token con payload alterado debe ser rechazado"
    );
    match result.unwrap_err() {
        AuthError::MfaTokenInvalid(_) => {}
        e => panic!("expected MfaTokenInvalid, got {e:?}"),
    }
}

#[test]
fn different_staff_ids_yield_different_tokens() {
    let t1 = mfa_token::issue(TEST_SECRET, "user-a");
    let t2 = mfa_token::issue(TEST_SECRET, "user-b");

    assert_ne!(t1, t2, "distintos staff_ids deben producir tokens distintos");

    // Ambos deben verificar correctamente y retornar el id correcto.
    assert!(
        mfa_token::verify(TEST_SECRET, &t1).is_ok(),
        "token user-a debe verificar"
    );
    assert!(
        mfa_token::verify(TEST_SECRET, &t2).is_ok(),
        "token user-b debe verificar"
    );
    assert_eq!(
        mfa_token::verify(TEST_SECRET, &t1).unwrap(),
        "user-a",
        "verify debe retornar user-a"
    );
    assert_eq!(
        mfa_token::verify(TEST_SECRET, &t2).unwrap(),
        "user-b",
        "verify debe retornar user-b"
    );
}

#[test]
fn verify_rejects_empty_token() {
    let result = mfa_token::verify(TEST_SECRET, "");
    assert!(result.is_err(), "empty token debe ser rechazado");
    match result.unwrap_err() {
        AuthError::MfaTokenInvalid(_) => {}
        e => panic!("expected MfaTokenInvalid, got {e:?}"),
    }
}
