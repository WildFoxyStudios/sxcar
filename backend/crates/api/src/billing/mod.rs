pub mod error;
pub mod plans;
pub mod simulate;
pub mod subscriptions;

use axum::{routing::{get, post}, Router};

use crate::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/billing/plans", get(plans::list_plans))
        .route("/billing/simulate-purchase", post(simulate::simulate_purchase))
        .route("/billing/me", get(subscriptions::my_subscription))
}