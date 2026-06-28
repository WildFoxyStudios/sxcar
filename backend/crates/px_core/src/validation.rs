use time::Date;

/// Validación de email mínima (la verificación real es por código de email).
pub fn valid_email(s: &str) -> bool {
    let mut parts = s.split('@');
    match (parts.next(), parts.next(), parts.next()) {
        (Some(local), Some(domain), None) => {
            !local.is_empty()
                && domain.contains('.')
                && !domain.starts_with('.')
                && !domain.ends_with('.')
        }
        _ => false,
    }
}

/// Edad en años cumplidos a `today`.
pub fn age(dob: Date, today: Date) -> i32 {
    let mut years = today.year() - dob.year();
    if (today.month() as u8, today.day()) < (dob.month() as u8, dob.day()) {
        years -= 1;
    }
    years
}

/// True si `dob` implica 18 años cumplidos a `today`.
pub fn is_adult(dob: Date, today: Date) -> bool {
    age(dob, today) >= 18
}

/// Validación de contraseña: mínimo 8 caracteres.
pub fn valid_password(s: &str) -> bool {
    s.len() >= 8
}

#[cfg(test)]
mod tests {
    use super::*;
    use time::macros::date;

    #[test]
    fn age_gate() {
        let today = date!(2026 - 06 - 26);
        assert!(is_adult(date!(2008 - 06 - 26), today)); // exactamente 18
        assert!(!is_adult(date!(2008 - 06 - 27), today)); // 17 (cumple mañana)
        assert!(is_adult(date!(1990 - 01 - 01), today));
        assert_eq!(age(date!(2000 - 06 - 26), today), 26);
    }

    #[test]
    fn test_valid_email_valid() {
        assert!(valid_email("user@example.com"));
    }

    #[test]
    fn test_valid_email_no_at() {
        assert!(!valid_email("userexample.com"));
    }

    #[test]
    fn test_valid_password_valid() {
        assert!(valid_password("password123"));
    }

    #[test]
    fn test_valid_password_too_short() {
        assert!(!valid_password("1234567"));
    }

    #[test]
    fn test_valid_password_exactly_eight() {
        assert!(valid_password("12345678"));
    }
}
