use rand::Rng;
use sha2::{Digest, Sha256};

/// Código numérico de 6 dígitos.
pub fn generate_code() -> String {
    let n: u32 = rand::thread_rng().gen_range(0..1_000_000);
    format!("{n:06}")
}

/// Hash hex (SHA-256) del código para guardarlo.
pub fn hash_code(code: &str) -> String {
    let digest = Sha256::digest(code.as_bytes());
    hex_lower(&digest)
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
    fn code_is_6_digits_and_hash_stable() {
        let c = generate_code();
        assert_eq!(c.len(), 6);
        assert!(c.chars().all(|ch| ch.is_ascii_digit()));
        assert_eq!(hash_code("123456"), hash_code("123456"));
        assert_ne!(hash_code("123456"), hash_code("000000"));
    }
}
