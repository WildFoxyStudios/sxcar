//! Recovery codes (10 single-use, hashed at rest).
//!
//! Implementado en T5. Spec AD1 §1: 10 codes sin ambiguedad visual
//! (sin 0/O, 1/I/L), hashed con argon2id, single-use.

// TODO(T5): implementar gen, hash, verify_and_consume.
// Tests:
//   gen_returns_10_codes_crockford_base32_like_format
//   hash_and_verify_roundtrips
//   verify_wrong_code_returns_false
//   verify_empty_input_returns_error
