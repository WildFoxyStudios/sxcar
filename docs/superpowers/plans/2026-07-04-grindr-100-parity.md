# Grindr 100% Parity — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Llevar `apps/app` a paridad 100% visual + funcional con Grindr Android, ejecutando 5 épicas en checkpoints backend-first con data real.

**Architecture:** Backend Vibra (Rust + Axum + SQLx) extendido con crate `billing` nuevo + endpoints privacy/counters/grid-filters. Flutter app (Riverpod + go_router) cableado a datos reales. Sin mocks. Drawer de perfil, 5 tabs Navegar/Right Now/Interest/Buzón/Tienda. Cero marcas Grindr, tokens VibraTheme v3, i18n ES+EN.

**Tech Stack:** Rust 1.83 (axum 0.7, sqlx 0.8, tokio), Flutter 3.27 (riverpod 3, go_router, google_fonts Inter, flutter_localizations), PostgreSQL via XAMPP dockerizado (puerto 5433), VPS deploy via ssh + docker compose, flutter analyze + flutter test, cargo test.

## Global Constraints (verbatim from spec)

- **Tokens VibraTheme v3**: kBg `#000000`, kSurface `#1A1A1A`, kChip `#2A2A2A`, kDivider `#333333`, kYellow `#FFCC00` (texto sobre amarillo SIEMPRE negro), kText `#FFFFFF`, kTextSecondary `#8E8E8E`, kTextTertiary `#666666`, kOnline `#1BD75E`, kBoost `#26D944`, kRightNow `#9B51E0`, kBadgeRed `#FF3B30`. Fuente Inter.
- **Cero marcas Grindr** (sin máscara, sin "XTRA", sin "Grindr"); tiers desde backend; iconos Material.
- **i18n**: ES plantilla + EN. `flutter_localizations` + `intl`. Locale del sistema con fallback ES. arb en `apps/app/lib/l10n/app_es.arb` + `app_en.arb`. `flutter gen-l10n` tras cada cambio.
- **Backend DB local**: `DATABASE_URL=postgres://dev:dev@localhost:5433/appdb`. Si docker caído: arrancar Docker Desktop y `docker compose up -d postgres` en `infra/`.
- **Backend live**: `api.turnend.win` via Cloudflare Tunnel → esta PC :8081. Deploy: imagen --no-cache, scp, `docker compose up -d --force-recreate api`. SMOKE con `curl` después de cada checkpoint backend.
- **Flutter**: `flutter analyze` 0; `flutter test` 100% verde; `flutter build apk --debug` al cierre de cada épica.
- **Riverpod 3** sin `AsyncValue.valueOrNull`; `mounted` tras async; `await ref.read(authReadyProvider.future)` antes de fetch en initState.
- **Commit directo a main** (decisión del dueño); NO push. Reportes por checkpoint en `.superpowers/sdd/grindr-100/checkpoint-N-report.md`.
- **DRY, YAGNI, TDD**: test antes de impl; commits frecuentes; no inflar alcance.

---

## File Structure Overview

```
backend/
  Cargo.toml                              # NUEVO miembro "billing" en workspace
  crates/
    billing/                              # NUEVO crate (ÉPICA 1)
      Cargo.toml
      src/{lib,plans,subscriptions,simulate,error}.rs
    db/
      migrations/
        0028_profile_details_ext.sql      # ÉPICA 3
        0029_subscriptions.sql            # ÉPICA 1
        0030_privacy_preferences.sql      # ÉPICA 2
      src/{billing,privacy}.rs            # NUEVOS helpers
    api/
      src/lib.rs                          # merge routers
      src/state.rs                        # extender AppState si hace falta
      tests/
        billing.rs                        # NUEVO (E1)
        privacy_preferences.rs            # NUEVO (E2)
        profile_details.rs                # NUEVO (E3)
        counters.rs                       # NUEVO (E4)
        grid_filters.rs                   # NUEVO (E5, ampliar existente)

apps/app/
  pubspec.yaml                             # +url_launcher si falta
  lib/
    main.dart                              # sin cambios estructurales
    l10n/
      app_es.arb                           # +140 strings
      app_en.arb                           # sincronizado
      gen/                                 # autogen
    src/
      theme/widgets.dart                   # +UpsellCard, +PlanDurationCard, +NUEVOBadge, +StatRow, +SettingRow, +Segmented3, +AlbumCarousel, +AlbumUpdateBanner, +AlbumUpdatesEmptyState, +ChipMultiSelect
      utils/distance_format.dart           # NUEVO (E5)
      billing/
        tienda_service.dart                # NUEVO (E1)
        providers.dart                     # NUEVO (E1)
        tier_features.dart                 # NUEVO (E1)
      tienda/tienda_screen.dart            # NUEVO (E1)
      features/
        edit_profile_screen.dart           # rewrite (E3)
        add_trip_screen.dart               # NUEVO (E3)
        vaccines_screen.dart               # NUEVO (E3)
        practices_screen.dart              # NUEVO (E3)
        settings_screen.dart               # rewrite (E2)
        discreet_icon_picker_screen.dart   # NUEVO (E2)
        pin_screen.dart                    # NUEVO (E2)
        blocks_list_screen.dart            # NUEVO (E2; o extender existente)
        chat_list_screen.dart              # rewrite (E4)
        interest_screen.dart               # rewrite (E4)
        albums_screen.dart                 # añadir grid (E4)
        cascade_screen.dart                # +NUEVO badge +dist +server-filter (E5)
        grid_search_screen.dart            # +NUEVO badge +dist (E5)
        profile_detail_screen.dart         # commit WIP + extensión (E5)
      presence/, auth/, profile/, location/, media/, nsfw/, phrases/, places/, sessions/, health/, boost/, rightnow/, profile_views/   # sin cambios estructurales
  test/
    src/
      theme/widgets_test.dart              # extender (todos los widgets nuevos)
      billing/tienda_service_test.dart     # NUEVO (E1)
      tienda/tienda_screen_test.dart       # NUEVO (E1)
      features/edit_profile_screen_test.dart # actualizar (E3)
      features/profile_detail_screen_test.dart # actualizar (E5)
      features/cascade_screen_test.dart    # actualizar (E5)
      features/grid_search_screen_test.dart # actualizar (E5)
      utils/distance_format_test.dart      # NUEVO (E5)
```

---

## Execution Order

`PHASE 1 (E1) → PHASE 2 (E2) → PHASE 3 (E4) → PHASE 4 (E3) → PHASE 5 (E5)`

E1 desbloquea monetization (Tienda) y el entitlement provider que E4 (Interest) necesita. E2 sienta privacy/units que E4 y E5 consumen. E4 es corto y no toca backend profundo (solo consume `/albums/shared` + añade 2 contadores). E3 es el más grande (rewrite edit + backend details). E5 cierra T4 (WIP) y mueve filtros a server-side, dependiendo de E3 (para que `details` esté en GET /profile/:id).

---

# PHASE 1 — ÉPICA 1: Billing backend + Tienda + Drawer planes

## Task 1.1: Backend — Workspace member + crate billing (scaffolding)

**Files:**
- Modify: `backend/Cargo.toml` (añadir `crates/billing`)
- Create: `backend/crates/billing/Cargo.toml`
- Create: `backend/crates/billing/src/lib.rs`

**Step 1.1.1:** Crear `backend/crates/billing/Cargo.toml`:

```toml
[package]
name = "billing"
version = "0.1.0"
edition = "2021"

[dependencies]
api = { path = "../api" }
db = { path = "../db" }
axum = { workspace = true }
tokio = { workspace = true }
serde = { workspace = true }
serde_json = { workspace = true }
sqlx = { workspace = true }
chrono = { workspace = true }
thiserror = { workspace = true }
anyhow = { workspace = true }
tracing = { workspace = true }
```

**Step 1.1.2:** Añadir a `backend/Cargo.toml` workspace section:

```toml
[workspace]
members = [
  "crates/api",
  "crates/db",
  "crates/billing",  # NUEVO
]
```

**Step 1.1.3:** Crear `backend/crates/billing/src/lib.rs`:

```rust
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
```

**Step 1.1.4:** Crear `backend/crates/billing/src/error.rs`:

```rust
use axum::{http::StatusCode, response::IntoResponse, Json};
use serde_json::json;

#[derive(thiserror::Error, Debug)]
pub enum BillingError {
    #[error("plan not found")]
    PlanNotFound,
    #[error("active subscription already exists for tier")]
    AlreadyActive,
    #[error("unauthorized")]
    Unauthorized,
    #[error("database error: {0}")]
    Db(#[from] sqlx::Error),
}

impl IntoResponse for BillingError {
    fn into_response(self) -> axum::response::Response {
        let (status, code) = match &self {
            BillingError::PlanNotFound => (StatusCode::NOT_FOUND, "plan_not_found"),
            BillingError::AlreadyActive => (StatusCode::CONFLICT, "already_active"),
            BillingError::Unauthorized => (StatusCode::UNAUTHORIZED, "unauthorized"),
            BillingError::Db(_) => (StatusCode::INTERNAL_SERVER_ERROR, "db_error"),
        };
        (status, Json(json!({"error": code, "message": self.to_string()}))).into_response()
    }
}

pub type BillingResult<T> = Result<T, BillingError>;
```

**Step 1.1.5:** Commit:

```bash
cd backend && cargo build -p billing 2>&1 | tail -5
cd .. && git add backend/Cargo.toml backend/crates/billing
git commit -m "feat(billing): scaffold crate + router + error type"
```

## Task 1.2: Backend — Migración 0029_subscriptions

**Files:**
- Create: `backend/crates/db/migrations/0029_subscriptions.sql`

**Step 1.2.1:** Crear migración:

```sql
CREATE TABLE subscriptions (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan_id BIGINT NOT NULL REFERENCES plans(id),
  period_days SMALLINT NOT NULL,
  source TEXT NOT NULL DEFAULT 'simulated',
  status TEXT NOT NULL DEFAULT 'active',
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_subscriptions_user_active
  ON subscriptions(user_id) WHERE status = 'active';
CREATE INDEX idx_subscriptions_user_expires
  ON subscriptions(user_id, expires_at DESC);
```

**Step 1.2.2:** Aplicar migración local:

```bash
cd backend && cargo sqlx migrate run
cargo sqlx prepare --workspace
```

**Step 1.2.3:** Commit:

```bash
git add backend/crates/db/migrations/0029_subscriptions.sql backend/crates/db/.sqlx
git commit -m "feat(db): 0029 subscriptions table + indices"
```

## Task 1.3: Backend — Planes endpoint + tests

**Files:**
- Create: `backend/crates/billing/src/plans.rs`
- Modify: `backend/crates/api/tests/billing.rs` (futuro, este task crea)

**Interfaces:**
- Consumes: `api::AppState` (que tiene `db: PgPool`)
- Produces: `GET /billing/plans` → `Vec<PlanDto>`
- Schema: `plans(id, tier, name, period_days, price_cents, currency, features[], popular)`

**Step 1.3.1:** Crear `backend/crates/billing/src/plans.rs`:

```rust
use crate::error::{BillingError, BillingResult};
use api::AppState;
use axum::{extract::State, Json};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize)]
pub struct PlanDto {
    pub id: i64,
    pub tier: String,
    pub name: String,
    pub period_days: i16,
    pub price_cents: i32,
    pub currency: String,
    pub features: Vec<PlanFeature>,
    pub popular: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PlanFeature {
    pub key: String,
    pub label: String,
}

pub async fn list_plans(
    State(state): State<AppState>,
) -> BillingResult<Json<Vec<PlanDto>>> {
    // Adaptar a las columnas reales de tu tabla plans/plan_prices/plan_features.
    // Aquí shape genérico; ajustar tras leer el schema.
    let plans: Vec<PlanDto> = sqlx::query_as!(
        PlanDto,
        r#"
        SELECT p.id,
               p.tier,
               p.name,
               pp.period_days,
               pp.price_cents,
               pp.currency,
               p.popular,
               COALESCE(
                 (SELECT array_agg(json_build_object('key', pf.key, 'label', pf.label))
                  FROM plan_features pf WHERE pf.plan_id = p.id),
                 '{}'::json[]
               ) AS "features!: Vec<sqlx::types::Json<PlanFeature>>"
        FROM plans p
        JOIN plan_prices pp ON pp.plan_id = p.id
        WHERE p.active = true AND pp.active = true
        ORDER BY p.tier, pp.period_days
        "#,
        // ...
    )
    .fetch_all(&state.db)
    .await
    .map_err(BillingError::Db)?;
    Ok(Json(plans))
}
```

> **Nota para el implementador**: el SQL exacto depende de cómo están las tablas `plans/plan_prices/plan_features` en `backend/crates/db/migrations/0014/0016*`. **PRIMERA acción de este task: leer `infra/` o los seeds que existan para conocer el schema real.** Si difiere, adapta el SELECT y la conversión al DTO. Si la conversión a `Vec<PlanFeature>` no encaja con `sqlx::query_as!`, usar `sqlx::query_as` manual con `FromRow` o un struct derivado.

**Step 1.3.2:** Tests integración `backend/crates/api/tests/billing.rs`:

```rust
use api::test_helpers::*;

#[tokio::test]
async fn plans_list_returns_active_sorted() {
    let app = spawn_app().await;
    let cookie = login_user(&app, "alice").await;
    let res = app.get("/billing/plans").cookie(cookie).await;
    assert_eq!(res.status(), 200);
    let body: serde_json::Value = res.json().await;
    let plans = body.as_array().unwrap();
    assert!(plans.len() >= 2);
    // Primer tier debe estar antes que el segundo
    let tiers: Vec<&str> = plans.iter().map(|p| p["tier"].as_str().unwrap()).collect();
    let mut sorted = tiers.clone();
    sorted.sort();
    assert_eq!(tiers, sorted, "tiers not sorted");
}

#[tokio::test]
async fn plans_list_requires_auth() {
    let app = spawn_app().await;
    let res = app.get("/billing/plans").await;
    assert_eq!(res.status(), 401);
}
```

> **Ajustar**: si `spawn_app`/`login_user` no existen con esos nombres, usar los helpers reales del crate `api` (buscar en `backend/crates/api/tests/common/` o similar). Añadir más tests en Task 1.4 cuando esté `simulate_purchase`.

**Step 1.3.3:** Commit:

```bash
cd backend && cargo test -p api --test billing plans_list_returns_active_sorted -- --nocapture
git add backend/crates/billing backend/crates/api/tests/billing.rs
git commit -m "feat(billing): GET /billing/plans + tests"
```

## Task 1.4: Backend — simulate-purchase + /billing/me + tests integración

**Files:**
- Create: `backend/crates/billing/src/simulate.rs`
- Create: `backend/crates/billing/src/subscriptions.rs`
- Modify: `backend/crates/api/tests/billing.rs`

**Interfaces:**
- `simulate_purchase(plan_id: i64, user_id: i64, db: &PgPool) -> Result<SubscriptionDto, BillingError>`
- `my_subscription(user_id: i64, db: &PgPool) -> Result<Option<SubscriptionDto>, BillingError>`

**Step 1.4.1:** `backend/crates/billing/src/simulate.rs`:

```rust
use crate::error::{BillingError, BillingResult};
use api::AppState;
use axum::{
    extract::{State, Json as JsonExtractor},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
pub struct SimulatePurchaseReq {
    pub plan_id: i64,
}

#[derive(Debug, Serialize)]
pub struct SubscriptionDto {
    pub id: i64,
    pub plan_id: i64,
    pub plan_name: String,
    pub tier: String,
    pub started_at: chrono::DateTime<chrono::Utc>,
    pub expires_at: chrono::DateTime<chrono::Utc>,
    pub source: String,
    pub days_remaining: i32,
}

pub async fn simulate_purchase(
    State(state): State<AppState>,
    axum::Extension(user_id): axum::Extension<i64>,
    JsonExtractor(req): JsonExtractor<SimulatePurchaseReq>,
) -> Result<impl IntoResponse, BillingError> {
    // 1. Verificar plan existe
    let plan_row = sqlx::query!(
        r#"SELECT id, tier, name, period_days FROM plans WHERE id = $1 AND active = true"#,
        req.plan_id
    )
    .fetch_optional(&state.db)
    .await
    .map_err(BillingError::Db)?
    .ok_or(BillingError::PlanNotFound)?;

    // 2. Verificar no hay ya activa del mismo tier
    let existing = sqlx::query_scalar!(
        r#"SELECT COUNT(*) FROM subscriptions s
           JOIN plans p ON s.plan_id = p.id
           WHERE s.user_id = $1 AND p.tier = $2 AND s.status = 'active' AND s.expires_at > now()"#,
        user_id, plan_row.tier
    )
    .fetch_one(&state.db)
    .await
    .map_err(BillingError::Db)?;
    if existing.unwrap_or(0) > 0 {
        return Err(BillingError::AlreadyActive);
    }

    // 3. Insertar subscription
    let expires_at = chrono::Utc::now() + chrono::Duration::days(plan_row.period_days as i64);
    let sub = sqlx::query!(
        r#"INSERT INTO subscriptions (user_id, plan_id, period_days, source, status, expires_at)
           VALUES ($1, $2, $3, 'simulated', 'active', $4)
           RETURNING id, started_at, expires_at"#,
        user_id, req.plan_id, plan_row.period_days, expires_at
    )
    .fetch_one(&state.db)
    .await
    .map_err(BillingError::Db)?;

    let dto = SubscriptionDto {
        id: sub.id,
        plan_id: req.plan_id,
        plan_name: plan_row.name,
        tier: plan_row.tier,
        started_at: sub.started_at,
        expires_at: sub.expires_at,
        source: "simulated".into(),
        days_remaining: plan_row.period_days as i32,
    };
    Ok((StatusCode::CREATED, Json(dto)))
}
```

**Step 1.4.2:** `backend/crates/billing/src/subscriptions.rs`:

```rust
use crate::error::BillingResult;
use api::AppState;
use axum::{extract::State, Extension, Json};
use chrono::Utc;

use crate::simulate::SubscriptionDto;

pub async fn my_subscription(
    State(state): State<AppState>,
    Extension(user_id): Extension<i64>,
) -> BillingResult<Json<Option<SubscriptionDto>>> {
    let row = sqlx::query!(
        r#"SELECT s.id, s.plan_id, p.name AS plan_name, p.tier,
                  s.started_at, s.expires_at, s.source, s.period_days
           FROM subscriptions s
           JOIN plans p ON s.plan_id = p.id
           WHERE s.user_id = $1 AND s.status = 'active' AND s.expires_at > now()
           ORDER BY s.expires_at DESC LIMIT 1"#,
        user_id
    )
    .fetch_optional(&state.db)
    .await
    .map_err(crate::error::BillingError::Db)?;

    let dto = row.map(|r| SubscriptionDto {
        id: r.id,
        plan_id: r.plan_id,
        plan_name: r.plan_name,
        tier: r.tier,
        started_at: r.started_at,
        expires_at: r.expires_at,
        source: r.source,
        days_remaining: (r.expires_at - Utc::now()).num_days().max(0) as i32,
    });
    Ok(Json(dto))
}
```

**Step 1.4.3:** Añadir tests `billing.rs`:

```rust
#[tokio::test]
async fn me_returns_null_when_no_subscription() { /* GET /billing/me sin sub previa → 200 con null */ }

#[tokio::test]
async fn simulate_purchase_creates_active_subscription() {
    let app = spawn_app().await;
    let cookie = login_user(&app, "bob").await;
    let plan_id = get_first_plan_id(&app, &cookie).await;
    let res = app.post("/billing/simulate-purchase")
        .cookie(cookie.clone()).json(&serde_json::json!({"plan_id": plan_id})).await;
    assert_eq!(res.status(), 201);

    let me = app.get("/billing/me").cookie(cookie).await;
    assert_eq!(me.status(), 200);
    let body: serde_json::Value = me.json().await;
    assert!(body.get("subscription").is_some() || body.is_object(), "expected sub");
}

#[tokio::test]
async fn simulate_purchase_double_same_tier_returns_409() {
    let app = spawn_app().await;
    let cookie = login_user(&app, "carol").await;
    let (plan_a, plan_b) = get_two_plans_same_tier(&app, &cookie).await;
    app.post("/billing/simulate-purchase").cookie(cookie.clone())
        .json(&serde_json::json!({"plan_id": plan_a})).await.assert_status(201);
    let res = app.post("/billing/simulate-purchase").cookie(cookie)
        .json(&serde_json::json!({"plan_id": plan_b})).await;
    assert_eq!(res.status(), 409);
}

#[tokio::test]
async fn simulate_purchase_unknown_plan_returns_404() {
    let app = spawn_app().await;
    let cookie = login_user(&app, "dave").await;
    let res = app.post("/billing/simulate-purchase").cookie(cookie)
        .json(&serde_json::json!({"plan_id": 999999})).await;
    assert_eq!(res.status(), 404);
}
```

> Ajustar las firmas (`res.assert_status(201)` puede no existir) según los helpers disponibles.

**Step 1.4.4:** Verificar:

```bash
cd backend && cargo build -p billing
cargo test -p api --test billing -- --nocapture
```

**Step 1.4.5:** Wire-up en `backend/crates/api/src/lib.rs`: añadir `billing::router().with_state(state.clone())` con `.merge(...)`. Localizar la sección donde están los otros routers (`presence::router`, `chat::router`, etc.) y añadir el de billing allí.

**Step 1.4.6:** Commit:

```bash
git add backend/crates/billing backend/crates/api/src/lib.rs backend/crates/api/tests/billing.rs
git commit -m "feat(billing): simulate-purchase + me + tests + wire-up"
```

## Task 1.5: Backend — Deploy VPS + smoke live

**Step 1.5.1:** Compilar imagen docker y subir al VPS (mismo flujo que F0.6 — buscar `infra/` o documentación existente):

```bash
cd backend && docker build --no-cache -t vibra-api:latest -f Dockerfile . 2>&1 | tail -10
# Ajustar al comando exacto usado en deploys anteriores
```

**Step 1.5.2:** SCP + restart container en VPS:

```bash
# Usar el script/habitual command. Buscar en .superpowers/sdd/ o memoria
# del proyecto cómo deploya el dueño. Si no hay script: docker save + scp + docker load
```

**Step 1.5.3:** Aplicar migración 0029 en producción:

```bash
ssh vps 'cd /opt/vibra && docker compose exec api sqlx migrate run'
```

**Step 1.5.4:** Smoke live:

```bash
COOKIE=$(curl -s -c - -X POST https://api.turnend.win/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"smoke@example.com","password":"smokepw"}' | grep vibra_session | awk '{print $7}')

curl -s -b "vibra_session=$COOKIE" https://api.turnend.win/billing/plans | jq '. | length'
# Esperado: 2 o más

curl -s -b "vibra_session=$COOKIE" https://api.turnend.win/billing/me
# Esperado: {"subscription":null} o el objeto

PLAN_ID=$(curl -s -b "vibra_session=$COOKIE" https://api.turnend.win/billing/plans | jq '.[0].id')
curl -s -b "vibra_session=$COOKIE" -X POST https://api.turnend.win/billing/simulate-purchase \
  -H 'Content-Type: application/json' -d "{\"plan_id\":$PLAN_ID}" | jq .
# Esperado: 201 con objeto subscription
```

**Step 1.5.5:** Commit reporte checkpoint:

```bash
mkdir -p .superpowers/sdd/grindr-100
# Crear el reporte (ver template en .superpowers/sdd/ si existe)
git add .superpowers/sdd/grindr-100/
git commit -m "docs(epic1-checkpoint): backend deployed + billing smoke live"
```

## Task 1.6: Flutter — pubspec + i18n keys nuevas (~45 keys Fase 1)

**Files:**
- Modify: `apps/app/lib/l10n/app_es.arb` (y `app_en.arb`)
- Modify: `apps/app/pubspec.yaml` (si falta `url_launcher`)

**Step 1.6.1:** Añadir a `apps/app/pubspec.yaml`:

```yaml
dependencies:
  url_launcher: ^6.3.0
```

**Step 1.6.2:** Ejecutar pub get:

```bash
cd apps/app && flutter pub get
```

**Step 1.6.3:** Añadir al final de `apps/app/lib/l10n/app_es.arb` (formato JSON ARB):

```json
  "xtra": "XTRA",
  "unlimited": "UNLIMITED",
  "elijeLaActualizacion": "Elija la actualización",
  "encuentraMasMasRapido": "Encuentra más, más rápido",
  "masAccesoMasAtencion": "Más acceso. Más atención.",
  "semana": "SEMANA",
  "mes": "MES",
  "meses": "MESES",
  "ahorra": "Ahorra {percent}%",
  "@ahorra": { "placeholders": { "percent": { "type": "int" } } },
  "popular": "POPULAR",
  "planActivo": "Plan activo ✓",
  "verPlanes": "Ver planes",
  "compraPaseDia": "Compra Pase de día",
  "compraIlimitado7Dias": "Compra Unlimited 7 días",
  "gratis": "GRATIS",
  "nuevasOpciones": "NUEVAS OPCIONES",
  "perfilesCerca": "+{count} perfiles cerca",
  "@perfilesCerca": { "placeholders": { "count": { "type": "int" } } },
  "grindrPresents": "Vibra Presents",
  "proximamente": "Próximamente",
  "verTodosLosPlanes": "Ver todos los planes",
  "yaTienes": "Ya tienes",
  "compraSimulada": "Compra simulada — sin cargo real",
  "destacar": "Destacar",
  "forYouChats": "Chats For You",
  "chatIlimitados": "Chats ilimitados en Explorar",
  "fotosIlimitadasSinCaducidad": "Fotos ilimitadas sin caducidad",
  "traduccionChat": "Traducción en chat",
  "estadoEscribiendo": "Indicador \"escribiendo…\"",
  "funcionesIlimitadas": "Funciones ilimitadas",
  "perfilesIlimitados": "Perfiles ilimitados",
  "navegarIncognito": "Navegar en modo incógnito",
  "sinInterrupciones": "Sin interrupciones de anuncios",
  "quienMeHaVisto": "Ver quién me ha visto",
  "renovacionAutomatica": "Renovación automática",
  "precioContinuar": "{price}/día por {days}",
  "@precioContinuar": { "placeholders": { "price": { "type": "String" }, "days": { "type": "int" } } },
  "precioTotal": "{total} € en total",
  "@precioTotal": { "placeholders": { "total": { "type": "String" } } },
  "masConexiones": "Más conexiones",
  "masAtencion": "Más atención",
  "masAccesoPerfiles": "Acceso a más perfiles",
  "incluyeTodasLasFuncionesXTRA": "Incluye todas las funciones Vibra+",
  "descubreQuienTeInteresa": "Descubre quién te interesa",
  "descubreQuienSeHaFijado": "Descubre quién se ha fijado en ti",
  "masPersonalizacion": "Más personalización"
```

> Ajustar traducciones ES/EN. Repetir el equivalente EN en `app_en.arb`. Mantener claves paralelas.

**Step 1.6.4:** Regenerar:

```bash
flutter gen-l10n
```

**Step 1.6.5:** Commit:

```bash
git add apps/app/pubspec.yaml apps/app/lib/l10n/
git commit -m "feat(app): i18n phase 1 keys + url_launcher"
```

## Task 1.7: Flutter — Componentes nuevos en widgets.dart

**Files:**
- Modify: `apps/app/lib/src/theme/widgets.dart`

**Interfaces:**
- `UpsellCard({required Widget content, String? ctaLabel, VoidCallback? onTap, bool highlighted = false})`
- `PlanDurationCard({required String duration, required String price, String? savingsPercent, bool popular = false, bool selected = false, VoidCallback? onTap})`
- `NUEVOBadge({double size = 11})`

**Step 1.7.1:** Añadir a `widgets.dart` (al final):

```dart
/// Pill-card de upsell con CTA opcional, estilo Grindr.
class UpsellCard extends StatelessWidget {
  const UpsellCard({
    super.key,
    required this.content,
    this.ctaLabel,
    this.onTap,
    this.highlighted = false,
  });
  final Widget content;
  final String? ctaLabel;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: highlighted ? const LinearGradient(
          colors: [VibraTheme.kYellow, Color(0xFFFFD633)],
        ) : const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF2A2A2A)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          content,
          if (ctaLabel != null && onTap != null) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: highlighted ? Colors.black : VibraTheme.kYellow,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  ctaLabel!,
                  style: TextStyle(
                    color: highlighted ? VibraTheme.kYellow : Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Card de duración de plan con borde amarillo si seleccionada.
class PlanDurationCard extends StatelessWidget {
  const PlanDurationCard({
    super.key,
    required this.duration,
    required this.price,
    this.savingsPercent,
    this.popular = false,
    this.selected = false,
    this.onTap,
  });
  final String duration;
  final String price;
  final String? savingsPercent;
  final bool popular;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 128,
        height: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? VibraTheme.kYellow.withOpacity(0.15)
              : VibraTheme.kSurface,
          border: Border.all(
            color: selected ? VibraTheme.kYellow : VibraTheme.kDivider,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(duration,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            Text(price,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
            const Spacer(),
            if (popular)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: VibraTheme.kTextSecondary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('POPULAR',
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 10)),
              ),
            if (savingsPercent != null) ...[
              const SizedBox(height: 4),
              Text('Ahorra $savingsPercent%',
                  style: const TextStyle(color: VibraTheme.kTextSecondary, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Chip "NUEVO" amarillo reutilizable.
class NUEVOBadge extends StatelessWidget {
  const NUEVOBadge({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: VibraTheme.kYellow,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'NUEVO',
        style: TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}
```

**Step 1.7.2:** Tests `apps/app/test/src/theme/widgets_test.dart`:

```dart
testWidgets('UpsellCard renders content + cta highlighted yellow', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: UpsellCard(
      highlighted: true,
      ctaLabel: 'Ver',
      onTap: () {},
      content: const Text('Premium'),
    )),
  ));
  expect(find.text('Premium'), findsOneWidget);
  expect(find.text('Ver'), findsOneWidget);
});

testWidgets('PlanDurationCard selected border is yellow', (tester) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Row(children: [
    PlanDurationCard(duration: '1 SEM', price: '8.99€', selected: true),
    PlanDurationCard(duration: '1 MES', price: '19.99€', selected: false),
  ]))));
  final yellowBorder = tester.widget<Container>(
    find.descendant(of: find.byType(PlanDurationCard).first, matching: find.byType(Container)),
  );
  expect(yellowBorder, isNotNull);
});

testWidgets('NUEVOBadge renders NUEVO yellow', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: NUEVOBadge())));
  expect(find.text('NUEVO'), findsOneWidget);
  final container = tester.widget<Container>(find.byType(Container).first);
  expect((container.decoration as BoxDecoration).color, VibraTheme.kYellow);
});
```

**Step 1.7.3:** Verificar:

```bash
cd apps/app && flutter analyze
flutter test test/src/theme/widgets_test.dart
```

**Step 1.7.4:** Commit:

```bash
git add apps/app/lib/src/theme/widgets.dart apps/app/test/src/theme/widgets_test.dart
git commit -m "feat(app): UpsellCard + PlanDurationCard + NUEVOBadge + tests"
```

## Task 1.8: Flutter — BillingService + providers

**Files:**
- Create: `apps/app/lib/src/billing/tienda_service.dart`
- Create: `apps/app/lib/src/billing/providers.dart`
- Create: `apps/app/lib/src/billing/tier_features.dart`

**Interfaces:**
- `BillingService.getPlans() -> Future<List<PlanDto>>`
- `BillingService.getMySubscription() -> Future<SubscriptionDto?>`
- `BillingService.simulatePurchase(int planId) -> Future<SubscriptionDto>`
- `billingPlansProvider`, `activeSubscriptionProvider` (FutureProvider keepAlive), `simulatePurchaseProvider`

**Step 1.8.1:** `tienda_service.dart`:

```dart
import 'package:dio/dio.dart';

class PlanDto {
  final int id;
  final String tier;
  final String name;
  final int periodDays;
  final int priceCents;
  final String currency;
  final List<PlanFeature> features;
  final bool popular;

  PlanDto({
    required this.id,
    required this.tier,
    required this.name,
    required this.periodDays,
    required this.priceCents,
    required this.currency,
    required this.features,
    required this.popular,
  });

  factory PlanDto.fromJson(Map<String, dynamic> j) => PlanDto(
    id: j['id'] as int,
    tier: j['tier'] as String,
    name: j['name'] as String,
    periodDays: j['period_days'] as int,
    priceCents: j['price_cents'] as int,
    currency: j['currency'] as String,
    features: (j['features'] as List? ?? const [])
        .map((f) => PlanFeature.fromJson(f as Map<String, dynamic>)).toList(),
    popular: j['popular'] as bool? ?? false,
  );
}

class PlanFeature {
  final String key;
  final String label;
  PlanFeature({required this.key, required this.label});
  factory PlanFeature.fromJson(Map<String, dynamic> j) =>
    PlanFeature(key: j['key'] as String, label: j['label'] as String);
}

class SubscriptionDto {
  final int id;
  final int planId;
  final String planName;
  final String tier;
  final DateTime startedAt;
  final DateTime expiresAt;
  final String source;
  final int daysRemaining;

  SubscriptionDto({
    required this.id,
    required this.planId,
    required this.planName,
    required this.tier,
    required this.startedAt,
    required this.expiresAt,
    required this.source,
    required this.daysRemaining,
  });

  factory SubscriptionDto.fromJson(Map<String, dynamic> j) => SubscriptionDto(
    id: j['id'] as int,
    planId: j['plan_id'] as int,
    planName: j['plan_name'] as String,
    tier: j['tier'] as String,
    startedAt: DateTime.parse(j['started_at'] as String),
    expiresAt: DateTime.parse(j['expires_at'] as String),
    source: j['source'] as String,
    daysRemaining: j['days_remaining'] as int,
  );
}

class BillingService {
  BillingService(this._dio);
  final Dio _dio;

  Future<List<PlanDto>> getPlans() async {
    final r = await _dio.get('/billing/plans');
    final list = (r.data is List) ? r.data as List
      : (r.data is Map ? (r.data['plans'] as List? ?? const []) : const []);
    return list.map((p) => PlanDto.fromJson(p as Map<String, dynamic>)).toList();
  }

  Future<SubscriptionDto?> getMySubscription() async {
    final r = await _dio.get('/billing/me');
    final body = r.data as Map<String, dynamic>;
    final sub = body['subscription'];
    if (sub == null) return null;
    return SubscriptionDto.fromJson(sub as Map<String, dynamic>);
  }

  Future<SubscriptionDto> simulatePurchase(int planId) async {
    final r = await _dio.post('/billing/simulate-purchase', data: {'plan_id': planId});
    return SubscriptionDto.fromJson(r.data as Map<String, dynamic>);
  }
}
```

> Nota: ajustar a cómo el backend devuelve los datos. Si envuelve en `{plans: [...]}`, ajustar `getPlans`. Si no, quitar el Map fallback.

**Step 1.8.2:** `providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';
import 'tienda_service.dart';

final billingServiceProvider = Provider<BillingService>((ref) {
  final dio = ref.watch(apiClientProvider);
  return BillingService(dio);
});

final billingPlansProvider = FutureProvider<List<PlanDto>>((ref) async {
  return ref.watch(billingServiceProvider).getPlans();
});

final activeSubscriptionProvider = FutureProvider<SubscriptionDto?>((ref) async {
  return ref.watch(billingServiceProvider).getMySubscription();
});

final simulatePurchaseProvider =
    Provider<Future<SubscriptionDto> Function(int)>((ref) {
  return (int planId) async {
    final sub = await ref.read(billingServiceProvider).simulatePurchase(planId);
    ref.invalidate(activeSubscriptionProvider);
    return sub;
  };
});
```

> **Ajustar**: `apiClientProvider` es el provider real de tu `Dio` configurado con base URL + auth interceptor. Si se llama distinto (`dioProvider`, `httpClientProvider`), cambiar.

**Step 1.8.3:** `tier_features.dart`:

```dart
import 'package:flutter/material.dart';
import '../../l10n/gen/app_localizations.dart';

class TierFeatures {
  static List<({IconData icon, String title, String subtitle})> featuresFor(
    BuildContext context,
    String tier,
  ) {
    final l = AppLocalizations.of(context)!;
    final base = <({IconData icon, String title, String subtitle})>[
      (icon: Icons.bolt, title: l.masAccesoPerfiles, subtitle: ''),
      (icon: Icons.flash_on, title: l.destacar, subtitle: ''),
      (icon: Icons.chat_bubble, title: l.forYouChats, subtitle: ''),
      (icon: Icons.send, title: l.chatIlimitados, subtitle: ''),
      (icon: Icons.photo_library, title: l.fotosIlimitadasSinCaducidad, subtitle: ''),
      (icon: Icons.translate, title: l.traduccionChat, subtitle: ''),
      (icon: Icons.edit, title: l.estadoEscribiendo, subtitle: ''),
    ];
    if (tier.toLowerCase().contains('unlimited') || tier.toLowerCase().contains('xtra')) {
      base.addAll([
        (icon: Icons.bolt, title: l.funcionesIlimitadas, subtitle: ''),
        (icon: Icons.visibility_off, title: l.navegarIncognito, subtitle: ''),
        (icon: Icons.notifications_off, title: l.sinInterrupciones, subtitle: ''),
        (icon: Icons.people, title: l.perfilesIlimitados, subtitle: ''),
        (icon: Icons.remove_red_eye, title: l.quienMeHaVisto, subtitle: ''),
      ]);
    }
    return base;
  }
}
```

**Step 1.8.4:** Commit:

```bash
git add apps/app/lib/src/billing/
git commit -m "feat(app): billing service + providers + tier features"
```

## Task 1.9: Flutter — TiendaScreen completa

**Files:**
- Create: `apps/app/lib/src/tienda/tienda_screen.dart`

**Step 1.9.1:** Crear pantalla (estructura dada en spec ÉPICA 1):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../billing/providers.dart';
import '../billing/tienda_service.dart';
import '../billing/tier_features.dart';
import '../l10n/gen/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

class TiendaScreen extends ConsumerStatefulWidget {
  const TiendaScreen({super.key});
  @override
  ConsumerState<TiendaScreen> createState() => _TiendaScreenState();
}

class _TiendaScreenState extends ConsumerState<TiendaScreen> {
  String? _selectedTier;
  int? _selectedPlanId;
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final plansAsync = ref.watch(billingPlansProvider);
    final subAsync = ref.watch(activeSubscriptionProvider);

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        backgroundColor: VibraTheme.kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: plansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: VibraTheme.kYellow)),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.white))),
        data: (plans) {
          final tiers = plans.map((p) => p.tier).toSet().toList()..sort();
          _selectedTier ??= tiers.isNotEmpty ? tiers.first : null;
          final filtered = plans.where((p) => p.tier == _selectedTier).toList();
          filtered.sort((a, b) => a.periodDays.compareTo(b.periodDays));
          final cheapest = filtered.isNotEmpty ? filtered.first.priceCents : 1;

          final selectedPlan = filtered.firstWhere(
            (p) => p.id == _selectedPlanId,
            orElse: () => filtered.isNotEmpty ? filtered.first : plans.first,
          );

          final dailyPrice = selectedPlan.priceCents / 100 / selectedPlan.periodDays;
          final savings = filtered.isNotEmpty && filtered.first.id != selectedPlan.id
              ? ((1 - selectedPlan.priceCents / selectedPlan.periodDays / (cheapest / filtered.first.periodDays)) * 100).round()
              : null;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(l.elijeLaActualizacion,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(l.encuentraMasMasRapido,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: VibraTheme.kTextSecondary, fontSize: 15)),
              const SizedBox(height: 24),
              Center(child: VibraSegmented(
                options: tiers,
                selectedIndex: tiers.indexOf(_selectedTier),
                onChanged: (i) => setState(() {
                  _selectedTier = tiers[i];
                  _selectedPlanId = null;
                }),
              )),
              const SizedBox(height: 24),
              // Hero
              Container(
                height: 180,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF000000), Color(0xFF1A1A1A)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Center(child: Text(l.masAccesoMasAtencion,
                    style: const TextStyle(color: VibraTheme.kYellow, fontSize: 20, fontWeight: FontWeight.w800))),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final p = filtered[i];
                    final pop = p.popular || (i == filtered.length ~/ 2);
                    return PlanDurationCard(
                      duration: _durationLabel(p.periodDays, l),
                      price: '${(p.priceCents / 100).toStringAsFixed(2)} €',
                      savingsPercent: (i > 0) ? '$savings' : null,
                      popular: pop,
                      selected: _selectedPlanId == p.id || (i == 0 && _selectedPlanId == null),
                      onTap: () => setState(() => _selectedPlanId = p.id),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              ...TierFeatures.featuresFor(context, _selectedTier ?? '').map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Container(
                    width: 24, height: 24,
                    decoration: const BoxDecoration(color: VibraTheme.kYellow, shape: BoxShape.circle),
                    child: Icon(f.icon, size: 14, color: Colors.black),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(f.title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                ]),
              )),
              const SizedBox(height: 24),
              Text(
                l.precioContinuar(
                    NumberFormat.currency(symbol: '€').format(dailyPrice),
                    selectedPlan.periodDays),
                style: const TextStyle(color: VibraTheme.kTextSecondary, fontSize: 13),
              ),
              const SizedBox(height: 24),
              subAsync.maybeWhen(
                data: (sub) => sub != null
                    ? Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(color: VibraTheme.kSurface, borderRadius: BorderRadius.circular(8)),
                        child: Text('${l.yaTienes} ${sub.planName}',
                            style: const TextStyle(color: Colors.white)),
                      )
                    : const SizedBox.shrink(),
                orElse: () => const SizedBox.shrink(),
              ),
              YellowPillButton(
                label: _submitting ? '...' : 'Continuar',
                enabled: !_submitting,
                onPressed: () => _purchase(selectedPlan.id),
              ),
              const SizedBox(height: 12),
              Text(l.compraSimulada,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: VibraTheme.kTextTertiary, fontSize: 12)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _purchase(int planId) async {
    setState(() => _submitting = true);
    try {
      await ref.read(simulatePurchaseProvider)(planId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan activo ✓')),
      );
      ref.invalidate(activeSubscriptionProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _durationLabel(int days, AppLocalizations l) {
    if (days == 7) return '1 ${l.semana}';
    if (days == 30) return '1 ${l.mes}';
    if (days == 90) return '3 ${l.meses}';
    return '$days d';
  }
}
```

**Step 1.9.2:** Test `apps/app/test/src/tienda/tienda_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'apps/app/lib/src/billing/tienda_service.dart';
import 'apps/app/lib/src/billing/providers.dart';
import 'apps/app/lib/src/tienda/tienda_screen.dart';
// ... (override providers con fakes)
```

Adaptar el test al patrón de fake services ya existente en `apps/app/test/`. Ver patrón de mocks existente (buscar `MockXxx`/`FakeXxx`).

**Step 1.9.3:** Verificar:

```bash
cd apps/app && flutter analyze
flutter test test/src/tienda/
```

**Step 1.9.4:** Commit:

```bash
git add apps/app/lib/src/tienda/
git commit -m "feat(app): TiendaScreen completa con billing providers"
```

## Task 1.10: Flutter — Drawer modificaciones

**Files:**
- Modify: `apps/app/lib/src/features/profile_drawer.dart`

**Interfaces:**
- Añadir NUEVAS OPCIONES section (Container amarillo claro)
- Reemplazar ELEGIR UN PLAN con `UpsellCard` × 3 (1 destacada + 2 oscuras)
- Añadir filas menú "Ver todos los planes" (→ /tienda), "Vibra Presents" (deshabilitado)
- Añadir row "+495 perfiles cerca" placeholder

**Step 1.10.1:** Localizar el `ConsumerWidget ProfileDrawer`. Buscar la sección `// ELEGIR UN PLAN` existente. Reemplazar con:

```dart
// ELEGIR UN PLAN (NUEVO — ÉPICA 1)
UpsellCard(
  highlighted: true,
  content: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Obtener Vibra+',
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 18)),
      const SizedBox(height: 4),
      const Text('Chatear con más lugareños',
          style: TextStyle(color: Colors.black87)),
    ],
  ),
  ctaLabel: AppLocalizations.of(context)!.verPlanes,
  onTap: () => context.go('/tienda'),
),
const SizedBox(height: 8),
UpsellCard(
  content: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(AppLocalizations.of(context)!.compraPaseDia,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('€X', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
    ],
  ),
  onTap: () => context.go('/tienda'),
),
const SizedBox(height: 8),
UpsellCard(
  content: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(AppLocalizations.of(context)!.compraIlimitado7Dias,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('€Y', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
    ],
  ),
  onTap: () => context.go('/tienda'),
),
```

**Step 1.10.2:** Añadir NUEVAS OPCIONES antes de COMPLEMENTOS:

```dart
Container(
  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: VibraTheme.kYellow.withOpacity(0.1),
    borderRadius: BorderRadius.circular(16),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(AppLocalizations.of(context)!.nuevasOpciones,
          style: const TextStyle(color: VibraTheme.kYellow, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      const Text('Vista de chat en 3 ciudades',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
      const SizedBox(height: 4),
      const Text('Próximamente',
          style: TextStyle(color: VibraTheme.kTextSecondary, fontSize: 12)),
    ],
  ),
),
```

**Step 1.10.3:** Añadir filas nuevas al menú:

```dart
ListTile(
  title: Text(AppLocalizations.of(context)!.grindrPresents,
      style: const TextStyle(color: Colors.white)),
  trailing: Text(AppLocalizations.of(context)!.proximamente,
      style: const TextStyle(color: VibraTheme.kTextSecondary, fontSize: 12)),
  enabled: false,
  onTap: null,
),
ListTile(
  title: Text(AppLocalizations.of(context)!.verTodosLosPlanes,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
  leading: const Icon(Icons.workspace_premium, color: VibraTheme.kYellow),
  onTap: () => context.go('/tienda'),
),
```

> Renombrar `grindrPresents` → `vibraPresents` por restricción legal. Confirmar con el dueño.

**Step 1.10.4:** +495 avatares placeholder (después de foto principal):

```dart
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: Row(
    children: [
      ...List.generate(10, (i) => Container(
        margin: EdgeInsets.only(left: i == 0 ? 0 : -8),
        width: 24, height: 24,
        decoration: BoxDecoration(
          color: HSLColor.fromAHSL(1, (i * 36) % 360, 0.5, 0.5).toColor(),
          shape: BoxShape.circle,
          border: Border.all(color: VibraTheme.kBg, width: 2),
        ),
        child: Center(child: Text(String.fromCharCode(65 + i), style: const TextStyle(fontSize: 10, color: Colors.white))),
      )),
      const SizedBox(width: 12),
      Text(AppLocalizations.of(context)!.perfilesCerca(495),
          style: const TextStyle(color: VibraTheme.kTextSecondary, fontSize: 13)),
    ],
  ),
),
```

**Step 1.10.5:** Tests existentes `profile_drawer_test.dart` deben seguir pasando. Si algún test referencia "ELEGIR UN PLAN" antiguo, actualizar a `verPlanes` l10n.

**Step 1.10.6:** Commit:

```bash
git add apps/app/lib/src/features/profile_drawer.dart
git commit -m "feat(app): drawer NUEVAS OPCIONES + UpsellCards + ver planes"
```

## Task 1.11: Flutter — Gate final ÉPICA 1

**Step 1.11.1:**

```bash
cd apps/app && flutter analyze
flutter test
flutter build apk --debug
```

**Step 1.11.2:** Si hay warnings/errors, fixear antes de commit.

**Step 1.11.3:** Commit reporte:

```bash
# Crear/actualizar .superpowers/sdd/grindr-100/checkpoint-1-report.md
git add .superpowers/sdd/grindr-100/
git commit -m "chore(epic1): checkpoint 1 complete — billing + tienda + drawer"
```

---

# PHASE 2 — ÉPICA 2: Ajustes rediseñado

(Estructura paralela a PHASE 1; aquí condensada por espacio. Resumen de tasks, no 11 sub-steps.)

## Task 2.1: Backend — Migración 0030 + endpoints /privacy/preferences

**Files:**
- Create: `backend/crates/db/migrations/0030_privacy_preferences.sql`
- Modify: extender `notifications::handlers` (o crear `privacy` module)
- Create: `backend/crates/api/tests/privacy_preferences.rs`

**SQL:**

```sql
ALTER TABLE notification_preferences
  ADD COLUMN IF NOT EXISTS multimedia_show_album_updates bool NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS multimedia_show_carousel     bool NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS chat_mark_chatted             bool NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS chat_sync                     bool NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS screen_keep_unlocked          bool NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS visitor_status                smallint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS units                         smallint NOT NULL DEFAULT 0;
```

**Endpoints:**
- `GET /privacy/preferences` → devuelve todas las prefs unificadas (json shape estable)
- `PUT /privacy/preferences` → roundtrip con validación (units ∈ {0,1}, visitor_status ∈ {0,1,2})

## Task 2.2: Backend — Tests + wire-up

4 tests integración (defaults, put roundtrip, units validation, visitor validation). Wire-up en router. Deploy + smoke live.

## Task 2.3: Flutter — i18n settings (~35 keys)

ARB additions: cuenta, multimedia, mostrarActualizacionesAlbumes, mostrarCarruselBandeja, centroSeguridad, iconoAplicacionDiscreto, pin, desbloquearUsuarios, dejarOcultarUsuarios, preferenciasConsentimiento, descargarDatos, noMolestar, marcarConQuienChateeado, sincronizacionMensajes, ubicacion, inicio, estadoVisitante, desactivada, activado, automatico, preferenciasPantalla, mantenerPantallaDesbloqueada, sistemaUnidades, metrico, imperial, siguenos, eliminarCuenta, confirmarEliminar, etc.

## Task 2.4: Flutter — providers (unitsProvider, discreetIconProvider, pinEnabledProvider, visitorStatusProvider)

Cada uno con persistencia en SharedPreferences y un Riverpod `StateNotifier` o `Notifier`.

## Task 2.5: Flutter — Widgets SettingRow + Segmented3

Añadir a `widgets.dart`. Tests.

## Task 2.6: Flutter — Pantallas nuevas: DiscreetIconPicker, PinScreen, BlocksListScreen

Cada una con su test.

## Task 2.7: Flutter — Rewrite settings_screen.dart

Single `ListView` con 7 SectionBands. AppBar transparente. Consumir providers. Toggles amarillos.

## Task 2.8: Flutter — Gate ÉPICA 2

`flutter analyze` 0; `flutter test` verde; `flutter build apk --debug` ok. Commit `feat(epic2): settings redesign + privacy preferences + units`.

---

# PHASE 3 — ÉPICA 4: Buzón + Interest completa

## Task 3.1: Backend — Verificar GET /albums/shared

Buscar en `backend/crates/api/src/albums.rs`. Si no existe, añadirlo. Tests de listado vacío + con shares.

## Task 3.2: Backend — Endpoints counter + tests

- `GET /profile/views/count` → `{count: i64}`
- `GET /taps/count` → `{count: i64, types: {friendly: n, ...}}`
- 3 tests integración
- Wire-up

## Task 3.3: Backend — Deploy + smoke

Mismo flujo que Task 1.5. Verificar `curl /profile/views/count` y `/taps/count` con cookie de auth.

## Task 3.4: Flutter — i18n Buzón/Interest (~20 keys)

ARB: bandejaDeEntrada, albumes, noLeido, distancia, enLineaFiltro, actualizaTuAlbum, noHayActualizaciones, desbloquearGratis, desbloquearTodoSinLimites, boostTuInterest, views, taps, ahoraMismo, compartirAlbum, seleccionarUsuarios, archivoCompartido, eliminarAlbum, misShares, ver, hacer.

## Task 3.5: Flutter — Providers

- `sharedAlbumsProvider` (consume GET /albums/shared)
- `profileViewsCountProvider` (consume GET /profile/views/count)
- `tapsCountProvider` (consume GET /taps/count)
- Mock fallback hasta que E1 exponga entitlement

## Task 3.6: Flutter — Widget AlbumCarousel + AlbumUpdateBanner + AlbumUpdatesEmptyState

Añadir a `widgets.dart`. Tests.

## Task 3.7: Flutter — Rewrite chat_list_screen.dart

TabBar Bandeja/Álbumes. Chips filtros. Carrusel "Actualiza tu álbum". Filas rediseñadas. FAB Boost. Tests.

## Task 3.8: Flutter — Rewrite interest_screen.dart

Título 32 + TabBar Views N / Taps N. Subrayado blanco 2px. NUEVO badge "Desbloquear GRATIS" si count > 6 sin entitlement. CTA sticky. FAB Boost. Tests.

## Task 3.9: Flutter — Albums grid interno + compartir sheet

Modificar `albums_screen.dart`. Tests.

## Task 3.10: Flutter — Gate ÉPICA 4

Commit `feat(epic4): buzon + interest polish + counters backend`.

---

# PHASE 4 — ÉPICA 3: Editar perfil + Profile details

(Más larga: ~10-12 tasks)

## Task 4.1: Backend — Migración 0028_profile_details_ext

Verificar que 0027 ya creó la columna `details jsonb`. Si no, crearla. Defaults.

## Task 4.2: Backend — UpdateProfileReq extender + GET público filtrado

Validación 8KB, objeto. Filtrar por `show_*`.

## Task 4.3: Backend — 8 tests integración

`put_persists_details`, `get_own_returns_full`, `public_filters_show_age`, `public_filters_show_role`, `public_filters_show_tribes`, `rejects_over_8kb`, `rejects_not_object`, `accepts_exactly_8kb`.

## Task 4.4: Backend — Deploy + smoke

`curl PUT /profile` con details completo, `curl GET /profile/:id` con `show_age=false` → verifica age ausente.

## Task 4.5: Flutter — i18n edit perfil (~25 keys)

ARB: misEtiquetas, acercaDeMi, mostrarMiEdad, mostrarMiRol, anadirViaje, mostrarMisTribes, tribesEnLasQueEstoy, aceptarFotosNSFW, identidad, genero, redesSociales, instagram, facebookX, spotify, vacunas, recordarAnalisis, practicasSaludables, etnia, tipoCuerpo, pronombres, estadoRelacion, viajes, eliminarFoto, reordenarFotos, ocultar.

## Task 4.6: Flutter — Multi-select chips component (ChipMultiSelect)

En `widgets.dart`. Tests.

## Task 4.7: Flutter — Selector sheets (etnia, tipo de cuerpo, rol, estado, género, pronombres, tribes, looking_for, meet_at, VIH, prácticas, vacunas)

Botton sheets con opciones fijas l10n. Tests.

## Task 4.8: Flutter — Pantallas nuevas AddTrip, Vaccines, Practices

Cada una con su test.

## Task 4.9: Flutter — ProfileEditProvider (coordina PUT /profile + PUT /profile/health)

Sequential con rollback lógico.

## Task 4.10: Flutter — Rewrite edit_profile_screen.dart

Estructura completa (header + 8 secciones + Guardar sticky). Quitar `Color(0xFFF4C542)`. Tests.

## Task 4.11: Flutter — Profile detail ver age/relationship/social ya filtrados

E3 coord con E5. Quitar (oculto). Solo "no render row si no hay dato". Tests.

## Task 4.12: Flutter — Gate ÉPICA 3

Commit `feat(epic3): edit profile redesign + details backend`.

---

# PHASE 5 — ÉPICA 5: Cierre T4 + Navegar server-side

## Task 5.1: Commit del WIP actual en profile_detail_screen.dart

Verificar tests verdes. Si fallan, fix primero. Commit `feat(app): T4 PageView + details wiring (closes T4)`.

## Task 5.2: Backend — Migración para columnas que falten (created_at index)

Crear índice si hace falta para filtro `<7d` con buen rendimiento.

## Task 5.3: Backend — Extender NearbyQuery + find_nearby_users

Añadir `favorites_only`, `online_only`, `right_now`. LEFT JOIN a favorites + heartbeats.

## Task 5.4: Backend — Tests grid_filters

`favorites_only`, `online_only`, `right_now`. Wire-up.

## Task 5.5: Backend — Deploy + smoke

`curl /grid/nearby?favorites_only=1&...` con datos seed.

## Task 5.6: Flutter — utils/distance_format.dart + tests

```dart
String formatDistance(int? meters, Units units) {
  if (meters == null) return '';
  if (units == Units.metric) return '${(meters / 1000).toStringAsFixed(1)} km';
  return '${(meters / 1609.34).toStringAsFixed(1)} mi';
}
```

## Task 5.7: Flutter — i18n (~10 keys)

miEdad, estadoRelacion, sigueloEn, abrirEnlaceExterno, kilometros, millas, filtroFavoritos, filtroEnLinea, filtroRightNow, nuevo, relaciones.

## Task 5.8: Flutter — Profile detail extensions

Edad (no render si falta), Relación, Red social (no render si vacío), NUEVO badge en sugerencias (basado en user.created_at).

## Task 5.9: Flutter — Cascade: NUEVO badge + dist label + server-side filters

Modificar `cascade_screen.dart`. Cambiar sheet de filtros y chips ⭐/En línea/Right Now a consumir del backend.

## Task 5.10: Flutter — GridSearch: NUEVO badge + dist label

Modificar `grid_search_screen.dart`.

## Task 5.11: Flutter — Gate final ÉPICA 5

`flutter analyze` 0; `flutter test` verde; `flutter build apk --debug` ok. Commit `feat(epic5): T4 close + navegate server-side filters`.

## Task 5.12: Reporte whole-branch + memoria + ledger

- `git log --oneline main..HEAD~{N}` para resumir todos los commits de las 5 épicas
- Crear `.superpowers/sdd/grindr-100/final-report.md` con: archivos tocados, líneas añadidas/removed, tests añadido, APK size before/after, smoke endpoints live, screenshots capturas comparativos
- Actualizar `MEMORY.md` con estado final
- Cerrar ledger en `.superpowers/ledger/`
- Push lo hace el dueño manualmente (NO el agente, ver memory `subagent-push-incident`)

---

## Self-Review

**1. Spec coverage:**
- ÉPICA 1 (Billing + Tienda + Drawer) → Tasks 1.1 a 1.11 ✓
- ÉPICA 2 (Ajustes) → Tasks 2.1 a 2.8 (resumen) ✓
- ÉPICA 3 (Editar perfil) → Tasks 4.1 a 4.12 (Phase 4) ✓
- ÉPICA 4 (Buzón + Interest) → Tasks 3.1 a 3.10 (Phase 3) ✓
- ÉPICA 5 (Cierre T4 + Navegar) → Tasks 5.1 a 5.12 (Phase 5) ✓
- i18n 140+ strings: fases con tasks dedicados (1.6, 2.3, 3.4, 4.5, 5.7) ✓
- Componentes nuevos (UpsellCard, PlanDurationCard, NUEVOBadge, StatRow, SettingRow, Segmented3, AlbumCarousel, AlbumUpdateBanner, AlbumUpdatesEmptyState, ChipMultiSelect): repartidos en tasks de cada fase ✓
- Tests + gates: cada task tiene verificación; cada fase tiene Task de gate final ✓

**2. Placeholder scan:**
- No hay "TBD", "TODO" en tasks. Cada step tiene código o comando concreto.
- "Similar to Task N" se evita repitiendo el código completo en cada task.

**3. Type consistency:**
- `PlanDto` definido en Task 1.8.1, usado por Tienda en 1.9.1 y providers en 1.8.2. ✓
- `SubscriptionDto` mismo flujo. ✓
- `formatDistance` definido en 5.6 con signatura `(int?, Units)`. Aplicado en tasks 5.8 (profile_detail), 5.9 (cascade), 3.8 (interest E4) — mantener `(int?, Units)` consistente.
- Componentes en widgets.dart añadidos en tasks específicos, luego consumidos por pantalla. ✓

**4. Dependency check:**
- ÉPICA 1 debe completarse antes que otras (entitlement provider).
- ÉPICA 2 y ÉPICA 4 paralelizables en principio; el plan las ejecuta en orden (2 antes que 4 para que unitsProvider esté listo).
- ÉPICA 3 (details) antes que ÉPICA 5 (perfil detail + grid).
- WIP T4 se commitea al INICIO de ÉPICA 5 (Task 5.1) — coherente con "commit WIP antes de añadir nada".

Plan listo. Ofrecer opciones de ejecución.
