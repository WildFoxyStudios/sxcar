# Grindr Parity Audit — 2026-07-05

**Method:** inventoried the actual codebase (27 Flutter screens in `apps/app/lib/src/features/`, 24 feature modules in `lib/src/`, 93 backend endpoints across auth/grid/profile/tap/favorite/block/chat/album/tier2/tier3/billing/media/admin) and mapped it against Grindr's real product feature set. Status: ✅ done · ⚠️ partial · ❌ missing.

**Headline:** the app has **strong parity on the core social-discovery loop** (grid, profiles, chat, taps, favorites, albums, Right Now, Boost/Roam, Viewed Me, privacy/safety). The **real gaps are in monetization plumbing, push, and rich-chat/communication features** (voice, reactions, calls, translate) plus a few advanced filters and newer Grindr surfaces (Circles, Stories).

---

## 1. Discovery / Grid (Cascade)

| Feature | Status | Evidence / Notes |
|---|---|---|
| Nearby users grid (cascade) | ✅ | `cascade_screen.dart` + `GET /grid/nearby` (PostGIS distance sort) |
| Distance display (metric/imperial) | ✅ | `utils/distance_format.dart`, units-aware |
| Online/last-seen dot | ✅ | `/heartbeat`, `/users/:id/status`, `presence/` |
| Tap-to-open profile | ✅ | `profile_detail_screen.dart` |
| NUEVO badge (<7 days) | ✅ | `NUEVOBadge`, `idx_users_created_at` |
| Filter: Favorites / Online / Right Now | ✅ | server-side `favorites_only`/`online_only`/`right_now` (deployed 2026-07-05) |
| Filter: Age / Tribes / Looking-for / Body type / Text search | ✅ | `NearbyQuery` (`min_age`,`max_age`,`tribe`,`looking_for`,`body_type`,`q`) |
| Filter: Position | ❌ | `position` is on the profile but not a grid filter |
| Filter: "Haven't chatted" / "Photos only" / "Face photos" / "My Type" | ❌ | Grindr XTRA filters not implemented |
| "Fresh"/new-users **filter** | ⚠️ | exists as a *badge*, not a filter toggle |

## 2. Explore / Travel

| Feature | Status | Evidence / Notes |
|---|---|---|
| Explore grid (separate from cascade) | ✅ | `grid_search_screen.dart` |
| Roam — appear in another location | ✅ | `places/roam_service.dart`, tier2 `GET/PUT /me/location`, saved places |
| Free-text city/place search (geocoding) | ⚠️ | Roam is backed by **saved places**, not confirmed arbitrary-city geocoding search like Grindr's map-tap |

## 3. Profile

| Feature | Status | Evidence / Notes |
|---|---|---|
| Photos (main + gallery) | ✅ | `media/`, R2 presigned upload |
| Name, age, distance, "About me" | ✅ | `profile_screen.dart`, `profile_detail_screen.dart` |
| Stats: height, weight, body type, position | ✅ | profile details + selector sheets |
| Tribes | ✅ | `ChipMultiSelect`, edit_profile |
| Relationship status, pronouns | ✅ | E3 (migration 0031) |
| Looking-for, Meet-at, Tags/interests | ✅ | edit_profile sections |
| Health: HIV status, last-tested, PrEP | ✅ | `/profile/health`, health section |
| Vaccines, Trips, Practices | ✅ | edit_profile sub-screens |
| Social links | ✅ | `showSocialLinks` privacy flag |
| Profile verification (photo) | ✅ | `POST /profile/verify`, `/profile/verify/status` |
| Per-field privacy (hide age/distance/…) | ✅ | migration 0032 `show_*` flags |

## 4. Chat / Messaging

| Feature | Status | Evidence / Notes |
|---|---|---|
| 1:1 real-time chat | ✅ | `chat_screen.dart`, `GET /ws/chat` (WebSocket), Redis pub/sub |
| Text messages | ✅ | kind `text` |
| Photo messages | ✅ | kind `photo` |
| Ephemeral "view once" photos | ✅ | kind `ephemeral_photo` + `/viewed` |
| Album shares in chat | ✅ | kind `album` |
| Read receipts | ✅ | `POST /chat/conversations/:id/read` |
| Unread badges / inbox (Buzón) | ✅ | `chat_list_screen.dart` |
| Saved phrases (canned replies) | ✅ | tier2 `/phrases` CRUD + reorder |
| **Voice / audio messages** | ❌ | no `audioplayers`/`record` dep |
| **Message reactions** | ❌ | not implemented |
| **Typing indicator** | ❌ | not implemented |
| **Unsend / delete message** | ❌ | not implemented |
| **Translate message** | ❌ | not implemented |
| **Gaymoji / stickers** | ❌ | not implemented |
| **Voice / video calls** | ❌ | no WebRTC/Agora |

## 5. Interactions

| Feature | Status | Evidence / Notes |
|---|---|---|
| Taps (send + variants) | ✅ | `POST /taps`, `/taps/received`, `/taps/sent`, `/taps/count` |
| Favorites (+ list, + filter) | ✅ | `/favorites`, favorites_only filter, `interest_screen.dart` |
| Blocks (+ list) | ✅ | `/blocks`, `blocks_list_screen.dart` |
| Viewed Me (who viewed you) | ✅ | `/profile/views`, `/profile/views/count` |
| Report user | ✅ | `POST /reports` |

## 6. Private Albums

| Feature | Status | Evidence / Notes |
|---|---|---|
| Create private album, add/remove photos | ✅ | `/albums`, `/albums/:id/photos` |
| Share album with a user / revoke | ✅ | `/albums/:id/share`, `.../share/:user_id` DELETE |
| "Shared with me" | ✅ | `/albums/shared`, `albums_screen.dart` |

## 7. Right Now

| Feature | Status | Evidence / Notes |
|---|---|---|
| Post a "Right Now" intent | ✅ | tier3 `POST /right-now`, `right_now_screen.dart` |
| Right Now feed | ✅ | Explore integration |
| Expiry / delete | ✅ | `DELETE /right-now/:id` |

## 8. Boost / Visibility

| Feature | Status | Evidence / Notes |
|---|---|---|
| Boost (temporary visibility bump) | ✅ | tier2 `POST /boost`, `/boost/active`, `boost/` |
| Roam (location override) | ✅ | see §2 |

## 9. Monetization

| Feature | Status | Evidence / Notes |
|---|---|---|
| Tier model (Free / Plus / Unlimited) | ✅ | `billing/tier_features.dart`, migration 0029 |
| Store UI (Tienda) + upsell cards | ✅ | `tienda_screen.dart`, drawer upsells |
| Active-subscription state | ✅ | `GET /billing/me`, `/billing/plans` |
| Feature gating (incognito, viewed-me, …) | ✅ | `tier_features.dart` |
| **Real payments (RevenueCat / IAP / store)** | ❌ | only `POST /billing/simulate-purchase` (`source='simulated'`); no `purchases_flutter`/`in_app_purchase` |
| Ads for free tier | ⚠️ | `ads/ad_provider.dart` via AdMob but **Google TEST unit IDs** — needs real ad units |

## 10. Safety / Privacy

| Feature | Status | Evidence / Notes |
|---|---|---|
| Discreet app icon | ✅ | `discreet_icon_picker_screen.dart` |
| PIN / app lock | ✅ | `pin_screen.dart` |
| Incognito / stealth browsing | ✅ | `incognito_mode` flag + tier gate |
| Screenshot alerts | ✅ | tier3 `POST /screenshots` |
| Privacy preferences | ✅ | `GET /privacy/preferences`, `show_*` flags |
| Multi-device session management | ✅ | tier3 `/me/sessions` (list/revoke) |
| Idle reminders | ✅ | tier3 `/me/idle-reminder` |
| NSFW blur (on-device) | ✅ | `nsfw/` tract-onnx, real on Android |

## 11. Notifications

| Feature | Status | Evidence / Notes |
|---|---|---|
| Notification preferences (backend) | ✅ | `GET /notifications/preferences` |
| Device token registration (backend) | ✅ | `POST /notifications/register` |
| FCM server SDK | ✅ | Firebase admin SDK (server-side) |
| **Client push (FCM) integration** | ❌ | no `firebase_messaging` in pubspec (only `firebase_core`+`firebase_auth`) — no token acquired on device, so push is not end-to-end |

## 12. Account / Auth

| Feature | Status | Evidence / Notes |
|---|---|---|
| Email + password | ✅ | `/auth/register`, `/auth/login` (argon2id) |
| Phone verification | ✅ | `/auth/send-phone-code`, `/auth/verify-phone` |
| OAuth (Google, …) | ✅ | `/auth/oauth/:provider` |
| Email verification, password reset | ✅ | `/auth/verify-email`, `/auth/password/reset` |
| Age gate (18+) | ✅ | register client + server |
| JWT + rotating refresh tokens | ✅ | `crates/auth` |

## 13. Moderation / Trust & Safety (mostly beyond Grindr's user app)

| Feature | Status | Evidence / Notes |
|---|---|---|
| Full admin panel | ✅ | 24 `/admin/*` endpoints (users, audit, reports, CSAM, GDPR, flags, config, plans, countries, experiments, i18n, cms, legal, campaigns, abuse rules, api-keys, webhooks) |
| CSAM hash-match | ✅ | `/admin/csam` |
| GDPR data export | ✅ | `/admin/gdpr`, `/admin/legal/export/:user_id` |

## 14. Grindr surfaces NOT present

| Feature | Status | Notes |
|---|---|---|
| **Circles** (group chats / communities) | ❌ | newer Grindr feature, not built |
| **Stories / Spotlight** | ❌ | not built |
| **Grindr Web** (desktop web app) | ❌ | app is Flutter mobile; the Next.js site is marketing only |
| Albums "unlocked count" / advanced album analytics | ❌ | basic album share only |

---

## Bottom line

**Core Grindr loop: ~95% there.** Discovery, profiles, chat basics, taps/favorites/blocks, albums, Right Now, Boost/Roam, Viewed Me, privacy/safety, auth, and moderation are implemented and (backend) deployed.

**The parity gaps that actually matter, ranked:**

1. **Real payments** — monetization is fully built *except* the payment rail (simulate-purchase only). Highest-value gap for a commercial launch. Needs RevenueCat/StoreKit/Play Billing wired to the existing tier model.
2. **Client push notifications** — backend + Firebase server SDK ready, but the Flutter app lacks `firebase_messaging`, so no device gets a token. Without this, no re-engagement notifications.
3. **Rich chat** — voice messages, reactions, typing indicator, unsend, translate. Grindr users expect several of these.
4. **Ads with real unit IDs** — AdMob is wired but on Google test IDs (no revenue yet).
5. **Advanced grid filters** — Haven't-chatted, Photos-only, Position, My-Type.
6. **Newer surfaces** — Circles, Stories (arguably out of scope for a v1 clone).
7. **Explore free-text city search** — Roam covers location override via saved places; arbitrary map-tap/city geocoding may be partial.

**Honest verdict:** it is **not** literally "100% of Grindr the product," but it **is** at 100% of the defined `2026-07-04-grindr-100-parity.md` plan scope, which covered the discovery/profile/chat/monetization-UI surface. The remaining gaps are mostly **integration rails** (payments, push, ads IDs) and **communication richness** (voice/reactions/calls) rather than missing core screens.
