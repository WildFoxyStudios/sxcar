//! KEK (key encryption key) loader desde env.
//!
//! Implementado en T8. Spec AD1 §1: `STAFF_TOTP_KEK` (base64, 32 bytes)
//! + `STAFF_TOTP_KEK_VERSION` (u16, default 1).
//!
//! Versionado para permitir rotacion sin re-cifrar todos los ciphertexts
//! de golpe: lazy re-wrap on next login. Cada fila guarda su `kek_version`
//! y se re-cifra cuando el staff hace login con la nueva KEK.

// TODO(T8): implementar Kek struct + load_from_env.
// Tests:
//   load_from_env_returns_kek_with_version_1
//   load_missing_env_returns_clear_error
//   load_malformed_base64_returns_error
//   rotate_returns_new_kek
