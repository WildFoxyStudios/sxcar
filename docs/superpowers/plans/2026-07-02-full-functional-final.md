# Plan: 100% funcional — chat media/efímeras UI + NSFW on-device real

## Context
Ephemeral backend is DONE and pushed (e52167e3): `POST .../messages` accepts `{media_key, media_type:"photo", ephemeral:true}` → kind `ephemeral_photo`; `POST /chat/conversations/:id/messages/:message_id/viewed` marks first view (`{viewed:bool}`); message list rows include `ephemeral_viewed_at`. The Flutter chat is text-only. The FRB Rust bridge (`apps/app/rust/`) has REAL tract-onnx NSFW inference but it is cfg-gated OFF for Android (returns Err) and no ONNX model exists — half-done. Android jniLibs pipeline exists (`android/app/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86_64}` built via cargo-ndk).

## Global Constraints
- Nothing simulated or half-wired. Every feature must work end-to-end on Android.
- Backend: `cargo build` clean, new/changed queries validated (sqlx prepare or live test), integration tests pass for touched areas.
- Flutter: `flutter analyze` 0 issues, `flutter test` green, `flutter build apk --debug` succeeds.
- Use `VibraTheme` tokens (`lib/src/theme/app_theme.dart`) for any new UI. Guard `mounted` after async gaps.
- Push only to `origin main`. No new git remotes. No secrets in git.
- Chat photo uploads use the existing presigned flow `POST /media/upload-url` with `kind: "album"` (private bucket), then PUT bytes raw.

## Task 1: Backend — presigned GET for an existing media key
**Files:** `backend/crates/api/src/media.rs` (+ router), `backend/crates/api/tests/media_urls.rs` (new)

Add `GET /media/get-url?key=<r2_key>&kind=<profile|album|verification>` (auth required):
- Validate `kind` ∈ {profile, album, verification} → same bucket routing as `upload_url` (profile→media bucket, album→private, verification→verification).
- Reject empty/`..`-containing keys (400).
- Response: `{ "get_url": "<presigned GET, 3600s>" }` using the existing `presign()` helper and `R2Config`.
- If `state.r2` is None (dev without R2), return 503 like `upload_url` does (mirror its behavior).
- Integration test (no real R2 needed): with a fake/env R2 config if upload_url tests do that — mirror the existing test approach for `upload_url` (check `crates/api/tests/` for how media is tested; if upload_url has only unit tests for presign, add unit-style test for the new handler's validation paths: bad kind → 400, traversal key → 400, unauth → 401).
- Wire route in `media.rs::router()`.

## Task 2: Flutter — chat photo messages + ephemeral "view once" UI
**Files:** `apps/app/lib/src/chat/models.dart`, `apps/app/lib/src/chat/chat_service.dart`, `apps/app/lib/src/features/chat_screen.dart`, tests under `apps/app/test/src/chat/`

Extend the Message model: `mediaKey`, `mediaType`, `readAt`, `ephemeralViewedAt` (all nullable, parse defensively from JSON; keep `fromWebSocketJson` in sync — WS payload includes `media_key`/`media_type` but NOT viewed fields, default null; WS `kind` comes in the payload, use it instead of hardcoded 'text').

ChatService additions:
- `Future<String> sendPhotoMessage(String conversationId, {required String mediaKey, bool ephemeral = false})` → POST messages with `{media_key, media_type: "photo", ephemeral}` (omit `ephemeral` when false), returns id.
- `Future<String> getMediaUrl(String key)` → `GET /media/get-url?key=...&kind=album` returns `get_url`.
- `Future<bool> markEphemeralViewed(String conversationId, String messageId)` → POST `/viewed`, returns `viewed`.

ChatScreen UI:
- Attach button (already an IconButton placeholder or add one in the input bar) → image_picker gallery → on pick, show a small bottom sheet/dialog with a preview + a "View once" toggle (default off) + Send.
- Upload flow: `MediaService.uploadPhoto`-style — request upload-url with `kind: "album"`, PUT bytes, then `sendPhotoMessage(mediaKey, ephemeral: toggle)`. Reuse `lib/src/media/media_service.dart` if it exposes the presigned upload; extend it if the kind is hardcoded.
- Rendering:
  - `kind == 'photo'`: rounded thumbnail (max ~220px), loaded via `getMediaUrl(mediaKey)` (FutureBuilder/cached), tap → full-screen viewer.
  - `kind == 'ephemeral_photo'` NOT mine, `ephemeralViewedAt == null`: "🔥 Tap to view once" placeholder card (accent border). On tap: call `markEphemeralViewed` FIRST; if `viewed=true`, fetch `getMediaUrl` and show the photo full-screen ONCE (on close, replace bubble with "Photo expired" state locally).
  - `kind == 'ephemeral_photo'` with `ephemeralViewedAt != null` (or after local view): "Photo expired" muted card.
  - My own ephemeral sends show "View-once photo sent" card (sender can't re-open).
- Tests: model parsing (photo + ephemeral fields incl. WS), service request shapes (sendPhotoMessage with/without ephemeral, markEphemeralViewed, getMediaUrl), and a widget test for the tap-to-view placeholder → expired transition using a fake service.
- `image_picker` is likely already a dep (profile photo upload uses it) — verify, add if missing.

## Task 3: NSFW on-device REAL on Android (Rust bridge end-to-end)
**Files:** `apps/app/rust/src/nsfw.rs`, `apps/app/rust/Cargo.toml` (if needed), `apps/app/android/app/src/main/jniLibs/*` (rebuilt .so), `apps/app/assets/models/` (new model), `apps/app/pubspec.yaml` (asset), `apps/app/lib/src/nsfw/nsfw_service.dart` (new), wiring in photo pick flows (edit_profile + chat attach from Task 2), tests.

1. **Un-gate Android:** remove the `target_os = "android"` from the cfg gates in `nsfw.rs` (keep the WASM gate). tract-onnx is pure Rust and should cross-compile with cargo-ndk (NDK clang is only the linker — that's standard). PROVE it: `cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o android/app/src/main/jniLibs build --release` from `apps/app/rust/` must succeed and refresh the .so files. If tract genuinely fails to cross-compile, STOP and report BLOCKED with the exact error (plan B is the `ort` crate — controller decision).
2. **Real model (ALREADY DOWNLOADED by controller):** `apps/app/assets/models/nsfw.onnx` (17,320,391 bytes, from HuggingFace `Sunxyw/nsfwjs-onnx` `onnx/model_quantized.onnx`, converted with tf2onnx 1.17.0 — a real ONNX protobuf, verified by magic bytes). Register it under `flutter:assets:` in pubspec. **Do NOT trust the repo's config.json (it claims ViT; the tf2onnx header suggests the actual nsfwjs TF graph).** Introspect the graph with tract in a quick Rust test/println (input name+shape+layout, output dims): tf2onnx models are typically **NHWC** (matches the existing Rust preprocessing). If output has 5 logits → nsfwjs classes `[drawings, hentai, neutral, porn, sexy]` → `score = hentai + porn (+ 0.5*sexy)` clamped to [0,1], `is_nsfw = score > 0.7`; if 2 logits → `[normal, nsfw]` → softmax, score = p(nsfw). Document the discovered shape + mapping in a comment. If tract cannot load the quantized model (unsupported quantized ops), report BLOCKED with the exact tract error — do NOT fake it.
3. **Desktop proof test:** a `cargo test` in `apps/app/rust` that loads the bundled model and classifies a tiny embedded/test JPEG (e.g. a generated solid-color or a small neutral test image under `rust/tests/fixtures/`) asserting it returns a score in [0,1] and `is_nsfw == false` for the neutral image. This proves real inference runs.
4. **Dart service:** `lib/src/nsfw/nsfw_service.dart` — at first use, copy the asset model to a temp file (`path_provider`), call `RustLib`'s `loadNsfwModel(path)` once, then `Future<NsfwResult> check(List<int> bytes)` calling `nsfwClassify`. Handle web (kIsWeb → skip check, return safe) and errors (if classify errors, LOG and fail-open with a warning — don't block uploads on engine failure, but surface a debug log).
5. **Wire into upload flows:** in `edit_profile_screen.dart` photo pick and in the chat attach flow (Task 2): after picking bytes, run `NsfwService.check`. If `is_nsfw`, show a dialog "This image appears to violate our content guidelines" and do NOT upload. Otherwise proceed.
6. **Flutter tests:** service unit test with the Rust call faked (inject a function), verifying block-on-nsfw and proceed-on-safe paths. (Real inference is covered by the Rust-side cargo test; don't attempt real inference in `flutter test`.)
7. Regenerate FRB bindings only if the Rust API surface changed (it shouldn't — same two functions).

## Task 4: Deploy + live verification (controller does this, not a subagent)
Rebuild backend image `--no-cache`, scp to new VPS (wildfox@100.74.226.125), `echo 9501 | sudo -S docker load -i` + `compose up -d`, migrate, verify live: send ephemeral flow smoke (register 2 users, conversation, ephemeral send → kind, viewed once → true, twice → false) and `GET /media/get-url` validation (401 unauth / 400 bad kind).
