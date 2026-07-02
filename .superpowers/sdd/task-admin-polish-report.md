# Admin Panel Polish — Task Report

**Commit:** `cfb2df57`  
**Branch:** `main`  
**Date:** 2026-07-02

---

## T1 — Windows + Android platforms + dart-define

### Platform status
- **Android** (`apps/admin/android/`): folder already scaffolded from a prior `flutter create`. Confirmed build succeeds.
- **Windows** (`apps/admin/windows/`): folder already scaffolded. Windows build also succeeded on this machine (Visual Studio present).

### dart-define
`apps/admin/lib/src/config.dart` now reads the base URL from the `ADMIN_API_URL` dart-define with a default of `https://api.turnend.win`:

```dart
static const String apiUrl = String.fromEnvironment(
  'ADMIN_API_URL',
  defaultValue: 'https://api.turnend.win',
);
```

Override at build time:
```
flutter build apk --dart-define=ADMIN_API_URL=https://staging.api.example.com
```

### Build gates
- `flutter build apk --debug` ✓ — `build/app/outputs/flutter-apk/app-debug.apk`
- `flutter build windows` ✓ — succeeded on this machine

---

## T2 — Professional UI polish

### New file: `lib/src/theme/admin_theme.dart`
Single source of truth for all design tokens:
- **Palette:** `#0F0F0F` canvas, `#1A1A1A` nav/surface, `#1E1E1E` cards, `#2A2A2A` borders
- **Accent:** `#F4C542` (Vibra yellow-gold) — primary buttons, active nav, icons, chips
- **Status colours:** green `#22C55E`, orange `#F97316`, red `#EF4444`, blue `#3B82F6`
- Full `ThemeData` covering cards, nav rail, inputs, buttons, dialogs, snackbars, switch, list tiles, popup menus, dividers

### `admin_layout.dart` — shell redesign
- **Top bar (52 px):** section title (left) + admin email pill + logout icon (right)
- **Vibra branding** in the nav rail leading area: icon badge + "VIBRA / Admin Console" wordmark when extended
- **NavigationRail** styled with accent indicator, proper selected/unselected icon themes
- `AuthState` gained an `adminEmail` field populated at login, shown in the top bar

### `dashboard_screen.dart` — metric cards
- Responsive 1/2/3-column grid, cards at `childAspectRatio: 2.6`
- Each card: coloured icon badge (accent-tinted background), large bold value, ALL-CAPS label with letter-spacing
- Refresh button, error banner with red border, number formatting (K/M suffix)

### `user_list_screen.dart` — data table
- Custom row layout: avatar initials → email (truncated) → status chip → role → date → chevron
- Sticky header row with grey column headers (`EMAIL / STATUS / ROLE / CREATED`)
- Hover highlight via `MouseRegion` + `GestureDetector`
- Footer row showing `X of Y users`

### `reports_screen.dart` — moderation queue
- Per-report cards with: reason (bold), target truncated, timestamp
- **Inline action row:** `[Dismiss]` `[Warn]` `[Ban]` `[Details →]` — no mandatory dialog for quick actions
- Status chip (`Open` / `Actioned` / `Dismissed`) with coloured border + background
- Empty state with green check icon; open-count badge in header

### `login_screen.dart` + `totp_screen.dart` — branded auth
- Centred card on dark canvas with `#F4C542` branded icon badge
- Compact error banner (icon + text, red border)
- Yellow `FilledButton` with loading indicator; 'Continue' / 'Verify' labels

### `flags_screen.dart` — feature flags
- Card-per-flag: enabled dot indicator, monospace key, description, toggle, delete icon
- Delete confirmation dialog with red FilledButton

### `plans_screen.dart` — subscription plans
- Card-per-plan with tier badge, monospace code, `ExpansionTile` feature rows
- Feature rows: check/close icon (green/red), monospace feature name, limit value

### `user_detail_screen.dart` — user profile
- Profile card with avatar, email, display name, role/status/verified chips, creation date
- Action buttons: Activate (green), Suspend (orange), Ban (red) — suspend/ban open reason dialog

---

## T3 — Verification

| Gate | Result |
|------|--------|
| `flutter analyze` | **0 issues** |
| `flutter test` | **5/5 pass** |
| `flutter build apk --debug` | **✓ Built** |
| `flutter build windows` | **✓ Built** |

### Test fix
`test/src/features/login/login_screen_test.dart` checked for `find.text('Login')` — updated to `find.text('Continue')` to match the refactored button label.

---

## Constraints honoured
- Only `apps/admin` was modified; `apps/app`, `apps/marketing`, and `backend` untouched
- No secrets in code; API URL is a dart-define default pointing to the live tunnel
- All existing API calls (`/admin/analytics/overview`, `/admin/users`, `/admin/reports`, `/admin/flags`, `/admin/plans`, etc.) remain intact
- No new git remotes added; pushed only to `origin main`
