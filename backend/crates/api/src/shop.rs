use axum::{extract::State, http::StatusCode, routing::post, Json, Router};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::auth::AuthUser;
use crate::AppState;

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// A product in the in-app merchandise store.
#[derive(Debug, Serialize, Deserialize)]
pub struct ShopProduct {
    pub id: String,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub price_usd: f64,
    #[serde(rename = "type")]
    pub product_type: String,
    pub revenuecat_id: String,
}

// ---------------------------------------------------------------------------
// Static catalog
// ---------------------------------------------------------------------------

fn catalog() -> Vec<ShopProduct> {
    vec![
        ShopProduct {
            id: "boost_1h".into(),
            name: "1 Hour Boost".into(),
            description: Some("Get seen by 10x more profiles".into()),
            price_usd: 1.99,
            product_type: "boost".into(),
            revenuecat_id: "boost_1h".into(),
        },
        ShopProduct {
            id: "boost_4h".into(),
            name: "4 Hour Boost".into(),
            description: None,
            price_usd: 4.99,
            product_type: "boost".into(),
            revenuecat_id: "boost_4h".into(),
        },
        ShopProduct {
            id: "boost_24h".into(),
            name: "24 Hour Boost".into(),
            description: None,
            price_usd: 9.99,
            product_type: "boost".into(),
            revenuecat_id: "boost_24h".into(),
        },
        ShopProduct {
            id: "highlight_1w".into(),
            name: "Profile Highlight".into(),
            description: Some("Stand out with a highlighted profile card".into()),
            price_usd: 3.99,
            product_type: "highlight".into(),
            revenuecat_id: "highlight_1w".into(),
        },
        ShopProduct {
            id: "tribe_extra".into(),
            name: "Extra Tribe Slot".into(),
            description: Some("Add one more tribe to your profile".into()),
            price_usd: 0.99,
            product_type: "tribe_slot".into(),
            revenuecat_id: "tribe_extra".into(),
        },
    ]
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

/// `GET /shop/products` — returns the static product catalog.
///
/// No authentication required so the catalog can be shown before login.
pub async fn list_products() -> Json<Value> {
    Json(json!({ "products": catalog() }))
}

/// `POST /shop/purchase` — validates the purchase intent for a product.
///
/// Expects `{ "product_id": "boost_1h" }`. Returns the product info and an
/// acknowledgement so the client can proceed with the RevenueCat purchase.
///
/// Authentication *is* required — only authenticated users can initiate
/// purchases so we can attribute them.
pub async fn purchase(
    AuthUser(_user_id): AuthUser,
    State(_state): State<AppState>,
    Json(body): Json<Value>,
) -> Result<Json<Value>, StatusCode> {
    let product_id = body
        .get("product_id")
        .and_then(|v| v.as_str())
        .ok_or(StatusCode::BAD_REQUEST)?;

    // Validate that the product exists in the catalog.
    let found = catalog().into_iter().find(|p| p.id == product_id);

    match found {
        Some(product) => Ok(Json(json!({
            "success": true,
            "product": product,
            "message": "Proceed with RevenueCat purchase using the product's revenuecat_id"
        }))),
        None => Err(StatusCode::NOT_FOUND),
    }
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/shop/products", axum::routing::get(list_products))
        .route("/shop/purchase", post(purchase))
}
