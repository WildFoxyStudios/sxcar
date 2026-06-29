use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Serialize;

/// Serialize `body` as the format preferred by the client via the `Accept` header.
///
/// - `Accept: application/msgpack` → MessagePack bytes, `Content-Type: application/msgpack`
/// - everything else (including missing `Accept`) → JSON (default)
pub fn respond(body: &impl Serialize, headers: &HeaderMap) -> Response {
    if accepts_msgpack(headers) {
        match rmp_serde::to_vec(body) {
            Ok(bytes) => Response::builder()
                .status(StatusCode::OK)
                .header(header::CONTENT_TYPE, "application/msgpack")
                .body(axum::body::Body::from(bytes))
                .unwrap()
                .into_response(),
            Err(_) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "serialization failed"})),
            )
                .into_response(),
        }
    } else {
        Json(body).into_response()
    }
}

/// Like [`respond`] but with a custom status code.
pub fn respond_with_status(
    status: StatusCode,
    body: &impl Serialize,
    headers: &HeaderMap,
) -> Response {
    if accepts_msgpack(headers) {
        match rmp_serde::to_vec(body) {
            Ok(bytes) => Response::builder()
                .status(status)
                .header(header::CONTENT_TYPE, "application/msgpack")
                .body(axum::body::Body::from(bytes))
                .unwrap()
                .into_response(),
            Err(_) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "serialization failed"})),
            )
                .into_response(),
        }
    } else {
        (status, Json(body)).into_response()
    }
}

/// Returns `true` when the `Accept` header contains `application/msgpack`.
fn accepts_msgpack(headers: &HeaderMap) -> bool {
    headers
        .get(header::ACCEPT)
        .and_then(|v| v.to_str().ok())
        .is_some_and(|v| {
            v.split(',')
                .any(|part| part.trim().eq_ignore_ascii_case("application/msgpack"))
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::HeaderValue;
    use serde::{Deserialize, Serialize};

    #[derive(Serialize, Deserialize)]
    struct TestBody {
        message: String,
        count: u32,
    }

    fn test_body() -> TestBody {
        TestBody {
            message: "hello".to_string(),
            count: 42,
        }
    }

    #[test]
    fn accepts_msgpack_header_true_when_present() {
        let mut headers = HeaderMap::new();
        headers.insert(header::ACCEPT, HeaderValue::from_static("application/msgpack"));
        assert!(accepts_msgpack(&headers));
    }

    #[test]
    fn accepts_msgpack_header_false_when_absent() {
        let headers = HeaderMap::new();
        assert!(!accepts_msgpack(&headers));
    }

    #[test]
    fn accepts_msgpack_header_false_when_json() {
        let mut headers = HeaderMap::new();
        headers.insert(header::ACCEPT, HeaderValue::from_static("application/json"));
        assert!(!accepts_msgpack(&headers));
    }

    #[test]
    fn accepts_msgpack_in_multi_value_accept() {
        let mut headers = HeaderMap::new();
        headers.insert(
            header::ACCEPT,
            HeaderValue::from_static("application/json, application/msgpack"),
        );
        assert!(accepts_msgpack(&headers));
    }

    #[tokio::test]
    async fn respond_returns_msgpack_when_accepted() {
        let mut headers = HeaderMap::new();
        headers.insert(header::ACCEPT, HeaderValue::from_static("application/msgpack"));
        let body = test_body();

        let res = respond(&body, &headers);
        assert_eq!(
            res.headers().get(header::CONTENT_TYPE).unwrap(),
            "application/msgpack"
        );

        let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
            .await
            .unwrap();
        let decoded: TestBody = rmp_serde::from_slice(&bytes).unwrap();
        assert_eq!(decoded.message, "hello");
        assert_eq!(decoded.count, 42);
    }

    #[tokio::test]
    async fn respond_defaults_to_json() {
        let headers = HeaderMap::new();
        let body = test_body();

        let res = respond(&body, &headers);
        // Default should be JSON, so Content-Type should be application/json
        let ct = res.headers().get(header::CONTENT_TYPE).unwrap().to_str().unwrap().to_lowercase();
        assert!(ct.contains("application/json") || ct.contains("json"));
    }

    #[tokio::test]
    async fn respond_with_status_uses_custom_status() {
        let mut headers = HeaderMap::new();
        headers.insert(header::ACCEPT, HeaderValue::from_static("application/json"));
        let body = TestBody {
            message: "not found".to_string(),
            count: 0,
        };

        let res = respond_with_status(StatusCode::NOT_FOUND, &body, &headers);
        assert_eq!(res.status(), StatusCode::NOT_FOUND);
    }
}
