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
    #[error(transparent)]
    Other(#[from] anyhow::Error),
}
