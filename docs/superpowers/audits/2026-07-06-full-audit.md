# proyecto-X Full Audit — 2026-07-06

## Summary
(populated by Task 4)

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
(populated by Task 3)

## Cross-app consistency
(populated by Task 4)

## Out of scope
(populated by Task 4)
