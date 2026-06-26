use time::Date;

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
}
