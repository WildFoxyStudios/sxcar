// TODO: filled in task 1.4
use axum::Json;
use serde_json::{json, Value};

// Stub handler so the router compiles. Replaced in task 1.4.
pub async fn my_subscription() -> Json<Value> {
    Json(json!({ "subscription": null }))
}