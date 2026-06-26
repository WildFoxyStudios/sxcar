use argon2::password_hash::{
    rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString,
};
use argon2::Argon2;

use crate::error::AuthError;

/// Hashea una contraseña con argon2id.
pub fn hash_password(password: &str) -> Result<String, AuthError> {
    let salt = SaltString::generate(&mut OsRng);
    let hash = Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map_err(|_| AuthError::Hashing)?
        .to_string();
    Ok(hash)
}

/// Verifica una contraseña contra su hash argon2id.
pub fn verify_password(hash: &str, password: &str) -> Result<bool, AuthError> {
    let parsed = PasswordHash::new(hash).map_err(|_| AuthError::Hashing)?;
    Ok(Argon2::default()
        .verify_password(password.as_bytes(), &parsed)
        .is_ok())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash_and_verify_roundtrip() {
        let h = hash_password("s3cr3t!").unwrap();
        assert!(h.starts_with("$argon2id$"));
        assert!(verify_password(&h, "s3cr3t!").unwrap());
        assert!(!verify_password(&h, "wrong").unwrap());
    }
}
