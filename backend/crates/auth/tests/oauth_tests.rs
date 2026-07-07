use auth::oauth::OAuthVerifierChoice;

#[test]
fn dev_oauth_requires_env_opt_in() {
    std::env::remove_var("OAUTH_GOOGLE_CLIENT_ID");
    std::env::remove_var("DEV_OAUTH_ENABLED");
    let result = OAuthVerifierChoice::from_env();
    assert!(
        result.is_none(),
        "DevOAuthVerifier must not be the default when OAUTH_GOOGLE_CLIENT_ID is absent"
    );
}

#[test]
fn dev_oauth_allowed_when_opted_in() {
    std::env::remove_var("OAUTH_GOOGLE_CLIENT_ID");
    std::env::set_var("DEV_OAUTH_ENABLED", "true");
    let result = OAuthVerifierChoice::from_env();
    assert!(
        result.is_some(),
        "DevOAuthVerifier must be returned when DEV_OAUTH_ENABLED=true"
    );
}

#[test]
fn real_oauth_used_when_google_client_id_set() {
    std::env::set_var("OAUTH_GOOGLE_CLIENT_ID", "test-google-id");
    std::env::set_var("OAUTH_APPLE_CLIENT_ID", "test-apple-id");
    let result = OAuthVerifierChoice::from_env();
    assert!(
        result.is_some(),
        "RealOAuthVerifier must be returned when OAUTH_GOOGLE_CLIENT_ID is set"
    );
    if let Some(v) = result {
        match v {
            OAuthVerifierChoice::Real(_) => {} // expected
            OAuthVerifierChoice::Dev(_) => {
                panic!("Expected RealOAuthVerifier but got DevOAuthVerifier");
            }
        }
    }
}
