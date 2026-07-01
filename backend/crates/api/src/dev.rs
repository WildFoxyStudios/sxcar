//! Dev seed endpoint — creates 20 fake users for development/testing.
//!
//! Only active when `DEV_SEED_ENABLED=true` is set at request time.

use axum::extract::State;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use rand::Rng;
use rand::SeedableRng;
use serde::Serialize;
use std::sync::Arc;
use std::convert::Infallible;

use crate::AppState;

#[derive(Serialize)]
struct SeedResponse {
    message: String,
    user_count: usize,
}

/// Build a tower service that handles `/dev/seed`.
pub fn seed_service() -> axum::routing::MethodRouter<AppState, Infallible> {
    axum::routing::post(
        |State(state): State<AppState>| async move { seed_inner(Arc::new(state)).await },
    )
}

async fn seed_inner(state: Arc<AppState>) -> Response {
    // Gate: only active when the env var is set at request time
    if std::env::var("DEV_SEED_ENABLED").as_deref() != Ok("true") {
        return StatusCode::NOT_FOUND.into_response();
    }

    match do_seed(&state).await {
        Ok(response) => (StatusCode::OK, Json(response)).into_response(),
        Err(status) => status.into_response(),
    }
}

async fn do_seed(state: &AppState) -> Result<SeedResponse, StatusCode> {
    let mut rng = rand::rngs::StdRng::from_entropy();

    let display_names = [
        "Carlos", "Miguel", "Alejandro", "Fernando", "Diego",
        "Santiago", "Mateo", "Andres", "Gabriel", "Luis",
        "Valentina", "Camila", "Sofia", "Isabella", "Ximena",
        "Renata", "Regina", "Paula", "Mia", "Abril",
    ];

    let bios = [
        "Amante del cafe y los atardeceres",
        "Fitness lover y aventurero",
        "Cinefilo buscando maratonear",
        "Chef en fin de semana, ingeniero entre semana",
        "Viajero con pasaporte lleno",
        "Musico y creativo de corazon",
        "Amante de los perros y la naturaleza",
        "Yogui y lector empedernido",
        "CEO de mi propio destino",
        "Amante del arte y la buena conversacion",
        "Sushi lover y viajera frecuente",
        "Runner y amante del yoga",
        "Fotografa aficionada buscando musa",
        "Escritora de corazones rotos",
        "Disenadora grafica y foodie",
        "Bailarina de salsa y bachata",
        "Arquitecta de suenos raros",
        "Medica de profesion, artista de corazon",
        "Emprendedora y cafeinodependiente",
        "Programadora por el dia, DJ por la noche",
    ];

    let body_types = ["slim", "athletic", "average", "muscular", "curvy", "bear", "fit"];
    let positions = ["top", "vers_top", "versatile", "vers_bottom", "bottom", "side"];
    let relationship_statuses = ["single", "open", "dating", "divorced", "married"];
    let tribes_pool = [
        "bear", "otter", "twink", "jock", "geek", "daddy", "leather",
        "military", "pup", "muscle", "chub", "diverse",
    ];
    let looking_for_pool = [
        "chat", "friends", "dates", "relationship", "networking",
        "hookup", "travel_buddy",
    ];

    let tap_types = ["fire", "wave", "smile", "hello"];

    let base_lat = 19.4;
    let base_lon = -99.1;

    let mut user_ids: Vec<uuid::Uuid> = Vec::with_capacity(20);

    for i in 0..20 {
        let email = format!("dev_user_{}@vibra.test", i);

        // Insert with ON CONFLICT to handle re-runs
        let user_id = sqlx::query_scalar::<_, uuid::Uuid>(
            r#"INSERT INTO users (email, password_hash, age_verified, email_verified)
               VALUES ($1, NULL, true, true)
               ON CONFLICT (email) DO UPDATE SET age_verified = true, email_verified = true
               RETURNING id"#
        )
        .bind(&email)
        .fetch_one(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!("dev seed create user error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

        // Ensure email_verified is set
        let _ = db::users::set_email_verified(&state.pool, user_id).await;

        let body_type = body_types[rng.gen_range(0..body_types.len())];
        let position = positions[rng.gen_range(0..positions.len())];
        let relationship_status = relationship_statuses[rng.gen_range(0..relationship_statuses.len())];

        db::profiles::upsert_profile(
            &state.pool,
            user_id,
            Some(display_names[i]),
            Some(bios[i]),
            None,
            None,
            None,
            Some(body_type),
            Some(relationship_status),
            Some(position),
            None,
            None,
        )
        .await
        .map_err(|e| {
            tracing::error!("dev seed upsert_profile error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

        // Assign 1-3 random tribes (no duplicates)
        let tribe_count = rng.gen_range(1..=3);
        let mut tribes: Vec<String> = Vec::with_capacity(tribe_count);
        for _ in 0..tribe_count {
            let t = tribes_pool[rng.gen_range(0..tribes_pool.len())].to_string();
            if !tribes.contains(&t) {
                tribes.push(t);
            }
        }
        db::profiles::replace_profile_tribes(&state.pool, user_id, &tribes)
            .await
            .map_err(|e| {
                tracing::error!("dev seed replace_profile_tribes error: {e}");
                StatusCode::INTERNAL_SERVER_ERROR
            })?;

        // Assign 1-3 random looking_for values (no duplicates)
        let lf_count = rng.gen_range(1..=3);
        let mut looking_for: Vec<String> = Vec::with_capacity(lf_count);
        for _ in 0..lf_count {
            let lf = looking_for_pool[rng.gen_range(0..looking_for_pool.len())].to_string();
            if !looking_for.contains(&lf) {
                looking_for.push(lf);
            }
        }
        db::profiles::replace_profile_looking_for(&state.pool, user_id, &looking_for)
            .await
            .map_err(|e| {
                tracing::error!("dev seed replace_profile_looking_for error: {e}");
                StatusCode::INTERNAL_SERVER_ERROR
            })?;

        // Random location around Mexico City (lat ±0.1, lon ±0.1)
        let lat = base_lat + (rng.gen::<f64>() - 0.5) * 0.2;
        let lon = base_lon + (rng.gen::<f64>() - 0.5) * 0.2;
        db::geo::upsert_location(&state.pool, user_id, lon, lat)
            .await
            .map_err(|e| {
                tracing::error!("dev seed upsert_location error: {e}");
                StatusCode::INTERNAL_SERVER_ERROR
            })?;

        user_ids.push(user_id);
    }

    // Create taps: users 0..10 tap users 10..20 respectively
    for i in 0..10 {
        let tap_type = tap_types[rng.gen_range(0..tap_types.len())];
        db::social::create_tap(&state.pool, user_ids[i], user_ids[10 + i], tap_type)
            .await
            .map_err(|e| {
                tracing::error!("dev seed create_tap error: {e}");
                StatusCode::INTERNAL_SERVER_ERROR
            })?;
    }

    // Favorites: users 0..5 favorite users 5..10
    for i in 0..5 {
        db::social::add_favorite(&state.pool, user_ids[i], user_ids[5 + i])
            .await
            .map_err(|e| {
                tracing::error!("dev seed add_favorite error: {e}");
                StatusCode::INTERNAL_SERVER_ERROR
            })?;
    }

    Ok(SeedResponse {
        message: "Seeded 20 users".to_string(),
        user_count: user_ids.len(),
    })
}
