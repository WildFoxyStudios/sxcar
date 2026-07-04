use axum::{http::StatusCode, response::IntoResponse, Json};
use serde_json::json;

#[derive(thiserror::Error, Debug)]
pub enum BillingError {
    #[error("plan not found")]
    PlanNotFound,
    #[error("active subscription already exists for tier")]
    AlreadyActive,
    #[error("unauthorized")]
    Unauthorized,
    #[error("database error: {0}")]
    Db(#[from] sqlx::Error),
}

impl IntoResponse for BillingError {
    fn into_response(self) -> axum::response::Response {
        let (status, code) = match &self {
            BillingError::PlanNotFound => (StatusCode::NOT_FOUND, "plan_not_found"),
            BillingError::AlreadyActive => (StatusCode::CONFLICT, "already_active"),
            BillingError::Unauthorized => (StatusCode::UNAUTHORIZED, "unauthorized"),
            BillingError::Db(_) => (StatusCode::INTERNAL_SERVER_ERROR, "db_error"),
        };
        (status, Json(json!({"error": code, "message": self.to_string()}))).into_response()
    }
}

pub type BillingResult<T> = Result<T, BillingError>;