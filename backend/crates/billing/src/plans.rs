// TODO: filled in task 1.3
use axum::Json;
use serde_json::{json, Value};

// Stub handler so the router compiles. Replaced in task 1.3.
pub async fn list_plans() -> Json<Value> {
    Json(json!({ "plans": [] }))
}