#[derive(Debug, thiserror::Error)]
pub enum AuthError {
    #[error("invalid credentials")]
    InvalidCredentials,
    #[error("token invalid or expired")]
    InvalidToken,
    #[error("under minimum age")]
    UnderAge,
    #[error("hashing error")]
    Hashing,
    #[error("notification error: {0}")]
    Notify(String),
    #[error("OAuth error: {0}")]
    OAuth(String),
    #[error(transparent)]
    Other(#[from] anyhow::Error),
}
