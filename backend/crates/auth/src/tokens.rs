use rand::RngCore;
use sha2::{Digest, Sha256};

/// Refresh token opaco (256 bits, hex).
pub fn generate_refresh() -> String {
    let mut bytes = [0u8; 32];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    hex_lower(&bytes)
}

/// Hash hex (SHA-256) del token para guardarlo.
pub fn hash_token(token: &str) -> String {
    hex_lower(&Sha256::digest(token.as_bytes()))
}

fn hex_lower(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refresh_is_unique_and_hashable() {
        let a = generate_refresh();
        let b = generate_refresh();
        assert_eq!(a.len(), 64);
        assert_ne!(a, b);
        assert_eq!(hash_token(&a), hash_token(&a));
        assert_ne!(hash_token(&a), hash_token(&b));
    }
}
