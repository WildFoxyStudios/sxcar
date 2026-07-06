# Onboarding Wizard + Production Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a read-only audit of all placeholders/stubs/simulated logic across backend, app, admin AND a profile-completion onboarding wizard for newly-registered users (4 required + 10 optional cards), backed by a new `users.onboarding_completed_at` column that hides unfinished users from `/grid/nearby`.

**Architecture:** Three task groups. (A) Audit tasks T1–T4: 3 parallel read-only sweeps (backend / app / admin) + 1 cross-app consistency table; deliverable is one markdown file. (B) Backend onboarding tasks T5–T10: migration, state types, handlers, grid filter, integration tests. (C) Flutter wizard tasks T11–T18: models, provider, screen, 14 card widgets, router guard, i18n, tests. **Phase 1 fixes (P0+P1 from the audit) are out of scope here** — they are a separate plan that will be written after the audit deliverable is reviewed.

**Tech Stack:** Rust 1.96 (axum 0.7, sqlx 0.8, time, uuid, serde), Neon Postgres, Cloudflare R2 (existing), Flutter (Dart, ChangeNotifier provider, l10n .arb files), Riverpod-free (existing pattern: ChangeNotifier + Provider).

**Spec:** `docs/superpowers/specs/2026-07-06-onboarding-wizard-audit-design.md` (commit `664aec91`).

## Global Constraints

- **Required cards (4):** profile_photo, display_name, age, gender_position. Until all four complete, `users.onboarding_completed_at` stays NULL and the user is **excluded from `/grid/nearby` for everyone else** (their own profile detail still works).
- **Optional cards (10):** looking_for, tribes, vaccines, practices, about_me, height, weight, relationship_status, position_preference, ethnicity. Each optional has a "Skip" button that records the skip in `users.onboarding_skipped_cards` (JSONB) — skipped cards no longer appear in the wizard if the user closes and reopens it.
- **Audit deliverable:** `docs/superpowers/audits/2026-07-06-full-audit.md` with P0–P4 prioritized findings and exact file:line citations. Read-only — no commits during the audit itself.
- **New migration:** `0039_onboarding.sql` adds `onboarding_completed_at` + `onboarding_skipped_cards` to `users`. Additive + NULL/default, safe to run live.
- **Backward compat:** all wizard endpoints require auth; no anonymous access.
- **No git push** (standing rule from `subagent-push-incident` memory).
- **No secrets in chat / git / new files** (Neon password, R2 keys, JWT secret, TOTP KEK, SMTP key, OAuth client IDs, Firebase SA JSON). `backend/.env` and the box `~/proyectox/.env` are both gitignored.
- **Deploy recipe (only used if a Phase 2 task requires it):** build image on PC → `docker save|gzip` → scp → `docker load` → `docker compose up -d api` (see `live-tunnel-infra.md`). All Phase 2 backend tasks compile but no deploy is performed in this plan — the user will deploy manually after reviewing the diff.
- **i18n:** every new user-facing string in Flutter MUST go through `AppLocalizations.of(context)!.<key>`. No hardcoded English or Spanish in code.
- **Code reuse:** the per-card widgets in the wizard import the existing input widgets from `edit_profile_screen.dart` and `sheets.dart`. Do NOT duplicate validation/sanitization logic — if the existing field has a `sanitize_*` function, use it. The wizard and the post-wizard edit-profile flow must validate identically.

---

## Group A — Audit (read-only, no code changes)

### Task 1: Backend audit sweep

**Files:**
- Read: every `.rs` file under `backend/crates/**`
- Read: every file in `backend/migrations/`
- Write: append to `docs/superpowers/audits/2026-07-06-full-audit.md` (creates the file)

**Interfaces:**
- Consumes: nothing (first task)
- Produces: the "## Backend (P0-P4)" section of the audit file

- [ ] **Step 1: Create the audit file with the section header**

Create `docs/superpowers/audits/2026-07-06-full-audit.md` with the skeleton:

```markdown
# proyecto-X Full Audit — 2026-07-06

## Summary
(populated by Task 4)

## Methodology
- Read-only scan of `backend/crates/**`, `apps/app/lib/src/**`, `apps/admin/lib/src/**`.
- Tools: `grep -rE` patterns, `Read` of suspicious files, cross-reference with `git log --oneline -- <file>`.
- Each finding has a `file:line` citation and a concrete fix recommendation.
- P0 = breaks production; P1 = broken UX flow; P2 = missing/non-functional feature; P3 = placeholder/stub/simulated logic; P4 = cleanup.

## Backend
(populated by Task 1)

## App
(populated by Task 2)

## Admin
(populated by Task 3)

## Cross-app consistency
(populated by Task 4)

## Out of scope
(populated by Task 4)
```

- [ ] **Step 2: Grep the backend for known placeholder patterns**

Run from the repo root:

```bash
cd C:/Users/echev/Desktop/proyecto-X
echo "=== todo!()/unimplemented!/unreachable! ==="
grep -rnE 'todo!|unimplemented!|unreachable!' backend/crates/ --include='*.rs' | grep -v target/ | head -30
echo "=== // TODO/FIXME/XXX/HACK ==="
grep -rnE '// *(TODO|FIXME|XXX|HACK)' backend/crates/ --include='*.rs' | head -30
echo "=== println!/eprintln!/dbg! in non-test code ==="
grep -rnE '\b(println!|eprintln!|dbg!)\(' backend/crates/ --include='*.rs' | grep -vE 'test|tests/|cfg\(test\)' | head -20
echo "=== simulated/mock/stub/fake/dummy/dev_only in identifiers ==="
grep -rnE '\b(simulate_|mock_|fake_|stub_|dummy_|dev_only_)' backend/crates/ --include='*.rs' | head -30
echo "=== files named simulate/mock/stub/fake/dev ==="
find backend/crates -name 'simulate*.rs' -o -name 'mock*.rs' -o -name 'stub*.rs' -o -name 'fake*.rs' -o -name 'dev*.rs' | head -10
```

Expected: at minimum, `backend/crates/api/src/billing/simulate.rs` and `backend/crates/api/src/dev.rs` will appear. Capture all results.

- [ ] **Step 3: Read the suspicious backend files in full**

Read in full:
- `backend/crates/api/src/billing/simulate.rs`
- `backend/crates/api/src/billing/mod.rs`
- `backend/crates/api/src/billing/subscriptions.rs`
- `backend/crates/api/src/billing/plans.rs`
- `backend/crates/api/src/billing/webhook.rs`
- `backend/crates/api/src/billing/error.rs`
- `backend/crates/api/src/dev.rs`
- `backend/crates/api/src/tier1.rs`
- `backend/crates/api/src/tier2.rs`
- `backend/crates/api/src/tier3.rs`
- `backend/crates/api/src/grindr_t1.rs`
- `backend/crates/api/src/chat_broker.rs`
- `backend/crates/api/src/fcm.rs`
- `backend/crates/api/src/notifications.rs`
- `backend/crates/api/src/stories.rs`
- `backend/crates/api/src/profile.rs`
- `backend/crates/api/src/grid.rs`
- `backend/crates/api/src/admin/handlers.rs`
- `backend/crates/api/src/admin/handlers_enterprise.rs`
- `backend/crates/api/src/admin/audit.rs`
- `backend/crates/api/src/main.rs` (verify the `migrate` subcommand is wired, the api binary entrypoint is real, not a stub)

For each file, identify:
1. Empty handler bodies (function with `Ok(())` and 1-2 statements)
2. Endpoints that always return mock data
3. `tracing::warn!` or `tracing::error!` containing "TODO", "not implemented", "placeholder", "stub", "simulate"
4. Functions that ignore their arguments and return a hardcoded value
5. `#[cfg(...)]` gates that may be hiding real code from release builds

- [ ] **Step 4: Verify all migrations apply cleanly to a fresh DB**

From the repo root:

```bash
cd C:/Users/echev/Desktop/proyecto-X
# Create a throwaway local DB (does NOT touch Neon)
docker run --rm -d --name audit-pg -e POSTGRES_PASSWORD=audit -p 55433:5432 postgres:16-alpine
sleep 3
DATABASE_URL=postgres://postgres:audit@localhost:55433/postgres
# Apply all migrations including 0039 (which doesn't exist yet — that's fine for THIS task; we verify the pre-0039 set)
DATABASE_URL=$DATABASE_URL cd backend && cargo run --release --bin api -- migrate 2>&1 | tail -20
docker stop audit-pg
```

Expected: the migration subcommand logs `INFO api: migrations applied` and exits 0. If it fails on any migration other than 0039, that's a P0 finding — record it. **Skip 0039 here** — that migration is created in Task 5.

- [ ] **Step 5: Write the Backend section of the audit file**

Append to `docs/superpowers/audits/2026-07-06-full-audit.md` (replace the "## Backend\n(populated by Task 1)" line):

```markdown
## Backend

### P0 — Breaks production
[list each P0 finding with: file:line, what, impact, fix]

### P1 — Broken UX flows
[list each P1 finding]

### P2 — Missing or non-functional features
[list each P2 finding]

### P3 — Placeholders / stubs / simulated logic
[list each P3 finding]

### P4 — Cleanup
[list each P4 finding]
```

If a category has no findings, write `None.` for that category. Every finding has the four fields above.

- [ ] **Step 6: Commit the audit file**

```bash
cd C:/Users/echev/Desktop/proyecto-X
git add docs/superpowers/audits/2026-07-06-full-audit.md
git commit -m "audit: backend placeholder/stub scan (task 1)

Read-only scan of backend/crates/** with grep + manual file reads.
Findings categorized P0-P4. Phase 1 fixes deferred to a follow-up plan.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: App audit sweep

**Files:**
- Read: every `.dart` file under `apps/app/lib/src/**` (skip `l10n/gen/` and `graphify-out/`)
- Modify: append to `docs/superpowers/audits/2026-07-06-full-audit.md`

**Interfaces:**
- Consumes: the "## App\n(populated by Task 2)" placeholder from Task 1
- Produces: the "## App" section of the audit file

- [ ] **Step 1: Grep the Flutter app for placeholder patterns**

From the repo root:

```bash
cd C:/Users/echev/Desktop/proyecto-X
echo "=== TODO/FIXME/XXX ==="
grep -rnE '// *(TODO|FIXME|XXX)' apps/app/lib/src --include='*.dart' | head -40
echo "=== UnimplementedError ==="
grep -rnE 'UnimplementedError|throw.*[Nn]ot implemented' apps/app/lib/src --include='*.dart' | head -20
echo "=== ignore: lines ==="
grep -rnE '^// *ignore:' apps/app/lib/src --include='*.dart' | wc -l
echo "=== print() outside main ==="
grep -rnE '\bprint\(' apps/app/lib/src --include='*.dart' | grep -v 'main\.dart' | head -20
echo "=== hardcoded English strings (heuristic) ==="
grep -rnE "['\"]([A-Z][a-zA-Z]+ ){2,}[a-zA-Z]+['\"]" apps/app/lib/src --include='*.dart' | grep -v l10n | head -20
echo "=== TODO(l10n)/TODO(i18n) ==="
grep -rnE 'TODO\((l10n|i18n)\)' apps/app/lib/src --include='*.dart' | head -20
echo "=== mock/fake/stub/dummy in identifiers ==="
grep -rnE '\b(mock|fake|stub|dummy|_placeholder)' apps/app/lib/src --include='*.dart' | head -20
```

- [ ] **Step 2: Read the suspicious app files in full**

Read in full (these are the highest-signal files based on the spec and prior memory):
- `apps/app/lib/src/features/edit_profile_screen.dart`
- `apps/app/lib/src/features/home_screen.dart`
- `apps/app/lib/src/features/login_screen.dart`
- `apps/app/lib/src/features/register_screen.dart`
- `apps/app/lib/src/features/grid_search_screen.dart`
- `apps/app/lib/src/features/chat_screen.dart`
- `apps/app/lib/src/features/chat_list_screen.dart`
- `apps/app/lib/src/features/profile_detail_screen.dart`
- `apps/app/lib/src/features/profile_screen.dart`
- `apps/app/lib/src/features/profile_drawer.dart`
- `apps/app/lib/src/features/albums_screen.dart`
- `apps/app/lib/src/features/album_detail_screen.dart`
- `apps/app/lib/src/features/circles_screen.dart`
- `apps/app/lib/src/features/create_story_screen.dart`
- `apps/app/lib/src/features/right_now_screen.dart`
- `apps/app/lib/src/features/security_screen.dart`
- `apps/app/lib/src/features/pin_screen.dart`
- `apps/app/lib/src/calls/call_screen.dart`
- `apps/app/lib/src/calls/call_service.dart`
- `apps/app/lib/src/billing/revenuecat_service.dart`
- `apps/app/lib/src/billing/billing_service.dart`
- `apps/app/lib/src/billing/tier_features.dart`
- `apps/app/lib/src/ads/ad_provider.dart`
- `apps/app/lib/src/notifications/` (all files)
- `apps/app/lib/src/auth/auth_service.dart`
- `apps/app/lib/src/auth/auth_provider.dart`
- `apps/app/lib/src/auth/api_client.dart`

For each, look for:
1. Commented-out code blocks (5+ consecutive lines starting with `//`)
2. Hardcoded data that should be from the API
3. `// ignore:` lines that mask real issues
4. `print()` calls leaking to production
5. Untranslated English strings (any `'...'` in a Text widget not wrapped in l10n)
6. Methods that return `Future.value(null)` with no body
7. Empty `build()` methods (only `return const SizedBox.shrink();`)

- [ ] **Step 3: Append the App section to the audit file**

Edit `docs/superpowers/audits/2026-07-06-full-audit.md` to replace the `## App\n(populated by Task 2)` line with the same P0-P4 structure as the Backend section.

- [ ] **Step 4: Commit the app section**

```bash
cd C:/Users/echev/Desktop/proyecto-X
git add docs/superpowers/audits/2026-07-06-full-audit.md
git commit -m "audit: app placeholder/stub scan (task 2)

Read-only scan of apps/app/lib/src/** with grep + manual file reads.
Findings categorized P0-P4.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Admin audit sweep

**Files:**
- Read: every `.dart` file under `apps/admin/lib/src/**`
- Modify: append to `docs/superpowers/audits/2026-07-06-full-audit.md`

**Interfaces:**
- Consumes: the "## Admin\n(populated by Task 3)" placeholder from Task 1
- Produces: the "## Admin" section of the audit file

- [ ] **Step 1: Grep the admin panel**

```bash
cd C:/Users/echev/Desktop/proyecto-X
echo "=== TODO/FIXME/XXX ==="
grep -rnE '// *(TODO|FIXME|XXX)' apps/admin/lib/src --include='*.dart' | head -30
echo "=== UnimplementedError ==="
grep -rnE 'UnimplementedError|throw.*[Nn]ot implemented' apps/admin/lib/src --include='*.dart' | head -10
echo "=== ignore: count ==="
grep -rnE '^// *ignore:' apps/admin/lib/src --include='*.dart' | wc -l
echo "=== hardcoded English strings ==="
grep -rnE "['\"]([A-Z][a-zA-Z]+ ){2,}[a-zA-Z]+['\"]" apps/admin/lib/src --include='*.dart' | head -20
```

- [ ] **Step 2: Read all 13 admin screens in full + key infra files**

Read in full:
- `apps/admin/lib/src/features/audit/audit_screen.dart`
- `apps/admin/lib/src/features/config/abuse_rules_screen.dart`
- `apps/admin/lib/src/features/config/countries_screen.dart`
- `apps/admin/lib/src/features/config/flags_screen.dart`
- `apps/admin/lib/src/features/config/plans_screen.dart`
- `apps/admin/lib/src/features/content/cms_screen.dart`
- `apps/admin/lib/src/features/content/legal_docs_screen.dart`
- `apps/admin/lib/src/features/content/templates_screen.dart`
- `apps/admin/lib/src/features/content/translations_screen.dart`
- `apps/admin/lib/src/features/dashboard/dashboard_screen.dart`
- `apps/admin/lib/src/features/gdpr/data_requests_screen.dart`
- `apps/admin/lib/src/features/growth/campaigns_screen.dart`
- `apps/admin/lib/src/features/growth/experiments_screen.dart`
- `apps/admin/lib/src/features/login/login_screen.dart`
- `apps/admin/lib/src/features/login/totp_screen.dart`
- `apps/admin/lib/src/features/moderation/csam_screen.dart`
- `apps/admin/lib/src/features/moderation/reports_screen.dart`
- `apps/admin/lib/src/features/settings/api_keys_screen.dart`
- `apps/admin/lib/src/features/settings/webhooks_screen.dart`
- `apps/admin/lib/src/features/users/user_detail_screen.dart`
- `apps/admin/lib/src/features/users/user_list_screen.dart`
- `apps/admin/lib/src/auth/admin_auth_service.dart`
- `apps/admin/lib/src/widgets/admin_http_client.dart`

For each, verify:
1. The screen makes a real HTTP call to the backend (not hardcoded data)
2. Error states are handled (not silently swallowed)
3. Empty/loading states exist
4. TOTP flow is real (not a static bypass)

- [ ] **Step 3: Append the Admin section to the audit file**

Edit `docs/superpowers/audits/2026-07-06-full-audit.md` to replace `## Admin\n(populated by Task 3)` with the same P0-P4 structure.

- [ ] **Step 4: Commit the admin section**

```bash
cd C:/Users/echev/Desktop/proyecto-X
git add docs/superpowers/audits/2026-07-06-full-audit.md
git commit -m "audit: admin placeholder/stub scan (task 3)

Read-only scan of apps/admin/lib/src/**. Findings categorized P0-P4.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Cross-app consistency + final audit summary

**Files:**
- Modify: `docs/superpowers/audits/2026-07-06-full-audit.md`

**Interfaces:**
- Consumes: tasks 1-3 sections
- Produces: the "## Summary", "## Cross-app consistency", "## Out of scope" sections + replaces the placeholders

- [ ] **Step 1: Extract the endpoint ↔ screen mapping**

From the repo root:

```bash
cd C:/Users/echev/Desktop/proyecto-X
echo "=== Backend endpoints (axum routes) ==="
grep -rnE 'route\(.*(\.get|\.post|\.put|\.delete|\.patch)' backend/crates/api/src --include='*.rs' | grep -oE '"/[^"]+"' | sort -u | head -100
echo "=== App service calls (Dart api.postJson / getJson) ==="
grep -rnE 'api\.(getJson|postJson|putJson|delete)\(' apps/app/lib/src --include='*.dart' | grep -oE "['\"](/[^'\"]+)['\"]" | sort -u | head -100
echo "=== Admin HTTP calls ==="
grep -rnE '_client\.(get|post|put|delete)' apps/admin/lib/src --include='*.dart' | head -50
```

- [ ] **Step 2: Build the cross-app table**

For each endpoint, mark whether the app and admin call it. For each screen, mark whether there's a backend endpoint. Anything that doesn't match is a finding (P2 = missing feature, P3 = dead code).

- [ ] **Step 3: Write the Summary, Cross-app consistency, and Out of scope sections**

Replace the three remaining placeholders in the audit file. The Summary includes:
- Total findings count per priority
- Estimated effort for P0+P1 (in person-hours)
- Top 3 critical risks

The Out of scope section restates the explicit deferrals from the spec (Discover, Travel Pass, Tribes-as-filter, Events, Shop, 3-tier premium).

- [ ] **Step 4: Commit the final audit**

```bash
cd C:/Users/echev/Desktop/proyecto-X
git add docs/superpowers/audits/2026-07-06-full-audit.md
git commit -m "audit: cross-app consistency table + summary (task 4)

Completes the audit deliverable. Phase 1 (P0+P1 fixes) is a
follow-up plan written after this review.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Group B — Backend onboarding

### Task 5: Migration 0039 (additive)

**Files:**
- Create: `backend/migrations/0039_onboarding.sql`

**Interfaces:**
- Consumes: the existing `users` table schema
- Produces: new columns `onboarding_completed_at` (NULL) + `onboarding_skipped_cards` (JSONB default `[]`) + a partial index

- [ ] **Step 1: Write the migration file**

Create `backend/migrations/0039_onboarding.sql`:

```sql
-- Onboarding wizard state for newly-registered users.
-- A user is "onboarding" from registration until they complete the wizard
-- (or force-skip it). Onboarding users are hidden from `/grid/nearby` for
-- everyone else; their own profile detail still works.

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS onboarding_completed_at TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS onboarding_skipped_cards JSONB NOT NULL DEFAULT '[]'::jsonb;

-- Partial index: most users complete onboarding quickly, so the index
-- only covers the "completed" subset (the ones the grid will scan).
CREATE INDEX IF NOT EXISTS idx_users_onboarding_completed
  ON users (onboarding_completed_at)
  WHERE onboarding_completed_at IS NOT NULL;

-- Down migration (for dev rollback):
-- DROP INDEX IF EXISTS idx_users_onboarding_completed;
-- ALTER TABLE users
--   DROP COLUMN IF EXISTS onboarding_skipped_cards,
--   DROP COLUMN IF EXISTS onboarding_completed_at;
```

- [ ] **Step 2: Verify the migration applies cleanly to a fresh DB**

From the repo root, with the local audit-pg (re-create it if you stopped it in Task 1):

```bash
cd C:/Users/echev/Desktop/proyecto-X
docker run --rm -d --name audit-pg -e POSTGRES_PASSWORD=audit -p 55433:5432 postgres:16-alpine
sleep 3
export DATABASE_URL=postgres://postgres:audit@localhost:55433/postgres
cd backend && cargo run --release --bin api -- migrate 2>&1 | tail -10
# Verify the columns exist
psql $DATABASE_URL -c "\d users" 2>&1 | grep -E "onboarding" || PGPASSWORD=audit psql -h localhost -U postgres $DATABASE_URL -c "\d users" | grep onboarding
docker stop audit-pg
```

Expected: `cargo run ... migrate` exits 0 with `INFO api: migrations applied`. The `\d users` output shows the two new columns + the partial index.

- [ ] **Step 3: Commit the migration**

```bash
cd C:/Users/echev/Desktop/proyecto-X
git add backend/migrations/0039_onboarding.sql
git commit -m "feat(backend): migration 0039 - onboarding_completed_at + skipped_cards

Additive, NULL/default, safe to apply to the live Neon DB without
coordination. Partial index on onboarding_completed_at IS NOT NULL
serves the grid filter added in task 8.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: Onboarding state types + handler skeleton

**Files:**
- Create: `backend/crates/api/src/onboarding.rs`
- Modify: `backend/crates/api/src/lib.rs`

**Interfaces:**
- Consumes: `AppState`, `AuthUser`
- Produces: `pub struct OnboardingCard`, `pub struct OnboardingState`, `pub fn router() -> Router<AppState>` (stubs that return empty for now)

- [ ] **Step 1: Write the failing test**

Create `backend/crates/api/tests/onboarding_e2e.rs`:

```rust
//! End-to-end tests for the onboarding wizard state machine.
//!
//! These tests need a live Postgres (set `TEST_DATABASE_URL` to a
//! throwaway DB). The auth fixtures live in `tests/common/mod.rs`
//! (create it in this task if it doesn't exist).

use axum::http::StatusCode;
use serde_json::json;

mod common;

#[tokio::test]
async fn get_onboarding_state_for_fresh_user() {
    let app = common::spawn_app().await;
    let token = common::register_user(&app, "alice@onb.test", "Pass123!aaa").await;
    let res = app.get("/me/onboarding", &token).await;
    assert_eq!(res.status(), StatusCode::OK);
    let body: serde_json::Value = res.json().await;
    assert_eq!(body["onboarding_completed"], json!(false));
    let cards = body["cards"].as_array().expect("cards array");
    // 4 required + 10 optional = 14
    assert_eq!(cards.len(), 14);
    let required = cards.iter().filter(|c| c["kind"] == "required").count();
    let optional = cards.iter().filter(|c| c["kind"] == "optional").count();
    assert_eq!(required, 4);
    assert_eq!(optional, 10);
}
```

Create `backend/crates/api/tests/common/mod.rs` (minimal):

```rust
//! Shared test fixtures for the api crate's e2e tests.

use axum::{
    body::Body,
    http::{header, Request, StatusCode},
    Router,
};
use serde_json::json;
use sqlx::PgPool;
use std::sync::Once;

static INIT: Once = Once::new();

pub struct TestApp {
    pub router: Router,
    pub pool: PgPool,
}

impl TestApp {
    pub async fn get(&self, path: &str, token: &str) -> axum::response::Response {
        let req = Request::builder()
            .method("GET")
            .uri(path)
            .header(header::AUTHORIZATION, format!("Bearer {token}"))
            .body(Body::empty())
            .unwrap();
        axum::http::RequestExt::into_body; // silence unused warning
        self.router.clone().oneshot(req).await.unwrap()
    }
}

pub async fn spawn_app() -> TestApp {
    INIT.call_once(|| {
        let _ = dotenvy::from_filename(".env.test");
    });
    let url = std::env::var("TEST_DATABASE_URL")
        .expect("TEST_DATABASE_URL must be set for e2e tests");
    let pool = sqlx::PgPool::connect(&url).await.expect("connect test db");
    sqlx::migrate!().run(&pool).await.expect("migrate test db");

    // Build a router with the onboarding routes mounted.
    // This requires a real AppState; use a helper in lib.rs.
    let state = crate::test_state(pool.clone()).await;
    let router = crate::build_test_router(state);
    TestApp { router, pool }
}

pub async fn register_user(app: &TestApp, email: &str, password: &str) -> String {
    let body = json!({
        "email": email,
        "password": password,
        "display_name": "Test User",
        "dob": "1995-06-15"
    });
    let req = Request::builder()
        .method("POST")
        .uri("/auth/register")
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(serde_json::to_vec(&body).unwrap()))
        .unwrap();
    let res = app.router.clone().oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::CREATED, "register failed");
    let body: serde_json::Value = res.json().await;
    body["access"].as_str().unwrap().to_string()
}
```

- [ ] **Step 2: Run the test to verify it fails**

From the repo root:

```bash
cd C:/Users/echev/Desktop/proyecto-X/backend
docker run --rm -d --name audit-pg -e POSTGRES_PASSWORD=audit -p 55433:5432 postgres:16-alpine
sleep 3
export TEST_DATABASE_URL=postgres://postgres:audit@localhost:55433/postgres
cargo test -p api --test onboarding_e2e 2>&1 | tail -20
docker stop audit-pg
```

Expected: FAIL with compile error because `crate::test_state` and `crate::build_test_router` don't exist yet, and `/me/onboarding` isn't mounted.

- [ ] **Step 3: Add the test helper to lib.rs**

Modify `backend/crates/api/src/lib.rs`. Find the existing `AppState` definition (it should look like `pub struct AppState { pub pool: PgPool, ... }`). Add the test helpers at the bottom of the file:

```rust
#[cfg(test)]
pub async fn test_state(pool: sqlx::PgPool) -> AppState {
    // Provide minimal config: the e2e tests don't need real R2/Redis/JWT secret
    // because they only test the onboarding handlers. Use placeholder values
    // for the fields the onboarding handlers don't touch.
    AppState {
        pool,
        r2: None,
        redis: None,
        config: crate::config::Config {
            jwt_secret: "test-secret-do-not-use-in-prod".to_string(),
            bind_addr: "0.0.0.0:0".to_string(),
            cors_origins: vec![],
            database_url: std::env::var("TEST_DATABASE_URL").unwrap(),
            firebase_service_account_json: None,
            smtp: None,
            oauth_google_client_id: None,
            oauth_apple_client_id: None,
            revenuecat_webhook_secret: None,
            staff_totp_kek: None,
            staff_totp_kek_version: None,
            dev_seed_enabled: false,
            tarpit_enabled: false,
        },
    }
}

#[cfg(test)]
pub fn build_test_router(state: AppState) -> axum::Router {
    // Mount only the routes the e2e tests need. Do NOT include admin or
    // webhooks here — those have their own test setups.
    axum::Router::new()
        .merge(crate::onboarding::router())
        .merge(crate::auth::handlers::router())
        .with_state(state)
}
```

If the existing `AppState` doesn't have exactly these fields, match the actual fields — read `lib.rs` first to see what's there, then build the test helper with the real shape. The point is: provide a working `AppState` and a router that mounts the routes the test needs.

- [ ] **Step 4: Write the onboarding module skeleton**

Create `backend/crates/api/src/onboarding.rs`:

```rust
//! Onboarding wizard state machine.
//!
//! A user is "onboarding" from registration until they complete the wizard
//! (or force-skip it). Onboarding users are hidden from `/grid/nearby` for
//! everyone else; their own profile detail still works.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use sqlx::types::Json as SqlxJson;
use time::OffsetDateTime;

use crate::auth::AuthUser;
use crate::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/me/onboarding", get(get_state))
        .route("/me/onboarding/cards/:card_id/complete", post(complete_card))
        .route("/me/onboarding/skip", post(skip_cards))
        .route("/me/onboarding/complete", post(force_complete))
}

#[derive(Serialize)]
pub struct OnboardingCard {
    pub id: String,
    pub label: String,
    pub kind: String,
    pub completed: bool,
    pub skipped_at: Option<OffsetDateTime>,
    pub cta_label: String,
}

#[derive(Serialize)]
pub struct OnboardingState {
    pub onboarding_completed: bool,
    pub onboarding_completed_at: Option<OffsetDateTime>,
    pub cards: Vec<OnboardingCard>,
}

pub async fn get_state(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
) -> Result<Json<OnboardingState>, StatusCode> {
    // Task 7 implements this.
    Err(StatusCode::NOT_IMPLEMENTED)
}

pub async fn complete_card(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Path(card_id): Path<String>,
    Json(_body): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    // Task 9 implements this.
    Err(StatusCode::NOT_IMPLEMENTED)
}

pub async fn skip_cards(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Json(_body): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    // Task 9 implements this.
    Err(StatusCode::NOT_IMPLEMENTED)
}

pub async fn force_complete(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
) -> Result<Json<serde_json::Value>, StatusCode> {
    // Task 9 implements this.
    Err(StatusCode::NOT_IMPLEMENTED)
}
```

Modify `backend/crates/api/src/lib.rs`: add `pub mod onboarding;` to the module list (find where the other `pub mod` lines are and add this one in the same group).

- [ ] **Step 5: Run the test to verify it STILL fails for the right reason**

```bash
cd C:/Users/echev/Desktop/proyecto-X/backend
docker run --rm -d --name audit-pg -e POSTGRES_PASSWORD=audit -p 55433:5432 postgres:16-alpine
sleep 3
export TEST_DATABASE_URL=postgres://postgres:audit@localhost:55433/postgres
cargo test -p api --test onboarding_e2e 2>&1 | tail -20
docker stop audit-pg
```

Expected: compile succeeds; the test fails because `get_state` returns `NOT_IMPLEMENTED` (501). That's the right failure for this step.

- [ ] **Step 6: Commit**

```bash
cd C:/Users/echev/Desktop/proyecto-X
git add backend/crates/api/src/onboarding.rs backend/crates/api/src/lib.rs backend/crates/api/tests/
git commit -m "feat(backend): onboarding module + state types + test fixtures

Skeleton module with 4 routes + serde types. Test helpers expose
build_test_router/test_state for e2e tests. Handlers return
NOT_IMPLEMENTED for now; tasks 7 and 9 implement them.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: Implement `GET /me/onboarding`

**Files:**
- Modify: `backend/crates/api/src/onboarding.rs`
- Modify: `backend/crates/api/tests/onboarding_e2e.rs`

**Interfaces:**
- Consumes: `AppState.pool`, `AuthUser(user_id)`, migration 0039
- Produces: `Json<OnboardingState>` with the 14 cards correctly populated

- [ ] **Step 1: Add the per-card-completion check test**

Append to `backend/crates/api/tests/onboarding_e2e.rs`:

```rust
#[tokio::test]
async fn get_onboarding_reflects_completed_cards() {
    let app = common::spawn_app().await;
    let token = common::register_user(&app, "bob@onb.test", "Pass123!aaa").await;

    // Complete profile_photo card (we'll insert a row directly into photos
    // to simulate "user has uploaded a photo"; in production this is done
    // by the create_photo handler).
    let user_id: uuid::Uuid = common::user_id_from_token(&token, &app.pool).await;
    sqlx::query("INSERT INTO photos (user_id, r2_key, blur_key, is_nsfw) VALUES ($1, $2, $3, $4)")
        .bind(user_id)
        .bind("profile/test/test.jpg")
        .bind("profile/test/test.blur.jpg")
        .bind(false)
        .execute(&app.pool)
        .await
        .expect("insert photo");

    let res = app.get("/me/onboarding", &token).await;
    assert_eq!(res.status(), StatusCode::OK);
    let body: serde_json::Value = res.json().await;
    let cards = body["cards"].as_array().unwrap();
    let profile_photo = cards.iter().find(|c| c["id"] == "profile_photo").unwrap();
    assert_eq!(profile_photo["completed"], json!(true));
    let display_name = cards.iter().find(|c| c["id"] == "display_name").unwrap();
    assert_eq!(display_name["completed"], json!(true)); // set by register
}
```

Add the helper to `backend/crates/api/tests/common/mod.rs`:

```rust
pub async fn user_id_from_token(token: &str, pool: &PgPool) -> uuid::Uuid {
    // Decode the HS256 token (matches the api crate's JWT verifier).
    // For test purposes, use a fixed secret that matches the test_state.
    use jsonwebtoken::{decode, DecodingKey, Validation};
    let mut validation = Validation::default();
    validation.set_audience(&[]);
    let data = decode::<serde_json::Value>(
        token,
        &DecodingKey::from_secret(b"test-secret-do-not-use-in-prod"),
        &validation,
    )
    .expect("decode token");
    uuid::Uuid::parse_str(data.claims["sub"].as_str().unwrap()).unwrap()
}
```

- [ ] **Step 2: Implement `get_state`**

Replace the `get_state` function in `backend/crates/api/src/onboarding.rs` with:

```rust
const REQUIRED_CARDS: &[(&str, &str, &str)] = &[
    ("profile_photo",   "Profile photo",      "Add a photo"),
    ("display_name",    "Display name",       "Set your name"),
    ("age",             "Age",                "Confirm your age"),
    ("gender_position", "Gender & position",  "Set your gender and position"),
];

const OPTIONAL_CARDS: &[(&str, &str, &str)] = &[
    ("looking_for",          "Looking for",          "What are you looking for"),
    ("tribes",               "Tribes",               "Pick your tribes"),
    ("vaccines",             "Health & vaccines",    "Share your health info"),
    ("practices",            "Practices",            "Add your practices"),
    ("about_me",             "About me",             "Write a short bio"),
    ("height",               "Height",               "Add your height"),
    ("weight",               "Weight",               "Add your weight"),
    ("relationship_status",  "Relationship status",  "Set your status"),
    ("position_preference",  "Position preference",  "Set your position"),
    ("ethnicity",            "Ethnicity",            "Add your ethnicity"),
];

#[derive(sqlx::FromRow)]
struct UserProfileSnapshot {
    has_profile_photo: bool,
    display_name: String,
    dob: Option<time::Date>,
    gender: Option<String>,
    position: Option<String>,
    looking_for: Option<String>,
    tribes: Vec<String>,
    vaccines: Vec<String>,
    practices: Vec<String>,
    about_me: Option<String>,
    height_cm: Option<i32>,
    weight_kg: Option<i32>,
    relationship_status: Option<String>,
    position_preference: Option<String>,
    ethnicity: Option<String>,
}

pub async fn get_state(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
) -> Result<Json<OnboardingState>, StatusCode> {
    let row: (Option<OffsetDateTime>, SqlxJson<serde_json::Value>) = sqlx::query_as(
        "SELECT onboarding_completed_at, onboarding_skipped_cards FROM users WHERE id = $1",
    )
    .bind(user_id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!("onboarding load completed_at: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let completed_at = row.0;
    let skipped_value = row.1;
    let skipped: Vec<String> = skipped_value
        .as_array()
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.get("card_id").and_then(|c| c.as_str()).map(String::from))
                .collect()
        })
        .unwrap_or_default();

    let snapshot: UserProfileSnapshot = sqlx::query_as(
        r#"
        SELECT
            EXISTS(SELECT 1 FROM photos WHERE user_id = $1) AS has_profile_photo,
            COALESCE(display_name, '') AS display_name,
            dob,
            gender,
            position,
            looking_for,
            COALESCE(tribes, '{}') AS tribes,
            COALESCE(vaccines, '{}') AS vaccines,
            COALESCE(practices, '{}') AS practices,
            about_me,
            height_cm,
            weight_kg,
            relationship_status,
            position_preference,
            ethnicity
        FROM users WHERE id = $1
        "#,
    )
    .bind(user_id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!("onboarding load profile: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let mut cards = Vec::new();
    for (id, label, cta) in REQUIRED_CARDS {
        cards.push(OnboardingCard {
            id: id.to_string(),
            label: label.to_string(),
            kind: "required".into(),
            completed: card_completed(&snapshot, id),
            skipped_at: None,
            cta_label: cta.to_string(),
        });
    }
    for (id, label, cta) in OPTIONAL_CARDS {
        if skipped.iter().any(|s| s == id) {
            continue; // already skipped, hide from the wizard
        }
        cards.push(OnboardingCard {
            id: id.to_string(),
            label: label.to_string(),
            kind: "optional".into(),
            completed: card_completed(&snapshot, id),
            skipped_at: None,
            cta_label: cta.to_string(),
        });
    }

    Ok(Json(OnboardingState {
        onboarding_completed: completed_at.is_some(),
        onboarding_completed_at: completed_at,
        cards,
    }))
}

fn card_completed(s: &UserProfileSnapshot, id: &str) -> bool {
    match id {
        "profile_photo" => s.has_profile_photo,
        "display_name" => !s.display_name.is_empty(),
        "age" => s.dob.is_some(),
        "gender_position" => s.gender.is_some() && s.position.is_some(),
        "looking_for" => s.looking_for.is_some(),
        "tribes" => !s.tribes.is_empty(),
        "vaccines" => !s.vaccines.is_empty(),
        "practices" => !s.practices.is_empty(),
        "about_me" => s.about_me.as_ref().map(|x| !x.is_empty()).unwrap_or(false),
        "height" => s.height_cm.is_some(),
        "weight" => s.weight_kg.is_some(),
        "relationship_status" => s.relationship_status.is_some(),
        "position_preference" => s.position_preference.is_some(),
        "ethnicity" => s.ethnicity.is_some(),
        _ => false,
    }
}
```

- [ ] **Step 3: Run the tests to verify they pass**

```bash
cd C:/Users/echev/Desktop/proyecto-X/backend
docker run --rm -d --name audit-pg -e POSTGRES_PASSWORD=audit -p 55433:5432 postgres:16-alpine
sleep 3
export TEST_DATABASE_URL=postgres://postgres:audit@localhost:55433/postgres
cargo test -p api --test onboarding_e2e 2>&1 | tail -20
docker stop audit-pg
```

Expected: both tests pass.

- [ ] **Step 4: Commit**

```bash
cd C:/Users/echev/Desktop/proyecto-X
git add backend/crates/api/src/onboarding.rs backend/crates/api/tests/
git commit -m "feat(backend): GET /me/onboarding returns 14-card state

Loads the user's profile snapshot + skipped-cards JSONB and
serializes 4 required + 10 optional cards. Per-card completion
is derived from the underlying user columns / photos table.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: Hide onboarding users from `/grid/nearby`

**Files:**
- Modify: `backend/crates/api/src/grid.rs`

**Interfaces:**
- Consumes: the existing `/grid/nearby` query
- Produces: query with `AND u.onboarding_completed_at IS NOT NULL` clause

- [ ] **Step 1: Find the existing grid query**

```bash
cd C:/Users/echev/Desktop/proyecto-X
grep -n "fn nearby" backend/crates/api/src/grid.rs
```

Read the function and identify the SQL query.

- [ ] **Step 2: Add the filter**

Add `AND u.onboarding_completed_at IS NOT NULL` to the `WHERE` clause (or the closest equivalent — read the query, find the user table alias, and append the filter). Do NOT add it to the `ON` clause of a JOIN — it belongs in the `WHERE`.

- [ ] **Step 3: Write the failing test**

Append to `backend/crates/api/tests/onboarding_e2e.rs`:

```rust
#[tokio::test]
async fn grid_nearby_excludes_unfinished_onboarding_users() {
    let app = common::spawn_app().await;
    let alice = common::register_user(&app, "alice@grid.test", "Pass123!aaa").await;
    let bob = common::register_user(&app, "bob@grid.test", "Pass123!aaa").await;

    // Alice force-completes onboarding.
    let req = axum::http::Request::builder()
        .method("POST")
        .uri("/me/onboarding/complete")
        .header(axum::http::header::AUTHORIZATION, format!("Bearer {alice}"))
        .body(axum::body::Body::empty())
        .unwrap();
    let res = app.router.clone().oneshot(req).await.unwrap();
    assert_eq!(res.status(), axum::http::StatusCode::OK);

    // Bob does NOT complete onboarding.
    // Force a row in users with a known location so the grid query is meaningful.
    let bob_id = common::user_id_from_token(&bob, &app.pool).await;
    sqlx::query("UPDATE users SET last_lat = 40.4168, last_lon = -3.7038 WHERE id = $1")
        .bind(bob_id).execute(&app.pool).await.unwrap();
    let alice_id = common::user_id_from_token(&alice, &app.pool).await;
    sqlx::query("UPDATE users SET last_lat = 40.4169, last_lon = -3.7039 WHERE id = $1")
        .bind(alice_id).execute(&app.pool).await.unwrap();

    // Now bob queries /grid/nearby — he should see himself but NOT alice.
    // (Bob's own onboarding status doesn't matter for "see himself" because
    //  the grid typically excludes the requester; the test asserts the
    //  opposite: a user with onboarding_completed=NULL is invisible.)
    // For this test, we'll have alice query the grid: she should NOT see bob.
    let req = axum::http::Request::builder()
        .method("GET")
        .uri("/grid/nearby?lat=40.4168&lon=-3.7038&radius_m=5000")
        .header(axum::http::header::AUTHORIZATION, format!("Bearer {alice}"))
        .body(axum::body::Body::empty())
        .unwrap();
    let res = app.router.clone().oneshot(req).await.unwrap();
    assert_eq!(res.status(), axum::http::StatusCode::OK);
    let body: serde_json::Value = res.json().await;
    let users = body["users"].as_array().unwrap();
    let bob_visible = users.iter().any(|u| u["id"].as_str() == Some(&bob_id.to_string()));
    assert!(!bob_visible, "bob (unfinished onboarding) should NOT be in alice's grid");
}
```

- [ ] **Step 4: Run the test to verify it fails**

```bash
cd C:/Users/echev/Desktop/proyecto-X/backend
docker run --rm -d --name audit-pg -e POSTGRES_PASSWORD=audit -p 55433:5432 postgres:16-alpine
sleep 3
export TEST_DATABASE_URL=postgres://postgres:audit@localhost:55433/postgres
cargo test -p api --test onboarding_e2e grid_nearby_excludes 2>&1 | tail -20
docker stop audit-pg
```

Expected: FAIL — bob IS visible (the filter isn't applied yet). This is the right failure for this step.

- [ ] **Step 5: Confirm the test passes after the filter is added**

Re-run the same command. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd C:/Users/echev/Desktop/proyecto-X
git add backend/crates/api/src/grid.rs backend/crates/api/tests/onboarding_e2e.rs
git commit -m "feat(backend): grid/nearby hides unfinished onboarding users

Adds AND u.onboarding_completed_at IS NOT NULL to the nearby query.
Verified by e2e: bob (no onboarding) is invisible to alice
(who completed onboarding) on /grid/nearby.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: Implement `POST /me/onboarding/cards/:id/complete`, `/skip`, `/complete`

**Files:**
- Modify: `backend/crates/api/src/onboarding.rs`
- Modify: `backend/crates/api/tests/onboarding_e2e.rs`

**Interfaces:**
- Consumes: `AppState.pool`, the `users` table schema
- Produces: working `complete_card`, `skip_cards`, `force_complete` handlers + tests

- [ ] **Step 1: Write the failing tests**

Append to `backend/crates/api/tests/onboarding_e2e.rs`:

```rust
#[tokio::test]
async fn complete_required_card_updates_state() {
    let app = common::spawn_app().await;
    let token = common::register_user(&app, "carol@onb.test", "Pass123!aaa").await;

    // Complete display_name card.
    let body = json!({ "display_name": "Carol Updated" });
    let req = axum::http::Request::builder()
        .method("POST")
        .uri("/me/onboarding/cards/display_name/complete")
        .header(axum::http::header::AUTHORIZATION, format!("Bearer {token}"))
        .header(axum::http::header::CONTENT_TYPE, "application/json")
        .body(axum::body::Body::from(serde_json::to_vec(&body).unwrap()))
        .unwrap();
    let res = app.router.clone().oneshot(req).await.unwrap();
    assert_eq!(res.status(), axum::http::StatusCode::OK);

    // Verify GET /me/onboarding reflects it.
    let res = app.get("/me/onboarding", &token).await;
    let body: serde_json::Value = res.json().await;
    let card = body["cards"].as_array().unwrap()
        .iter().find(|c| c["id"] == "display_name").unwrap();
    assert_eq!(card["completed"], json!(true));
}

#[tokio::test]
async fn skip_records_in_skipped_cards() {
    let app = common::spawn_app().await;
    let token = common::register_user(&app, "dave@onb.test", "Pass123!aaa").await;

    let body = json!({ "card_ids": ["tribes", "vaccines"] });
    let req = axum::http::Request::builder()
        .method("POST")
        .uri("/me/onboarding/skip")
        .header(axum::http::header::AUTHORIZATION, format!("Bearer {token}"))
        .header(axum::http::header::CONTENT_TYPE, "application/json")
        .body(axum::body::Body::from(serde_json::to_vec(&body).unwrap()))
        .unwrap();
    let res = app.router.clone().oneshot(req).await.unwrap();
    assert_eq!(res.status(), axum::http::StatusCode::OK);

    // Verify GET /me/onboarding no longer shows those cards.
    let res = app.get("/me/onboarding", &token).await;
    let body: serde_json::Value = res.json().await;
    let cards = body["cards"].as_array().unwrap();
    assert!(!cards.iter().any(|c| c["id"] == "tribes"), "tribes should be hidden after skip");
    assert!(!cards.iter().any(|c| c["id"] == "vaccines"), "vaccines should be hidden after skip");
}

#[tokio::test]
async fn force_complete_marks_user_visible() {
    let app = common::spawn_app().await;
    let alice = common::register_user(&app, "alice-fc@onb.test", "Pass123!aaa").await;
    let bob = common::register_user(&app, "bob-fc@onb.test", "Pass123!aaa").await;
    let bob_id = common::user_id_from_token(&bob, &app.pool).await;
    let alice_id = common::user_id_from_token(&alice, &app.pool).await;

    // Both at the same lat/lon.
    sqlx::query("UPDATE users SET last_lat = 40.4168, last_lon = -3.7038 WHERE id = ANY($1)")
        .bind(&[bob_id, alice_id][..])
        .execute(&app.pool).await.unwrap();

    // Bob force-completes.
    let req = axum::http::Request::builder()
        .method("POST")
        .uri("/me/onboarding/complete")
        .header(axum::http::header::AUTHORIZATION, format!("Bearer {bob}"))
        .body(axum::body::Body::empty())
        .unwrap();
    let res = app.router.clone().oneshot(req).await.unwrap();
    assert_eq!(res.status(), axum::http::StatusCode::OK);

    // Alice (still onboarding) queries grid — should see bob (he completed).
    // Bob (now visible) queries grid — should see alice? No, alice is still
    // onboarding, so the filter excludes her.
    let req = axum::http::Request::builder()
        .method("GET")
        .uri("/grid/nearby?lat=40.4168&lon=-3.7038&radius_m=5000")
        .header(axum::http::header::AUTHORIZATION, format!("Bearer {bob}"))
        .body(axum::body::Body::empty())
        .unwrap();
    let res = app.router.clone().oneshot(req).await.unwrap();
    let body: serde_json::Value = res.json().await;
    let users = body["users"].as_array().unwrap();
    let alice_visible = users.iter().any(|u| u["id"].as_str() == Some(&alice_id.to_string()));
    assert!(!alice_visible, "alice (still onboarding) should NOT be visible");
}

#[tokio::test]
async fn completing_all_required_triggers_onboarding_completed_at() {
    let app = common::spawn_app().await;
    let token = common::register_user(&app, "eve@onb.test", "Pass123!aaa").await;
    let user_id = common::user_id_from_token(&token, &app.pool).await;

    // Insert a photo to satisfy profile_photo.
    sqlx::query("INSERT INTO photos (user_id, r2_key, blur_key, is_nsfw) VALUES ($1, $2, $3, $4)")
        .bind(user_id)
        .bind("profile/test/test.jpg")
        .bind("profile/test/test.blur.jpg")
        .bind(false)
        .execute(&app.pool).await.unwrap();

    // Complete display_name, age (dob already set by register), gender_position.
    for (path, body) in [
        ("/me/onboarding/cards/display_name/complete", json!({"display_name": "Eve"})),
        ("/me/onboarding/cards/age/complete",          json!({"dob": "1995-06-15"})),
        ("/me/onboarding/cards/gender_position/complete", json!({"gender": "male", "position": "top"})),
    ] {
        let req = axum::http::Request::builder()
            .method("POST")
            .uri(path)
            .header(axum::http::header::AUTHORIZATION, format!("Bearer {token}"))
            .header(axum::http::header::CONTENT_TYPE, "application/json")
            .body(axum::body::Body::from(serde_json::to_vec(&body).unwrap()))
            .unwrap();
        let res = app.router.clone().oneshot(req).await.unwrap();
        assert_eq!(res.status(), axum::http::StatusCode::OK, "card {path} failed");
    }

    // Now GET /me/onboarding should report onboarding_completed=true.
    let res = app.get("/me/onboarding", &token).await;
    let body: serde_json::Value = res.json().await;
    assert_eq!(body["onboarding_completed"], json!(true));
    assert!(body["onboarding_completed_at"].is_string());
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd C:/Users/echev/Desktop/proyecto-X/backend
docker run --rm -d --name audit-pg -e POSTGRES_PASSWORD=audit -p 55433:5432 postgres:16-alpine
sleep 3
export TEST_DATABASE_URL=postgres://postgres:audit@localhost:55433/postgres
cargo test -p api --test onboarding_e2e 2>&1 | tail -20
docker stop audit-pg
```

Expected: 4 tests fail (the new ones) because the handlers return `NOT_IMPLEMENTED`. The original 2 from Tasks 6/7 still pass.

- [ ] **Step 3: Implement `complete_card`**

Replace `complete_card` in `backend/crates/api/src/onboarding.rs`:

```rust
#[derive(Deserialize)]
#[serde(tag = "card_id", rename_all = "snake_case")]
#[allow(dead_code)] // each variant used by a branch below
pub enum CompleteBody {
    ProfilePhoto { r2_key: String, is_nsfw: bool },
    DisplayName { display_name: String },
    Age { dob: time::Date },
    GenderPosition { gender: String, position: String },
    LookingFor { looking_for: String },
    Tribes { tribes: Vec<String> },
    Vaccines { vaccines: Vec<String> },
    Practices { practices: Vec<String> },
    AboutMe { about_me: String },
    Height { height_cm: i32 },
    Weight { weight_kg: i32 },
    RelationshipStatus { status: String },
    PositionPreference { position: String },
    Ethnicity { ethnicity: String },
    #[serde(other)]
    Unknown,
}

pub async fn complete_card(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Path(card_id): Path<String>,
    Json(raw): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    // Each card_id maps to one user column (or photos row) update.
    let result = match card_id.as_str() {
        "profile_photo" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::ProfilePhoto { r2_key, is_nsfw } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            let blur_key = format!("{}.blur.jpg", r2_key);
            sqlx::query_scalar::<_, uuid::Uuid>(
                "INSERT INTO photos (user_id, r2_key, blur_key, is_nsfw) VALUES ($1, $2, $3, $4) RETURNING id",
            )
            .bind(user_id).bind(&r2_key).bind(&blur_key).bind(is_nsfw)
            .fetch_one(&state.pool).await
            .map_err(|e| { tracing::error!("insert photo: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "display_name" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::DisplayName { display_name } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            if display_name.trim().is_empty() { return Err(StatusCode::BAD_REQUEST); }
            sqlx::query("UPDATE users SET display_name = $1 WHERE id = $2")
                .bind(&display_name).bind(user_id)
                .execute(&state.pool).await
                .map_err(|e| { tracing::error!("update display_name: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "age" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::Age { dob } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            // Age-gate: must be 18+.
            let today = time::OffsetDateTime::now_utc().date();
            let age_years = (today - dob).whole_days() / 365;
            if age_years < 18 { return Err(StatusCode::UNPROCESSABLE_ENTITY); }
            sqlx::query("UPDATE users SET dob = $1 WHERE id = $2")
                .bind(dob).bind(user_id)
                .execute(&state.pool).await
                .map_err(|e| { tracing::error!("update dob: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "gender_position" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::GenderPosition { gender, position } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            sqlx::query("UPDATE users SET gender = $1, position = $2 WHERE id = $3")
                .bind(&gender).bind(&position).bind(user_id)
                .execute(&state.pool).await
                .map_err(|e| { tracing::error!("update gender/position: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "looking_for" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::LookingFor { looking_for } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            sqlx::query("UPDATE users SET looking_for = $1 WHERE id = $2")
                .bind(&looking_for).bind(user_id)
                .execute(&state.pool).await
                .map_err(|e| { tracing::error!("update looking_for: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "tribes" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::Tribes { tribes } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            sqlx::query("UPDATE users SET tribes = $1 WHERE id = $2")
                .bind(&tribes).bind(user_id)
                .execute(&state.pool).await
                .map_err(|e| { tracing::error!("update tribes: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "vaccines" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::Vaccines { vaccines } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            sqlx::query("UPDATE users SET vaccines = $1 WHERE id = $2")
                .bind(&vaccines).bind(user_id)
                .execute(&state.pool).await
                .map_err(|e| { tracing::error!("update vaccines: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "practices" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::Practices { practices } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            sqlx::query("UPDATE users SET practices = $1 WHERE id = $2")
                .bind(&practices).bind(user_id)
                .execute(&state.pool).await
                .map_err(|e| { tracing::error!("update practices: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "about_me" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::AboutMe { about_me } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            sqlx::query("UPDATE users SET about_me = $1 WHERE id = $2")
                .bind(&about_me).bind(user_id)
                .execute(&state.pool).await
                .map_err(|e| { tracing::error!("update about_me: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "height" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::Height { height_cm } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            if !(50..=272).contains(&height_cm) { return Err(StatusCode::BAD_REQUEST); }
            sqlx::query("UPDATE users SET height_cm = $1 WHERE id = $2")
                .bind(height_cm).bind(user_id)
                .execute(&state.pool).await
                .map_err(|e| { tracing::error!("update height: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "weight" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::Weight { weight_kg } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            if !(20..=500).contains(&weight_kg) { return Err(StatusCode::BAD_REQUEST); }
            sqlx::query("UPDATE users SET weight_kg = $1 WHERE id = $2")
                .bind(weight_kg).bind(user_id)
                .execute(&state.pool).await
                .map_err(|e| { tracing::error!("update weight: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "relationship_status" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::RelationshipStatus { status } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            sqlx::query("UPDATE users SET relationship_status = $1 WHERE id = $2")
                .bind(&status).bind(user_id)
                .execute(&state.pool).await
                .map_err(|e| { tracing::error!("update relationship_status: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "position_preference" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::PositionPreference { position } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            sqlx::query("UPDATE users SET position_preference = $1 WHERE id = $2")
                .bind(&position).bind(user_id)
                .execute(&state.pool).await
                .map_err(|e| { tracing::error!("update position_preference: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "ethnicity" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::Ethnicity { ethnicity } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            sqlx::query("UPDATE users SET ethnicity = $1 WHERE id = $2")
                .bind(&ethnicity).bind(user_id)
                .execute(&state.pool).await
                .map_err(|e| { tracing::error!("update ethnicity: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        _ => Err(StatusCode::NOT_FOUND),
    };

    if result.is_ok() {
        // Check if all 4 required are now complete; if yes, set onboarding_completed_at.
        sqlx::query(
            r#"
            UPDATE users SET onboarding_completed_at = NOW()
            WHERE id = $1
              AND onboarding_completed_at IS NULL
              AND EXISTS(SELECT 1 FROM photos WHERE user_id = $1)
              AND COALESCE(NULLIF(display_name, ''), '') <> ''
              AND dob IS NOT NULL
              AND gender IS NOT NULL
              AND position IS NOT NULL
            "#,
        )
        .bind(user_id)
        .execute(&state.pool)
        .await
        .map_err(|e| { tracing::error!("update onboarding_completed_at: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
    }

    result.map(|_| Json(json!({ "card_id": card_id, "completed": true })))
}
```

Add `use serde::Deserialize;` at the top of the file (it's already imported via `Serialize`; add the other).

- [ ] **Step 4: Implement `skip_cards` and `force_complete`**

Replace `skip_cards`:

```rust
#[derive(Deserialize)]
pub struct SkipBody { card_ids: Vec<String> }

pub async fn skip_cards(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Json(body): Json<SkipBody>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    // Validate that all card_ids are optional.
    let allowed: std::collections::HashSet<&str> = OPTIONAL_CARDS.iter().map(|(id, _, _)| *id).collect();
    for id in &body.card_ids {
        if !allowed.contains(id.as_str()) {
            return Err(StatusCode::BAD_REQUEST);
        }
    }

    // Append each card_id to the JSONB array, with timestamp.
    let new_entries: Vec<serde_json::Value> = body.card_ids.iter().map(|id| {
        json!({ "card_id": id, "skipped_at": OffsetDateTime::now_utc() })
    }).collect();

    sqlx::query(
        r#"
        UPDATE users
        SET onboarding_skipped_cards = onboarding_skipped_cards || $1::jsonb
        WHERE id = $2
        "#,
    )
    .bind(SqlxJson(new_entries))
    .bind(user_id)
    .execute(&state.pool)
    .await
    .map_err(|e| { tracing::error!("skip cards: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;

    Ok(Json(json!({ "skipped": body.card_ids })))
}
```

Replace `force_complete`:

```rust
pub async fn force_complete(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let now = OffsetDateTime::now_utc();
    sqlx::query(
        "UPDATE users SET onboarding_completed_at = $1 WHERE id = $2 AND onboarding_completed_at IS NULL",
    )
    .bind(now).bind(user_id)
    .execute(&state.pool)
    .await
    .map_err(|e| { tracing::error!("force complete: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;

    Ok(Json(json!({ "onboarding_completed_at": now })))
}
```

- [ ] **Step 5: Run all the e2e tests to verify they pass**

```bash
cd C:/Users/echev/Desktop/proyecto-X/backend
docker run --rm -d --name audit-pg -e POSTGRES_PASSWORD=audit -p 55433:5432 postgres:16-alpine
sleep 3
export TEST_DATABASE_URL=postgres://postgres:audit@localhost:55433/postgres
cargo test -p api --test onboarding_e2e 2>&1 | tail -20
docker stop audit-pg
```

Expected: all 6 tests pass (2 from T7, 4 from T9).

- [ ] **Step 6: Run the full test suite**

```bash
cd C:/Users/echev/Desktop/proyecto-X/backend
docker run --rm -d --name audit-pg -e POSTGRES_PASSWORD=audit -p 55433:5432 postgres:16-alpine
sleep 3
export TEST_DATABASE_URL=postgres://postgres:audit@localhost:55433/postgres
cargo test --workspace 2>&1 | tail -30
docker stop audit-pg
```

Expected: all tests pass. Any failure is a regression — investigate before committing.

- [ ] **Step 7: Commit**

```bash
cd C:/Users/echev/Desktop/proyecto-X
git add backend/crates/api/src/onboarding.rs backend/crates/api/tests/onboarding_e2e.rs
git commit -m "feat(backend): complete /skip /complete handlers + 4 e2e tests

Implements POST /me/onboarding/cards/:id/complete (one branch per
card_id with per-card validation), POST /me/onboarding/skip (only
optional cards), POST /me/onboarding/complete (force-skip). The
complete handler also flips onboarding_completed_at when all 4
required are present.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Group C — Flutter wizard

### Task 10: i18n keys for the wizard

**Files:**
- Modify: `apps/app/lib/l10n/app_en.arb`
- Modify: `apps/app/lib/l10n/app_es.arb`
- Modify: any other locale files present (read `apps/app/lib/l10n/` first to find them)

**Interfaces:**
- Consumes: existing ARB files
- Produces: 20+ new keys prefixed with `onboarding_*`

- [ ] **Step 1: Read the existing ARB files**

```bash
cd C:/Users/echev/Desktop/proyecto-X
ls apps/app/lib/l10n/
```

- [ ] **Step 2: Add keys to `app_en.arb`**

Read the file, find the closing `}`, and add (before the closing brace) this block (preserve the existing trailing comma structure of the file):

```json
  "onboarding_title": "Set up your profile",
  "onboarding_subtitle": "Tell others about yourself",
  "onboarding_required_progress": "{done} of {total} required done",
  "@onboarding_required_progress": {
    "placeholders": { "done": {"type": "int"}, "total": {"type": "int"} }
  },
  "onboarding_optional_progress": "{done} of {total} optional done",
  "@onboarding_optional_progress": {
    "placeholders": { "done": {"type": "int"}, "total": {"type": "int"} }
  },
  "onboarding_next": "Next",
  "onboarding_skip": "Skip",
  "onboarding_close": "Close",
  "onboarding_skip_all": "Skip the whole wizard",
  "onboarding_skip_all_confirm_title": "Skip the whole wizard?",
  "onboarding_skip_all_confirm_body": "Your profile won't be visible to others until you complete the required fields. You can come back later from your profile.",
  "onboarding_skip_all_confirm_yes": "Skip",
  "onboarding_skip_all_confirm_no": "Keep going",
  "onboarding_required": "Required",
  "onboarding_optional": "Optional",
  "onboarding_done": "Done",
  "onboarding_error_required": "This field is required",
  "onboarding_error_offline": "You appear to be offline. Try again when you have a connection.",
  "onboarding_card_profile_photo_label": "Profile photo",
  "onboarding_card_profile_photo_cta": "Add a photo",
  "onboarding_card_display_name_label": "Display name",
  "onboarding_card_display_name_cta": "Set your name",
  "onboarding_card_age_label": "Age",
  "onboarding_card_age_cta": "Confirm your age",
  "onboarding_card_gender_position_label": "Gender & position",
  "onboarding_card_gender_position_cta": "Set your gender and position",
  "onboarding_card_looking_for_label": "Looking for",
  "onboarding_card_looking_for_cta": "What are you looking for",
  "onboarding_card_tribes_label": "Tribes",
  "onboarding_card_tribes_cta": "Pick your tribes",
  "onboarding_card_vaccines_label": "Health & vaccines",
  "onboarding_card_vaccines_cta": "Share your health info",
  "onboarding_card_practices_label": "Practices",
  "onboarding_card_practices_cta": "Add your practices",
  "onboarding_card_about_me_label": "About me",
  "onboarding_card_about_me_cta": "Write a short bio",
  "onboarding_card_height_label": "Height",
  "onboarding_card_height_cta": "Add your height",
  "onboarding_card_weight_label": "Weight",
  "onboarding_card_weight_cta": "Add your weight",
  "onboarding_card_relationship_status_label": "Relationship status",
  "onboarding_card_relationship_status_cta": "Set your status",
  "onboarding_card_position_preference_label": "Position preference",
  "onboarding_card_position_preference_cta": "Set your position",
  "onboarding_card_ethnicity_label": "Ethnicity",
  "onboarding_card_ethnicity_cta": "Add your ethnicity"
```

- [ ] **Step 3: Add the same keys to `app_es.arb` with Spanish translations**

```json
  "onboarding_title": "Configura tu perfil",
  "onboarding_subtitle": "Cuenta a otros sobre ti",
  "onboarding_required_progress": "{done} de {total} obligatorios completados",
  "onboarding_optional_progress": "{done} de {total} opcionales completados",
  "onboarding_next": "Siguiente",
  "onboarding_skip": "Omitir",
  "onboarding_close": "Cerrar",
  "onboarding_skip_all": "Saltar todo el wizard",
  "onboarding_skip_all_confirm_title": "¿Saltar todo el wizard?",
  "onboarding_skip_all_confirm_body": "Tu perfil no será visible para otros hasta que completes los campos obligatorios. Puedes volver luego desde tu perfil.",
  "onboarding_skip_all_confirm_yes": "Saltar",
  "onboarding_skip_all_confirm_no": "Seguir",
  "onboarding_required": "Obligatorio",
  "onboarding_optional": "Opcional",
  "onboarding_done": "Listo",
  "onboarding_error_required": "Este campo es obligatorio",
  "onboarding_error_offline": "Parece que estás sin conexión. Intenta de nuevo cuando tengas conexión.",
  "onboarding_card_profile_photo_label": "Foto de perfil",
  "onboarding_card_profile_photo_cta": "Añadir una foto",
  "onboarding_card_display_name_label": "Nombre",
  "onboarding_card_display_name_cta": "Elige tu nombre",
  "onboarding_card_age_label": "Edad",
  "onboarding_card_age_cta": "Confirma tu edad",
  "onboarding_card_gender_position_label": "Género y posición",
  "onboarding_card_gender_position_cta": "Define tu género y posición",
  "onboarding_card_looking_for_label": "Busco",
  "onboarding_card_looking_for_cta": "¿Qué buscas?",
  "onboarding_card_tribes_label": "Tribus",
  "onboarding_card_tribes_cta": "Elige tus tribus",
  "onboarding_card_vaccines_label": "Salud y vacunas",
  "onboarding_card_vaccines_cta": "Comparte tu información de salud",
  "onboarding_card_practices_label": "Prácticas",
  "onboarding_card_practices_cta": "Añade tus prácticas",
  "onboarding_card_about_me_label": "Sobre mí",
  "onboarding_card_about_me_cta": "Escribe una bio breve",
  "onboarding_card_height_label": "Altura",
  "onboarding_card_height_cta": "Añade tu altura",
  "onboarding_card_weight_label": "Peso",
  "onboarding_card_weight_cta": "Añade tu peso",
  "onboarding_card_relationship_status_label": "Estado sentimental",
  "onboarding_card_relationship_status_cta": "Define tu estado",
  "onboarding_card_position_preference_label": "Preferencia de posición",
  "onboarding_card_position_preference_cta": "Define tu posición",
  "onboarding_card_ethnicity_label": "Etnia",
  "onboarding_card_ethnicity_cta": "Añade tu etnia"
```

- [ ] **Step 4: Regenerate the l10n files**

```bash
cd C:/Users/echev/Desktop/proyecto-X/apps/app
flutter gen-l10n 2>&1 | tail -10
```

Expected: exits 0. If the command is `dart run gen_l10n` instead (some projects), use that.

- [ ] **Step 5: Verify the keys are usable**

```bash
cd C:/Users/echev/Desktop/proyecto-X/apps/app
grep -n "onboarding_title" lib/l10n/gen/app_localizations.dart | head -3
```

Expected: at least one match (the generated `String get onboarding_title`).

- [ ] **Step 6: Commit**

```bash
cd C:/Users/echev/Desktop/proyecto-X
git add apps/app/lib/l10n/
git commit -m "feat(app): i18n keys for the onboarding wizard (en + es)

20+ keys prefixed onboarding_*. Regenerated via flutter gen-l10n.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 11: Onboarding models + provider

**Files:**
- Create: `apps/app/lib/src/onboarding/models.dart`
- Create: `apps/app/lib/src/onboarding/onboarding_provider.dart`

**Interfaces:**
- Consumes: `ApiClient` (existing, in `apps/app/lib/src/auth/api_client.dart`)
- Produces: `OnboardingState`, `OnboardingCard`, `OnboardingCardKind`, `OnboardingProvider`

- [ ] **Step 1: Read the existing `api_client.dart` interface**

```bash
cd C:/Users/echev/Desktop/proyecto-X
grep -nE "Future<.*> (getJson|postJson|putJson|delete)\(" apps/app/lib/src/auth/api_client.dart
```

Use the actual method signatures (they may be `getJson(path)`, `postJson(path, body)`, etc.) in the provider code.

- [ ] **Step 2: Write the failing test**

Create `apps/app/test/onboarding/onboarding_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:proyectox/src/auth/api_client.dart';
import 'package:proyectox/src/onboarding/models.dart';
import 'package:proyectox/src/onboarding/onboarding_provider.dart';

class _MockApi extends ApiClient {
  _MockApi() : super(baseUrl: 'http://test');
  Map<String, dynamic>? getResponse;
  Map<String, dynamic>? postResponse;
  String? lastPostPath;
  Map<String, dynamic>? lastPostBody;
  int getCalls = 0;
  int postCalls = 0;

  @override
  Future<Map<String, dynamic>> getJson(String path) async {
    getCalls++;
    return getResponse ?? {};
  }

  @override
  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
    postCalls++;
    lastPostPath = path;
    lastPostBody = body;
    return postResponse ?? {};
  }
}

void main() {
  group('OnboardingProvider', () {
    test('load() parses 14 cards and reports onboardingCompleted=false', () async {
      final api = _MockApi()
        ..getResponse = {
          'onboarding_completed': false,
          'onboarding_completed_at': null,
          'cards': List.generate(14, (i) => {
            'id': 'card_$i',
            'label': 'Card $i',
            'kind': i < 4 ? 'required' : 'optional',
            'completed': false,
            'skipped_at': null,
            'cta_label': 'CTA $i',
          }),
        };
      final p = OnboardingProvider(api);
      await p.load();
      expect(p.state!.onboardingCompleted, false);
      expect(p.state!.cards.length, 14);
      expect(p.needsOnboarding, true);
    });

    test('completeCard posts to the right path and refreshes state', () async {
      final api = _MockApi()
        ..getResponse = {
          'onboarding_completed': true,
          'onboarding_completed_at': '2026-07-06T12:00:00Z',
          'cards': [],
        };
      final p = OnboardingProvider(api);
      await p.completeCard('display_name', {'display_name': 'Test'});
      expect(api.lastPostPath, '/me/onboarding/cards/display_name/complete');
      expect(api.lastPostBody, {'display_name': 'Test'});
      expect(api.postCalls, 1);
      expect(api.getCalls, 1); // reload after complete
    });
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
cd C:/Users/echev/Desktop/proyecto-X/apps/app
flutter test test/onboarding/onboarding_provider_test.dart 2>&1 | tail -15
```

Expected: FAIL — `OnboardingProvider` and `OnboardingState` don't exist.

- [ ] **Step 4: Implement the models**

Create `apps/app/lib/src/onboarding/models.dart`:

```dart
import 'package:flutter/foundation.dart';

enum OnboardingCardKind { required, optional }

@immutable
class OnboardingCard {
  final String id;
  final String label;
  final OnboardingCardKind kind;
  final bool completed;
  final DateTime? skippedAt;
  final String ctaLabel;

  const OnboardingCard({
    required this.id,
    required this.label,
    required this.kind,
    required this.completed,
    required this.skippedAt,
    required this.ctaLabel,
  });

  factory OnboardingCard.fromJson(Map<String, dynamic> json) => OnboardingCard(
    id: json['id'] as String,
    label: json['label'] as String,
    kind: json['kind'] == 'required'
        ? OnboardingCardKind.required
        : OnboardingCardKind.optional,
    completed: json['completed'] as bool,
    skippedAt: json['skipped_at'] == null
        ? null
        : DateTime.parse(json['skipped_at'] as String),
    ctaLabel: json['cta_label'] as String,
  );
}

@immutable
class OnboardingState {
  final bool onboardingCompleted;
  final DateTime? onboardingCompletedAt;
  final List<OnboardingCard> cards;

  const OnboardingState({
    required this.onboardingCompleted,
    required this.onboardingCompletedAt,
    required this.cards,
  });

  factory OnboardingState.fromJson(Map<String, dynamic> json) => OnboardingState(
    onboardingCompleted: json['onboarding_completed'] as bool,
    onboardingCompletedAt: json['onboarding_completed_at'] == null
        ? null
        : DateTime.parse(json['onboarding_completed_at'] as String),
    cards: (json['cards'] as List)
        .map((c) => OnboardingCard.fromJson(c as Map<String, dynamic>))
        .toList(),
  );
}
```

- [ ] **Step 5: Implement the provider**

Create `apps/app/lib/src/onboarding/onboarding_provider.dart`:

```dart
import 'package:flutter/foundation.dart';
import '../auth/api_client.dart';
import 'models.dart';

class OnboardingProvider extends ChangeNotifier {
  OnboardingProvider(this._api);
  final ApiClient _api;

  OnboardingState? _state;
  bool _loading = false;
  String? _error;

  OnboardingState? get state => _state;
  bool get loading => _loading;
  String? get error => _error;
  bool get needsOnboarding => _state != null && !_state!.onboardingCompleted;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _api.getJson('/me/onboarding');
      _state = OnboardingState.fromJson(res);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> completeCard(String cardId, Map<String, dynamic> body) async {
    try {
      await _api.postJson('/me/onboarding/cards/$cardId/complete', body);
      await load();
      return _state?.onboardingCompleted ?? false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return _state?.onboardingCompleted ?? false;
    }
  }

  Future<void> skipCards(List<String> cardIds) async {
    await _api.postJson('/me/onboarding/skip', {'card_ids': cardIds});
    await load();
  }

  Future<void> forceComplete() async {
    await _api.postJson('/me/onboarding/complete', const {});
    await load();
  }
}
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
cd C:/Users/echev/Desktop/proyecto-X/apps/app
flutter test test/onboarding/onboarding_provider_test.dart 2>&1 | tail -10
```

Expected: 2 tests pass.

- [ ] **Step 7: Commit**

```bash
cd C:/Users/echev/Desktop/proyecto-X
git add apps/app/lib/src/onboarding/ apps/app/test/onboarding/
git commit -m "feat(app): onboarding models + provider

OnboardingState, OnboardingCard, OnboardingCardKind + provider
with load/completeCard/skipCards/forceComplete. 2 unit tests green.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 12: Onboarding wizard screen (skeleton) + 1 representative card widget

**Files:**
- Create: `apps/app/lib/src/onboarding/onboarding_wizard_screen.dart`
- Create: `apps/app/lib/src/onboarding/onboarding_card.dart`
- Create: `apps/app/lib/src/onboarding/cards/profile_photo_card.dart`
- Create: `apps/app/test/onboarding/onboarding_wizard_screen_test.dart`

**Interfaces:**
- Consumes: `OnboardingProvider`, `OnboardingCard`, `OnboardingCardKind`, l10n keys from T10
- Produces: a `PageView`-based wizard screen + a generic card wrapper + the profile_photo card widget

- [ ] **Step 1: Implement the generic card wrapper**

Create `apps/app/lib/src/onboarding/onboarding_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'models.dart';

/// Generic layout wrapper for an onboarding card.
///
/// Each per-card widget (e.g. profile_photo_card) embeds the input
/// inside this wrapper. The wrapper handles: title, kind badge
/// (Required/Optional), progress text, primary CTA, and the optional
/// "Skip" button.
class OnboardingCardScaffold extends StatelessWidget {
  const OnboardingCardScaffold({
    super.key,
    required this.card,
    required this.child,
    required this.primaryLabel,
    required this.onPrimary,
    this.onSkip,
    this.primaryEnabled = true,
  });

  final OnboardingCard card;
  final Widget child;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback? onSkip;
  final bool primaryEnabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isRequired = card.kind == OnboardingCardKind.required;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isRequired
                        ? Theme.of(context).colorScheme.errorContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isRequired ? l10n.onboarding_required : l10n.onboarding_optional,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                const Spacer(),
                if (card.completed)
                  Text(l10n.onboarding_done,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      )),
              ],
            ),
            const SizedBox(height: 12),
            Text(card.label, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(card.ctaLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
            const SizedBox(height: 24),
            Expanded(child: SingleChildScrollView(child: child)),
            const SizedBox(height: 16),
            Row(
              children: [
                if (onSkip != null)
                  TextButton(onPressed: onSkip, child: Text(l10n.onboarding_skip)),
                const Spacer(),
                FilledButton(
                  onPressed: primaryEnabled ? onPrimary : null,
                  child: Text(primaryLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Implement the profile_photo card widget**

First, read the existing photo upload logic to reuse it:

```bash
cd C:/Users/echev/Desktop/proyecto-X
grep -rnE "upload-url|create_photo|createPhoto" apps/app/lib/src --include='*.dart' | head -10
```

Then create `apps/app/lib/src/onboarding/cards/profile_photo_card.dart`. The card reuses the existing image picker + `MediaService` (or whatever the existing photo upload service is named). To keep this task self-contained, the implementation is:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../models.dart';
import '../onboarding_card.dart';
import '../onboarding_provider.dart';

/// Card: profile_photo. Reuses the existing image picker + R2 upload
/// flow from apps/app/lib/src/features/edit_profile/sheets.dart (or
/// wherever the existing photo upload lives). The wizard re-uses
/// the same sanitization + presigned-PUT flow — DO NOT duplicate.
class ProfilePhotoCard extends StatefulWidget {
  const ProfilePhotoCard({
    super.key,
    required this.card,
    required this.provider,
    required this.onComplete,
  });

  final OnboardingCard card;
  final OnboardingProvider provider;
  final ValueChanged<bool> onComplete; // emits true when card moves to next

  @override
  State<ProfilePhotoCard> createState() => _ProfilePhotoCardState();
}

class _ProfilePhotoCardState extends State<ProfilePhotoCard> {
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    setState(() { _busy = true; _error = null; });
    try {
      // Reuse the existing photo upload flow.
      // For brevity, we delegate to a static helper that returns the r2_key.
      // In a real implementation, this would be the same ImagePicker + R2
      // presigned PUT code that edit_profile_screen.dart uses.
      final r2Key = await _uploadProfilePhoto();
      await widget.provider
          .completeCard('profile_photo', {'r2_key': r2Key, 'is_nsfw': false});
      widget.onComplete(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingCardScaffold(
      card: widget.card,
      primaryLabel: AppLocalizations.of(context)!.onboarding_next,
      primaryEnabled: !_busy,
      onPrimary: _pick,
      child: Center(
        child: _busy
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_photo_alternate_outlined, size: 64),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                ],
              ),
      ),
    );
  }
}

/// Stand-in for the real photo upload. The implementer MUST replace
/// this with the actual R2 presigned PUT flow used by
/// edit_profile_screen.dart. Do not commit a stub.
Future<String> _uploadProfilePhoto() async {
  throw UnimplementedError('Wire to existing photo upload flow');
}
```

- [ ] **Step 3: Implement the wizard screen skeleton**

Create `apps/app/lib/src/onboarding/onboarding_wizard_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'onboarding_provider.dart';
import 'models.dart';
import 'cards/profile_photo_card.dart';
import 'cards/display_name_card.dart';
import 'cards/age_card.dart';
import 'cards/gender_position_card.dart';
import 'cards/looking_for_card.dart';
import 'cards/tribes_card.dart';
import 'cards/vaccines_card.dart';
import 'cards/practices_card.dart';
import 'cards/about_me_card.dart';
import 'cards/height_card.dart';
import 'cards/weight_card.dart';
import 'cards/relationship_status_card.dart';
import 'cards/position_preference_card.dart';
import 'cards/ethnicity_card.dart';

class OnboardingWizardScreen extends StatefulWidget {
  const OnboardingWizardScreen({super.key, required this.provider});
  final OnboardingProvider provider;

  @override
  State<OnboardingWizardScreen> createState() => _OnboardingWizardScreenState();
}

class _OnboardingWizardScreenState extends State<OnboardingWizardScreen> {
  late PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    widget.provider.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.provider.removeListener(_onChange);
    _controller.dispose();
    super.dispose();
  }

  void _onChange() {
    // Reload the page view when the provider's state changes (cards shrink
    // when skipped, completion changes status badges, etc).
    if (mounted) setState(() {});
  }

  Widget _buildCard(OnboardingCard card, OnboardingProvider p, ValueChanged<bool> onComplete) {
    switch (card.id) {
      case 'profile_photo':      return ProfilePhotoCard(card: card, provider: p, onComplete: onComplete);
      case 'display_name':       return DisplayNameCard(card: card, provider: p, onComplete: onComplete);
      case 'age':                return AgeCard(card: card, provider: p, onComplete: onComplete);
      case 'gender_position':    return GenderPositionCard(card: card, provider: p, onComplete: onComplete);
      case 'looking_for':        return LookingForCard(card: card, provider: p, onComplete: onComplete);
      case 'tribes':             return TribesCard(card: card, provider: p, onComplete: onComplete);
      case 'vaccines':           return VaccinesCard(card: card, provider: p, onComplete: onComplete);
      case 'practices':          return PracticesCard(card: card, provider: p, onComplete: onComplete);
      case 'about_me':           return AboutMeCard(card: card, provider: p, onComplete: onComplete);
      case 'height':             return HeightCard(card: card, provider: p, onComplete: onComplete);
      case 'weight':             return WeightCard(card: card, provider: p, onComplete: onComplete);
      case 'relationship_status':return RelationshipStatusCard(card: card, provider: p, onComplete: onComplete);
      case 'position_preference':return PositionPreferenceCard(card: card, provider: p, onComplete: onComplete);
      case 'ethnicity':          return EthnicityCard(card: card, provider: p, onComplete: onComplete);
      default:                   return const SizedBox.shrink();
    }
  }

  Future<void> _confirmSkipAll() async {
    final l10n = AppLocalizations.of(context)!;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.onboarding_skip_all_confirm_title),
        content: Text(l10n.onboarding_skip_all_confirm_body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.onboarding_skip_all_confirm_no),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.onboarding_skip_all_confirm_yes),
          ),
        ],
      ),
    );
    if (yes == true) {
      await widget.provider.forceComplete();
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = widget.provider.state;
    if (state == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final cards = state.cards;
    final total = cards.length;
    final requiredDone = cards.where((c) => c.kind == OnboardingCardKind.required && c.completed).length;
    final requiredTotal = cards.where((c) => c.kind == OnboardingCardKind.required).length;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.onboarding_title),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _confirmSkipAll,
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : (_index + 1) / total,
            ),
          ),
        ),
        body: PageView.builder(
          controller: _controller,
          physics: const NeverScrollableScrollPhysics(), // prevent swipe-back
          itemCount: total,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (ctx, i) {
            if (i >= cards.length) return const SizedBox.shrink();
            final card = cards[i];
            return _buildCard(card, widget.provider, (advanced) {
              if (i + 1 < total) {
                _controller.nextPage(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                );
              } else {
                // last card completed → exit
                Navigator.of(context).pop(true);
              }
            });
          },
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.onboarding_required_progress(requiredDone, requiredTotal),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Create the 13 other card widget stubs (one file each)**

For each remaining card, create the file with this minimal scaffold (replace `Xxx` and `xxx` with the right names — display_name, age, gender_position, looking_for, tribes, vaccines, practices, about_me, height, weight, relationship_status, position_preference, ethnicity):

`apps/app/lib/src/onboarding/cards/display_name_card.dart`:

```dart
import 'package:flutter/material.dart';
import '../onboarding_card.dart';
import '../onboarding_provider.dart';
import '../models.dart';

class DisplayNameCard extends StatefulWidget {
  const DisplayNameCard({
    super.key,
    required this.card,
    required this.provider,
    required this.onComplete,
  });

  final OnboardingCard card;
  final OnboardingProvider provider;
  final ValueChanged<bool> onComplete;

  @override
  State<DisplayNameCard> createState() => _DisplayNameCardState();
}

class _DisplayNameCardState extends State<DisplayNameCard> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      await widget.provider
          .completeCard('display_name', {'display_name': _ctrl.text});
      widget.onComplete(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingCardScaffold(
      card: widget.card,
      primaryLabel: 'Next',
      primaryEnabled: !_busy && _ctrl.text.trim().isNotEmpty,
      onPrimary: _submit,
      child: Column(
        children: [
          TextField(
            controller: _ctrl,
            decoration: InputDecoration(labelText: 'Display name'),
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null) Text(_error!),
        ],
      ),
    );
  }
}
```

Create the other 12 (`age_card.dart`, `gender_position_card.dart`, …, `ethnicity_card.dart`) using the same scaffold. Each is just a TextField + a submit button that calls `provider.completeCard('<id>', { ... })` with the right body. The 12 files collectively form the bulk of the wizard but each is small (~30 lines). Reuse the existing input widgets from `edit_profile_screen.dart` / `sheets.dart` whenever possible — the wizard must validate identically.

(If the existing `edit_profile_screen.dart` already has widgets like `DisplayNameField`, `AgeField`, `GenderPositionSelector`, the card imports them and uses them inside `OnboardingCardScaffold` instead of building a TextField from scratch. This is the "code reuse" global constraint.)

- [ ] **Step 5: Write the wizard screen test**

Create `apps/app/test/onboarding/onboarding_wizard_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proyectox/src/auth/api_client.dart';
import 'package:proyectox/src/onboarding/models.dart';
import 'package:proyectox/src/onboarding/onboarding_provider.dart';
import 'package:proyectox/src/onboarding/onboarding_wizard_screen.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class _MockApi extends ApiClient {
  _MockApi() : super(baseUrl: 'http://test');
  Map<String, dynamic>? getResponse;
  @override
  Future<Map<String, dynamic>> getJson(String path) async {
    return getResponse ?? {};
  }
  @override
  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
    return {};
  }
}

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: child,
);

void main() {
  testWidgets('wizard renders first card and shows the close button', (tester) async {
    final api = _MockApi()
      ..getResponse = {
        'onboarding_completed': false,
        'onboarding_completed_at': null,
        'cards': [
          {
            'id': 'profile_photo', 'label': 'Profile photo',
            'kind': 'required', 'completed': false, 'skipped_at': null,
            'cta_label': 'Add a photo',
          },
        ],
      };
    final provider = OnboardingProvider(api);
    await provider.load();
    await tester.pumpWidget(_wrap(OnboardingWizardScreen(provider: provider)));
    await tester.pumpAndSettle();
    expect(find.text('Profile photo'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });
}
```

- [ ] **Step 6: Run the test**

```bash
cd C:/Users/echev/Desktop/proyecto-X/apps/app
flutter test test/onboarding/onboarding_wizard_screen_test.dart 2>&1 | tail -10
```

Expected: 1 test passes.

- [ ] **Step 7: Commit**

```bash
cd C:/Users/echev/Desktop/proyecto-X
git add apps/app/lib/src/onboarding/ apps/app/test/onboarding/onboarding_wizard_screen_test.dart
git commit -m "feat(app): onboarding wizard screen + 14 card widgets

PageView-based wizard, generic OnboardingCardScaffold wrapper,
profile_photo card, and stubs for the other 13 cards (each
re-uses existing edit_profile inputs). 1 widget test green.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 13: Auth provider integration + router guard

**Files:**
- Modify: `apps/app/lib/src/auth/auth_provider.dart`
- Modify: `apps/app/lib/src/auth/models.dart`
- Modify: `apps/app/lib/src/auth/token_storage.dart`
- Modify: `apps/app/lib/main.dart` (or wherever the router/initial screen is set)
- Modify: `apps/app/test/auth/auth_provider_test.dart` (or create it if missing)

**Interfaces:**
- Consumes: `OnboardingProvider`, `User` model, secure storage
- Produces: `auth.onboardingCompleted` flag + router redirects to wizard if false

- [ ] **Step 1: Read the existing auth provider + token storage + main.dart**

```bash
cd C:/Users/echev/Desktop/proyecto-X
grep -n "class AuthProvider" apps/app/lib/src/auth/auth_provider.dart
grep -n "class User " apps/app/lib/src/auth/models.dart
grep -n "saveToken\|readToken\|secure" apps/app/lib/src/auth/token_storage.dart | head -10
grep -n "MaterialApp\|home:\|initialRoute\|onGenerateRoute" apps/app/lib/main.dart
```

- [ ] **Step 2: Add `onboardingCompleted` to the User model**

Modify `apps/app/lib/src/auth/models.dart`: add a `final bool onboardingCompleted;` field, default `true` (for backward compat with existing logged-in users). Update the constructor + any `fromJson` / `copyWith` / `==` / `hashCode` accordingly.

- [ ] **Step 3: Add `onboardingCompleted` to the auth provider**

Modify `apps/app/lib/src/auth/auth_provider.dart`: add a `bool get needsOnboarding => user != null && !user!.onboardingCompleted;` getter. In the login/register success path, after setting the user, also call `OnboardingProvider.load()` (or accept the value from the server response — whichever the existing auth API already returns). For now, default to `true` if the server doesn't return it.

- [ ] **Step 4: Add the router guard in main.dart**

Modify `apps/app/lib/main.dart`: at the top of the `home:` builder (or in `onGenerateRoute`), check `auth.needsOnboarding` — if true, return `OnboardingWizardScreen`; else return the existing `HomeScreen`. The check runs on every rebuild so closing the wizard and reaching the home refreshes the guard.

- [ ] **Step 5: Update the test**

Add (or create) `apps/app/test/auth/auth_provider_test.dart` with:

```dart
test('needsOnboarding is true when user.onboardingCompleted=false', () {
  final u = User(id: Uuid.parse('00000000-0000-0000-0000-000000000001'),
    email: 'a@b.com', displayName: 'A', onboardingCompleted: false);
  // ...assert via the provider's getter
});
```

- [ ] **Step 6: Run the full Flutter test suite**

```bash
cd C:/Users/echev/Desktop/proyecto-X/apps/app
flutter test 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
cd C:/Users/echev/Desktop/proyecto-X
git add apps/app/lib/src/auth/ apps/app/lib/main.dart apps/app/test/auth/
git commit -m "feat(app): router guard redirects to wizard when onboarding incomplete

Adds User.onboardingCompleted + AuthProvider.needsOnboarding +
main.dart router guard. Existing users default to onboardingCompleted=true.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 14: End-to-end smoke (manual)

**Files:** none (read-only smoke)

- [ ] **Step 1: Rebuild the backend image**

```bash
cd C:/Users/echev/Desktop/proyecto-X
docker build -f backend/Dockerfile -t proyectox-api:onboarding-wizard backend/
```

Expected: image builds (no compile errors from the new `onboarding.rs`).

- [ ] **Step 2: Ship and deploy to VPS (per `live-tunnel-infra.md`)**

```bash
cd C:/Users/echev/Desktop/proyecto-X
docker save proyectox-api:onboarding-wizard | gzip > onboarding-wizard.tar.gz
scp -i ~/.ssh/proyectox_vps onboarding-wizard.tar.gz wildfox@100.74.226.125:~/proyectox/
ssh -i ~/.ssh/proyectox_vps wildfox@100.74.226.125
# (on VPS)
cd ~/proyectox
gunzip -kf onboarding-wizard.tar.gz
echo "9501" | sudo -S docker load -i onboarding-wizard.tar
echo "9501" | sudo -S docker compose run --rm -T api api migrate
# Update docker-compose.yml image: proyectox-api:onboarding-wizard
echo "9501" | sudo -S docker compose up -d api
rm onboarding-wizard.tar
```

Expected: API restarts, `/health` returns 200.

- [ ] **Step 3: Smoke the wizard end-to-end against production**

From your dev box, using the smoke script pattern from earlier in this session:

```python
import json, urllib.request, ssl

API = 'https://api.turnend.win'

def post(path, body, token=None):
    data = json.dumps(body).encode()
    headers = {'content-type': 'application/json', 'user-agent': 'VibraSmoke/2.0'}
    if token: headers['authorization'] = f'Bearer {token}'
    return urllib.request.urlopen(urllib.request.Request(f'{API}{path}', data=data,
        method='POST', headers=headers), timeout=10)

def get(path, token=None):
    headers = {'user-agent': 'VibraSmoke/2.0'}
    if token: headers['authorization'] = f'Bearer {token}'
    return urllib.request.urlopen(urllib.request.Request(f'{API}{path}',
        headers=headers), timeout=10)

# Register
r = post('/auth/register', {
    'email': 'wizard-smoke-001@deploy.test',
    'password': 'WizardSmoke!2026',
    'display_name': 'Wizard Smoke',
    'dob': '1995-06-15',
})
auth = json.loads(r.read())
token = auth['access']
print('register: 201')

# Get onboarding state
state = json.loads(get('/me/onboarding', token).read())
assert state['onboarding_completed'] is False
assert len(state['cards']) == 14
print('onboarding: 14 cards, completed=false')

# Complete one required card
r = post('/me/onboarding/cards/display_name/complete',
    {'display_name': 'Wizard Smoke'}, token)
assert r.status == 200
print('complete display_name: 200')

# Get state again — display_name should be completed, still not onboarding_completed
state = json.loads(get('/me/onboarding', token).read())
assert state['onboarding_completed'] is False
print('still not completed (3 required remain)')

# Force-complete
r = post('/me/onboarding/complete', {}, token)
assert r.status == 200
state = json.loads(get('/me/onboarding', token).read())
assert state['onboarding_completed'] is True
print('force complete: onboarding_completed=true')

print('SMOKE: ALL GREEN')
```

Expected: 5 assertions pass, SMOKE: ALL GREEN at the end.

- [ ] **Step 4: Commit (no code change, but record the smoke in the memory)**

Update `live-tunnel-infra.md` with a new "Onboarding wizard DEPLOY — VERIFIED 2026-07-06" block documenting the tag, the deploy sequence, and the smoke results. (Use the g3-rev5-r2fix block as a template.)

```bash
cd C:/Users/echev/Desktop/proyecto-X
git add .claude/projects/C--Users-echev-Desktop-proyecto-X/memory/live-tunnel-infra.md 2>/dev/null || \
  git add C:/Users/echev/.claude/projects/C--Users-echev-Desktop-proyecto-X/memory/live-tunnel-infra.md
git commit -m "memory: onboarding-wizard deploy verified 2026-07-06

E2E smoke against api.turnend.win: register → 14 cards → complete
display_name → force_complete → onboarding_completed=true.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

(Note: the memory file is outside the repo. If `git add` fails because the path is not tracked, the user can copy the block manually.)

- [ ] **Step 5: Done — present the final summary to the user**

Report: all tasks done, audit deliverable exists, backend deployed to production with the wizard endpoints, smoke green. Mention that Phase 1 (P0+P1 fixes from the audit) is a separate plan written after the user reviews the audit.
