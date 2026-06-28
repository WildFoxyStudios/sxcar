//! JWT issue/verify con aud=admin.
//!
//! Implementado en T6. Spec AD1 §1: HS256, claim `aud = "admin"`.
//! Cross-audience (`aud = "app"`) rechazado en verify — el handler en
//! `api::admin::extractors::StaffAuth` lo convierte a 401 (no 403).

// TODO(T6): implementar issue_admin_jwt y verify_admin_jwt.
// Tests:
//   issue_admin_jwt_includes_aud_admin
//   verify_admin_jwt_accepts_admin_token
//   verify_admin_jwt_rejects_app_token_with_wrong_aud
//   verify_rejects_expired_token
//   verify_rejects_tampered_signature
