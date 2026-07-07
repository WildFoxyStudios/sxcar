# Remaining Audit Fixes — P2+P3+P4 + Wizard Gaps

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve all remaining audit findings (P2 ×9, P3 ×13, P4 ×10) plus wizard gaps (×3) — 25 tasks grouped into 7 waves by impact and subsystem.

**Architecture:** Seven independent waves. Each wave targets one subsystem and can be executed sequentially. Waves 1-2 are backend security, Waves 3-5 are app features/l10n, Wave 6 is admin CRUD, Wave 7 is cleanup.

**Tech Stack:** Rust 1.96 (axum 0.7, sqlx 0.8, jsonwebtoken), Flutter (Dart, AppLocalizations, intl), Flutter admin.

**Source:** `docs/superpowers/audits/2026-07-06-full-audit.md`

## Global Constraints

- **No git push** (standing rule from `subagent-push-incident` memory).
- **No secrets in chat / git / new files.**
- **All user-facing strings MUST use l10n** (AppLocalizations). No hardcoded English in Text widgets, button labels, dialogs, or error messages.
- **TDD required:** write failing test → verify failure → implement → verify pass → commit.
- **Deploy only after backend changes** (Waves 1, 2, 6 if backend endpoints added).
- **DevNotifier/DevOAuthVerifier pattern:** dev fallbacks must be gated behind env vars, never silent in production.

---

## Wave 1 — Wizard gaps (3 tasks)

### Task 1: Wire profile_photo card to existing R2 upload flow

**Files:**
- Modify: `apps/app/lib/src/onboarding/cards/profile_photo_card.dart`
- Read: edit_profile_screen or sheets.dart to find existing photo upload code

**Fix:** Replace the `UnimplementedError` stub in `_uploadProfilePhoto()` with the real ImagePicker + R2 presigned PUT flow. Find the existing upload implementation (grep for `upload-url` or `createPhoto` in the app), extract it as a reusable service method, and call it from the card.

- [ ] Read existing photo upload code: `grep -rn "upload-url\|create_photo\|image_picker\|ImagePicker" apps/app/lib/src/`
- [ ] Extract upload logic into a shared helper if not already extractable
- [ ] Replace `_uploadProfilePhoto()` stub with the real flow
- [ ] Run: `cd apps/app && flutter test test/onboarding/onboarding_wizard_screen_test.dart`
- [ ] Commit: `fix(app): wire profile_photo card to existing R2 upload flow`

### Task 2: Wire individual Skip button on optional cards

**Files:**
- Modify: `apps/app/lib/src/onboarding/onboarding_card.dart` (or each card)

**Fix:** Pass `onSkip` callback to `OnboardingCardScaffold` on all 10 optional cards. The callback calls `provider.skipCards(['<card_id>'])`. Required cards must NOT have a skip button.

- [ ] Add `onSkip` parameter to each optional card widget constructor
- [ ] Wire `onSkip: () => provider.skipCards(['<card_id>'])` in the wizard screen's `_buildCard`
- [ ] Verify Skip button appears only on optional cards
- [ ] Run: `flutter test test/onboarding/`
- [ ] Commit: `fix(app): wire individual Skip button on optional onboarding cards`

### Task 3: Share option lists between wizard and edit_profile

**Files:**
- Create: `apps/app/lib/src/models/profile_options.dart`
- Modify: `apps/app/lib/src/features/edit_profile_screen.dart` (import shared lists)
- Modify: onboarding cards that define duplicate option lists (tribes, looking_for, gender, position, etc.)

**Fix:** Extract static option lists from edit_profile_screen and onboarding cards into a shared file. Both import from the shared source.

- [ ] Create `profile_options.dart` with all shared const lists
- [ ] Update edit_profile_screen imports
- [ ] Update wizard card imports (all 14 cards)
- [ ] Run: `flutter test`
- [ ] Commit: `refactor(app): share profile option lists between wizard and edit_profile`

---

## Wave 2 — Backend security gaps (4 tasks)

### Task 4: Gate /billing/simulate-purchase behind DEV_SEED_ENABLED

**Files:**
- Modify: `backend/crates/api/src/billing/simulate.rs`
- Modify: `backend/crates/api/src/billing/mod.rs` (if route is mounted here)

**Fix:** Add runtime env check at the top of `simulate_purchase` handler. If `DEV_SEED_ENABLED` is not `"true"`, return `403 Forbidden`. Use the same pattern as `dev.rs`:

```rust
if std::env::var("DEV_SEED_ENABLED").map_or(true, |v| v != "true") {
    return Err(StatusCode::FORBIDDEN);
}
```

- [ ] Read simulate.rs and mod.rs to find handler + route mounting
- [ ] Add env gate at top of handler
- [ ] Test: `cargo test -p api billing` (if tests exist)
- [ ] Commit: `fix(backend): P2 — gate simulate-purchase behind DEV_SEED_ENABLED`

### Task 5: DevNotifier — fail at startup when SMTP_API_KEY absent in production

**Files:**
- Modify: `backend/crates/api/src/main.rs` (~line 32)
- Modify: `backend/crates/auth/src/notify.rs` (SmtpNotifier::from_env)

**Fix:** Add a startup check. If `SMTP_API_KEY` is unset AND the environment is not explicitly dev (`DEV_SMTP_ENABLED` != `"true"`), log an error and return `None` from `from_env()`. Then in main.rs, if the notifier is `None`, either panic or print a loud warning. Follow the same pattern as the OAuth fix (Task 2 from the P0+P1 plan).

- [ ] Read notify.rs `SmtpNotifier::from_env()` 
- [ ] Add env gate: require `SMTP_API_KEY` or `DEV_SMTP_ENABLED=true`
- [ ] Update main.rs to handle `None` notifier
- [ ] Commit: `fix(backend): P3 — DevNotifier requires SMTP_API_KEY or DEV_SMTP_ENABLED`

### Task 6: Verify Apple identity token JWT signature

**Files:**
- Modify: `backend/crates/auth/src/oauth.rs:101-130`

**Fix:** Fetch Apple's public JWKS from `https://appleid.apple.com/auth/keys` and verify the JWT signature using `jsonwebtoken` with `Algorithm::RS256`. The `jsonwebtoken` crate is already a dependency.

```rust
use jsonwebtoken::{decode, decode_header, DecodingKey, Validation, Algorithm};

let jwks: serde_json::Value = reqwest::get("https://appleid.apple.com/auth/keys")
    .await?.json().await?;
// Find the key matching the token's kid header
let header = decode_header(token)?;
let kid = header.kid.ok_or(...)?;
let key = jwks["keys"].as_array().unwrap().iter()
    .find(|k| k["kid"] == kid).ok_or(...)?;
// Build DecodingKey from the JWK's n (modulus) and e (exponent)
let decoding_key = DecodingKey::from_rsa_components(
    key["n"].as_str().unwrap(),
    key["e"].as_str().unwrap(),
)?;
let mut validation = Validation::new(Algorithm::RS256);
validation.set_audience(&["com.turnend.vibra"]); // your app's bundle ID
let token_data = decode::<AppleClaims>(token, &decoding_key, &validation)?;
```

- [ ] Read the current `verify_apple_token()` function
- [ ] Add `reqwest` call to fetch JWKS (or cache it)
- [ ] Replace decode-without-verification with signature-verified decode
- [ ] Write test with a real Apple token or a unit test that verifies the JWKS fetch
- [ ] Commit: `fix(backend): P3 — verify Apple identity token JWT signature`

### Task 7: SMS no-op → return Err

**Files:**
- Modify: `backend/crates/auth/src/notify.rs:80-83`

**Fix:** Change `send_sms` from `Ok(())` to `Err(anyhow::anyhow!("SMS not implemented"))` so callers know SMS is unavailable instead of silently dropping messages.

- [ ] Read current `send_sms` implementation
- [ ] Replace `tracing::info!` + `Ok(())` with an error return
- [ ] Update any callers to handle the error (or verify they already propagate errors)
- [ ] Commit: `fix(backend): P3 — SMS send_sms returns Err instead of silent no-op`

---

## Wave 3 — App P2 (broken features, 4 tasks)

### Task 8: Implement Delete Account

**Files:**
- Modify: `apps/app/lib/src/features/you_screen.dart:86-100`
- Check if backend has `DELETE /me` or similar endpoint

**Fix:** Replace the "not yet available" dialog with an actual API call. First, verify the backend has a delete account endpoint. If it exists, call it. If not, create the endpoint first (add to Wave 2).

- [ ] Check backend: `grep -rn "delete.*account\|DELETE.*me\|delete_me" backend/crates/api/src/`
- [ ] If endpoint exists: replace dialog with API call + confirmation flow
- [ ] If not: create `DELETE /me` handler in backend (new task) + wire in app
- [ ] Add l10n keys for delete confirmation dialog
- [ ] Run: `flutter test`
- [ ] Commit: `feat(app): P2 — implement Delete Account`

### Task 9: Remove deprecated HomeScreen

**Files:**
- Delete: `apps/app/lib/src/features/home_screen.dart`
- Modify: any file that imports HomeScreen

**Fix:** Delete the file. Update imports/routes. Verify no widget tests reference it.

- [ ] Delete the file
- [ ] Run: `grep -rn "HomeScreen\|home_screen" apps/app/` to find remaining references
- [ ] Remove all imports and route references
- [ ] Run: `flutter test` to verify no regressions
- [ ] Commit: `chore(app): P2 — remove deprecated HomeScreen`

### Task 10: Strip inline editing from profile_screen

**Files:**
- Modify: `apps/app/lib/src/features/profile_screen.dart:540-586`

**Fix:** Remove `_buildTextField()`, save/cancel buttons, and edit-mode state from profile_screen.dart. Replace with a button that navigates to `/edit-profile`.

- [ ] Read profile_screen.dart edit-mode code
- [ ] Remove edit-mode state variables, _buildTextField, save/cancel buttons
- [ ] Add "Edit Profile" button that navigates to edit_profile_screen
- [ ] Run: `flutter test`
- [ ] Commit: `fix(app): P2 — strip inline editing from profile_screen, redirect to /edit-profile`

### Task 11: Move filter options to backend GET /meta/filters

**Files:**
- Create: `backend/crates/api/src/meta.rs` (new)
- Modify: `backend/crates/api/src/lib.rs` (mount route)
- Modify: `apps/app/lib/src/features/cascade_screen.dart` (fetch from API)

**Fix:** Create `GET /meta/filters` endpoint that returns `{tribes: [...], looking_for: [...], ...}`. The app fetches this on startup and caches the result. Falls back to hardcoded lists if the API is unreachable.

- [ ] Create meta.rs with `get_filters` handler returning static JSON lists
- [ ] Mount route in lib.rs
- [ ] Update cascade_screen.dart to fetch from API
- [ ] Run: `cargo test -p api` and `flutter test`
- [ ] Commit: `feat(backend): P2 — GET /meta/filters endpoint for dynamic filter options`

---

## Wave 4 — App l10n (3 P3 screens, 3 tasks)

### Task 12: Localize Right Now screen

**Files:**
- Modify: `apps/app/lib/src/features/right_now_screen.dart`
- Modify: `apps/app/lib/l10n/app_en.arb`
- Modify: `apps/app/lib/l10n/app_es.arb`

**Fix:** Import `AppLocalizations`. Replace every hardcoded English/Spanish string with l10n keys. Add ~12 new keys to ARB files.

New keys: `right_now_title`, `right_now_post`, `right_now_duration_30min`, `right_now_duration_1h`, `right_now_duration_2h`, `right_now_duration_4h`, `right_now_duration_6h`, `right_now_publish`, `right_now_retry`, `right_now_error`, `right_now_no_location`, `right_now_location_permission`

- [ ] Add keys to app_en.arb + app_es.arb
- [ ] Run `flutter gen-l10n`
- [ ] Replace all hardcoded strings in right_now_screen.dart
- [ ] Run: `flutter test`
- [ ] Commit: `fix(app): P3 — localize Right Now screen`

### Task 13: Localize Album Detail screen

**Files:**
- Modify: `apps/app/lib/src/features/album_detail_screen.dart`
- ARB files

**Fix:** Same as Task 12. Add ~8 keys: `album_not_found`, `album_no_photos`, `album_add_photos`, `album_close`, `album_delete`, `album_delete_confirm`, `album_share`, `album_share_link`

- [ ] Add keys, regenerate l10n, replace strings, test, commit

### Task 14: Localize You screen

**Files:**
- Modify: `apps/app/lib/src/features/you_screen.dart`
- ARB files

**Fix:** Same pattern. Add ~15 keys: `you_title`, `you_edit_profile`, `you_settings`, `you_notifications`, `you_privacy`, `you_logout`, `you_delete_account`, etc.

- [ ] Add keys, regenerate l10n, replace strings, test, commit

---

## Wave 5 — App P3 stubs + cleanup (3 tasks)

### Task 15: Chat relative-time formatting with intl

**Files:**
- Modify: `apps/app/lib/src/features/chat_list_screen.dart:295`

**Fix:** Replace the stub `_relativeTime()` with `intl` package. Use `DateFormat` for "yesterday", "2 days ago", "just now", etc.

- [ ] Read current _relativeTime implementation
- [ ] Implement relative formatting: <1min "just now", <60min "X min ago", same day "HH:mm", yesterday "Yesterday", <7 days "X days ago", older "dd/MM/yyyy"
- [ ] Write test: 5 cases
- [ ] Commit: `fix(app): P3 — implement relative-time formatting with intl`

### Task 16: Remove dead block/unblock code

**Files:**
- Modify: `apps/app/lib/src/features/profile_detail_screen.dart:177-202`

**Fix:** Remove `_toggleBlock()` method and its `// ignore: unused_element` directive.

- [ ] Delete the method
- [ ] Remove the ignore directive
- [ ] Commit: `chore(app): P3 — remove dead block/unblock code`

### Task 17: Rename cascade_screen.dart → navegar_screen.dart

**Files:**
- Rename: `apps/app/lib/src/features/cascade_screen.dart` → `navegar_screen.dart`
- Modify: all files that import cascade_screen.dart

**Fix:** The file is named `cascade_screen.dart` but contains `NavegarScreen`. Rename to match.

- [ ] Find all imports: `grep -rn "cascade_screen" apps/app/`
- [ ] Rename file
- [ ] Update all imports
- [ ] Run: `flutter test`
- [ ] Commit: `refactor(app): P3 — rename cascade_screen.dart to navegar_screen.dart`

---

## Wave 6 — Admin P2+P3 (3 tasks)

### Task 18: Wire CMS Edit button

**Files:**
- Modify: `apps/admin/lib/src/features/content/cms_screen.dart:290`

**Fix:** Replace `onPressed: () {}` with an edit dialog that makes a `PUT /admin/cms/:id` call. Follow the pattern in `TranslationsScreen` or `TemplatesScreen`.

- [ ] Read the CMS screen and find an existing edit dialog pattern
- [ ] Create edit dialog with pre-populated fields
- [ ] Wire to PUT /admin/cms/:id
- [ ] Commit: `fix(admin): P3 — wire CMS Edit button to edit dialog + PUT API call`

### Task 19: Add pagination to all admin list views

**Files:**
- Modify: audit_screen.dart, reports_screen.dart, csam_screen.dart, data_requests_screen.dart, user_list_screen.dart

**Fix:** Add `PageControls` widget to each list screen's footer with Previous/Next buttons. Update query params to pass dynamic `offset` based on current page.

- [ ] Create a reusable `PageControls` widget
- [ ] Add offset state to each list screen
- [ ] Wire Previous/Next to offset changes
- [ ] Run: `flutter analyze apps/admin/`
- [ ] Commit: `feat(admin): P3 — add pagination controls to all admin list views`

### Task 20: Add template body editor

**Files:**
- Modify: `apps/admin/lib/src/features/content/templates_screen.dart:224-262`

**Fix:** Add a multiline `TextField` for the template body in the edit dialog. Include `body` in the PUT payload.

- [ ] Add body TextField to edit dialog
- [ ] Include in PUT payload
- [ ] Commit: `feat(admin): P3 — add body content editing to template editor`

---

## Wave 7 — P4 Cleanup (5 tasks)

### Task 21: Add logging to all empty catch blocks

**Files:** 9 files with empty catch blocks (call_service.dart, right_now_screen.dart, cascade_screen.dart, token_storage.dart)

**Fix:** Add `debugPrint('[$context] error: $e')` in every empty catch block.

- [ ] Edit each file, add debugPrint in each `catch (_) {}`
- [ ] Commit: `fix(app): P4 — add debugPrint logging to all empty catch blocks`

### Task 22: Extract inline color literals to VibraTheme constants

**Files:**
- Modify: `apps/app/lib/src/theme/widgets.dart` (lines 395, 400-401, 483, 487, 519, 537, 689)

**Fix:** Replace each `Color(0xFF...)` literal with a named `VibraTheme` constant.

- [ ] Read each inline color, name it descriptively
- [ ] Add named constants to the theme file  
- [ ] Replace literals with constants
- [ ] Commit: `refactor(app): P4 — replace inline color literals with theme constants`

### Task 23: AdMob warning on missing env var in release mode

**Files:**
- Modify: `apps/app/lib/src/ads/ad_provider.dart:25-26`

**Fix:** Add an assert or log warning when `ADMOB_NATIVE_UNIT_ID` is absent in release mode.

```dart
if (kReleaseMode && const String.fromEnvironment('ADMOB_NATIVE_UNIT_ID').isEmpty) {
  debugPrint('[AdProvider] WARNING: ADMOB_NATIVE_UNIT_ID not set — serving test ads in production');
}
```

- [ ] Add the warning
- [ ] Commit: `fix(app): P4 — warn when AdMob unit ID is absent in release mode`

### Task 24: RevenueCat API key from environment

**Files:**
- Modify: `apps/app/lib/src/billing/revenuecat_service.dart:24`

**Fix:** Read from `String.fromEnvironment('REVENUECAT_API_KEY')` with test-key fallback for debug.

- [ ] Replace hardcoded key with env var + fallback
- [ ] Commit: `fix(app): P4 — read RevenueCat API key from environment`

### Task 25: Backend P4 — fix unused variable + migration gap note

**Files:**
- Modify: `backend/crates/api/src/profile.rs:283`
- Modify: `backend/migrations/README.md` (or add comment)

**Fix:** Prefix unused `url` variable with underscore. Add a note in migrations directory about the 0027/0028 gap.

- [ ] `let url = ...` → `let _url = ...`
- [ ] Add comment in migrations folder re: gap
- [ ] Commit: `chore(backend): P4 — fix unused variable, document migration gap`
