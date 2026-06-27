//! Media: URLs presignadas (AWS SigV4) para subir/leer objetos en Cloudflare R2
//! directamente desde el cliente, sin que los bytes pasen por el API.
//!
//! Implementación SigV4 mínima (sin SDK pesado de AWS): solo firma el header
//! `host` con payload `UNSIGNED-PAYLOAD`, que es lo que R2 espera para URLs
//! presignadas. La corrección de la firma se valida E2E contra R2.

use axum::{extract::State, http::StatusCode, routing::post, Json, Router};
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use time::OffsetDateTime;

use crate::AppState;

type HmacSha256 = Hmac<Sha256>;

/// Config de R2 leída del entorno. `None` si faltan credenciales.
#[derive(Clone)]
pub struct R2Config {
    pub endpoint: String,
    pub access_key: String,
    pub secret_key: String,
    pub region: String,
    pub bucket_media: String,
    pub bucket_private: String,
    pub bucket_verification: String,
}

impl R2Config {
    pub fn from_env() -> Option<Self> {
        let endpoint = std::env::var("R2_S3_ENDPOINT").ok()?;
        let access_key = std::env::var("R2_ACCESS_KEY_ID").ok()?;
        let secret_key = std::env::var("R2_SECRET_ACCESS_KEY").ok()?;
        if endpoint.is_empty() || access_key.is_empty() || secret_key.is_empty() {
            return None;
        }
        Some(Self {
            endpoint: endpoint.trim_end_matches('/').to_string(),
            access_key,
            secret_key,
            region: std::env::var("R2_REGION").unwrap_or_else(|_| "auto".into()),
            bucket_media: std::env::var("R2_BUCKET_MEDIA")
                .unwrap_or_else(|_| "proyectox-media".into()),
            bucket_private: std::env::var("R2_BUCKET_PRIVATE")
                .unwrap_or_else(|_| "proyectox-private".into()),
            bucket_verification: std::env::var("R2_BUCKET_VERIFICATION")
                .unwrap_or_else(|_| "proyectox-verification".into()),
        })
    }
}

fn hex_lower(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

fn hmac_sha256(key: &[u8], data: &[u8]) -> Vec<u8> {
    let mut mac = HmacSha256::new_from_slice(key).expect("HMAC acepta cualquier longitud de clave");
    mac.update(data);
    mac.finalize().into_bytes().to_vec()
}

fn sha256_hex(data: &[u8]) -> String {
    hex_lower(&Sha256::digest(data))
}

/// URI-encode estilo AWS (RFC 3986). `encode_slash=false` deja `/` (rutas).
fn uri_encode(s: &str, encode_slash: bool) -> String {
    let mut out = String::with_capacity(s.len());
    for &b in s.as_bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                out.push(b as char)
            }
            b'/' if !encode_slash => out.push('/'),
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

fn amz_timestamps(now: OffsetDateTime) -> (String, String) {
    let m = u8::from(now.month());
    let amzdate = format!(
        "{:04}{:02}{:02}T{:02}{:02}{:02}Z",
        now.year(),
        m,
        now.day(),
        now.hour(),
        now.minute(),
        now.second()
    );
    let datestamp = format!("{:04}{:02}{:02}", now.year(), m, now.day());
    (amzdate, datestamp)
}

/// URL presignada SigV4 (auth por query string) para `method` sobre `bucket/key`.
pub fn presign(
    cfg: &R2Config,
    method: &str,
    bucket: &str,
    key: &str,
    expires: u32,
    now: OffsetDateTime,
) -> String {
    let host = cfg.endpoint.strip_prefix("https://").unwrap_or(&cfg.endpoint);
    let (amzdate, datestamp) = amz_timestamps(now);
    let scope = format!("{datestamp}/{}/s3/aws4_request", cfg.region);
    let credential = format!("{}/{scope}", cfg.access_key);
    let canonical_uri = format!("/{}/{}", bucket, uri_encode(key, false));

    // Parámetros de firma, ordenados por clave.
    let mut params = [
        ("X-Amz-Algorithm", "AWS4-HMAC-SHA256".to_string()),
        ("X-Amz-Credential", credential),
        ("X-Amz-Date", amzdate.clone()),
        ("X-Amz-Expires", expires.to_string()),
        ("X-Amz-SignedHeaders", "host".to_string()),
    ];
    params.sort_by(|a, b| a.0.cmp(b.0));
    let canonical_query = params
        .iter()
        .map(|(k, v)| format!("{}={}", uri_encode(k, true), uri_encode(v, true)))
        .collect::<Vec<_>>()
        .join("&");

    // CanonicalHeaders="host:H\n", luego \n, SignedHeaders="host", payload=UNSIGNED-PAYLOAD.
    let canonical_request =
        format!("{method}\n{canonical_uri}\n{canonical_query}\nhost:{host}\n\nhost\nUNSIGNED-PAYLOAD");

    let string_to_sign = format!(
        "AWS4-HMAC-SHA256\n{amzdate}\n{scope}\n{}",
        sha256_hex(canonical_request.as_bytes())
    );

    let k_date = hmac_sha256(format!("AWS4{}", cfg.secret_key).as_bytes(), datestamp.as_bytes());
    let k_region = hmac_sha256(&k_date, cfg.region.as_bytes());
    let k_service = hmac_sha256(&k_region, b"s3");
    let k_signing = hmac_sha256(&k_service, b"aws4_request");
    let signature = hex_lower(&hmac_sha256(&k_signing, string_to_sign.as_bytes()));

    format!("{}{canonical_uri}?{canonical_query}&X-Amz-Signature={signature}", cfg.endpoint)
}

#[derive(Deserialize)]
pub struct UploadUrlReq {
    /// "profile" (público), "album" (privado) o "verification".
    pub kind: String,
    /// Extensión opcional (jpg, png, …); se sanea.
    pub ext: Option<String>,
}

#[derive(Serialize)]
pub struct UploadUrlRes {
    pub key: String,
    pub bucket: String,
    pub put_url: String,
    pub get_url: String,
    pub expires_in: u32,
}

fn sanitize_ext(ext: Option<&str>) -> String {
    match ext {
        Some(e) => {
            let e = e.trim_start_matches('.').to_lowercase();
            if !e.is_empty() && e.len() <= 5 && e.chars().all(|c| c.is_ascii_alphanumeric()) {
                e
            } else {
                "bin".to_string()
            }
        }
        None => "bin".to_string(),
    }
}

/// Devuelve una URL presignada PUT (subida directa) + GET (lectura) para el
/// usuario autenticado. El objeto se enruta al bucket según `kind`.
pub async fn upload_url(
    State(state): State<AppState>,
    user: crate::auth::AuthUser,
    Json(req): Json<UploadUrlReq>,
) -> Result<Json<UploadUrlRes>, StatusCode> {
    let cfg = state.r2.as_ref().ok_or(StatusCode::SERVICE_UNAVAILABLE)?;
    let bucket = match req.kind.as_str() {
        "profile" => &cfg.bucket_media,
        "album" => &cfg.bucket_private,
        "verification" => &cfg.bucket_verification,
        _ => return Err(StatusCode::BAD_REQUEST),
    };
    let ext = sanitize_ext(req.ext.as_deref());
    let id = uuid::Uuid::new_v4();
    let key = format!("{}/{}/{id}.{ext}", req.kind, user.0);
    let now = OffsetDateTime::now_utc();
    let put_url = presign(cfg, "PUT", bucket, &key, 300, now);
    let get_url = presign(cfg, "GET", bucket, &key, 3600, now);
    Ok(Json(UploadUrlRes {
        key,
        bucket: bucket.clone(),
        put_url,
        get_url,
        expires_in: 300,
    }))
}

pub fn router() -> Router<AppState> {
    Router::new().route("/media/upload-url", post(upload_url))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cfg() -> R2Config {
        R2Config {
            endpoint: "https://acct.r2.cloudflarestorage.com".into(),
            access_key: "AKID".into(),
            secret_key: "SECRET".into(),
            region: "auto".into(),
            bucket_media: "m".into(),
            bucket_private: "p".into(),
            bucket_verification: "v".into(),
        }
    }

    #[test]
    fn uri_encode_paths_and_values() {
        assert_eq!(uri_encode("a/b c", false), "a/b%20c");
        assert_eq!(uri_encode("a/b c", true), "a%2Fb%20c");
        assert_eq!(uri_encode("AZaz09-._~", true), "AZaz09-._~");
    }

    #[test]
    fn sanitize_ext_rules() {
        assert_eq!(sanitize_ext(Some(".JPG")), "jpg");
        assert_eq!(sanitize_ext(Some("png")), "png");
        assert_eq!(sanitize_ext(Some("../etc")), "bin");
        assert_eq!(sanitize_ext(None), "bin");
    }

    #[test]
    fn presign_structure() {
        let now = OffsetDateTime::from_unix_timestamp(1_700_000_000).unwrap();
        let url = presign(&cfg(), "PUT", "m", "profile/u/x.jpg", 300, now);
        assert!(url.starts_with("https://acct.r2.cloudflarestorage.com/m/profile/u/x.jpg?"));
        assert!(url.contains("X-Amz-Algorithm=AWS4-HMAC-SHA256"));
        assert!(url.contains("X-Amz-Credential=AKID%2F"));
        assert!(url.contains("X-Amz-Date="));
        assert!(url.contains("X-Amz-Expires=300"));
        assert!(url.contains("X-Amz-SignedHeaders=host"));
        assert!(url.contains("&X-Amz-Signature="));
    }

    #[test]
    fn presign_is_deterministic() {
        let now = OffsetDateTime::from_unix_timestamp(1_700_000_000).unwrap();
        assert_eq!(
            presign(&cfg(), "GET", "m", "k", 60, now),
            presign(&cfg(), "GET", "m", "k", 60, now)
        );
    }
}
