# Task Report: Albums Feature

## Summary

Implemented full private albums feature (backend + Flutter) following API-first TDD approach.

## Backend

### Files created
- `backend/migrations/0019_albums_extras.sql` — adds `description` and `is_private` columns to `albums`
- `backend/crates/db/src/albums.rs` — all DB queries: list, create, update, delete, get, get_album_photos, add_photos_to_album, remove_photo_from_album, share, unshare, list_shared_albums
- `backend/crates/api/src/albums.rs` — all HTTP handlers: list, create, update, delete, get, add_photos, remove_photo, share, unshare, shared
- `backend/crates/api/tests/albums.rs` — 7 integration tests

### Files modified
- `backend/crates/db/src/lib.rs` — added `pub mod albums;`
- `backend/crates/api/src/lib.rs` — added `mod albums;` + route wiring for 10 album endpoints

### Endpoints
| Method | Path | Handler |
|--------|------|---------|
| GET | /albums | list albums owned by user |
| POST | /albums | create album |
| PUT | /albums/:id | update album |
| DELETE | /albums/:id | delete album |
| GET | /albums/:id | get album with photos |
| POST | /albums/:id/photos | add photos (r2 keys) to album |
| DELETE | /albums/:id/photos/:photo_id | remove photo from album |
| POST | /albums/:id/share | share album with user |
| DELETE | /albums/:id/share/:user_id | unshare album |
| GET | /albums/shared | list albums shared with me |

### DB design
- `add_photos_to_album` — transaction: insert each `r2_key` into `photos` table (RETURNING id), then link via `album_photos`. Returns count of photos added.
- `share_album` — upsert pattern (re-activates if unshared+reshared)
- `unshare_album` — sets `revoked_at` (soft delete)
- `list_shared_albums` — filters by `revoked_at IS NULL AND (expires_at IS NULL OR expires_at > now())`
- Each album list response includes `photo_count` and `cover_photo_url` via LEFT JOIN + subquery

### Tests (7 pass)
- `create_and_list_albums` — create 2 albums, list, verify both present with photo_count=0
- `add_photos_to_album_and_get` — add 2 photos via r2 keys, verify response, remove one, verify
- `share_album_and_recipient_sees_it` — share with user2, user2 sees in /albums/shared
- `unshare_removes_access` — share, verify seen, unshare, verify gone
- `delete_album_returns_204` — create, delete, verify 404 on re-fetch and re-delete
- `update_album_modifies_fields` — update name + is_private, verify only those changed
- `unauthorized_returns_401` — POST and GET without token return 401

## Flutter

### Files created
- `apps/app/lib/src/features/albums_screen.dart` — Albums list screen with create dialog (FAB), loading/error/empty states
- `apps/app/lib/src/features/album_detail_screen.dart` — Album detail with photo GridView, "add photos" button (ImagePicker + MediaService upload flow + R2 presigned PUT), photo preview dialog
- `apps/app/test/src/features/albums_screen_test.dart` — 3 widget tests (list display, empty state, error state)

### Files modified
- `apps/app/pubspec.yaml` — added `image_picker: ^1.1.2`
- `apps/app/lib/main.dart` — added `/albums` and `/albums/:albumId` GoRouter routes
- `apps/app/lib/src/features/home_screen.dart` — added "Albums" navigation button

## Gates
- `cargo build --workspace` — clean (no warnings)
- `cargo test -p api --test albums` — 7/7 pass
- `flutter analyze` — 0 issues
- `flutter test` — 47 passed, 4 skipped (pre-existing), 0 failed

Pre-existing failure: `admin_moderation.rs::list_pending_photos_returns_only_pending` (unrelated to albums)
