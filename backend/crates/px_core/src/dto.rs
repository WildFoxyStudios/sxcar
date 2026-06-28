use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
pub struct TokenPair {
    pub access: String,
    pub refresh: String,
}

#[derive(Serialize, Deserialize)]
pub struct RegisterReq {
    pub email: String,
    pub password: String,
    /// fecha de nacimiento YYYY-MM-DD
    pub dob: String,
    #[serde(default)]
    pub consents: Vec<String>,
}

#[derive(Serialize, Deserialize)]
pub struct LoginReq {
    pub email: String,
    pub password: String,
}

#[derive(Serialize, Deserialize)]
pub struct RefreshReq {
    pub refresh: String,
}

#[derive(Serialize, Deserialize)]
pub struct CodeReq {
    pub code: String,
}
