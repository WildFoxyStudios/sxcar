//! Capa CORS para clientes web (Expo web, futura app RN-web, sitio de marketing).
//!
//! Seguridad: lista de orígenes EXPLÍCITA (sin `*`) y SIN `allow_credentials`
//! (la auth es por Bearer en el header `Authorization`, no por cookies). En
//! desarrollo se permiten orígenes `localhost`/`127.0.0.1` por conveniencia.
//! La lista de producción es configurable con `CORS_ALLOWED_ORIGINS`
//! (separada por comas), p.ej. `https://turnend.win,https://app.turnend.win`.

use std::time::Duration;

use axum::http::{header, request::Parts, HeaderValue, Method};
use tower_http::cors::{AllowOrigin, CorsLayer};

/// Orígenes permitidos por defecto cuando `CORS_ALLOWED_ORIGINS` no está definido.
const DEFAULT_ORIGINS: &[&str] = &[
    "https://turnend.win",
    "https://www.turnend.win",
    "https://app.turnend.win",
];

/// `true` si el origen es localhost/127.0.0.1 (cualquier puerto, http) — solo dev.
fn is_localhost(origin: &[u8]) -> bool {
    match std::str::from_utf8(origin) {
        Ok(s) => {
            s == "http://localhost"
                || s == "http://127.0.0.1"
                || s.starts_with("http://localhost:")
                || s.starts_with("http://127.0.0.1:")
        }
        Err(_) => false,
    }
}

fn allowed_origins() -> Vec<String> {
    match std::env::var("CORS_ALLOWED_ORIGINS") {
        Ok(v) if !v.trim().is_empty() => v
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect(),
        _ => DEFAULT_ORIGINS.iter().map(|s| s.to_string()).collect(),
    }
}

/// Construye la `CorsLayer` a aplicar como capa externa del router.
pub fn cors_layer() -> CorsLayer {
    let configured = allowed_origins();
    CorsLayer::new()
        .allow_origin(AllowOrigin::predicate(
            move |origin: &HeaderValue, _: &Parts| {
                let o = origin.as_bytes();
                configured.iter().any(|c| c.as_bytes() == o) || is_localhost(o)
            },
        ))
        .allow_methods([
            Method::GET,
            Method::POST,
            Method::PUT,
            Method::DELETE,
            Method::PATCH,
            Method::OPTIONS,
        ])
        .allow_headers([header::AUTHORIZATION, header::CONTENT_TYPE])
        .max_age(Duration::from_secs(3600))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{body::Body, http::Request, http::StatusCode, routing::get, Router};
    use tower::ServiceExt;

    fn test_app() -> Router {
        Router::new()
            .route("/x", get(|| async { "ok" }))
            .layer(cors_layer())
    }

    #[tokio::test]
    async fn preflight_allows_localhost_origin() {
        let res = test_app()
            .oneshot(
                Request::builder()
                    .method("OPTIONS")
                    .uri("/x")
                    .header("origin", "http://localhost:8081")
                    .header("access-control-request-method", "POST")
                    .header("access-control-request-headers", "authorization,content-type")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let allow = res
            .headers()
            .get("access-control-allow-origin")
            .map(|v| v.to_str().unwrap().to_string());
        assert_eq!(allow.as_deref(), Some("http://localhost:8081"));
    }

    #[tokio::test]
    async fn preflight_allows_configured_prod_origin() {
        let res = test_app()
            .oneshot(
                Request::builder()
                    .method("OPTIONS")
                    .uri("/x")
                    .header("origin", "https://turnend.win")
                    .header("access-control-request-method", "POST")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            res.headers()
                .get("access-control-allow-origin")
                .and_then(|v| v.to_str().ok()),
            Some("https://turnend.win")
        );
    }

    #[tokio::test]
    async fn blocks_unknown_origin() {
        let res = test_app()
            .oneshot(
                Request::builder()
                    .method("OPTIONS")
                    .uri("/x")
                    .header("origin", "https://evil.example")
                    .header("access-control-request-method", "POST")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        // Sin cabecera allow-origin para un origen no permitido.
        assert!(res
            .headers()
            .get("access-control-allow-origin")
            .is_none());
        // La respuesta del preflight en sí no es un error del servidor.
        assert_ne!(res.status(), StatusCode::INTERNAL_SERVER_ERROR);
    }
}
