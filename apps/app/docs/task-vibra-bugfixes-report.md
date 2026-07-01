# Vibra Android bugfixes + audit — report

Three reported Android bugs fixed (TDD, one commit per fix), remaining
stubs/simulations in `apps/app/lib/` catalogued. All gates green:
`flutter analyze` 0 issues, `flutter test` 155/155 passing,
`flutter build apk --debug` succeeds.

---

## Bug 1 — Photo upload returns HTTP 400

### Root cause

`EditProfileScreen._pickAndUploadPhoto` called
`MediaService.getUploadUrl(kind: 'profile_photo')`, but the backend's
`POST /media/upload-url` only accepts `kind ∈ {profile, album, verification}`.
The value `"profile_photo"` was rejected with HTTP 400.

The MediaService code itself was already correct: it sends a JSON
body `{kind, ext?}` and uploads raw bytes with `Content-Type: image/jpeg`
to the presigned R2 URL. The bug was purely in the **call site**.

### Files changed

- `apps/app/lib/src/features/edit_profile_screen.dart:222`
  - `kind: 'profile_photo'` → `kind: 'profile'`
  - Added comment explaining the allowed values and why the value was changed.

### Tests added

- `apps/app/test/src/media/media_service_test.dart`
  - **New test**: `profile photo upload request shape: kind=profile, POST /media/upload-url`
    — asserts the request body uses `kind='profile'` from the allowed set,
    and the path is `POST /media/upload-url`. This is the regression test
    for the bug: the call site must produce this exact body shape.
  - **Updated tests**: replaced the legacy `'avatar'` and `'photo'` kind
    values in 3 existing tests with valid kinds (`'profile'`, `'album'`)
    so they don't encode the wrong invariant.

### Commit

`8503875a fix(app): photo upload: use valid kind=profile + raw bytes for R2 PUT`

---

## Bug 2 — GoRouter `goroute /` doesn't exist on deep link

### Root cause

When the app is opened from a deep link to a path that is not in the
registered route table (an old link, a typo, a route we removed),
GoRouter runs the `redirect` callback first. The old redirect only
handled auth-state checks; it returned `null` for any path, and the
framework later threw `goroute /<path> doesn't exist` on the first
frame. Additionally, the Android `AndroidManifest.xml` only registered
`https://` App Links — there was no intent-filter for the `vibra://`
custom scheme, so even registered custom-scheme deep links could not
reach the activity.

### Files changed

- `apps/app/lib/main.dart`
  - Added `_knownTopLevelPaths` set and `_topLevelPath()` helper.
  - Extracted the redirect body into a top-level `appRedirect()` function
    so widget tests can drive the logic without spinning up Firebase +
    the full router.
  - Renamed `_router` to `appRouter` (non-private) for the same reason.
  - In the redirect: if the incoming top-level path is not in the known
    set, bounce to `/login` (unauthed) or `/cascade` (authed/loading)
    before the auth-state checks.
- `apps/app/android/app/src/main/AndroidManifest.xml`
  - Added a second intent-filter for the `vibra://` custom scheme,
    sibling to the existing `https://` App Links filter.

### Tests added

- `apps/app/test/router_deeplink_test.dart` (new file, 11 tests)
  - 10 unit tests on `appRedirect()` covering: unmatched path +
    unauthed → `/login`; unmatched path + authed → `/cascade`; unmatched
    + loading → `/cascade`; unmatched + emailUnverified → `/cascade`;
    known path + each auth state — all the original auth-guards still
    behave as before.
  - 1 widget test: pumps a GoRouter using `appRedirect()` as the
    redirect callback with 5 different deep-link URLs (3 valid, 2
    invalid) and asserts `tester.takeException()` is `null` on each.

### Commit

`e2bfe401 fix(app): go-router handles unmatched routes (deep-link fallback)`

---

## Bug 3 — Chat screen crashes with `_AssertionError` (binding.dart:509)

### Root cause

`_ChatScreenState` has three async paths that call `setState()` (and
the WS listener that also calls `setState()`) without checking
`mounted` after the await:

1. `_loadMessages` — after `await chatService.getMessages(...)` in both
   the success and catch arms.
2. `_sendMessage` — and indirectly via the optimistic `_messages.add()`.
3. WebSocket `messageStream.listen` — fires whenever the service pushes
   a message, even if the widget has been disposed.

A secondary bug surfaced while writing the test: `_loadMessages` assigns
`messages` (from the service) directly to `_messages`, but the service
may return a `const`/unmodifiable list. Subsequent `_messages.add(...)`
in `_sendMessage` and the WS listener then throws
`UnsupportedError: Cannot add to an unmodifiable list`. The brief's
binding.dart:509 assertion is exactly the kind of failure the unmounted
setState produces; the unmodifiable list was a separate latent bug.

### Files changed

- `apps/app/lib/src/features/chat_screen.dart`
  - WS listener: `if (!mounted) return;` at the top.
  - `_loadMessages` success/catch: `if (!mounted) return;` after the
    await, before the `setState`.
  - `_scrollToBottom`: `if (!mounted) return;` before scheduling, and
    again inside the `addPostFrameCallback` (the widget may have been
    disposed between the schedule and the actual frame).
  - `_loadMessages`: copy the service list via `List<Message>.from(messages)`
    before assigning to `_messages`, so the list is mutable when
    `_sendMessage` and the WS listener append to it.

### Tests added

- `apps/app/test/src/features/chat_screen_dispose_test.dart` (new file, 3 tests)
  - Uses a `_FakeChatService extends ChatService` whose async methods are
    gated by `Completer`s. The test pumps the real `ChatScreen`,
    disposes the widget tree mid-flight by replacing it with a
    `SizedBox.shrink()`, then resolves the pending future and asserts
    `tester.takeException()` is `null`.
  - Covers all three regression paths:
    1. `getMessages` in flight + dispose + resolve.
    2. `sendMessage` in flight + dispose + resolve.
    3. WebSocket message arriving after dispose (via `injectMessage`).

### Commit

`1a704af3 fix(app): chat: guard setState/messenger calls with mounted check after async gaps`

---

## Audit: remaining stubs / simulations in `apps/app/lib/`

Run from `apps/app/`:

```
grep -rE "TODO|FIXME|stub|STUB|CHANGE_ME|unimplemented|coming soon|placeholder" lib/
grep -rE "class Fake|class Mock|throw new UnimplementedError" lib/
```

### Findings

| # | File:Line | What | Severity | Recommendation |
|---|-----------|------|----------|----------------|
| 1 | `lib/src/ads/ad_provider.dart:79` | `/// Returns the real AdMob provider on mobile, stub on web.` and `StubAdProvider` (line 67) — stub provider on web / for entitled users that returns `SizedBox.shrink()`. | **Cosmetic** | Intentional: the web has no AdMob SDK, paying users get no ads. Keep — but add a `// intentional` annotation so future greps don't flag it. |
| 2 | `lib/src/features/cascade_screen.dart:5` | `/// Replaces the old NearbyScreen. Each card shows a photo placeholder,` — doc comment uses the word "placeholder" but is documenting a real photo-thumbnail widget, not a stub. | **Cosmetic** | Rephrase the doc comment to "photo thumbnail" so the grep doesn't false-positive. |
| 3 | `lib/src/rust/frb_generated.dart:42` / `:46` | `initMock({required RustLibApi api})` and `initMockImpl(api: api)` — generated by flutter_rust_bridge to allow injecting a mock Rust API for tests. | **Cosmetic** | Generated file; safe to ignore. |
| 4 | `lib/src/features/chat_screen.dart:219-222` | `String? _currentUserId() { return null; }` with comment "In a real app, extract user ID from token or store it in auth state". Because `isMe` is `message.senderId == _currentUserId()`, every message bubble is rendered on the left, including messages the current user sent. | **Critical (cosmetic UX, not crash)** | Decode the user id from the JWT access token (it's signed, payload is base64url), or add a `userId` field to `AuthState` that the auth flow populates. Then the `isMe` bubble alignment works. |
| 5 | `lib/src/features/home_screen.dart` (whole file) | `// DEPRECATED: HomeScreen has been replaced by NearbyScreen... This file is kept for test compatibility.` — 3 lines, no class. | **Cosmetic** | Either delete (and update any tests that import it) or keep with the deprecation banner. Search for `home_screen.dart` imports to confirm no live reference. |
| 6 | `lib/firebase_options.dart:3-5` (3 sites) | `throw UnsupportedError(...)` for "no Firebase options for this platform" — by design: FlutterFire is initialized at app start and these are only called in unsupported builds. | **Cosmetic** | Keep — correct behaviour. |
| 7 | `lib/src/features/edit_profile_screen.dart:201` | `// Best-effort — leave fields null if endpoint fails.` — swallows a backend error silently when loading the health fields for the form. | **Cosmetic** | The user sees the form with no error message and no health data. Consider a SnackBar or a one-shot retry; not blocking. |
| 8 | `lib/src/features/chat_screen.dart:127` | `// Message will be replaced when WS broadcasts it back` — `sendMessage` catches all errors and swallows them, optimistically assuming the WS broadcast will deliver the message. | **Cosmetic** | A user typing a message and being offline will see it briefly appear then disappear with no error. Show a "Failed to send — retry" affordance instead. |

### Total

8 findings. **1 critical-UX** (#4: `isMe` always false), **7 cosmetic**.

None block production deployment, but #4 is the kind of thing a real
user notices on the first message they send and it should be a small
follow-up task. The other 7 are either intentional (ads web stub, FRB
mock init, Firebase fallback throws) or low-priority polish.

### Recommendation for follow-up work

1. **High**: #4 — wire `userId` into `AuthState` and decode the JWT
   once after login so `isMe` works. Probably a 30-line change plus a
   test in `auth_notifier_test.dart`.
2. **Low**: #8 — surface send failures in the chat UI.
3. **Low**: #7 — show a SnackBar when the health section fails to load.
4. **Low (chore)**: rephrase #2 doc comment so the audit grep doesn't
   false-positive next time.

---

## Final commit

`55c753ac chore(app): gate-passing lint cleanups (analyze = 0 issues)`

The final commit cleans up the 3 `info`-level lints that surfaced
during analyze, plus restructures the chat dispose test to use
`extends ChatService` so the analyzer is happy. No behaviour change;
the diff is `+37 / -77` lines.

---

## Summary

| | Bug 1 | Bug 2 | Bug 3 |
|---|---|---|---|
| Root cause | Wrong `kind` value at call site | No fallback for unmatched route | `setState()` / messenger after dispose |
| Files changed | 1 | 2 (+1 test) | 1 (+1 test) |
| Tests added | 1 new + 3 updated | 11 | 3 |
| Commit | `8503875a` | `e2bfe401` | `1a704af3` |

**Gates**: `flutter analyze` 0 issues · `flutter test` 155/155 green · `flutter build apk --debug` succeeds.
