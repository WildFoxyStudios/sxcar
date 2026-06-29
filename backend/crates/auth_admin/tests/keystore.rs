//! Tests for [`auth_admin::keystore`].
//!
//! Spec AD1 §1: `STAFF_TOTP_KEK` (base64, 32 bytes) + `STAFF_TOTP_KEK_VERSION`
//! (u8, default 1). Tests atómicos: cada test limpia las env vars al final
//! para no contaminar tests vecinos.
//!
//! Usamos un mutex global para serializar tests que modifican vars de entorno,
//! ya que `std::env` es global al proceso y Rust corre tests en paralelo.

use auth_admin::keystore::Kek;
use base64::{engine::general_purpose::STANDARD, Engine};
use std::sync::{Mutex, OnceLock};

/// Mutex global para serializar acceso a env vars entre tests paralelos.
fn env_lock() -> &'static Mutex<()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(()))
}

/// Helper: setea `STAFF_TOTP_KEK`.
fn set_kek_env(b64: &str) {
    std::env::set_var("STAFF_TOTP_KEK", b64);
}

/// Helper: setea `STAFF_TOTP_KEK_VERSION`.
fn set_version_env(v: u8) {
    std::env::set_var("STAFF_TOTP_KEK_VERSION", v.to_string());
}

/// Helper: limpia ambas env vars.
fn cleanup_env() {
    std::env::remove_var("STAFF_TOTP_KEK");
    std::env::remove_var("STAFF_TOTP_KEK_VERSION");
}

// ---------------------------------------------------------------------------
// from_env tests (adquieren env_lock)
// ---------------------------------------------------------------------------

#[test]
fn from_env_with_valid_base64_key_succeeds() {
    let _guard = env_lock().lock().unwrap();
    let key_bytes = [0u8; 32];
    let b64 = STANDARD.encode(key_bytes);
    set_kek_env(&b64);
    let result = Kek::from_env();
    cleanup_env();

    let kek = result.expect("valid base64 key should succeed");
    assert_eq!(kek.key, key_bytes, "key debe coincidir");
    assert_eq!(kek.version, 1, "version default debe ser 1");
}

#[test]
fn from_env_with_custom_version() {
    let _guard = env_lock().lock().unwrap();
    let key_bytes = [0xab; 32];
    let b64 = STANDARD.encode(key_bytes);
    set_kek_env(&b64);
    set_version_env(5);
    let result = Kek::from_env();
    cleanup_env();

    let kek = result.expect("custom version should succeed");
    assert_eq!(kek.key, key_bytes, "key debe coincidir");
    assert_eq!(kek.version, 5, "version debe ser 5");
}

#[test]
fn from_env_missing_env_returns_kek_missing() {
    let _guard = env_lock().lock().unwrap();
    // Asegurar que STAFF_TOTP_KEK no existe.
    cleanup_env();
    let result = Kek::from_env();
    match result {
        Err(auth_admin::AuthError::KekMissing) => {}
        other => panic!("expected Err(KekMissing), got {other:?}"),
    }
}

#[test]
fn from_env_malformed_base64_returns_error() {
    let _guard = env_lock().lock().unwrap();
    set_kek_env("not-valid-base64!!!");
    let result = Kek::from_env();
    cleanup_env();

    match result {
        Err(auth_admin::AuthError::KekMalformed(msg)) => {
            assert!(
                msg.contains("base64"),
                "mensaje debe mencionar base64, got: {msg}"
            );
        }
        other => panic!("expected Err(KekMalformed), got {other:?}"),
    }
}

#[test]
fn from_env_wrong_key_length_returns_error() {
    let _guard = env_lock().lock().unwrap();
    let key_bytes = [0u8; 16]; // 16 bytes, no 32
    let b64 = STANDARD.encode(key_bytes);
    set_kek_env(&b64);
    let result = Kek::from_env();
    cleanup_env();

    match result {
        Err(auth_admin::AuthError::KekMalformed(msg)) => {
            assert!(
                msg.contains("length") && msg.contains("16"),
                "mensaje debe mencionar longitud 16, got: {msg}"
            );
        }
        other => panic!("expected Err(KekMalformed), got {other:?}"),
    }
}

// ---------------------------------------------------------------------------
// new() tests (no env, no lock needed)
// ---------------------------------------------------------------------------

#[test]
fn new_constructor_stores_correctly() {
    let key = [
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e,
        0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d,
        0x1e, 0x1f,
    ];
    let kek = Kek::new(key, 3);
    assert_eq!(kek.key, key, "new debe almacenar la key correctamente");
    assert_eq!(kek.version, 3, "new debe almacenar la version correctamente");
}

#[test]
fn version_zero_should_fail() {
    let _guard = env_lock().lock().unwrap();
    let key_bytes = [0xff; 32];
    let b64 = STANDARD.encode(key_bytes);
    set_kek_env(&b64);
    set_version_env(0);
    let result = Kek::from_env();
    cleanup_env();

    match result {
        Err(auth_admin::AuthError::KekMalformed(msg)) => {
            assert!(
                msg.contains("0"),
                "mensaje debe mencionar que version 0 es invalida, got: {msg}"
            );
        }
        other => panic!("expected Err(KekMalformed) for version 0, got {other:?}"),
    }
}
