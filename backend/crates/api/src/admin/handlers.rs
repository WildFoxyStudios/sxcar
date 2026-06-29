//! Handlers para /admin/* endpoints.
//!
//! Incluye:
//! - Auth: login, 2fa, logout (AD1)
//! - Users: list, get, ban, suspend, activate, force-logout (AD2)
//! - Audit: list (AD2)

use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use time::{Duration, OffsetDateTime};
use uuid::Uuid;

use crate::admin::audit::{AuditJustification, AuditTarget};
use crate::admin::extractors::StaffAuth;
use crate::AppState;

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Convierte una fila UserRow a json, serializando `created_at` como string
/// (time::OffsetDateTime no impl Serialize sin feature flag en workspace).
fn user_row_to_json(u: db::users::UserRow) -> Value {
    json!({
        "id": u.id,
        "email": u.email,
        "email_verified": u.email_verified,
        "status": u.status,
        "role": u.role,
        "created_at": u.created_at.to_string(),
    })
}

/// Convierte una fila UserFullRow a json.
fn user_full_to_json(u: db::users::UserFullRow) -> Value {
    json!({
        "id": u.id,
        "email": u.email,
        "email_verified": u.email_verified,
        "status": u.status,
        "role": u.role,
        "created_at": u.created_at.to_string(),
        "display_name": u.display_name,
        "bio": u.bio,
        "profile_photo_url": u.profile_photo_url,
    })
}

// ---------------------------------------------------------------------------
// AD3 — Moderation request / response types
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct ListReportsQuery {
    pub status: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

#[derive(Deserialize)]
pub struct ListPhotosQuery {
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

#[derive(Deserialize)]
pub struct ListCsamQuery {
    pub status: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

#[derive(Deserialize)]
pub struct ResolveReportRequest {
    pub resolution: String,
    pub action: String,
    pub note: Option<String>,
}

#[derive(Deserialize)]
pub struct ReportCsamRequest {
    pub notes: Option<String>,
}

// ---------------------------------------------------------------------------
// AD3 — Moderation handlers
// ---------------------------------------------------------------------------

/// GET /admin/reports?status=open&limit=20&offset=0
///
/// RBAC: reports.view (checked inline).
/// Retorna lista paginada de reportes.
pub async fn list_reports(
    State(state): State<AppState>,
    staff: StaffAuth,
    Query(query): Query<ListReportsQuery>,
) -> Result<Json<Value>, StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "reports.view") {
        return Err(StatusCode::FORBIDDEN);
    }

    let status = query.status.as_deref();
    let limit = query.limit.unwrap_or(20).clamp(1, 100);
    let offset = query.offset.unwrap_or(0).max(0);

    let (reports, total) = db::moderation::list_reports(&state.pool, status, limit, offset)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let reports_json: Vec<Value> = reports
        .into_iter()
        .map(|r| {
            json!({
                "id": r.id,
                "reporter_id": r.reporter_id,
                "target_user_id": r.target_user_id,
                "target_kind": r.target_kind,
                "target_id": r.target_id,
                "reason": r.reason,
                "status": r.status,
                "created_at": r.created_at.to_string(),
                "resolved_at": r.resolved_at.map(|t| t.to_string()),
            })
        })
        .collect();

    Ok(Json(json!({
        "reports": reports_json,
        "total": total,
    })))
}

/// POST /admin/reports/:id/review
///
/// RBAC: reports.resolve (checked inline).
/// Cambia status a "reviewing".
pub async fn review_report(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
) -> Result<(AuditTarget, Json<Value>), StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "reports.resolve") {
        return Err(StatusCode::FORBIDDEN);
    }

    // Verificar que el reporte existe
    let report = db::moderation::find_report_by_id(&state.pool, id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)?;

    db::moderation::update_report_status(&state.pool, report.id, "reviewing")
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(id.to_string()),
        Json(json!({"status": "reviewing"})),
    ))
}

/// POST /admin/reports/:id/resolve
///
/// RBAC: reports.resolve (checked inline).
/// Body: { resolution: "actioned"|"dismissed", action: "warn"|"suspend"|"ban"|"clear", note: String? }
///
/// Si resolution=actioned, crea moderation_action con staff_id.
/// Si action es warn/suspend/ban, actualiza el status del usuario.
pub async fn resolve_report(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
    Json(body): Json<ResolveReportRequest>,
) -> Result<
    (AuditTarget, AuditJustification, Json<Value>),
    StatusCode,
> {
    if !staff.0.permissions.iter().any(|p| p == "reports.resolve") {
        return Err(StatusCode::FORBIDDEN);
    }

    let report = db::moderation::find_report_by_id(&state.pool, id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)?;

    let resolution = &body.resolution;
    let action = &body.action;
    let note = body.note.as_deref();

    // Validar resolution
    if resolution != "actioned" && resolution != "dismissed" {
        return Err(StatusCode::BAD_REQUEST);
    }

    let mut moderation_action_id: Option<Uuid> = None;

    if resolution == "actioned" {
        // Crear moderation_action
        let ma_id = db::moderation::create_moderation_action(
            &state.pool,
            staff.0.id,
            report.target_user_id,
            action,
            note,
        )
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        moderation_action_id = Some(ma_id);

        // Si action es warn/suspend/ban, actualizar status del usuario
        if action == "warn" || action == "suspend" || action == "ban" {
            let user_status = match action.as_str() {
                "warn" => "active",     // warn no cambia status, solo registra
                "suspend" => "suspended",
                "ban" => "banned",
                _ => unreachable!(),
            };
            // Solo suspend/ban realmente cambian status
            if action == "suspend" || action == "ban" {
                db::users::update_user_status(&state.pool, report.target_user_id, user_status)
                    .await
                    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
            }
        }
    }

    // Resolver el reporte (status + resolved_at)
    db::moderation::resolve_report(&state.pool, id, resolution)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let mut resp = json!({
        "report_status": resolution,
    });
    if let Some(ma_id) = moderation_action_id {
        resp["moderation_action_id"] = json!(ma_id);
    }

    Ok((
        AuditTarget(id.to_string()),
        AuditJustification(note.unwrap_or_default().to_string()),
        Json(resp),
    ))
}

/// GET /admin/moderation/photos?limit=20&offset=0
///
/// RBAC: photos.moderate (checked inline).
/// Retorna fotos pendientes de moderacion, ordenadas ASC por created_at.
pub async fn list_pending_photos(
    State(state): State<AppState>,
    staff: StaffAuth,
    Query(query): Query<ListPhotosQuery>,
) -> Result<Json<Value>, StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "photos.moderate") {
        return Err(StatusCode::FORBIDDEN);
    }

    let limit = query.limit.unwrap_or(20).clamp(1, 100);
    let offset = query.offset.unwrap_or(0).max(0);

    let (photos, total) = db::moderation::list_pending_photos(&state.pool, limit, offset)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let photos_json: Vec<Value> = photos
        .into_iter()
        .map(|p| {
            json!({
                "id": p.id,
                "user_id": p.user_id,
                "r2_key": p.r2_key,
                "is_nsfw": p.is_nsfw,
                "moderation_status": p.moderation_status,
                "created_at": p.created_at.to_string(),
            })
        })
        .collect();

    Ok(Json(json!({
        "photos": photos_json,
        "total": total,
    })))
}

/// POST /admin/moderation/photos/:id/approve
///
/// RBAC: photos.moderate (checked inline).
/// Cambia moderation_status a "approved".
pub async fn approve_photo(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
) -> Result<(AuditTarget, Json<Value>), StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "photos.moderate") {
        return Err(StatusCode::FORBIDDEN);
    }

    db::moderation::update_photo_moderation(&state.pool, id, "approved")
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(id.to_string()),
        Json(json!({"status": "approved"})),
    ))
}

/// POST /admin/moderation/photos/:id/reject
///
/// RBAC: photos.moderate (checked inline).
/// Cambia moderation_status a "rejected".
pub async fn reject_photo(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
) -> Result<(AuditTarget, Json<Value>), StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "photos.moderate") {
        return Err(StatusCode::FORBIDDEN);
    }

    db::moderation::update_photo_moderation(&state.pool, id, "rejected")
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(id.to_string()),
        Json(json!({"status": "rejected"})),
    ))
}

/// GET /admin/csam?status=pending&limit=20&offset=0
///
/// RBAC: csam.view (checked inline).
/// Retorna hits de CSAM paginados.
pub async fn list_csam_hits(
    State(state): State<AppState>,
    staff: StaffAuth,
    Query(query): Query<ListCsamQuery>,
) -> Result<Json<Value>, StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "csam.view") {
        return Err(StatusCode::FORBIDDEN);
    }

    let status = query.status.as_deref();
    let limit = query.limit.unwrap_or(20).clamp(1, 100);
    let offset = query.offset.unwrap_or(0).max(0);

    let (hits, total) = db::moderation::list_csam_hits(&state.pool, status, limit, offset)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let hits_json: Vec<Value> = hits
        .into_iter()
        .map(|h| {
            json!({
                "id": h.id,
                "photo_id": h.photo_id,
                "hash": h.hash,
                "source": h.source,
                "status": h.status,
                "matched_at": h.matched_at.to_string(),
                "reported_to_authority_at": h.reported_to_authority_at.map(|t| t.to_string()),
                "notes": h.notes,
            })
        })
        .collect();

    Ok(Json(json!({
        "hits": hits_json,
        "total": total,
    })))
}

/// POST /admin/csam/:id/report
///
/// RBAC: csam.report (requires_justification).
/// Body: { notes: String? }.
/// Cambia status a "reported", setea reported_to_authority_at = now().
pub async fn report_csam_hit(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
    Json(body): Json<ReportCsamRequest>,
) -> Result<
    (AuditTarget, AuditJustification, Json<Value>),
    StatusCode,
> {
    if !staff.0.permissions.iter().any(|p| p == "csam.report") {
        return Err(StatusCode::FORBIDDEN);
    }

    db::moderation::report_csam_hit(&state.pool, id, body.notes.as_deref())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(id.to_string()),
        AuditJustification(body.notes.clone().unwrap_or_default()),
        Json(json!({"status": "reported"})),
    ))
}

/// Extrae la direccion IP del cliente desde headers (X-Forwarded-For o X-Real-IP).
fn client_ip(headers: &HeaderMap) -> Option<String> {
    headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.split(',').next().map(|s| s.trim().to_string()))
        .or_else(|| {
            headers
                .get("x-real-ip")
                .and_then(|v| v.to_str().ok())
                .map(String::from)
        })
}

// ---------------------------------------------------------------------------
// Auth — Request / Response types (AD1)
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct LoginRequest {
    pub email: String,
    pub password: String,
}

#[derive(Serialize)]
pub struct LoginResponse {
    pub mfa_token: String,
}

#[derive(Deserialize)]
pub struct TwoFactorRequest {
    pub mfa_token: String,
    pub totp_code: String,
}

#[derive(Serialize)]
pub struct TwoFactorResponse {
    pub access_token: String,
    pub session_id: String,
}

#[derive(Deserialize)]
pub struct LogoutRequest {
    pub session_id: String,
}

// ---------------------------------------------------------------------------
// AD2 — Request / Response types
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct ListUsersQuery {
    pub q: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

#[derive(Deserialize)]
pub struct ActionRequest {
    pub reason: Option<String>,
}

#[derive(Deserialize)]
pub struct ListAuditQuery {
    pub staff_id: Option<Uuid>,
    pub action: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

// ---------------------------------------------------------------------------
// Auth handlers (AD1)
// ---------------------------------------------------------------------------

/// POST /admin/auth/login
///
/// Valida email+password, emite mfa_token (15 min TTL) para el paso 2FA.
pub async fn login(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<LoginRequest>,
) -> Result<Json<LoginResponse>, StatusCode> {
    let staff = db::staff::find_staff_by_email(&state.pool, &req.email)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let staff = match staff {
        Some(s) if s.status == "active" => s,
        _ => return Err(StatusCode::UNAUTHORIZED),
    };

    if let Some(locked_until) = staff.locked_until {
        if locked_until > OffsetDateTime::now_utc() {
            return Err(StatusCode::from_u16(423).unwrap());
        }
    }

    let password_ok = auth_admin::password::verify(&req.password, &staff.password_hash)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if !password_ok {
        let _ = db::staff::increment_failed_login(&state.pool, staff.id).await;
        return Err(StatusCode::UNAUTHORIZED);
    }

    let ip = client_ip(&headers);
    db::staff::update_last_login(&state.pool, staff.id, ip.as_deref())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let mfa_token = auth_admin::mfa_token::issue(
        state.admin_jwt_secret.as_bytes(),
        &staff.id.to_string(),
    );

    Ok(Json(LoginResponse { mfa_token }))
}

/// POST /admin/auth/2fa
///
/// Verifica mfa_token + codigo TOTP, crea sesion, emite JWT (8h).
pub async fn two_factor(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<TwoFactorRequest>,
) -> Result<Json<TwoFactorResponse>, StatusCode> {
    let staff_id_str = auth_admin::mfa_token::verify(
        state.admin_jwt_secret.as_bytes(),
        &req.mfa_token,
    )
    .map_err(|_| StatusCode::UNAUTHORIZED)?;

    let staff_id: Uuid = staff_id_str.parse().map_err(|_| StatusCode::UNAUTHORIZED)?;

    let staff = db::staff::find_staff_by_id(&state.pool, staff_id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::UNAUTHORIZED)?;

    if staff.status != "active" {
        return Err(StatusCode::UNAUTHORIZED);
    }

    let kek = auth_admin::keystore::Kek::from_env()
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let totp_raw = auth_admin::totp::decrypt_secret(&kek.key, &staff.totp_secret_enc)
        .map_err(|_| StatusCode::UNAUTHORIZED)?;

    let totp_b32 = auth_admin::totp::raw_to_b32(&totp_raw);
    let totp_ok = auth_admin::totp::verify_code(&totp_b32, &req.totp_code, 1)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if !totp_ok {
        return Err(StatusCode::UNAUTHORIZED);
    }

    let permissions = db::staff::get_role_permissions(&state.pool, &staff.role)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let expires_at = OffsetDateTime::now_utc() + Duration::hours(8);
    let ip = client_ip(&headers);
    let user_agent = headers
        .get("user-agent")
        .and_then(|v| v.to_str().ok())
        .map(String::from);

    let session_id = db::staff::create_session(
        &state.pool,
        staff_id,
        expires_at,
        ip.as_deref(),
        user_agent.as_deref(),
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let access_token = auth_admin::jwt::issue(
        &state.admin_jwt_secret,
        staff_id,
        &staff.role,
        &permissions,
        28800,
        &session_id.to_string(),
    )
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(TwoFactorResponse {
        access_token,
        session_id: session_id.to_string(),
    }))
}

/// POST /admin/auth/logout
///
/// Revoca la sesion indicada (requiere token valido en Authorization header).
pub async fn logout(
    State(state): State<AppState>,
    _staff: StaffAuth,
    Json(req): Json<LogoutRequest>,
) -> Result<StatusCode, StatusCode> {
    let session_id: Uuid = req
        .session_id
        .parse()
        .map_err(|_| StatusCode::BAD_REQUEST)?;

    db::staff::revoke_session(&state.pool, session_id, "logout")
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------------------
// AD2 — User management handlers
// ---------------------------------------------------------------------------

/// GET /admin/users?q=&limit=20&offset=0
///
/// RBAC: user.view (checked inline).
/// Retorna lista paginada de usuarios + total + conteo por status.
pub async fn list_users(
    State(state): State<AppState>,
    staff: StaffAuth,
    Query(query): Query<ListUsersQuery>,
) -> Result<Json<Value>, StatusCode> {
    // RBAC check inline
    if !staff.0.permissions.iter().any(|p| p == "user.view") {
        return Err(StatusCode::FORBIDDEN);
    }

    let q = query.q.as_deref().unwrap_or("");
    let limit = query.limit.unwrap_or(20).clamp(1, 100);
    let offset = query.offset.unwrap_or(0).max(0);

    let (users, total) = db::users::search_users(&state.pool, q, limit, offset)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let by_status = db::users::count_users_by_status(&state.pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let users_json: Vec<Value> = users.into_iter().map(user_row_to_json).collect();
    let by_status_json: Vec<Value> = by_status
        .into_iter()
        .map(|s| json!({"status": s.status, "count": s.count}))
        .collect();

    Ok(Json(json!({
        "users": users_json,
        "total": total,
        "by_status": by_status_json,
    })))
}

/// GET /admin/users/:id
///
/// RBAC: user.view (checked inline).
/// Retorna perfil completo del usuario (incluye datos de perfil/foto).
pub async fn get_user(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "user.view") {
        return Err(StatusCode::FORBIDDEN);
    }

    let user = db::users::find_user_full(&state.pool, id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)?;

    Ok(Json(json!({ "user": user_full_to_json(user) })))
}

/// POST /admin/users/:id/ban
///
/// RBAC: user.ban (requires_justification=true).
/// Body: { "reason": "..." }
pub async fn ban_user(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
    Json(body): Json<ActionRequest>,
) -> Result<
    (AuditTarget, AuditJustification, Json<Value>),
    StatusCode,
> {
    if !staff.0.permissions.iter().any(|p| p == "user.ban") {
        return Err(StatusCode::FORBIDDEN);
    }

    db::users::update_user_status(&state.pool, id, "banned")
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(id.to_string()),
        AuditJustification(body.reason.unwrap_or_default()),
        Json(json!({"status": "banned"})),
    ))
}

/// POST /admin/users/:id/suspend
///
/// RBAC: user.suspend (requires_justification=true).
/// Body: { "reason": "..." }
pub async fn suspend_user(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
    Json(body): Json<ActionRequest>,
) -> Result<
    (AuditTarget, AuditJustification, Json<Value>),
    StatusCode,
> {
    if !staff.0.permissions.iter().any(|p| p == "user.suspend") {
        return Err(StatusCode::FORBIDDEN);
    }

    db::users::update_user_status(&state.pool, id, "suspended")
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(id.to_string()),
        AuditJustification(body.reason.unwrap_or_default()),
        Json(json!({"status": "suspended"})),
    ))
}

/// POST /admin/users/:id/activate
///
/// RBAC: user.activate (sin justificación obligatoria).
/// Body opcional (se ignora).
pub async fn activate_user(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
) -> Result<(AuditTarget, Json<Value>), StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "user.activate") {
        return Err(StatusCode::FORBIDDEN);
    }

    db::users::update_user_status(&state.pool, id, "active")
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(id.to_string()),
        Json(json!({"status": "active"})),
    ))
}

/// POST /admin/users/:id/force-logout
///
/// RBAC: user.force_logout (requires_justification=true).
/// Revoca todos los refresh tokens del usuario.
/// Body: { "reason": "..." }
pub async fn force_logout_user(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
    Json(body): Json<ActionRequest>,
) -> Result<
    (AuditTarget, AuditJustification, Json<Value>),
    StatusCode,
> {
    if !staff.0.permissions.iter().any(|p| p == "user.force_logout") {
        return Err(StatusCode::FORBIDDEN);
    }

    db::users::revoke_all_refresh(&state.pool, id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(id.to_string()),
        AuditJustification(body.reason.unwrap_or_default()),
        Json(json!({"revoked": true})),
    ))
}

// ---------------------------------------------------------------------------
// AD2 — Audit handler
// ---------------------------------------------------------------------------

/// GET /admin/audit?staff_id=&action=&limit=20&offset=0
///
/// RBAC: audit.read (checked inline).
/// Retorna entradas del audit_log con filtros opcionales.
pub async fn list_audit(
    State(state): State<AppState>,
    staff: StaffAuth,
    Query(query): Query<ListAuditQuery>,
) -> Result<Json<Value>, StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "audit.read") {
        return Err(StatusCode::FORBIDDEN);
    }

    let limit = query.limit.unwrap_or(20).clamp(1, 200);
    let offset = query.offset.unwrap_or(0).max(0);

    let (entries, total) = db::staff::search_audit_log(
        &state.pool,
        query.staff_id,
        query.action.as_deref(),
        limit,
        offset,
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // Convertir cada entrada manualmente porque AuditRow contiene
    // OffsetDateTime que no implementa Serialize sin feature flag en time.
    let entries_json: Vec<Value> = entries
        .into_iter()
        .map(|e| {
            json!({
                "id": e.id,
                "actor_staff_id": e.actor_staff_id,
                "action": e.action,
                "target": e.target,
                "metadata": e.metadata,
                "created_at": e.created_at.to_string(),
            })
        })
        .collect();

    Ok(Json(json!({
        "entries": entries_json,
        "total": total,
    })))
}

// ---------------------------------------------------------------------------
// AD5 — Feature flags / config / analytics types
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct UpsertFlagRequest {
    pub key: String,
    pub value: serde_json::Value,
    pub description: Option<String>,
    pub enabled: bool,
}

#[derive(Deserialize)]
pub struct UpsertConfigRequest {
    pub key: String,
    pub value: serde_json::Value,
}

// ---------------------------------------------------------------------------
// AD5 — Feature flags handlers
// ---------------------------------------------------------------------------

/// GET /admin/flags
///
/// RBAC: flags.read (checked inline).
/// Retorna lista de feature flags.
pub async fn list_flags(
    State(state): State<AppState>,
    staff: StaffAuth,
) -> Result<Json<Value>, StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "flags.read") {
        return Err(StatusCode::FORBIDDEN);
    }

    let flags = db::config::list_feature_flags(&state.pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let flags_json: Vec<Value> = flags
        .into_iter()
        .map(|f| {
            json!({
                "key": f.key,
                "value": f.value,
                "description": f.description,
                "enabled": f.enabled,
                "created_at": f.created_at.to_string(),
                "updated_at": f.updated_at.to_string(),
                "updated_by": f.updated_by,
            })
        })
        .collect();

    Ok(Json(json!({ "flags": flags_json })))
}

/// POST /admin/flags
///
/// RBAC: flags.write (checked inline).
/// Body: { key, value, description?, enabled }.
/// Crea o actualiza un feature flag.
pub async fn upsert_flag(
    State(state): State<AppState>,
    staff: StaffAuth,
    Json(body): Json<UpsertFlagRequest>,
) -> Result<(AuditTarget, AuditJustification, Json<Value>), StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "flags.write") {
        return Err(StatusCode::FORBIDDEN);
    }

    db::config::upsert_feature_flag(
        &state.pool,
        &body.key,
        &body.value,
        body.description.as_deref(),
        body.enabled,
        staff.0.id,
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(body.key.clone()),
        AuditJustification(body.key.clone()),
        Json(json!({
            "key": body.key,
            "enabled": body.enabled,
        })),
    ))
}

/// DELETE /admin/flags/:key
///
/// RBAC: flags.write (checked inline).
/// Elimina un feature flag. 204 No Content.
pub async fn delete_flag(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(key): Path<String>,
) -> Result<(AuditTarget, StatusCode), StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "flags.write") {
        return Err(StatusCode::FORBIDDEN);
    }

    db::config::delete_feature_flag(&state.pool, &key)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((AuditTarget(key), StatusCode::NO_CONTENT))
}

// ---------------------------------------------------------------------------
// AD5 — App config handlers
// ---------------------------------------------------------------------------

/// GET /admin/config
///
/// RBAC: config.read (checked inline).
/// Retorna la configuracion global de la app.
pub async fn list_config(
    State(state): State<AppState>,
    staff: StaffAuth,
) -> Result<Json<Value>, StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "config.read") {
        return Err(StatusCode::FORBIDDEN);
    }

    let configs = db::config::list_app_config(&state.pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let config_json: Vec<Value> = configs
        .into_iter()
        .map(|c| {
            json!({
                "key": c.key,
                "value": c.value,
                "description": c.description,
                "updated_at": c.updated_at.to_string(),
                "updated_by": c.updated_by,
            })
        })
        .collect();

    Ok(Json(json!({ "config": config_json })))
}

/// POST /admin/config
///
/// RBAC: config.write (checked inline).
/// Body: { key, value }.
/// Crea o actualiza una entrada de configuracion.
pub async fn upsert_config(
    State(state): State<AppState>,
    staff: StaffAuth,
    Json(body): Json<UpsertConfigRequest>,
) -> Result<(AuditTarget, AuditJustification, Json<Value>), StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "config.write") {
        return Err(StatusCode::FORBIDDEN);
    }

    db::config::upsert_app_config(&state.pool, &body.key, &body.value, staff.0.id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(body.key.clone()),
        AuditJustification(body.key.clone()),
        Json(json!({ "key": body.key })),
    ))
}

// ---------------------------------------------------------------------------
// AD5 — Analytics handlers
// ---------------------------------------------------------------------------

/// GET /admin/analytics/overview
///
/// RBAC: config.read (checked inline, read-only endpoint).
/// Retorna metricas agregadas del panel de administracion.
pub async fn analytics_overview(
    State(state): State<AppState>,
    staff: StaffAuth,
) -> Result<Json<Value>, StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "config.read") {
        return Err(StatusCode::FORBIDDEN);
    }

    let analytics = db::config::get_analytics_overview(&state.pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(json!({
        "total_users": analytics.total_users,
        "active_today": analytics.active_today,
        "banned_users": analytics.banned_users,
        "suspended_users": analytics.suspended_users,
        "premium_users": analytics.premium_users,
        "new_users_today": analytics.new_users_today,
    })))
}

// ---------------------------------------------------------------------------
// AD4 — Support types
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct ManageEntitlementRequest {
    pub feature: String,
    pub action: String,
}

#[derive(Deserialize)]
pub struct ListDataRequestsQuery {
    pub status: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

#[derive(Deserialize)]
pub struct ProcessDataRequest {
    pub status: String,
    pub notes: Option<String>,
}

#[derive(Deserialize)]
pub struct LegalExportRequest {
    pub justification: String,
    pub legal_basis: String,
}

#[derive(Deserialize)]
pub struct PlaceLegalHoldRequest {
    pub user_id: Uuid,
    pub reason: String,
    pub reference: Option<String>,
}

#[derive(Deserialize)]
pub struct ReleaseLegalHoldRequest {
    pub reason: String,
}

// ---------------------------------------------------------------------------
// AD4 — Support handlers
// ---------------------------------------------------------------------------

/// GET /admin/support/users/:id/entitlements
///
/// RBAC: entitlements.view (checked inline).
/// Retorna subscriptions + entitlements del usuario.
pub async fn list_entitlements(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "entitlements.view") {
        return Err(StatusCode::FORBIDDEN);
    }

    let subscriptions = db::support::list_subscriptions(&state.pool, id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let entitlements = db::support::list_entitlements(&state.pool, id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let subs_json: Vec<Value> = subscriptions
        .into_iter()
        .map(|s| {
            json!({
                "id": s.id,
                "user_id": s.user_id,
                "tier": s.tier,
                "store": s.store,
                "revenuecat_id": s.revenuecat_id,
                "status": s.status,
                "current_period_end": s.current_period_end.map(|t| t.to_string()),
            })
        })
        .collect();

    let ents_json: Vec<Value> = entitlements
        .into_iter()
        .map(|e| {
            json!({
                "user_id": e.user_id,
                "feature": e.feature,
                "enabled": e.enabled,
            })
        })
        .collect();

    Ok(Json(json!({
        "subscriptions": subs_json,
        "entitlements": ents_json,
    })))
}

/// POST /admin/support/users/:id/entitlements
///
/// RBAC: entitlements.manage (requires_justification, checked inline).
/// Body: { feature: String, action: "grant" | "revoke" }.
pub async fn manage_entitlement(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
    Json(body): Json<ManageEntitlementRequest>,
) -> Result<(AuditTarget, AuditJustification, Json<Value>), StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "entitlements.manage") {
        return Err(StatusCode::FORBIDDEN);
    }

    match body.action.as_str() {
        "grant" => {
            db::support::grant_entitlement(&state.pool, id, &body.feature)
                .await
                .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        }
        "revoke" => {
            db::support::revoke_entitlement(&state.pool, id, &body.feature)
                .await
                .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        }
        _ => return Err(StatusCode::BAD_REQUEST),
    }

    Ok((
        AuditTarget(id.to_string()),
        AuditJustification(format!("{} {}", body.action, body.feature)),
        Json(json!({"status": body.action})),
    ))
}

// ---------------------------------------------------------------------------
// AD4 — GDPR (DSAR) handlers
// ---------------------------------------------------------------------------

/// GET /admin/gdpr/data-requests?status=pending&limit=20
///
/// RBAC: dsar.view (checked inline).
/// Retorna lista paginada de solicitudes de datos.
pub async fn list_data_requests(
    State(state): State<AppState>,
    staff: StaffAuth,
    Query(query): Query<ListDataRequestsQuery>,
) -> Result<Json<Value>, StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "dsar.view") {
        return Err(StatusCode::FORBIDDEN);
    }

    let status = query.status.as_deref();
    let limit = query.limit.unwrap_or(20).clamp(1, 100);
    let offset = query.offset.unwrap_or(0).max(0);

    let (requests, total) = db::support::list_data_requests(&state.pool, status, limit, offset)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let requests_json: Vec<Value> = requests
        .into_iter()
        .map(|r| {
            json!({
                "id": r.id,
                "user_id": r.user_id,
                "kind": r.kind,
                "status": r.status,
                "requested_at": r.requested_at.to_string(),
                "completed_at": r.completed_at.map(|t| t.to_string()),
            })
        })
        .collect();

    Ok(Json(json!({
        "requests": requests_json,
        "total": total,
    })))
}

/// POST /admin/gdpr/data-requests/:id/process
///
/// RBAC: dsar.process (requires_justification, checked inline).
/// Body: { status: "processing"|"completed"|"rejected", notes?: String }.
pub async fn process_data_request(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
    Json(body): Json<ProcessDataRequest>,
) -> Result<(AuditTarget, AuditJustification, Json<Value>), StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "dsar.process") {
        return Err(StatusCode::FORBIDDEN);
    }

    match body.status.as_str() {
        "processing" | "completed" | "rejected" => {}
        _ => return Err(StatusCode::BAD_REQUEST),
    }

    db::support::update_data_request(&state.pool, id, &body.status)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(id.to_string()),
        AuditJustification(body.notes.unwrap_or_default()),
        Json(json!({"status": body.status})),
    ))
}

// ---------------------------------------------------------------------------
// AD4 — Legal handlers (LER)
// ---------------------------------------------------------------------------

/// GET /admin/legal/export/:user_id
///
/// RBAC: legal.export (requires_justification, checked inline).
/// Body: { justification: String, legal_basis: String }.
/// Construye el dossier legal y audita manualmente (GET no pasa por audit_mutation).
pub async fn legal_export(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(user_id): Path<Uuid>,
    Json(body): Json<LegalExportRequest>,
) -> Result<Json<Value>, StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "legal.export") {
        return Err(StatusCode::FORBIDDEN);
    }

    let dossier = db::support::build_legal_dossier(&state.pool, user_id)
        .await
        .map_err(|_| StatusCode::NOT_FOUND)?;

    // Audit manual (GET no pasa por audit_mutation middleware)
    let action = format!("GET:/admin/legal/export/{user_id}");
    let _ = sqlx::query(
        "INSERT INTO audit_log (actor_staff_id, staff_session_id, action, target, justification, legal_basis) \
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(staff.0.id)
    .bind(staff.0.session_id)
    .bind(&action)
    .bind(user_id.to_string())
    .bind(&body.justification)
    .bind(&body.legal_basis)
    .execute(&state.pool)
    .await;

    Ok(Json(dossier_to_json(dossier)))
}

fn dossier_to_json(d: db::support::LegalDossier) -> Value {
    json!({
        "user": {
            "id": d.user.id,
            "email": d.user.email,
            "email_verified": d.user.email_verified,
            "status": d.user.status,
            "role": d.user.role,
            "created_at": d.user.created_at.to_string(),
        },
        "profile": d.profile.map(|p| json!({
            "user_id": p.user_id,
            "display_name": p.display_name,
            "about": p.about,
            "gender_identity": p.gender_identity,
            "relationship_status": p.relationship_status,
            "created_at": p.created_at.to_string(),
        })),
        "devices": d.devices.into_iter().map(|dev| json!({
            "id": dev.id,
            "platform": dev.platform,
            "last_seen_at": dev.last_seen_at.map(|t| t.to_string()),
            "created_at": dev.created_at.to_string(),
        })).collect::<Vec<_>>(),
        "access_events": d.access_events.into_iter().map(|e| json!({
            "id": e.id,
            "event": e.event,
            "ip": e.ip,
            "user_agent": e.user_agent,
            "created_at": e.created_at.to_string(),
        })).collect::<Vec<_>>(),
        "photos": d.photos.into_iter().map(|p| json!({
            "id": p.id,
            "r2_key": p.r2_key,
            "is_primary": p.is_primary,
            "is_nsfw": p.is_nsfw,
            "moderation_status": p.moderation_status,
            "created_at": p.created_at.to_string(),
        })).collect::<Vec<_>>(),
        "subscriptions": d.subscriptions.into_iter().map(|s| json!({
            "id": s.id,
            "tier": s.tier,
            "store": s.store,
            "revenuecat_id": s.revenuecat_id,
            "status": s.status,
            "current_period_end": s.current_period_end.map(|t| t.to_string()),
        })).collect::<Vec<_>>(),
        "reports_against": d.reports_against.into_iter().map(|r| json!({
            "id": r.id,
            "reporter_id": r.reporter_id,
            "target_user_id": r.target_user_id,
            "target_kind": r.target_kind,
            "reason": r.reason,
            "status": r.status,
            "created_at": r.created_at.to_string(),
            "resolved_at": r.resolved_at.map(|t| t.to_string()),
        })).collect::<Vec<_>>(),
        "reports_by": d.reports_by.into_iter().map(|r| json!({
            "id": r.id,
            "reporter_id": r.reporter_id,
            "target_user_id": r.target_user_id,
            "target_kind": r.target_kind,
            "reason": r.reason,
            "status": r.status,
            "created_at": r.created_at.to_string(),
            "resolved_at": r.resolved_at.map(|t| t.to_string()),
        })).collect::<Vec<_>>(),
        "consent_records": d.consent_records.into_iter().map(|c| json!({
            "id": c.id,
            "kind": c.kind,
            "version": c.version,
            "granted_at": c.granted_at.to_string(),
        })).collect::<Vec<_>>(),
        "legal_holds": d.legal_holds.into_iter().map(|h| json!({
            "id": h.id,
            "user_id": h.user_id,
            "reason": h.reason,
            "reference": h.reference,
            "placed_by": h.placed_by,
            "placed_at": h.placed_at.to_string(),
            "released_at": h.released_at.map(|t| t.to_string()),
        })).collect::<Vec<_>>(),
    })
}

/// POST /admin/legal/hold
///
/// RBAC: legal.hold (requires_justification, checked inline).
/// Body: { user_id: Uuid, reason: String, reference?: String }.
pub async fn place_legal_hold(
    State(state): State<AppState>,
    staff: StaffAuth,
    Json(body): Json<PlaceLegalHoldRequest>,
) -> Result<
    (AuditTarget, AuditJustification, (StatusCode, Json<Value>)),
    StatusCode,
> {
    if !staff.0.permissions.iter().any(|p| p == "legal.hold") {
        return Err(StatusCode::FORBIDDEN);
    }

    let hold_id = db::support::place_legal_hold(
        &state.pool,
        body.user_id,
        staff.0.id,
        &body.reason,
        body.reference.as_deref(),
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(body.user_id.to_string()),
        AuditJustification(body.reason),
        (StatusCode::CREATED, Json(json!({"id": hold_id}))),
    ))
}

/// POST /admin/legal/hold/:id/release
///
/// RBAC: legal.hold (checked inline).
/// Body: { reason: String }.
pub async fn release_legal_hold(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
    Json(body): Json<ReleaseLegalHoldRequest>,
) -> Result<(AuditTarget, AuditJustification, Json<Value>), StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "legal.hold") {
        return Err(StatusCode::FORBIDDEN);
    }

    db::support::release_legal_hold(&state.pool, id, staff.0.id, &body.reason)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(id.to_string()),
        AuditJustification(body.reason),
        Json(json!({"status": "released"})),
    ))
}
