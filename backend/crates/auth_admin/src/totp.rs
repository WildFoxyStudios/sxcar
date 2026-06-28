//! TOTP (RFC 6238) + AES-256-GCM encryption for at-rest TOTP secrets.
//!
//! Implementado en T4. Spec AD1 §1: TOTP SHA1, step 30s, 6 digits
//! (compatible con Google Authenticator / 1Password / Authy). El secret
//! se cifra en reposo (AES-256-GCM, key via [`crate::keystore::Kek`]).

// TODO(T4): implementar gen_secret, current_code, verify, encrypt, decrypt.
// Tests:
//   gen_secret_returns_32_bytes_base32
//   current_code_is_6_digits
//   verify_accepts_correct_code_within_window
//   verify_rejects_old_code_outside_window
//   encrypt_then_decrypt_roundtrips
//   decrypt_with_wrong_key_fails
