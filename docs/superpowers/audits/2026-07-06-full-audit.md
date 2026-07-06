# proyecto-X Full Audit — 2026-07-06

## Summary

### Findings by priority

| Priority | Backend | App | Admin | Total |
|----------|---------|-----|-------|-------|
| P0 | 2 | 0 | 0 | 2 |
| P1 | 0 | 3 | 1 | 4 |
| P2 | 1 | 4 | 4 | 9 |
| P3 | 3 | 7 | 3 | 13 |
| P4 | 2 | 7 | 1 | 10 |
| **Total** | **8** | **21** | **9** | **38** |

### Estimated effort for P0+P1 (person-hours)

- **P0-1 (android_sha256 recursion)**: 0.5 h — trivial one-line fix.
- **P0-2 (DevOAuthVerifier auth bypass)**: 1 h — gate the fallback behind a build flag or startup check.
- **P1-1 (chat timestamp display)**: 0.5 h — add modulo condition.
- **P1-2 (PIN stored unencrypted)**: 1 h — replace SharedPreferences with `flutter_secure_storage`.
- **P1-3 (NSFW service fails open)**: 2 h — add fail-closed mode for production builds.
- **P1-4 (admin reports dropdown)**: 0.5 h — rename `initialValue` to `value`.
- **Total P0+P1 effort**: **5.5 person-hours**.

### Top 3 critical risks

1. **Authentication bypass (P0)**: `DevOAuthVerifier` accepts forged tokens when `OAUTH_GOOGLE_CLIENT_ID` is unset. Any production deployment missing this env var is fully compromised — arbitrary user impersonation with no auth required. **Fix first**, before any deployment.
2. **Server crash on `.well-known` (P0)**: `android_sha256()` infinite-recursion stack overflow crashes the server process. If `ANDROID_SHA256_FINGERPRINT` is not set (or set to empty in CI/CD), the first request to `/.well-known/assetlinks.json` brings the server down.
3. **Content moderation bypass (P1)**: The NSFW detector fails open — every error path silently allows explicit images through. A corrupt model file or missing asset means zero content filtering without any visible alert.

## Methodology
- Read-only scan of `backend/crates/**`, `apps/app/lib/src/**`, `apps/admin/lib/src/**`.
- Tools: `grep -rE` patterns, `Read` of suspicious files, cross-reference with `git log --oneline -- <file>`.
- Each finding has a `file:line` citation and a concrete fix recommendation.
- P0 = breaks production; P1 = broken UX flow; P2 = missing/non-functional feature; P3 = placeholder/stub/simulated logic; P4 = cleanup.

## Backend

### P0 — Breaks production

1. **`android_sha256()` infinite recursion on missing env var** — `backend/crates/api/src/well_known.rs:9`

   - **What**: `android_sha256()` calls itself recursively in the `unwrap_or_else` closure when `ANDROID_SHA256_FINGERPRINT` is not set. Each call fails the env var lookup and recurses, causing a stack overflow.
   - **Impact**: Any request to `GET /.well-known/assetlinks.json` without this env var crashes the server process (P0).
   - **Fix**: Change the closure to return a static default string or `String::new()`:
     ```rust
     fn android_sha256() -> String {
         std::env::var("ANDROID_SHA256_FINGERPRINT")
             .unwrap_or_else(|_| "CHANGE_ME".into())
     }
     ```

2. **`DevOAuthVerifier` fallback authenticates arbitrary users when `OAUTH_GOOGLE_CLIENT_ID` is unset** — `backend/crates/api/src/main.rs:35`

   - **What**: When `OAUTH_GOOGLE_CLIENT_ID` is not set, `RealOAuthVerifier::from_env()` returns `None` and the application falls back to `DevOAuthVerifier`. This verifier accepts tokens in the format `dev:<provider_uid>:<email>` without any cryptographic verification.
   - **Impact**: In any deployment where `OAUTH_GOOGLE_CLIENT_ID` is absent (including production), anyone who knows this token format can authenticate as any user, bypassing all authentication. This is a production-authentication-bypass vulnerability (P0).
   - **Fix**: Fail at startup if OAuth is not configured and the environment is production, or require at least Google client ID for all builds. Remove the `DevOAuthVerifier` fallback from production builds entirely.

### P1 — Broken UX flows

None.

### P2 — Missing or non-functional features

1. **`/billing/simulate-purchase` exposed in production router without env gate** — `backend/crates/api/src/billing/simulate.rs:55`

   - **What**: The `simulate_purchase` handler creates an active subscription row (`source='simulated'`) for any authenticated user who provides a valid `price_id`. Unlike `/dev/seed` which is guarded by `DEV_SEED_ENABLED=true`, this endpoint has no runtime gate.
   - **Impact**: Any authenticated user can obtain a free premium subscription by calling this endpoint with a known `price_id`.
   - **Fix**: Gate the route behind `DEV_SEED_ENABLED` env var, or remove the route for production builds. Pattern to follow: `dev.rs` uses `std::env::var("DEV_SEED_ENABLED")` at request time.

### P3 — Placeholders / stubs / simulated logic

1. **`DevNotifier` fallback silently drops emails in production** — `backend/crates/api/src/main.rs:32`

   - **What**: `SmtpNotifier::from_env()` returns `None` when `SMTP_API_KEY` is unset. The fallback `DevNotifier` logs email content to `tracing::info!` and returns `Ok(())` without actually sending. The code path has no warning or startup failure.
   - **Impact**: Password-reset and email-verification emails are silently not delivered in production if SMTP is misconfigured.
   - **Fix**: Fail at startup (`panic!` or `bail!`) when `SMTP_API_KEY` is absent and the environment is detected as production, or add a startup warning with clear instructions.

2. **Apple identity token signature verification is permanently skipped** — `backend/crates/auth/src/oauth.rs:101-130`

   - **What**: `verify_apple_token()` decodes the JWT payload without verifying the RSA signature against Apple's public keys. A comment on line 103 reads "without signature verification". Only the `aud` claim is checked.
   - **Impact**: A forged Apple identity token with a matching `aud` field (obtainable from any app) would be accepted as valid.
   - **Fix**: Fetch Apple's public JWKS from `https://appleid.apple.com/auth/keys` and verify the JWT signature using the `jsonwebtoken` crate with `Algorithm::RS256`.

3. **`SmtpNotifier::send_sms` is a no-op stub** — `backend/crates/auth/src/notify.rs:80-83`

   - **What**: SMS sending via the SMTP notifier logs to `tracing::info!` and returns `Ok(())` without contacting any provider. The comment says "SMS not yet implemented via SMTP".
   - **Impact**: If SMS-based flows (e.g. 2FA) ever use this code path, the messages are silently dropped.
   - **Fix**: Either implement SMS via a dedicated provider (Twilio, etc.) or return an `Err` so callers know SMS is unavailable.

### P4 — Cleanup

1. **Migration numbering gap (0027, 0028 missing)** — `backend/migrations/`

   - **What**: Migration files jump from `0026_ephemeral_photos.sql` to `0029_subscriptions.sql`. Files `0027` and `0028` are absent. This was likely a renumbering or deletion.
   - **Impact**: None at runtime (the migration runner tracks applied hashes, not sequence). Cosmetic issue for developers reading the migration list.
   - **Fix**: Renumber `0029` through `0038` to close the gap, or leave well enough alone and avoid gaps in future additions.

2. **Unused variable warning in profile photo handling** — `backend/crates/api/src/profile.rs:283`

   - **What**: The `url` variable is assigned from `crate::media::presign(...)` but never read. The compiler emits `warning: unused variable: url`.
   - **Impact**: None — cosmetic, but indicates dead code.
   - **Fix**: Prefix with underscore (`_url`) or remove the assignment if the presigned URL is not needed.

## App

### P0 — Breaks production

None.

### P1 — Broken UX flows

1. **Chat timestamp display logic always returns false for non-zero indices** — `apps/app/lib/src/features/chat_screen.dart:518-521`

   - **What**: `_shouldShowTimestamp()` is documented to show timestamps "every 10 messages or at the first message", but the implementation is `if (index == 0) return true; return false;`. No user ever sees timestamp separators after the first message in a chat.
   - **Impact**: Users never see message timestamps beyond the initial load (P1 — broken UX flow).
   - **Fix**: Add modulo logic to show a timestamp every N messages, e.g. `if (index == 0) return true; if (index % 10 == 0) return true; return false;`.

2. **PIN stored unencrypted despite comment claiming encryption** — `apps/app/lib/src/settings/settings_providers.dart:103-127`

   - **What**: The file-level doc comment on line 103 says "stored encrypted in SharedPreferences", but `prefs.setString()` on line 125 stores the PIN as plaintext. SharedPreferences on Android is an unencrypted XML file, world-readable on rooted devices.
   - **Impact**: A 4-digit app-lock PIN is stored without encryption, contradicting the documented security promise (P1).
   - **Fix**: Use `flutter_secure_storage` or encrypt via `encrypt` package before writing to SharedPreferences.

3. **NSFW service fails open — all errors silently allow uploads through** — `apps/app/lib/src/nsfw/nsfw_service.dart:58,67,78-79`

   - **What**: Every error path in the NSFW detector returns `NsfwResult(score: 0.0, isNsfw: false)`. If the detection model fails to load or inference throws, the image is allowed through without any filtering.
   - **Impact**: A consistently failing NSFW detector (corrupt model, missing assets) silently bypasses content moderation for all uploads (P1).
   - **Fix**: Consider a "fail-closed" fallback for production builds (block uploads when NSFW is unavailable) or at minimum log a separate error metric.

### P2 — Missing or non-functional features

1. **Delete Account is stubbed — shows "not yet available" dialog** — `apps/app/lib/src/features/you_screen.dart:86-100`

   - **What**: The `_deleteAccount()` method shows a dialog with the message "This feature is not yet available." and never calls the API. Users who want to delete their account have no working path.
   - **Impact**: Users cannot delete their account from the app (P2 — missing feature).
   - **Fix**: Implement the API call, or at minimum remove the misleading UI affordance and route to a support flow.

2. **Filter options hardcoded instead of served by API** — `apps/app/lib/src/features/cascade_screen.dart:78-90`

   - **What**: Three static lists (`_kTribes`, `_kBodyTypes`, `_kLookingFor`) are embedded in source code. Adding or renaming a filter option requires an app release.
   - **Impact**: Filter options are stale until the next app update (P2).
   - **Fix**: Serve filter option enumerations from the backend (e.g. `GET /meta/filters`).

3. **HomeScreen entirely deprecated — zero implementation** — `apps/app/lib/src/features/home_screen.dart:1-3`

   - **What**: The file contains only a deprecation comment. Any route or test referencing this screen hits a null widget.
   - **Impact**: Broken if any route still references `HomeScreen` (P2).
   - **Fix**: Remove the file and update any remaining imports/routes.

4. **Profile screen retains inline editing despite dedicated EditProfileScreen** — `apps/app/lib/src/features/profile_screen.dart:540-586`

   - **What**: `profile_screen.dart` still contains `_buildTextField()`, save/cancel buttons, and edit-mode state management, duplicating what `edit_profile_screen.dart` does.
   - **Impact**: Two conflicting edit paths confuse users and double maintenance (P2).
   - **Fix**: Strip edit-mode from `profile_screen.dart` and redirect to `/edit-profile` for all edits.

### P3 — Placeholders / stubs / simulated logic

1. **Chat relative-time formatting is a documented stub** — `apps/app/lib/src/features/chat_list_screen.dart:295`

   - **What**: `_relativeTime()` comment says "Stub: in production use intl.DateFormat". Returns only `HH:mm` for same-day or `dd/MM` for older dates — no "yesterday", "2 days ago", etc.
   - **Impact**: Chat timestamps are bare, without relative human-readable formatting (P3).
   - **Fix**: Replace with `intl` package's `DateFormat` or a dedicated relative-time library.

2. **Block/unblock method retained under `// ignore: unused_element`** — `apps/app/lib/src/features/profile_detail_screen.dart:177`

   - **What**: `_toggleBlock()` (lines 178-202) is suppressed from the unused-element lint with an ignore directive. Comment says "no block button in the new UI," but the method is kept alive.
   - **Impact**: Dead code preserved under an ignore directive (P3).
   - **Fix**: Remove the method and the ignore directive. Re-introduce when the block UI is built.

3. **Visitor status provider marked as local-only / temporary** — `apps/app/lib/src/settings/settings_providers.dart:136-138`

   - **What**: The doc comment says "mirrors backend visitor_status column from T2.1, but kept LOCAL for now — no backend sync in this task."
   - **Impact**: Visitor status state lives only on-device with no backend synchronization (P3).
   - **Fix**: Implement backend sync for visitor status or remove the comment if the state is intentionally local-only.

4. **Right Now screen has zero l10n — mixed English/Spanish hardcoded strings** — `apps/app/lib/src/features/right_now_screen.dart:22-221`

   - **What**: The entire screen is unlocalized. Strings are a mix of English (`'Post Right Now'`, `'30 min'`) and Spanish (`'1 hora'`, `'Publicar'`, `'Reintentar'`). No `AppLocalizations` import exists.
   - **Impact**: Users see a mix of languages regardless of locale setting (P3 — simulated logic, not real i18n).
   - **Fix**: Import `AppLocalizations` and use l10n keys for all user-facing strings.

5. **Album detail screen has zero l10n** — `apps/app/lib/src/features/album_detail_screen.dart`

   - **What**: No `AppLocalizations` import exists. All user-facing strings (`'Album not found'`, `'No photos yet'`, `'Add Photos'`, `'Close'`, etc.) are hardcoded in English.
   - **Impact**: Entire screen is untranslated regardless of locale (P3).
   - **Fix**: Import `AppLocalizations` and use l10n keys for all strings.

6. **You screen has zero l10n** — `apps/app/lib/src/features/you_screen.dart`

   - **What**: No `AppLocalizations` import. All user-facing strings (`'You'`, `'Edit Profile'`, `'Settings'`, `'Notifications'`, `'Privacy'`, `'Logout'`, etc.) are hardcoded in English.
   - **Impact**: Entire screen is untranslated regardless of locale (P3).
   - **Fix**: Import `AppLocalizations` and use l10n keys for all strings.

7. **Cascade screen filename does not match class name** — `apps/app/lib/src/features/cascade_screen.dart`

   - **What**: The file is named `cascade_screen.dart` but the main class inside is `NavegarScreen`. A comment on line 921 says "UNCHANGED from original CascadeScreen".
   - **Impact**: Confusion for developers navigating the codebase (P3).
   - **Fix**: Rename the file to `navegar_screen.dart` to match the class, or vice versa.

### P4 — Cleanup

1. **Widespread incomplete l10n coverage across many screens**

   The following screens have no `AppLocalizations` import at all (every user-facing string is hardcoded):
   - `apps/app/lib/src/features/login_screen.dart` — all strings hardcoded
   - `apps/app/lib/src/features/register_screen.dart` — all strings hardcoded
   - `apps/app/lib/src/features/profile_screen.dart` — all strings hardcoded

   The following screens import l10n but have significant gaps:
   - `apps/app/lib/src/features/edit_profile_screen.dart` — hardcoded strings at lines 409 (`'Edit Profile'`), 509 (`'Display Name'`), 518 (`'Bio'`), 796 (`'HIV Status'`), 812 (`'Last Tested On'`), 861 (`'On PrEP'`), 958 (`'Change Photo'`), and many label/hint/button texts
   - `apps/app/lib/src/features/security_screen.dart:23-56` — 6 tip cards (12 strings) hardcoded despite importing l10n
   - `apps/app/lib/src/features/pin_screen.dart` — imports l10n for title only; validation, dialogs, buttons all hardcoded
   - `apps/app/lib/src/features/chat_screen.dart` — ~20 hardcoded strings: error states, input hints, buttons, view-once flow
   - `apps/app/lib/src/features/grid_search_screen.dart` — Roam bottom sheet (~10 strings) hardcoded in English
   - `apps/app/lib/src/features/cascade_screen.dart` — entire filter sheet (~25 strings) hardcoded
   - `apps/app/lib/src/features/albums_screen.dart` — 6 strings in create dialog and SnackBars hardcoded
   - `apps/app/lib/src/features/create_story_screen.dart` — 3 strings (Share, Error, Upload error) hardcoded
   - `apps/app/lib/src/features/circles_screen.dart` — `'Group'` fallback and member count not localized
   - `apps/app/lib/src/calls/call_screen.dart` — `'Unmute'`, `'Mute'`, `'Speaker'`, `'Earpiece'` not localized
   - `apps/app/lib/src/theme/widgets.dart:540-541` — `'POPULAR'` badge not localized

   - **Fix**: Add l10n keys for every hardcoded string listed above.

2. **Hardcoded static option lists in edit_profile_screen** — `apps/app/lib/src/features/edit_profile_screen.dart:67-78`

   - **What**: Two static `const List<String>` fields (`_hivStatusOptions` with 4 entries, `_tribeOptions` with 18 entries) are embedded in source code rather than fetched from the API.
   - **Impact**: Adding/renaming HIV status or tribe options requires an app release.
   - **Fix**: Serve these enumerations from the backend (e.g. `GET /meta/enums`).

3. **RevenueCat test API key hardcoded as static const** — `apps/app/lib/src/billing/revenuecat_service.dart:24`

   - **What**: The public test API key is embedded in source code. There is no environment-based override to swap between test and production keys.
   - **Impact**: Changing environments requires a rebuild.
   - **Fix**: Read the API key from `String.fromEnvironment('REVENUECAT_API_KEY')` with a test-key fallback for debug builds.

4. **AdMob unit ID fallback to test ID without warning** — `apps/app/lib/src/ads/ad_provider.dart:25-26`

   - **What**: The production AdMob unit ID is read from `String.fromEnvironment('ADMOB_NATIVE_UNIT_ID')`. If unset in a release build, it silently serves test ads in production.
   - **Impact**: Production builds could serve test ads without any developer notification.
   - **Fix**: Assert or log a warning if the env var is absent in release mode.

5. **Hardcoded connection timeouts in API client** — `apps/app/lib/src/auth/api_client.dart:9-10`

   - **What**: `connectTimeout` and `receiveTimeout` are both hardcoded to 10 seconds. These should be configurable or come from a shared settings source.
   - **Impact**: Cannot adjust timeouts without a rebuild.
   - **Fix**: Read timeout values from env vars or a config provider.

6. **Empty catch blocks with no logging** — multiple files

   - `apps/app/lib/src/calls/call_service.dart:367,375` — two empty `catch (_) {}` blocks in `_cleanup()` with no logging
   - `apps/app/lib/src/features/right_now_screen.dart:124,219` — two empty `catch (_)` blocks
   - `apps/app/lib/src/features/cascade_screen.dart:168,333` — two empty `catch (_)` blocks
   - `apps/app/lib/src/auth/token_storage.dart:46,57,69` — three empty `catch (_) {}` blocks (with fallback-to-SharedPreferences comment)

   - **Fix**: Add `debugPrint` or `tracing` log statements in each catch block for debuggability.

7. **Inline hex color literals not using theme constants** — `apps/app/lib/src/theme/widgets.dart`

   - **What**: Multiple inline `Color(0x...)` literals (lines 395, 400-401, 483, 487, 519, 537, 689) bypass `VibraTheme` named constants.
   - **Impact**: Theme changes require hunting down inline literals.
   - **Fix**: Define each unique color as a `VibraTheme` constant and reference it.

## Admin

### P0 — Breaks production

None.

### P1 — Broken UX flows

1. **`DropdownButtonFormField` uses `initialValue` instead of `value` — reports screen cannot compile** — `apps/admin/lib/src/features/moderation/reports_screen.dart:198`

   - **What**: The Review Report dialog's action selector uses `initialValue: selectedAction` on a `DropdownButtonFormField<String>`. The Flutter API resolves this as an unknown named parameter — `DropdownButtonFormField` accepts `value`, not `initialValue`. The Dart compiler rejects this, so the entire Moderation Queue screen fails to build.
   - **Impact**: The reports/moderation screen is completely inaccessible. Any navigation to the moderation queue results in a build failure, making the entire moderation workflow unavailable from the admin panel (P1).
   - **Fix**: Replace `initialValue` with `value` at line 198.

### P2 — Missing or non-functional features

1. **Webhooks screen is read-only — no create, edit, delete, or test** — `apps/admin/lib/src/features/settings/webhooks_screen.dart`

   - **What**: The `WebhooksScreen` lists webhooks with name, URL, status, and last-fired timestamp. There are no action buttons, no "New Webhook" button, and no way to toggle or delete an existing webhook. The screen is a view-only listing.
   - **Impact**: Operators cannot configure integrations from the admin panel. Any webhook management requires direct database access or API calls (P2).
   - **Fix**: Add "New Webhook", "Edit", "Toggle", "Delete" affordances, matching the pattern used in `FlagsScreen` or `ApiKeysScreen`.

2. **Legal documents screen has no edit or delete actions on existing rows** — `apps/admin/lib/src/features/content/legal_docs_screen.dart`

   - **What**: `LegalDocsScreen` displays a table of documents with title, version, effective date, and status. Each row has no action column. The only write operation is "New Version" via the header button. Users cannot edit or archive existing documents.
   - **Impact**: Once created, a legal document version is effectively immutable from the UI (P2).
   - **Fix**: Add Edit and Delete/Archive action buttons to each row, matching the pattern in `CmsScreen`.

3. **Campaigns screen is read-only — no create, edit, launch, or delete** — `apps/admin/lib/src/features/growth/campaigns_screen.dart`

   - **What**: `CampaignsScreen` displays a listing with name, type, status, sent date, and stats. There are no action buttons and no create button. The screen is view-only.
   - **Impact**: Operators cannot create or manage campaigns from the admin panel (P2).
   - **Fix**: Add create/edit/launch affordances or, if the screen is intentionally read-only, add a note explaining where campaigns are managed.

4. **Experiments screen is read-only — no create, start, pause, or stop** — `apps/admin/lib/src/features/growth/experiments_screen.dart`

   - **What**: `ExperimentsScreen` lists experiments with name, status, variants, start date, and end date. No action buttons exist on rows and no create button is present. The screen cannot be used to manage experiments.
   - **Impact**: Operators cannot start, stop, or create A/B experiments from the admin panel (P2).
   - **Fix**: Add create/start/pause/stop controls or, if intentionally read-only, add a note explaining where experiments are managed.

### P3 — Placeholders / stubs / simulated logic

1. **CMS "Edit" button is a no-op stub** — `apps/admin/lib/src/features/content/cms_screen.dart:290`

   - **What**: `_CmsRow` renders an "Edit" action button with `onPressed: () {}`. Clicking the button performs zero operations. The "Delete" button next to it works correctly (makes a real HTTP call).
   - **Impact**: Users cannot edit existing CMS content from the admin panel. The Edit button appears functional but does nothing (P3).
   - **Fix**: Wire `onPressed` to an edit dialog (matching the pattern in `TranslationsScreen` or `TemplatesScreen`) that makes a `PUT /admin/cms/:id` call.

2. **No pagination on any list view — hardcoded `limit: 50, offset: 0`** — multiple files

   - `apps/admin/lib/src/features/audit/audit_screen.dart:39` — `'limit': '50', 'offset': '0'`
   - `apps/admin/lib/src/features/moderation/reports_screen.dart:50-51` — same pattern
   - `apps/admin/lib/src/features/moderation/csam_screen.dart:40` — `'limit': '50'`
   - `apps/admin/lib/src/features/gdpr/data_requests_screen.dart:38` — same pattern
   - `apps/admin/lib/src/features/users/user_list_screen.dart:72` — `'limit': '20', 'offset': '0'`

   - **What**: Every list screen fetches a hardcoded page of results. There is no pagination widget, infinite scroll, or "Load more" control. If the dataset exceeds the page size, users never see the remaining entries.
   - **Impact**: For datasets larger than 50 records (audit logs, CSAM hits, data requests) or 20 records (users), content beyond the first page is inaccessible from the admin panel (P3).
   - **Fix**: Add cursor or offset-based pagination to each list provider, and render "Previous" / "Next" controls in the table footer.

3. **Template editor only updates the subject field — no content body editing** — `apps/admin/lib/src/features/content/templates_screen.dart:224-262`

   - **What**: The edit dialog for notification templates contains a single `TextField` for the `subject` field. The template's body/content cannot be edited from the UI. The `PUT /admin/templates/:id` call only sends `{'subject': ...}`.
   - **Impact**: Operators can rename a template but cannot modify its push/email body content (P3).
   - **Fix**: Add a multiline body field to the edit dialog and include it in the PUT payload.

### P4 — Cleanup

1. **Hardcoded English UI strings pervasive across every admin screen**

   A sample of the affected locations (screen titles, dialog titles, button labels, error messages):
   - `apps/admin/lib/src/features/config/abuse_rules_screen.dart:74` — `Text('Abuse Detection Rules', ...)`
   - `apps/admin/lib/src/features/config/flags_screen.dart:161` — `title: const Text('Create Feature Flag')`
   - `apps/admin/lib/src/features/content/cms_screen.dart:184` — `title: const Text('Create CMS Content')`
   - `apps/admin/lib/src/features/content/cms_screen.dart:307` — `title: const Text('Delete CMS Item')`
   - `apps/admin/lib/src/features/content/legal_docs_screen.dart:183` — `title: const Text('New Legal Document Version')`
   - `apps/admin/lib/src/features/gdpr/data_requests_screen.dart:75` — `Text('GDPR Data Requests', ...)`
   - `apps/admin/lib/src/features/moderation/csam_screen.dart:77` — `Text('CSAM Hash Queue', ...)`
   - `apps/admin/lib/src/features/settings/api_keys_screen.dart:181` — `title: const Text('Create API Key')`

   - **What**: Screen titles, dialog titles, button labels, error messages, and descriptions are hardcoded English strings in every admin screen. The admin panel has no l10n infrastructure at all — no `AppLocalizations` import, no translation keys, no localization setup. This is a systemic issue: every single `Text()` widget in the admin module is unlocalized (50+ instances across all screens), not merely a handful of outliers.
   - **Impact**: The entire admin panel cannot be localized. Any deployment serving non-English-speaking admins would require a full l10n pass, not a spot fix (P4).
   - **Fix**: Add l10n infrastructure to the admin module (following the pattern in `apps/app/` which uses `AppLocalizations`), then extract every user-facing string into translation keys.

## Cross-app consistency

### Endpoint coverage matrix

Legend: Backend = exposes endpoint, App = app client calls it, Admin = admin client calls it.

| Group | Endpoint | Backend | App | Admin |
|-------|----------|---------|-----|-------|
| **Auth** | POST /auth/register | Y | Y | - |
| | POST /auth/login | Y | Y | - |
| | POST /auth/refresh | Y | Y | - |
| | POST /auth/logout | Y | Y | - |
| | POST /auth/verify-email | Y | Y | - |
| | POST /auth/resend-email | Y | - | - |
| | POST /auth/password/reset-request | Y | - | - |
| | POST /auth/password/reset | Y | - | - |
| | POST /auth/send-phone-code | Y | - | - |
| | POST /auth/verify-phone | Y | - | - |
| | POST /auth/oauth/:provider | Y | Y | - |
| **Profile** | GET /profile | Y | Y | - |
| | PUT /profile | Y | Y | - |
| | DELETE /profile | Y | Y | - |
| | GET /profile/:id | Y | Y | - |
| | GET /profile/health | Y | Y | - |
| | PUT /profile/health | Y | Y | - |
| | GET /profile/views | Y | Y | - |
| | GET /profile/views/count | Y | Y | - |
| | POST /profile/verify | Y | - | - |
| | GET /profile/verify/status | Y | - | - |
| **Grid** | GET /grid/nearby | Y | Y | - |
| **Chat** | GET /chat/conversations | Y | Y | - |
| | POST /chat/conversations | Y | Y | - |
| | DELETE /chat/conversations/:id | Y | Y | - |
| | GET /chat/conversations/:id/messages | Y | Y | - |
| | POST /chat/conversations/:id/messages | Y | Y | - |
| | POST /chat/conversations/:id/read | Y | Y | - |
| | POST /chat/conversations/:id/messages/:mid/viewed | Y | Y | - |
| | PUT /chat/messages/:id/reaction | Y | Y | - |
| | DELETE /chat/messages/:id/reaction | Y | Y | - |
| | POST /chat/messages/:id/unsend | Y | Y | - |
| | GET /chat/groups | Y | Y | - |
| | POST /chat/groups | Y | Y | - |
| | PUT /chat/groups/:id/name | Y | Y | - |
| | GET /chat/groups/:id/members | Y | Y | - |
| | POST /chat/groups/:id/members | Y | Y | - |
| | DELETE /chat/groups/:id/members/:uid | Y | Y | - |
| | GET /ws/chat | Y | Y (WebSocket) | - |
| **Social** | POST /taps | Y | Y | - |
| | GET /taps/count | Y | Y | - |
| | GET /taps/received | Y | Y | - |
| | GET /taps/sent | Y | - | - |
| | GET /favorites | Y | Y | - |
| | POST /favorites | Y | Y | - |
| | DELETE /favorites/:user_id | Y | Y | - |
| | GET /blocks | Y | Y | - |
| | POST /blocks | Y | Y | - |
| | DELETE /blocks/:user_id | Y | Y | - |
| | POST /reports | Y | Y | - |
| **Albums** | GET /albums | Y | Y | - |
| | POST /albums | Y | Y | - |
| | GET /albums/:id | Y | - | - |
| | PUT /albums/:id | Y | - | - |
| | DELETE /albums/:id | Y | - | - |
| | GET /albums/shared | Y | Y | - |
| | POST /albums/:id/photos | Y | Y | - |
| | DELETE /albums/:id/photos/:photo_id | Y | - | - |
| | POST /albums/:id/share | Y | - | - |
| | DELETE /albums/:id/share/:user_id | Y | - | - |
| **Stories** | POST /stories | Y | Y | - |
| | GET /stories | Y | Y | - |
| | DELETE /stories/:id | Y | Y | - |
| | POST /stories/:id/view | Y | Y | - |
| **Right Now** | POST /right-now | Y | Y | - |
| | GET /right-now | Y | Y | - |
| | DELETE /right-now/:id | Y | Y | - |
| **Presence** | POST /heartbeat | Y | Y | - |
| | GET /users/:id/status | Y | Y | - |
| **Billing** | GET /billing/plans | Y | Y | - |
| | POST /billing/simulate-purchase | Y | Y | - |
| | GET /billing/me | Y | Y | - |
| | POST /billing/revenuecat/webhook | Y | - | - (server-to-server) |
| **Notifications** | POST /notifications/register | Y | Y | - |
| | GET /notifications/preferences | Y | Y | - |
| | PUT /notifications/preferences | Y | Y | - |
| **Privacy** | GET /privacy/preferences | Y | - | - |
| | PUT /privacy/preferences | Y | - | - |
| **Media** | POST /media/upload-url | Y | Y | - |
| | GET /media/get-url | Y | Y | - |
| | POST /media/photos | Y | - | - |
| **Tier 2** | POST /boost | Y | Y | - |
| | GET /boost/active | Y | Y | - |
| | GET /phrases | Y | Y | - |
| | POST /phrases | Y | Y | - |
| | PUT /phrases/order | Y | Y | - |
| | DELETE /phrases/:id | Y | Y | - |
| | GET /places | Y | Y | - |
| | POST /places | Y | Y | - |
| | DELETE /places/:id | Y | Y | - |
| | GET /me/location | Y | Y | - |
| | PUT /me/location | Y | Y | - |
| **Tier 3** | GET /me/sessions | Y | Y | - |
| | DELETE /me/sessions/:id | Y | Y | - |
| | POST /screenshots | Y | - | - |
| | GET /screenshots | Y | - | - |
| | GET /me/idle-reminder | Y | Y | - |
| | PUT /me/idle-reminder | Y | Y | - |
| **Admin** | POST /admin/auth/login | Y | - | Y |
| | POST /admin/auth/2fa | Y | - | Y |
| | POST /admin/auth/logout | Y | - | Y |
| | GET /admin/users | Y | - | Y |
| | GET /admin/users/:id | Y | - | Y |
| | POST /admin/users/:id/:action | Y | - | Y |
| | GET /admin/audit | Y | - | Y |
| | GET /admin/reports | Y | - | Y |
| | POST /admin/reports/:id/review | Y | - | - |
| | POST /admin/reports/:id/resolve | Y | - | Y |
| | GET /admin/moderation/photos | Y | - | - |
| | POST /admin/moderation/photos/:id/approve | Y | - | - |
| | POST /admin/moderation/photos/:id/reject | Y | - | - |
| | GET /admin/csam | Y | - | Y |
| | POST /admin/csam/:id/report | Y | - | Y |
| | GET /admin/support/users/:id/entitlements | Y | - | - |
| | POST /admin/support/users/:id/entitlements | Y | - | - |
| | GET /admin/gdpr/data-requests | Y | - | Y |
| | POST /admin/gdpr/data-requests/:id/process | Y | - | - |
| | GET /admin/legal/export/:user_id | Y | - | - |
| | POST /admin/legal/hold | Y | - | - |
| | POST /admin/legal/hold/:id/release | Y | - | - |
| | GET /admin/flags | Y | - | Y |
| | POST /admin/flags | Y | - | Y |
| | DELETE /admin/flags/:key | Y | - | Y |
| | GET /admin/config | Y | - | - |
| | POST /admin/config | Y | - | - |
| | GET /admin/analytics/overview | Y | - | Y |
| | GET /admin/plans | Y | - | Y |
| | POST /admin/plans | Y | - | - |
| | GET /admin/plans/:code/features | Y | - | Y |
| | POST /admin/plans/:code/features | Y | - | Y |
| | DELETE /admin/plans/:code/features/:feature | Y | - | - |
| | POST /admin/plans/:code/prices | Y | - | - |
| | GET /admin/countries | Y | - | Y |
| | GET /admin/countries/:code | Y | - | - |
| | POST /admin/countries/:code | Y | - | - |
| | GET /admin/experiments | Y | - | Y |
| | POST /admin/experiments | Y | - | - |
| | DELETE /admin/experiments/:key | Y | - | - |
| | GET /admin/i18n | Y | - | Y |
| | POST /admin/i18n | Y | - | - |
| | GET /admin/cms | Y | - | Y |
| | POST /admin/cms | Y | - | Y |
| | POST /admin/cms/:key | Y | - | - |
| | DELETE /admin/cms/:key | Y | - | Y |
| | GET /admin/legal-docs | Y | - | Y |
| | POST /admin/legal-docs | Y | - | Y |
| | GET /admin/campaigns | Y | - | Y |
| | POST /admin/campaigns | Y | - | - |
| | POST /admin/campaigns/:id/send | Y | - | - |
| | GET /admin/templates | Y | - | Y |
| | POST /admin/templates | Y | - | - |
| | GET /admin/abuse/rules | Y | - | Y |
| | POST /admin/abuse/rules | Y | - | - |
| | DELETE /admin/abuse/rules/:id | Y | - | - |
| | GET /admin/api-keys | Y | - | Y |
| | POST /admin/api-keys | Y | - | Y |
| | POST /admin/api-keys/:id/revoke | Y | - | Y |
| | GET /admin/webhooks | Y | - | Y |
| | POST /admin/webhooks | Y | - | - |
| | DELETE /admin/webhooks/:id | Y | - | - |
| | GET /admin/config/history | Y | - | - |
| | POST /admin/config/history/:version/rollback | Y | - | - |

### Key consistency findings

**1. App does not consume 13 backend endpoints**

These endpoints exist on the backend but have no caller in the app codebase:

| Endpoint | Likely reason |
|----------|---------------|
| POST /auth/resend-email | Verification email resend never wired into app UI |
| POST /auth/password/reset-request | Password reset flow not implemented in app |
| POST /auth/password/reset | Same -- reset token submission not implemented |
| POST /auth/send-phone-code | Phone verification not wired in app |
| POST /auth/verify-phone | Same |
| GET /privacy/preferences | Privacy settings screen pending in app |
| PUT /privacy/preferences | Same |
| POST /profile/verify | Profile verification flow not built in app |
| GET /profile/verify/status | Same |
| GET /taps/sent | "Taps sent" list has no UI affordance -- unused endpoint |
| DELETE /albums/:id/photos/:photo_id | Individual photo delete not exposed in albums UI |
| POST /albums/:id/share | Album sharing not implemented in app |
| DELETE /albums/:id/share/:user_id | Same |
| POST /screenshots | Screenshot alert logging not implemented in app |
| GET /screenshots | Screenshot alert list not implemented in app |

Impact: **P2** -- 5 features are completely unconnected (password reset, phone verification, profile verification, albums sharing, screenshot alerts). The remaining endpoints exist but lack a consumer, indicating either dead code or work-in-progress.

**2. Admin app has no screen for 30+ backend admin endpoints**

The backend implements a full admin API (~80 endpoints for CRUD across 15 resource types). The admin app only calls ~34 of them. Major gaps:

- **Photo moderation**: Backend has full approval/rejection pipeline (`GET /admin/moderation/photos`, `POST .../approve`, `POST .../reject`) -- admin app has zero photo moderation screens.
- **Support entitlements**: Backend has `GET/POST /admin/support/users/:id/entitlements` -- admin app has no interface.
- **Legal hold**: Backend has `GET /admin/legal/export/:user_id`, `POST /admin/legal/hold`, `POST .../release` -- admin app has no legal/LER screens.
- **Config management**: Backend has `GET/POST /admin/config` + history/rollback -- admin app has no config editor.
- **Subscription plans**: Backend has full plans CRUD (`POST /admin/plans`, `POST .../prices`, `DELETE .../features/:feature`) -- admin app only reads plans.
- **Experiments**: Backend has `POST/DELETE /admin/experiments` -- admin app only reads.
- **Webhooks**: Backend has `POST/DELETE /admin/webhooks` -- admin app only reads.
- **Abuse rules**: Backend has `POST/DELETE /admin/abuse/rules` -- admin app only reads.

Impact: **P2-P3** -- The admin app is predominantly read-only. Operators must use direct API/DB access for most write operations.

**3. Admin app calls backend endpoints with inconsistent method/pattern**

- Admin app uses `PUT /admin/abuse/rules/:id` but backend expects `POST /admin/abuse/rules` for upsert (id in body) -- method mismatch may cause 405.
- Admin app uses `PUT /admin/countries/:code` but backend expects `POST /admin/countries/:code` -- method mismatch.
- Admin app uses `PUT /admin/i18n/:locale/:key` but backend expects `POST /admin/i18n` -- endpoint path and method both mismatch.
- Admin app uses `PUT /admin/templates/:id` but backend expects `POST /admin/templates` for upsert -- method mismatch.

Impact: **P1** -- These mismatches mean the admin app's write operations for abuse rules, countries, translations, and templates may silently fail (405 Method Not Allowed if backend has no PUT handler, or 404 if the path differs).

**4. Backend endpoints with no consumer in either app (admin-only or orphaned)**

- `POST /billing/revenuecat/webhook` -- server-to-server webhook, intentional (not called by any client)
- `GET /.well-known/apple-app-site-association`, `GET /.well-known/assetlinks.json` -- universal link discovery, intentional
- `POST /dev/seed` -- development only, gated by env var
- `POST /media/photos` -- backend defines the route but no app caller found; likely used by admin or internal

These are correctly scoped and not findings.

### Screen-to-endpoint coverage

| Screen (App) | Backend endpoint(s) | Coverage |
|-------------|---------------------|----------|
| LoginScreen | POST /auth/login | Full |
| RegisterScreen | POST /auth/register | Full |
| CascadeScreen | GET /grid/nearby, GET /favorites, GET /stories | Full |
| ProfileScreen | GET/PUT /profile, GET /profile/:id | Full |
| ProfileDetailScreen | GET /grid/nearby, POST /taps, POST/DELETE /favorites, POST/DELETE /blocks, POST /reports | Full |
| EditProfileScreen | GET/PUT /profile, GET/PUT /profile/health | Full |
| YouScreen | GET /profile | Full |
| InterestScreen | GET /taps/received, GET /taps/count, GET /profile/views, GET /profile/views/count | Full |
| SettingsScreen | GET/PUT /notifications/preferences, POST /me/export-data, DELETE /profile, GET/PUT /me/idle-reminder, GET/DELETE /me/sessions, GET/PUT /phrases | Full |
| ChatScreen | GET/POST/DELETE /chat/conversations/*, PUT/DELETE /chat/messages/:id/reaction, POST /chat/messages/:id/unsend, GET /media/get-url | Full |
| ChatListScreen | GET /chat/conversations | Full |
| AlbumsScreen | GET/POST /albums, DELETE /albums/:id | Partial -- missing individual photo delete |
| AlbumDetailScreen | POST /albums/:id/photos | Partial -- missing photo delete |
| StoriesScreen | GET/POST /stories, DELETE /stories/:id, POST /stories/:id/view | Full |
| RightNowScreen | GET/POST /right-now, DELETE /right-now/:id | Full |
| GridSearchScreen | GET /grid/nearby | Full |
| BlocksListScreen | GET /blocks | Full |
| TiendaScreen | GET /billing/plans, POST /billing/simulate-purchase, GET /billing/me | Full |
| CirclesScreen | GET /chat/groups | Full |
| GroupInfoScreen | PUT /chat/groups/:id/name, POST/DELETE /chat/groups/:id/members | Full |

**Missing screens (endpoint exists but no consuming screen):**
- Password reset flow (POST /auth/password/reset-request, POST /auth/password/reset)
- Phone verification flow (POST /auth/send-phone-code, POST /auth/verify-phone)
- Profile identity verification (POST /profile/verify, GET /profile/verify/status)
- Privacy preferences screen (GET/PUT /privacy/preferences)
- Album sharing UI (POST /albums/:id/share, DELETE /albums/:id/share/:user_id)
- Screenshot alerts (POST/GET /screenshots)

| Screen (Admin) | Backend endpoint(s) | Coverage |
|----------------|---------------------|----------|
| AdminLoginScreen | POST /admin/auth/login | Full |
| UserListScreen | GET /admin/users | Full |
| UserDetailScreen | GET /admin/users/:id, POST /admin/users/:id/:action | Full |
| ReportsScreen | GET /admin/reports, POST /admin/reports/:id/resolve | Full -- but `POST /admin/reports/:id/review` not called |
| AuditScreen | GET /admin/audit | Full |
| DashboardScreen | GET /admin/analytics/overview | Full |
| CmsScreen | GET /admin/cms, POST /admin/cms, DELETE /admin/cms/:key | Full |
| TranslationsScreen | GET /admin/i18n, PUT /admin/i18n/:locale/:key | Partial -- backend expects POST, not PUT |
| LegalDocsScreen | GET /admin/legal-docs, POST /admin/legal-docs | Full |
| CampaignsScreen | GET /admin/campaigns | Partial -- POST /admin/campaigns not called |
| ExperimentsScreen | GET /admin/experiments | Partial -- POST/DELETE not called |
| TemplatesScreen | GET /admin/templates, PUT /admin/templates/:id | Partial -- backend expects POST, not PUT |
| WebhooksScreen | GET /admin/webhooks | Partial -- POST/DELETE not called |
| ApiKeysScreen | GET /admin/api-keys, POST /admin/api-keys, POST /admin/api-keys/:id/revoke | Full |
| FlagsScreen | GET /admin/flags, POST /admin/flags, DELETE /admin/flags/:key | Full |
| PlansScreen | GET /admin/plans, GET/POST /admin/plans/:code/features | Partial -- POST /admin/plans, DELETE /admin/plans not called |
| CountriesScreen | GET /admin/countries, PUT /admin/countries/:code | Partial -- backend expects POST, not PUT |
| AbuseRulesScreen | GET /admin/abuse/rules, PUT /admin/abuse/rules/:id | Partial -- backend expects POST, not PUT |
| CSAMSccreen | GET /admin/csam, POST /admin/csam/:id/report | Full |
| DataRequestsScreen | GET /admin/gdpr/data-requests, POST /admin/gdpr/data-requests/:id/resolve | Full |

**Missing admin screens (backend endpoint exists but no consuming screen):**
- Photo moderation: full pipeline not wired
- Support entitlements: no screen
- Legal hold / LER: no screen
- Config management: no screen
- Config history/rollback: no screen

## Out of scope

The following features are explicitly deferred per the spec and were **not** audited for correctness, completeness, or security:

1. **Discover** -- The algorithmic content feed / discovery tab is not implemented in any tier. No backend endpoints, app screens, or admin screens exist for this feature.

2. **Travel Pass** -- Roam-style location spoofing with a paid pass. The free tier's Roam feature (manual location change) exists at Tier 2, but the paid "Travel Pass" upsell / entitlement gate is not built.

3. **Tribes-as-filter** -- The current implementation uses tribes as user-profile attributes (tags on a profile). Using tribes as a grid/cascade filter criterion (the Grindr "Tribes" filter) is not implemented. The `cascade_screen.dart` filter sheet has hardcoded tribe options (P2 in the main audit), but a server-driven tribes-as-filter pipeline is deferred.

4. **Events** -- No event creation, browsing, RSVP, or check-in functionality exists in any layer.

5. **Shop** -- No in-app merchandise or digital goods storefront beyond the premium subscription Tienda.

6. **3-tier premium** -- Only a single premium subscription tier is implemented (via RevenueCat). The spec's 3-tier model (e.g., XTRA, Unlimited, or Bronze/Silver/Gold) is not built. The `plans` admin screen and backend endpoints exist but support only flat plan/feature configuration.

### What IS in scope (covered by this audit)

- All documented Tier 1, Tier 2, Tier 3 endpoints (chat, profile, albums, stories, right-now, etc.)
- Auth flows (register, login, OAuth, refresh, email verification)
- Billing integration (RevenueCat webhook, subscription state, simulate-purchase)
- Admin panel screens (users, reports, CMS, translations, flags, plans, countries, etc.)
- App screens (cascade, profile, chat, albums, stories, settings, etc.)
- Onboarding wizard (placeholder only -- not yet implemented)
- Deployments and infrastructure (env vars, R2 presigned URLs, Cloudflare Tunnel)
