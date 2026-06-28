//! Auth primitives for the admin panel.
//!
//! AD1 scope (real & end-to-end):
//! - Identidad staff **separada** de usuarios finales.
//! - 2FA obligatorio (TOTP) sin bypass.
//! - JWT con `aud=admin`; cross-audience rejected con 401.
//! - Audit inmutable via triggers PG (no depende de disciplina del codigo).
//!
//! AD2+ anade capacidades de dominio (ban/suspend/moderacion/NSFW/soporte/
//! GDPR/LER/planes/paises). Este crate crece solo en la medida que esos
//! endpoints compartan primitivos.
//!
//! Modulos:
//! - [`password`]: argon2id hash + verify.
//! - [`totp`]: gen secret, current_code, verify, AES-256-GCM encrypt/decrypt.
//! - [`recovery`]: 10 single-use codes, hashed.
//! - [`jwt`]: issue/verify con aud=admin, exp validation.
//! - [`mfa_token`]: pre-2FA opaque token, HMAC-signed, 15 min TTL.
//! - [`keystore`]: KEK loader desde env con version para rotacion.
//! - [`error`]: errores tipados via thiserror.

#![forbid(unsafe_code)]
#![warn(missing_docs)]

pub mod error;
pub mod jwt;
pub mod keystore;
pub mod mfa_token;
pub mod password;
pub mod recovery;
pub mod totp;

pub use error::AuthError;
