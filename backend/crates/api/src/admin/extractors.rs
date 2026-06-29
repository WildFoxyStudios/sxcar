//! StaffAuth — extractor de autenticacion para staff.
//!
//! Valida el JWT (Authorization: Bearer <token>), verifica `aud = "admin"`,
//! chequea que la sesion siga activa en DB, y expone `StaffUser`.

use axum::async_trait;
use axum::extract::FromRequestParts;
use axum::http::request::Parts;
use axum::http::StatusCode;
use uuid::Uuid;

use crate::AppState;

/// Staff autenticado, extraido del JWT + sesion activa.
#[derive(Debug)]
pub struct StaffUser {
    pub id: Uuid,
    pub role: String,
    pub permissions: Vec<String>,
    pub session_id: Uuid,
}

/// Extractor: valida JWT y sesion activa.
pub struct StaffAuth(pub StaffUser);

#[async_trait]
impl FromRequestParts<AppState> for StaffAuth {
    type Rejection = StatusCode;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        // 1. Extraer header Authorization: Bearer <token>
        let header = parts
            .headers
            .get(axum::http::header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .ok_or(StatusCode::UNAUTHORIZED)?;
        let token = header
            .strip_prefix("Bearer ")
            .ok_or(StatusCode::UNAUTHORIZED)?;

        // 2. Verificar JWT (valida firma, aud=admin, exp)
        let claims = auth_admin::jwt::verify(&state.admin_jwt_secret, token)
            .map_err(|_| StatusCode::UNAUTHORIZED)?;

        // 3. aud ya fue validado en verify(); extraer campos
        let staff_id: Uuid = claims
            .sub
            .parse()
            .map_err(|_| StatusCode::UNAUTHORIZED)?;

        let session_id: Uuid = claims
            .jti
            .parse()
            .map_err(|_| StatusCode::UNAUTHORIZED)?;

        // 4. Verificar sesion activa en DB
        let _session = db::staff::find_active_session(&state.pool, session_id)
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
            .ok_or(StatusCode::UNAUTHORIZED)?;

        Ok(StaffAuth(StaffUser {
            id: staff_id,
            role: claims.staff_role,
            permissions: claims.permissions,
            session_id,
        }))
    }
}
