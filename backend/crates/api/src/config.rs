#[derive(Clone, Debug)]
pub struct Config {
    pub database_url: String,
    pub bind_addr: String,
    pub jwt_secret: String,
    pub access_ttl_secs: i64,
    pub refresh_ttl_secs: i64,
}

impl Config {
    pub fn from_env() -> anyhow::Result<Self> {
        Self::from_getter(|k| std::env::var(k).ok())
    }

    pub fn from_getter(get: impl Fn(&str) -> Option<String>) -> anyhow::Result<Self> {
        let database_url =
            get("DATABASE_URL").ok_or_else(|| anyhow::anyhow!("DATABASE_URL must be set"))?;
        let bind_addr = get("BIND_ADDR").unwrap_or_else(|| "0.0.0.0:8080".to_string());
        // SECURITY (P0): JWT_SECRET MUST be provided in production. Failing
        // closed here prevents the server from silently booting with a
        // publicly-known signing key if the env var is missing. In debug/test
        // builds we keep the dev default so local workflows and unit tests
        // don't require it.
        let jwt_secret = match get("JWT_SECRET") {
            Some(s) => s,
            None => {
                if cfg!(debug_assertions) {
                    "dev-secret-change-me".to_string()
                } else {
                    anyhow::bail!("JWT_SECRET must be set");
                }
            }
        };
        let access_ttl_secs = get("ACCESS_TTL_SECS")
            .and_then(|v| v.parse().ok())
            .unwrap_or(900);
        let refresh_ttl_secs = get("REFRESH_TTL_SECS")
            .and_then(|v| v.parse().ok())
            .unwrap_or(2_592_000);
        Ok(Self {
            database_url,
            bind_addr,
            jwt_secret,
            access_ttl_secs,
            refresh_ttl_secs,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_bind_addr_when_unset() {
        let c = Config::from_getter(|k| match k {
            "DATABASE_URL" => Some("postgres://x".into()),
            _ => None,
        })
        .unwrap();
        assert_eq!(c.database_url, "postgres://x");
        assert_eq!(c.bind_addr, "0.0.0.0:8080");
    }

    #[test]
    fn errors_without_database_url() {
        assert!(Config::from_getter(|_| None).is_err());
    }
}
