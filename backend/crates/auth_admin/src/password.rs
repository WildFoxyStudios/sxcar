//! argon2id password hashing.
//!
//! Implementado en T3. Spec AD1 §1: argon2id con params m=64MB, t=3, p=1.

// TODO(T3): implementar hash() y verify() con los 4 tests:
//   hash_deterministic_per_instance_but_unique_per_password
//   verify_correct_password
//   verify_wrong_password_returns_false
//   verify_malformed_hash_returns_error
