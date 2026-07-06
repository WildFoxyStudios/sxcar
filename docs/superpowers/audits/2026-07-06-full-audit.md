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
(populated by Task 2)

## Admin
(populated by Task 3)

## Cross-app consistency
(populated by Task 4)

## Out of scope
(populated by Task 4)
