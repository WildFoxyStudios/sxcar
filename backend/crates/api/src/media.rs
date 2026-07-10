//! Media: URLs presignadas (AWS SigV4) para subir/leer objetos en Cloudflare R2
//! directamente desde el cliente, sin que los bytes pasen por el API.
//!
//! Implementación SigV4 mínima (sin SDK pesado de AWS): solo firma el header
//! `host` con payload `UNSIGNED-PAYLOAD`, que es lo que R2 espera para URLs
//! presignadas. La corrección de la firma se valida E2E contra R2.

use axum::{extract::{Path, Query, State}, http::StatusCode, routing::{delete, get, post, put}, Json, Router};
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::{Digest, Sha256};
use time::OffsetDateTime;
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::AppState;

pub mod renditions;

type HmacSha256 = Hmac<Sha256>;

/// Presign lifetime for PRIVATE media (album, verification): 1 hour. Short so a
/// leaked URL is only briefly usable. Public profile/story photos keep a longer
/// TTL because their URLs are handed out widely and cached by clients.
const PRIVATE_PRESIGN_EXPIRY: u32 = 3600;
/// Presign lifetime for public media (profile/story) served via `get_url`.
const PUBLIC_PRESIGN_EXPIRY: u32 = 3600;

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
    // `X-Amz-Content-Sha256=UNSIGNED-PAYLOAD` es OBLIGATORIO en query string para
    // PUT presignados en R2 (mismo comportamiento que AWS S3). Sin él, R2 devuelve
    // 403 SignatureDoesNotMatch al subir; GET funciona sin él porque no hay payload.
    let mut params = [
        ("X-Amz-Algorithm", "AWS4-HMAC-SHA256".to_string()),
        ("X-Amz-Content-Sha256", "UNSIGNED-PAYLOAD".to_string()),
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
    /// "profile" (público), "album" (privado), "verification" o "story".
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

// ---------------------------------------------------------------------------
// POST /media/photos — create photo record + generate blur rendition
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct CreatePhotoReq {
    /// R2 key of the originally uploaded image (e.g. "profile/uuid/uuid.jpg").
    pub r2_key: String,
    /// Whether the image was flagged as NSFW by the client.
    pub is_nsfw: bool,
}

#[derive(Serialize)]
pub struct CreatePhotoRes {
    pub id: Uuid,
    pub r2_key: String,
    pub blur_key: String,
    pub is_nsfw: bool,
}

/// After the client uploads the original to R2 via the presigned PUT URL from
/// `upload_url`, this endpoint downloads the image, generates a blurred
/// rendition, uploads it to R2, and creates the `photos` row.
pub async fn create_photo(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Json(req): Json<CreatePhotoReq>,
) -> Result<(StatusCode, Json<CreatePhotoRes>), StatusCode> {
    let cfg = state.r2.as_ref().ok_or(StatusCode::SERVICE_UNAVAILABLE)?;

    // Extract kind from key prefix (e.g. "profile/uuid/uuid.jpg" -> "profile")
    let kind = req.r2_key.split('/').next().unwrap_or("");
    let bucket = match kind {
        "profile" => &cfg.bucket_media,
        "album" => &cfg.bucket_private,
        "verification" => &cfg.bucket_verification,
        "story" => &cfg.bucket_media,
        _ => return Err(StatusCode::BAD_REQUEST),
    };

    // SECURITY (P0-2): the caller supplies `r2_key` and we presign a GET/PUT on
    // it below. Without an ownership check, an attacker could pass any user's
    // key (`profile/<victim>/...`, `album/<victim>/...`, `verification/<victim>/...`)
    // and have us fetch it / write a `.blur.jpg` sibling next to it. All keys
    // created via `upload_url` are `<kind>/<owner-user-id>/<uuid>.<ext>`, so
    // require the caller's id in the owner position. Also reject path traversal.
    let owned_prefix = format!("{kind}/{user_id}/");
    if req.r2_key.contains("..") || !req.r2_key.starts_with(&owned_prefix) {
        return Err(StatusCode::FORBIDDEN);
    }

    let now = OffsetDateTime::now_utc();

    // 1. Download original from R2 via presigned GET URL
    let get_url = presign(cfg, "GET", bucket, &req.r2_key, 300, now);
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(60))
        .build()
        .map_err(|e| {
            tracing::error!("build reqwest client: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    let response = client.get(&get_url).send().await.map_err(|e| {
        tracing::error!("download from R2 failed: {e}");
        StatusCode::BAD_GATEWAY
    })?;
    let status = response.status();
    if !status.is_success() {
        tracing::error!("R2 GET returned {status} for key {}", req.r2_key);
        return Err(StatusCode::BAD_GATEWAY);
    }
    let image_bytes = response.bytes().await.map_err(|e| {
        tracing::error!("read R2 response body failed: {e}");
        StatusCode::BAD_GATEWAY
    })?;

    // 2. Generate blur rendition
    let blur_bytes =
        renditions::generate_blur_rendition(&image_bytes).map_err(|e| {
            tracing::error!("generate blur rendition: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    // 3. Upload blur to R2 via presigned PUT URL
    let blur_key = format!("{}.blur.jpg", req.r2_key);
    let put_url = presign(cfg, "PUT", bucket, &blur_key, 300, now);
    let put_response = client
        .put(&put_url)
        .header("Content-Type", "image/jpeg")
        .body(blur_bytes.clone())
        .send()
        .await
        .map_err(|e| {
            tracing::error!("upload blur to R2 failed: {e}");
            StatusCode::BAD_GATEWAY
        })?;
    let put_status = put_response.status();
    if !put_status.is_success() {
        tracing::error!("R2 PUT returned {put_status} for key {blur_key}");
        return Err(StatusCode::BAD_GATEWAY);
    }

    // 4. Insert photo record — for "profile" kind, set position + is_primary.
    let photo_id: Uuid = if kind == "profile" {
        // Count existing photos to determine position and primary status.
        let existing_count = db::photos::count_user_photos(&state.pool, user_id)
            .await
            .map_err(|e| {
                tracing::error!("count_user_photos failed: {e}");
                StatusCode::INTERNAL_SERVER_ERROR
            })?;
        let position = existing_count as i32;
        let is_first = existing_count == 0;

        let id: Uuid = sqlx::query_scalar(
            "INSERT INTO photos (user_id, r2_key, blur_key, is_nsfw, position, is_primary) \
             VALUES ($1, $2, $3, $4, $5, $6) RETURNING id",
        )
        .bind(user_id)
        .bind(&req.r2_key)
        .bind(&blur_key)
        .bind(req.is_nsfw)
        .bind(position)
        .bind(is_first)
        .fetch_one(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!("insert photo failed: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

        // Sync legacy field when this is the first (primary) photo.
        if is_first {
            sqlx::query(
                "UPDATE profiles SET profile_photo_key = $1 WHERE user_id = $2",
            )
            .bind(&req.r2_key)
            .bind(user_id)
            .execute(&state.pool)
            .await
            .map_err(|e| {
                tracing::error!("sync profile_photo_key failed: {e}");
                StatusCode::INTERNAL_SERVER_ERROR
            })?;
        }

        id
    } else {
        sqlx::query_scalar(
            "INSERT INTO photos (user_id, r2_key, blur_key, is_nsfw) VALUES ($1, $2, $3, $4) RETURNING id",
        )
        .bind(user_id)
        .bind(&req.r2_key)
        .bind(&blur_key)
        .bind(req.is_nsfw)
        .fetch_one(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!("insert photo failed: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?
    };

    Ok((
        StatusCode::CREATED,
        Json(CreatePhotoRes {
            id: photo_id,
            r2_key: req.r2_key,
            blur_key,
            is_nsfw: req.is_nsfw,
        }),
    ))
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
        "story" => &cfg.bucket_media,
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

#[derive(Deserialize)]
pub struct GetUrlQuery {
    /// Existing R2 object key (e.g. "album/user-id/photo.jpg"). Must not be
    /// empty or contain ".." to prevent path-traversal.
    pub key: String,
    /// Bucket routing: "profile" → media bucket, "album" → private bucket,
    /// "verification" → verification bucket. Mirrors upload_url routing.
    pub kind: String,
}

#[derive(Serialize)]
pub struct GetUrlRes {
    pub get_url: String,
}

/// GET /media/get-url?key=<r2_key>&kind=<profile|album|verification>
///
/// Returns a presigned GET URL (3600 s) for an existing media key.
/// Auth required. Mirrors upload_url's bucket routing and 503 behaviour when
/// R2 credentials are absent.
pub async fn get_url(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Query(q): Query<GetUrlQuery>,
) -> Result<Json<GetUrlRes>, StatusCode> {
    // Validate the request before requiring R2 config, so bad input is 400
    // even in environments without R2 credentials (dev/CI → r2 = None).
    if !matches!(q.kind.as_str(), "profile" | "album" | "verification" | "story") {
        return Err(StatusCode::BAD_REQUEST);
    }
    if q.key.is_empty() || q.key.contains("..") {
        return Err(StatusCode::BAD_REQUEST);
    }
    // Require R2 config up front so environments without credentials (dev/CI)
    // return 503 before we spend a DB round-trip on the access check.
    if state.r2.is_none() {
        return Err(StatusCode::SERVICE_UNAVAILABLE);
    }

    // SECURITY (P0-1): `get_url` presigns a GET for an arbitrary caller-supplied
    // key. Without an access check any authenticated user could read ANY object
    // (private albums, ID-verification documents, other users' media). Keys are
    // structured `<kind>/<owner-user-id>/<uuid>.<ext>` and are NOT secret, so
    // we must authorize per kind:
    //
    //   * verification → OWNER-ONLY. Sensitive ID docs; nobody else may read
    //     them. Gate by key prefix `verification/<caller>/`.
    //   * profile      → PUBLIC-BY-DESIGN but must be a real photo. Clients call
    //     this with other users' avatar keys (grid, story author avatars), so a
    //     prefix match would break it. Gate by DB: the key must exist in
    //     `photos.r2_key`.
    //   * album        → PRIVATE. Allowed if the caller OWNS the photo, or the
    //     photo is in an album shared (non-revoked, non-expired) with the
    //     caller. Gate by DB lookup over photos/album_photos/album_shares.
    //   * story        → semi-public to connected users. The key must exist in
    //     `stories.media_key` AND belong to the caller or a connected user
    //     (same visibility rule as the stories feed). Gate by DB.
    // Run the per-kind access check. The check touches only `state.pool`, so it
    // does not borrow the R2 config; `expiry` is the presign TTL for this kind.
    let expiry: u32 = match q.kind.as_str() {
        "verification" => {
            // OWNER-ONLY: sensitive ID docs. Prefix-gate to the caller's path.
            let owned_prefix = format!("verification/{user_id}/");
            if !q.key.starts_with(&owned_prefix) {
                return Err(StatusCode::FORBIDDEN);
            }
            PRIVATE_PRESIGN_EXPIRY
        }
        "profile" => {
            // Profile photos are public; only require the key to be a genuine
            // photo we minted (prevents presigning arbitrary objects in the
            // public bucket that were never real profile photos).
            let exists: bool = sqlx::query_scalar::<_, bool>(
                "SELECT EXISTS(SELECT 1 FROM photos WHERE r2_key = $1)",
            )
            .bind(&q.key)
            .fetch_one(&state.pool)
            .await
            .map_err(|e| {
                tracing::error!("get_url profile lookup failed: {e}");
                StatusCode::INTERNAL_SERVER_ERROR
            })?;
            if !exists {
                return Err(StatusCode::FORBIDDEN);
            }
            PUBLIC_PRESIGN_EXPIRY
        }
        "album" => {
            // Owner OR shared-with-caller (non-revoked, non-expired share).
            let allowed: bool = sqlx::query_scalar::<_, bool>(
                r#"SELECT EXISTS(
                       SELECT 1 FROM photos p
                       WHERE p.r2_key = $1
                         AND (
                             p.user_id = $2
                             OR EXISTS(
                                 SELECT 1
                                 FROM album_photos ap
                                 JOIN album_shares s ON s.album_id = ap.album_id
                                 WHERE ap.photo_id = p.id
                                   AND s.shared_with_user_id = $2
                                   AND s.revoked_at IS NULL
                                   AND (s.expires_at IS NULL OR s.expires_at > now())
                             )
                         )
                   )"#,
            )
            .bind(&q.key)
            .bind(user_id)
            .fetch_one(&state.pool)
            .await
            .map_err(|e| {
                tracing::error!("get_url album access lookup failed: {e}");
                StatusCode::INTERNAL_SERVER_ERROR
            })?;
            if !allowed {
                return Err(StatusCode::FORBIDDEN);
            }
            PRIVATE_PRESIGN_EXPIRY
        }
        // "story"
        _ => {
            // The key must belong to a real story owned by the caller or by a
            // user connected to the caller (shares a conversation, not blocked).
            let allowed: bool = sqlx::query_scalar::<_, bool>(
                r#"SELECT EXISTS(
                       SELECT 1 FROM stories st
                       WHERE st.media_key = $1
                         AND (
                             st.user_id = $2
                             OR st.user_id IN (
                                 SELECT DISTINCT cm2.user_id
                                 FROM conversation_members cm1
                                 JOIN conversation_members cm2
                                   ON cm2.conversation_id = cm1.conversation_id
                                 WHERE cm1.user_id = $2
                                   AND cm2.user_id != $2
                                   AND cm2.user_id NOT IN (
                                       SELECT target_id FROM blocks WHERE user_id = $2
                                       UNION
                                       SELECT user_id FROM blocks WHERE target_id = $2
                                   )
                             )
                         )
                   )"#,
            )
            .bind(&q.key)
            .bind(user_id)
            .fetch_one(&state.pool)
            .await
            .map_err(|e| {
                tracing::error!("get_url story access lookup failed: {e}");
                StatusCode::INTERNAL_SERVER_ERROR
            })?;
            if !allowed {
                return Err(StatusCode::FORBIDDEN);
            }
            PUBLIC_PRESIGN_EXPIRY
        }
    };

    let cfg = state.r2.as_ref().ok_or(StatusCode::SERVICE_UNAVAILABLE)?;
    let bucket = match q.kind.as_str() {
        "profile" => &cfg.bucket_media,
        "album" => &cfg.bucket_private,
        "story" => &cfg.bucket_media,
        _ => &cfg.bucket_verification,
    };
    let now = OffsetDateTime::now_utc();
    let url = presign(cfg, "GET", bucket, &q.key, expiry, now);
    Ok(Json(GetUrlRes { get_url: url }))
}

// ---------------------------------------------------------------------------
// GET /media/photos — list authenticated user's profile photos
// ---------------------------------------------------------------------------

#[derive(Serialize)]
struct GalleryPhotoItem {
    id: Uuid,
    url: String,
    is_primary: bool,
    position: i32,
}

pub async fn list_photos(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let cfg = state.r2.as_ref().ok_or(StatusCode::SERVICE_UNAVAILABLE)?;
    let rows = db::photos::list_user_photos(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("list_user_photos failed: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    let now = OffsetDateTime::now_utc();
    let photos: Vec<GalleryPhotoItem> = rows
        .into_iter()
        .map(|r| GalleryPhotoItem {
            id: r.id,
            url: presign(cfg, "GET", &cfg.bucket_media, &r.r2_key, 604800, now),
            is_primary: r.is_primary,
            position: r.position,
        })
        .collect();
    Ok(Json(json!({ "photos": photos })))
}

// ---------------------------------------------------------------------------
// DELETE /media/photos/:id — delete own photo
// ---------------------------------------------------------------------------

pub async fn delete_photo(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Path(photo_id): Path<Uuid>,
) -> Result<StatusCode, StatusCode> {
    let deleted = db::photos::delete_photo(&state.pool, user_id, photo_id)
        .await
        .map_err(|e| {
            tracing::error!("delete_photo failed: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    if deleted {
        Ok(StatusCode::OK)
    } else {
        Err(StatusCode::NOT_FOUND)
    }
}

// ---------------------------------------------------------------------------
// PUT /media/photos/:id/primary — set as primary photo
// ---------------------------------------------------------------------------

pub async fn set_primary_photo(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Path(photo_id): Path<Uuid>,
) -> Result<StatusCode, StatusCode> {
    let updated = db::photos::set_primary_photo(&state.pool, user_id, photo_id)
        .await
        .map_err(|e| {
            tracing::error!("set_primary_photo failed: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    if updated {
        Ok(StatusCode::OK)
    } else {
        Err(StatusCode::NOT_FOUND)
    }
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/media/upload-url", post(upload_url))
        .route("/media/get-url", get(get_url))
        .route("/media/photos", post(create_photo))
        .route("/media/photos", get(list_photos))
        .route("/media/photos/:id", delete(delete_photo))
        .route("/media/photos/:id/primary", put(set_primary_photo))
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
        assert!(url.contains("X-Amz-Content-Sha256=UNSIGNED-PAYLOAD"));
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
