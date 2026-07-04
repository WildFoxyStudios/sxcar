pub mod error;
pub mod plans;
pub mod subscriptions;
pub mod simulate;

use axum::{routing::{get, post}, Router};

pub fn router() -> Router<api::AppState> {
    Router::new()
        .route("/billing/plans", get(plans::list_plans))
        .route("/billing/simulate-purchase", post(simulate::simulate_purchase))
        .route("/billing/me", get(subscriptions::my_subscription))
}