# Onboarding Wizard + Production Hardening + Parity Design

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Date:** 2026-07-06
**Status:** Approved by user
**Scope:** This spec covers (a) a full read-only audit of the proyecto-X codebase, (b) a profile-onboarding wizard for newly-registered users, and (c) production hardening of the critical issues the audit surfaces. Parity-complete work (Discover, Travel Pass, Tribes, Events, Shop, three-tier premium) is **explicitly out of scope** and will be a separate spec.

**Goal:** Ship a clean, production-ready backend + Flutter app where new users complete a profile-completion wizard at first login (mandatory + optional cards), and the codebase has no obvious placeholders, stubs, or simulated logic in critical paths.

**Architecture:** Three phases (audit → critical fixes → onboarding wizard), each delivering independently testable output. The audit is read-only; fixes and wizard work land as atomic commits.

**Tech Stack:** Rust (axum + sqlx + Neon Postgres) backend, Flutter app (`apps/app`), Flutter admin (`apps/admin`), already deployed to `https://api.turnend.win` via Cloudflare Tunnel. Existing design pattern: multi-stage Docker image, R2 presigned PUT/GET, Redis pub-sub for chat.

## Global Constraints

- **Parity scope (this spec):** Tier 1/2/3 + E3 (edit profile) + E5 (NUEVO/filters/units) + G3 (cards onboarding). Discover, Travel Pass, Tribes-as-filter, Events, Shop, and 3-tier premium are out of scope.
- **Required cards (4):** profile_photo, display_name, age, gender_position. Until all four are complete, `users.onboarding_completed_at` stays NULL and the user is **excluded from `/grid/nearby` for everyone else** (their own profile detail works normally).
- **Optional cards (10):** looking_for, tribes, vaccines, practices, about_me, height, weight, relationship_status, position_preference, ethnicity. Each optional has a "Skip" button that records the skip in `users.onboarding_skipped_cards` (JSONB) — skipped cards no longer appear in the wizard if the user closes and reopens it.
- **Audit deliverable:** `docs/superpowers/audits/2026-07-06-full-audit.md` with P0–P4 prioritized findings and exact file:line citations. Read-only — no commits during the audit itself.
- **Fixes scope (Phase 1):** Only P0 (breaks production) and P1 (broken UX flows) findings. P2–P4 are recorded but not addressed in this plan.
- **New migration:** `0039_onboarding.sql` adds `onboarding_completed_at` + `onboarding_skipped_cards` to `users`.
- **Backward compatibility:** the `users` table changes are additive (NULL + default `'[]'`), so the migration is safe to run on the live Neon DB without coordination beyond the standard maintenance window.
- **No git push** (standing rule from `subagent-push-incident` memory).
- **No secrets in chat / git** (Neon password, R2 keys, JWT secret, TOTP KEK, SMTP key, OAuth client IDs, Firebase SA JSON). `backend/.env` and the box `~/proyectox/.env` are both gitignored.
- **Deploy recipe:** build image on PC → `docker save|gzip` → scp → `docker load` → `docker compose up -d api` (see `live-tunnel-infra.md` for the full sequence with all gotchas — orphan docker-proxy, sudo password, etc.).

---

## Phase 0 — Audit (read-only, ~1 day)

**Goal:** Produce a complete inventory of placeholder / stub / simulated / inconsistent / poorly-implemented code in the three apps (backend, app, admin) and the cross-app data flow.

**Approach:** Three parallel subagent sweeps, then synthesize. Each subagent reads its assigned scope and writes findings to a section in `docs/superpowers/audits/2026-07-06-full-audit.md`. The main agent reviews the three sections and produces the prioritized final report.

**Sweep 1 — Backend (`backend/crates/**`):**

Grep the backend for known placeholder patterns:
- `todo!()`, `unimplemented!()`, `unreachable!()` in production paths
- `// TODO`, `// FIXME`, `// XXX`, `// HACK` (English and Spanish)
- `panic!` in handlers (acceptable in tests only)
- `println!`, `eprintln!`, `dbg!` in production (not tests)
- Identifiers containing `simulate_`, `mock_`, `fake_`, `stub_`, `dummy_`, `dev_only_`
- `tracing::warn!` or `tracing::error!` containing "TODO" or "not implemented"
- Files with name `simulate.rs`, `mock.rs`, `stub.rs`, `fake.rs`, `dev_only.rs`
- Handlers that return `Ok(())` with a body of <3 statements (likely stubs)
- Comments in Spanish/English that describe the function as "temporary" or "for now"

Read in full and report on:
- `backend/crates/api/src/billing/simulate.rs` (the file name itself is a red flag)
- `backend/crates/api/src/billing/mod.rs`, `subscriptions.rs`, `plans.rs`, `webhook.rs`, `error.rs` (verify RevenueCat webhook signature is real, plan definitions match the FE tier_features.dart)
- `backend/crates/api/src/dev.rs` (likely dev-only seed, should be gated)
- `backend/crates/api/src/tier1.rs`, `tier2.rs`, `tier3.rs`, `grindr_t1.rs` (may have dead endpoints)
- `backend/crates/api/src/chat_broker.rs` (Redis pub-sub: real or no-op fallback?)
- `backend/crates/api/src/fcm.rs` (Firebase admin SDK: real push or no-op?)
- `backend/crates/api/src/notifications.rs`
- `backend/crates/api/src/stories.rs`
- `backend/crates/api/src/profile.rs`
- `backend/crates/api/src/grid.rs`
- `backend/crates/api/src/admin/handlers.rs`, `handlers_enterprise.rs`, `audit.rs`
- All migrations in `backend/migrations/` — verify they apply cleanly to a fresh DB and the indexes they claim to create actually exist

**Sweep 2 — App (`apps/app/lib/src/**`):**

Grep the Flutter app for:
- `TODO`, `FIXME`, `XXX` in comments
- `throw UnimplementedError(...)`, `throw '...'`
- `// ignore:` lines (suspicious when there are many in one file)
- `print(` calls outside `main.dart` (logging leakage)
- Hardcoded English strings not wrapped in `AppLocalizations` or `l10n`
- Screens with `// TODO(l10n)` or `// TODO(i18n)` markers
- Empty `build()` methods
- `Navigator.push` to `AlertDialog` showing "Not implemented" or similar
- Methods returning `Future.value(null)` or `Future.value({})` with no body
- Identifiers `mock`, `fake`, `stub`, `dummy`, `_placeholder`

Read in full and report on:
- `apps/app/lib/src/features/edit_profile_screen.dart` (large file, may have commented-out sections)
- `apps/app/lib/src/features/home_screen.dart` (entry point after login)
- `apps/app/lib/src/features/login_screen.dart`, `register_screen.dart`
- `apps/app/lib/src/features/grid_search_screen.dart`
- `apps/app/lib/src/features/chat_screen.dart`, `chat_list_screen.dart`
- `apps/app/lib/src/features/profile_detail_screen.dart`, `profile_screen.dart`, `profile_drawer.dart`
- `apps/app/lib/src/features/albums_screen.dart`, `album_detail_screen.dart`
- `apps/app/lib/src/features/circles_screen.dart`, `group_info_screen.dart`
- `apps/app/lib/src/features/create_story_screen.dart`
- `apps/app/lib/src/features/right_now_screen.dart`
- `apps/app/lib/src/features/security_screen.dart`, `pin_screen.dart`
- `apps/app/lib/src/calls/call_screen.dart`, `call_service.dart`
- `apps/app/lib/src/billing/revenuecat_service.dart`, `billing_service.dart`, `tier_features.dart`
- `apps/app/lib/src/ads/ad_provider.dart`
- `apps/app/lib/src/notifications/`
- `apps/app/lib/src/auth/auth_service.dart`, `auth_provider.dart`, `api_client.dart`

**Sweep 3 — Admin (`apps/admin/lib/src/**`):**

Same grep patterns as Sweep 2, focused on:
- All 13 admin screens (audit, config, content, dashboard, gdpr, growth, login, moderation, settings, users)
- `apps/admin/lib/src/auth/admin_auth_service.dart`
- `apps/admin/lib/src/widgets/admin_http_client.dart`
- Verify the admin's TOTP login flow works against the real `/admin/auth/totp` endpoint
- Verify each admin screen calls a real backend endpoint (not a hardcoded JSON)

**Cross-app sweep (main agent, after the 3 subagents):**

For each endpoint in `backend/crates/api/src/**/handlers*.rs` (use grep `pub async fn`):
1. Is there a corresponding screen or service in the app/admin that calls it?
2. For each screen in the app/admin: does it have a corresponding backend endpoint, or does it use hardcoded data?
3. Are the field names consistent across backend JSON, app models, and admin models?
4. Are there backend endpoints that no client calls? (Dead code)

Produce a table:
```
| Endpoint | App caller | Admin caller | Status |
| GET /me | ✓ profile_screen | ✓ user_detail | OK |
| POST /billing/simulate-purchase | none | none | Likely dev-only |
| ...
```

**Audit deliverable structure (`docs/superpowers/audits/2026-07-06-full-audit.md`):**

```markdown
# proyecto-X Full Audit — 2026-07-06

## Summary
- Total findings: N (P0: x, P1: y, P2: z, P3: w, P4: v)
- Estimated effort for P0+P1: ~Xd
- Critical risks: [list]

## P0 — Breaks production (must fix before next deploy)
### P0-1: <Title>
- **File:** `path/to/file.rs:LINE`
- **What:** Description
- **Impact:** How this breaks users in production
- **Fix:** Concrete recommendation

## P1 — Broken UX flows
[same structure]

## P2 — Missing or non-functional features
[same structure]

## P3 — Placeholders / stubs / simulated logic
[same structure]

## P4 — Cleanup (lints, code, comments)
[same structure]

## Cross-app consistency table
[the table described above]

## Out of scope (P2–P4 deferred)
```

**Acceptance criteria for Phase 0:**
- File exists at the right path
- Every finding has a file:line citation
- Every finding has a concrete fix recommendation
- Findings are classified P0–P4
- The cross-app table is complete (no endpoint without a row, no screen without a row)

---

## Phase 1 — Critical Fixes (P0 + P1 only)

**Goal:** Fix every P0 and P1 finding from the audit. Defer P2–P4 to a future plan.

**Approach:** Each fix is one task. The number of tasks equals the number of P0+P1 findings, plus 1 for the test/E2E verification task at the end. Each task ends with `cargo test --workspace` green + the relevant Flutter `flutter test` green.

**Task shape (repeated for each fix):**
1. Write the failing test (Rust integration test, or Flutter widget test)
2. Run it to confirm it fails
3. Implement the fix
4. Run the test to confirm it passes
5. Run the full test suite
6. Commit (no push)

**Example fix tasks likely to exist (from the audit naming-convention grep alone):**
- T-1.1: Replace `billing/simulate.rs` with a real RevenueCat subscription refresh path (or remove it and gate dev-only endpoints behind `cfg(dev)`)
- T-1.2: Wire `chat_broker.rs` to use the existing Redis URL (or document the in-memory fallback explicitly)
- T-1.3: Replace the `fcm.rs` no-op with a real Firebase admin push
- T-1.4: Fix any endpoint with `Ok(())` empty body
- T-1.5: Gate `dev.rs` behind `#[cfg(feature = "dev-seed")]` and remove the feature flag from the release Dockerfile
- T-1.6: ...
- T-1.N: E2E smoke against `https://api.turnend.win` after fixes (re-run the g3-rev5-r2fix R2 smoke from this session to confirm no regression; the wizard smoke is in Phase 2)

**Acceptance criteria for Phase 1:**
- Zero P0 findings remain
- Zero P1 findings remain
- All tests pass
- Smoke against `https://api.turnend.win` confirms no regression (health 200, R2 roundtrip 200, login 200)

---

## Phase 2 — Onboarding Wizard

**Goal:** After a successful register, the new user sees a fullscreen modal wizard with 4 required + 10 optional cards. Once all required are done (or the user force-skips), the user enters the home. Until then, the user is invisible in `/grid/nearby` for everyone else.

### 2.1 — Backend changes

**New migration: `backend/migrations/0039_onboarding.sql`**

```sql
-- Onboarding wizard state for newly-registered users.
ALTER TABLE users
  ADD COLUMN onboarding_completed_at TIMESTAMPTZ NULL,
  ADD COLUMN onboarding_skipped_cards JSONB NOT NULL DEFAULT '[]'::jsonb;

-- Partial index for the grid filter (only users who've completed onboarding
-- are visible to others).
CREATE INDEX idx_users_onboarding_completed
  ON users (onboarding_completed_at)
  WHERE onboarding_completed_at IS NOT NULL;
```

**New module: `backend/crates/api/src/onboarding.rs`**

```rust
//! Onboarding wizard state machine.
//!
//! A user is "onboarding" from registration until they complete the wizard
//! (or force-skip it). Onboarding users are hidden from `/grid/nearby`.

use axum::{extract::{Path, State}, http::StatusCode, routing::{get, post}, Json, Router};
use serde::{Deserialize, Serialize};
use sqlx::types::Json as SqlxJson;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/me/onboarding", get(get_state))
        .route("/me/onboarding/cards/:card_id/complete", post(complete_card))
        .route("/me/onboarding/skip", post(skip_cards))
        .route("/me/onboarding/complete", post(force_complete))
}

#[derive(Serialize, sqlx::FromRow)]
pub struct OnboardingCard {
    pub id: String,
    pub label: String,           // "Profile photo"
    pub kind: String,            // "required" | "optional"
    pub completed: bool,
    pub skipped_at: Option<OffsetDateTime>,
    pub cta_label: String,       // "Add photo"
}

#[derive(Serialize, sqlx::FromRow)]
pub struct OnboardingState {
    pub onboarding_completed: bool,
    pub onboarding_completed_at: Option<OffsetDateTime>,
    pub cards: Vec<OnboardingCard>,
}

const REQUIRED_CARDS: &[(&str, &str, &str)] = &[
    ("profile_photo",   "Profile photo",   "Add a photo"),
    ("display_name",    "Display name",    "Set your name"),
    ("age",             "Age",             "Confirm your age"),
    ("gender_position", "Gender & position", "Set your gender and position"),
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

async fn get_state(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
) -> Result<Json<OnboardingState>, StatusCode> {
    let row: (Option<OffsetDateTime>, SqlxJson<Vec<serde_json::Value>>) =
        sqlx::query_as("SELECT onboarding_completed_at, onboarding_skipped_cards FROM users WHERE id = $1")
            .bind(user_id)
            .fetch_one(&state.pool)
            .await
            .map_err(|e| { tracing::error!("onboarding load: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;

    let completed_at = row.0;
    let skipped: Vec<String> = row.1.0.iter()
        .filter_map(|v| v.get("card_id").and_then(|c| c.as_str()).map(String::from))
        .collect();

    let mut cards = Vec::new();
    for (id, label, cta) in REQUIRED_CARDS {
        cards.push(OnboardingCard {
            id: id.to_string(),
            label: label.to_string(),
            kind: "required".into(),
            completed: false, // refreshed below from per-field state
            skipped_at: None,
            cta_label: cta.to_string(),
        });
    }
    for (id, label, cta) in OPTIONAL_CARDS {
        if !skipped.contains(&id.to_string()) {
            cards.push(OnboardingCard {
                id: id.to_string(),
                label: label.to_string(),
                kind: "optional".into(),
                completed: false,
                skipped_at: None,
                cta_label: cta.to_string(),
            });
        }
    }

    // Re-fetch per-card completion by checking the underlying field
    let user: UserProfileSnapshot = sqlx::query_as(...)
        .bind(user_id)
        .fetch_one(&state.pool).await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    for card in cards.iter_mut() {
        card.completed = match card.id.as_str() {
            "profile_photo" => user.has_profile_photo,
            "display_name" => !user.display_name.is_empty(),
            "age" => user.dob.is_some(),
            "gender_position" => user.gender.is_some() && user.position.is_some(),
            "looking_for" => user.looking_for.is_some(),
            "tribes" => !user.tribes.is_empty(),
            "vaccines" => !user.vaccines.is_empty(),
            "practices" => !user.practices.is_empty(),
            "about_me" => !user.about_me.is_empty(),
            "height" => user.height_cm.is_some(),
            "weight" => user.weight_kg.is_some(),
            "relationship_status" => user.relationship_status.is_some(),
            "position_preference" => user.position_preference.is_some(),
            "ethnicity" => user.ethnicity.is_some(),
            _ => false,
        };
    }

    Ok(Json(OnboardingState {
        onboarding_completed: completed_at.is_some(),
        onboarding_completed_at: completed_at,
        cards,
    }))
}
```

(The other handlers — `complete_card`, `skip_cards`, `force_complete` — follow the same pattern: load user, mutate the appropriate field based on `card_id`, persist, return. Full implementation in the implementation plan.)

**Grid filter change:** `backend/crates/api/src/grid.rs` — add `AND u.onboarding_completed_at IS NOT NULL` to the `nearby` query (and to any other grid endpoint that returns other users).

**Router wiring:** `backend/crates/api/src/lib.rs` — `.merge(onboarding::router())` alongside the existing routes.

**Tests (Rust):**
- `tests/onboarding_e2e.rs`:
  1. Register a fresh user → assert `GET /me/onboarding` returns `onboarding_completed=false` with 14 cards.
  2. Complete 3 of 4 required → assert `onboarding_completed` still false.
  3. Complete the 4th required → assert `onboarding_completed=true` and `users.onboarding_completed_at` is set.
  4. Register a second user who skips onboarding → assert `GET /grid/nearby` (called as user 1) does NOT include user 2.
  5. User 2 force-completes onboarding → assert `GET /grid/nearby` now includes user 2.

### 2.2 — App changes

**New file: `apps/app/lib/src/onboarding/models.dart`**

```dart
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
    kind: json['kind'] == 'required' ? OnboardingCardKind.required : OnboardingCardKind.optional,
    completed: json['completed'] as bool,
    skippedAt: json['skipped_at'] == null ? null : DateTime.parse(json['skipped_at'] as String),
    ctaLabel: json['cta_label'] as String,
  );
}

enum OnboardingCardKind { required, optional }

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

**New file: `apps/app/lib/src/onboarding/onboarding_provider.dart`**

```dart
class OnboardingProvider extends ChangeNotifier {
  OnboardingProvider(this._api);
  final ApiClient _api;

  OnboardingState? _state;
  bool _loading = false;
  String? _error;

  OnboardingState? get state => _state;
  bool get loading => _loading;
  String? get error => _error;
  bool get needsOnboarding =>
    _state != null && !_state!.onboardingCompleted;

  Future<void> load() async {
    _loading = true; _error = null; notifyListeners();
    try {
      final res = await _api.getJson('/me/onboarding');
      _state = OnboardingState.fromJson(res);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false; notifyListeners();
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

**New file: `apps/app/lib/src/onboarding/onboarding_wizard_screen.dart`**

A `PageView` over the cards. Each card is a widget that:
- Shows a title, description, and a slot for the input
- Has a "Siguiente" / "Saltar" button
- The "Saltar" button is only shown for optional cards

Top bar has: a progress indicator (X / 14), a "Cerrar" button that triggers the force-skip confirmation dialog.

The wizard exits when:
- The user completes all required cards (last required → `onboardingCompleted=true`) → pushReplacement to home.
- The user taps "Cerrar" → confirm dialog → `forceComplete` → pushReplacement to home.

**New per-card widgets:** `apps/app/lib/src/onboarding/cards/profile_photo_card.dart`, `display_name_card.dart`, `age_card.dart`, `gender_position_card.dart`, `looking_for_card.dart`, `tribes_card.dart`, `vaccines_card.dart`, `practices_card.dart`, `about_me_card.dart`, `height_card.dart`, `weight_card.dart`, `relationship_status_card.dart`, `position_preference_card.dart`, `ethnicity_card.dart`. Each is a self-contained form that calls `OnboardingProvider.completeCard` on submit.

(Reuse existing widgets where possible: the existing `EditProfileScreen` has the same fields, so the card widgets can be thin wrappers that re-use the existing inputs. This is a deliberate code-reuse choice — not a duplication of business logic.)

**Auth provider change:** `apps/app/lib/src/auth/auth_provider.dart` — add `bool onboardingCompleted` to the user state. After login/register, call `OnboardingProvider.load()` and set the flag. Persist the flag in the secure token storage (encrypted, alongside the access/refresh tokens) so the app doesn't need a network call to decide routing on next launch.

**Router change:** after the user has valid tokens, the router checks `auth.onboardingCompleted`:
- If `false` → `OnboardingWizardScreen`
- If `true` → `HomeScreen`

**i18n:** add to `apps/app/lib/l10n/app_en.arb` + `app_es.arb` (and any other locales):
- `onboarding_title`, `onboarding_subtitle`
- `onboarding_skip`, `onboarding_skip_all`, `onboarding_skip_confirm`
- `onboarding_required_cards_left`, `onboarding_optional_cards_left`
- Per-card labels: `onboarding_card_profile_photo_label`, `onboarding_card_profile_photo_cta`, etc.
- Validation messages: `onboarding_error_required`, `onboarding_error_offline`

**Tests (Flutter):**
- `test/onboarding/onboarding_wizard_screen_test.dart`:
  - Renders the first card
  - "Siguiente" disabled when input is empty
  - "Saltar" only on optional cards
  - Force-skip dialog appears when closing
- `test/onboarding/onboarding_provider_test.dart`:
  - `load()` sets state from mock API response
  - `completeCard` posts the right body and refreshes state
  - `skipCards` records the right card_ids
  - `forceComplete` posts to the right endpoint

**E2E (manual or integration):**
- Register a fresh user → wizard appears → complete all 4 required → home shown.
- Register a second fresh user → wizard appears → tap "Cerrar" → confirm → home shown.
- As user 1, call `/grid/nearby` → assert user 2 is NOT in the list.

---

## Out of Scope (Future Specs)

- **Parity-complete with Grindr:** Discover, Travel Pass, Tribes-as-filter, Events, Shop, 3-tier premium (Xtra/Unlimited/Supreme) with all 8 differentiated features. These each warrant their own spec and implementation plan.
- **Audit findings P2, P3, P4:** deferred.
- **Admin panel changes related to onboarding:** the admin already has a `user_detail_screen.dart`; we add a small "Onboarding status" section to it (out of scope here, document as a follow-up).
- **Marketing site / SEO changes:** not affected.
- **iOS/Android specific config:** not affected.

---

## Risk and Open Questions

- **R.** The audit may surface a P0 finding that's much bigger than expected (e.g. billing is 100% simulated). Phase 1 will then need a sub-plan of its own. Mitigation: the audit deliverable includes effort estimates so the user can decide before Phase 1 starts.
- **OQ.** The 14 cards may feel too long. If user testing in Phase 2 reveals fatigue, we can group them or auto-complete some (e.g. "looking_for" can be derived from initial signup if we add a field there).
- **OQ.** The `grid/nearby` exclusion means brand-new users can't see anyone else until they complete onboarding. This is by design but may surprise the user; we expose a 1-line setting `grid.hide_unfinished_onboarders` (default true) to make it a feature flag.

---

## Acceptance Criteria (whole spec)

- [ ] `docs/superpowers/audits/2026-07-06-full-audit.md` exists with the structure defined in Phase 0.
- [ ] Zero P0 findings remain after Phase 1.
- [ ] Zero P1 findings remain after Phase 1.
- [ ] `cargo test --workspace` is green.
- [ ] `flutter test` is green (in `apps/app` and `apps/admin`).
- [ ] A new user registering in production sees the wizard and can complete it.
- [ ] A new user who skips the wizard does NOT appear in other users' `/grid/nearby` responses.
- [ ] `curl https://api.turnend.win/health` returns `{"status":"ok","db":"up"}`.
- [ ] The R2 roundtrip smoke (PUT/GET) still returns 200 against the deployed API.
- [ ] All commits are local (no `git push`).
- [ ] No secrets in chat, git, or new files.
