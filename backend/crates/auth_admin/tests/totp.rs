//! Tests for [`crate::totp`].
//!
//! Spec AD1 §1: TOTP SHA1, step 30s, 6 digits (compatible con Google
//! Authenticator / 1Password / Authy). El secret se cifra en reposo con
//! AES-256-GCM (key via [`crate::keystore::Kek`]).
//!
//! Formato del blob cifrado (todo en un solo `Vec<u8>`):
//!   [ nonce: 12 bytes | ciphertext+tag: N+16 bytes ]
//! Overhead total: 28 bytes sobre plaintext.

use auth_admin::totp::{current_code, decrypt_secret, encrypt_secret, gen_secret, verify_code};

const TEST_KEK: [u8; 32] = [
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
    0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f,
];

#[test]
fn gen_secret_returns_32_chars_base32_alphabet() {
    // RFC 6238 recomienda >= 160 bits. Usamos lo que totp-rs::generate_secret
    // produce por default: 20 bytes = 32 chars base32 sin padding.
    let secret_b32 = gen_secret();
    assert_eq!(secret_b32.len(), 32, "secret = 20 bytes = 32 chars base32");
    assert!(
        secret_b32
            .chars()
            .all(|c| "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".contains(c)),
        "secret debe ser base32 alphabet RFC 4648, got '{secret_b32}'"
    );
}

#[test]
fn gen_secret_produces_unique_values() {
    let s1 = gen_secret();
    let s2 = gen_secret();
    assert_ne!(s1, s2, "cada gen_secret debe producir valor unico (OsRng)");
}

#[test]
fn current_code_is_6_digits() {
    let secret_b32 = gen_secret();
    let code = current_code(&secret_b32).expect("current_code");
    assert_eq!(code.len(), 6, "TOTP code debe ser 6 digitos");
    assert!(
        code.chars().all(|c| c.is_ascii_digit()),
        "TOTP code debe ser solo digitos, got '{code}'"
    );
}

#[test]
fn verify_accepts_correct_code_within_window() {
    let secret_b32 = gen_secret();
    let code = current_code(&secret_b32).expect("current_code");
    assert!(verify_code(&secret_b32, &code, 1).expect("verify correct"));
}

#[test]
fn verify_rejects_wrong_code() {
    let secret_b32 = gen_secret();
    let wrong = "000000".to_string();
    let correct = current_code(&secret_b32).expect("current_code");
    if wrong == correct {
        // Probabilidad astronomicamente baja; reintentar.
        return;
    }
    assert!(!verify_code(&secret_b32, &wrong, 1).expect("verify wrong"));
}

#[test]
fn verify_window_zero_accepts_only_current() {
    let secret_b32 = gen_secret();
    let code_now = current_code(&secret_b32).expect("current_code");
    // Con window=0, el codigo actual debe ser aceptado.
    assert!(verify_code(&secret_b32, &code_now, 0).expect("window=0 acepta current"));
    // Con window=0, un codigo claramente falso NO debe ser aceptado.
    let fake = "111111".to_string();
    if fake != code_now {
        assert!(!verify_code(&secret_b32, &fake, 0).expect("window=0 rechaza fake"));
    }
}

#[test]
fn encrypt_then_decrypt_roundtrips() {
    let secret_b32 = gen_secret();
    let ciphertext = encrypt_secret(&TEST_KEK, secret_b32.as_bytes()).expect("encrypt");
    let plaintext = decrypt_secret(&TEST_KEK, &ciphertext).expect("decrypt");
    assert_eq!(plaintext, secret_b32.as_bytes(), "roundtrip exacto");
}

#[test]
fn ciphertext_overhead_is_28_bytes() {
    // Overhead esperado: nonce (12) + GCM tag (16) = 28 bytes.
    // Si este test rompe, alguien cambio el formato del blob — update spec.
    let secret_b32 = gen_secret();
    let ciphertext = encrypt_secret(&TEST_KEK, secret_b32.as_bytes()).expect("encrypt");
    let expected_len = secret_b32.len() + 28;
    assert_eq!(
        ciphertext.len(),
        expected_len,
        "blob cifrado = plaintext + 28 bytes (nonce 12 + tag 16)"
    );
}

#[test]
fn ciphertext_is_unique_per_encryption() {
    let secret_b32 = gen_secret();
    let c1 = encrypt_secret(&TEST_KEK, secret_b32.as_bytes()).expect("encrypt 1");
    let c2 = encrypt_secret(&TEST_KEK, secret_b32.as_bytes()).expect("encrypt 2");
    assert_ne!(c1, c2, "nonce aleatorio -> ciphertexts distintos");
}

#[test]
fn decrypt_with_wrong_key_fails() {
    let secret_b32 = gen_secret();
    let ciphertext = encrypt_secret(&TEST_KEK, secret_b32.as_bytes()).expect("encrypt");

    let mut wrong_key = TEST_KEK;
    wrong_key[0] ^= 0xff; // flip one bit

    let result = decrypt_secret(&wrong_key, &ciphertext);
    assert!(
        result.is_err(),
        "decrypt con KEK incorrecta debe fallar (GCM tag mismatch), got {result:?}"
    );
}

#[test]
fn decrypt_with_truncated_ciphertext_fails() {
    let secret_b32 = gen_secret();
    let ciphertext = encrypt_secret(&TEST_KEK, secret_b32.as_bytes()).expect("encrypt");
    let truncated = &ciphertext[..ciphertext.len() / 2];
    let result = decrypt_secret(&TEST_KEK, truncated);
    assert!(result.is_err(), "truncated ciphertext debe fallar");
}
