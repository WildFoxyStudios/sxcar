//! mfa_token opaco pre-2FA (15 min TTL).
//!
//! Implementado en T7. Spec AD1 §3.1: el flujo de login es email+password
//! -> mfa_token -> TOTP -> JWT. El mfa_token es opaco (no JWT) porque
//! NO debe ser usable como access token — solo prueba que el password
//! paso y habilita la ventana de 15 min para que el usuario ingrese el
//! codigo TOTP. HMAC-SHA256 firmado, base64url.

// TODO(T7): implementar issue y verify.
// Tests:
//   issue_returns_32_byte_base64url
//   verify_accepts_within_15min
//   verify_rejects_after_15min
//   verify_rejects_tampered
//   different_payloads_yield_different_tokens
