# Graph Report - apps/app/lib  (2026-07-06)

## Corpus Check
- 85 files · ~65,957 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 989 nodes · 1254 edges · 60 communities (55 shown, 5 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 33|Community 33]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 48|Community 48]]
- [[_COMMUNITY_Community 49|Community 49]]
- [[_COMMUNITY_Community 50|Community 50]]
- [[_COMMUNITY_Community 51|Community 51]]
- [[_COMMUNITY_Community 52|Community 52]]
- [[_COMMUNITY_Community 53|Community 53]]
- [[_COMMUNITY_Community 54|Community 54]]
- [[_COMMUNITY_Community 55|Community 55]]
- [[_COMMUNITY_Community 56|Community 56]]
- [[_COMMUNITY_Community 57|Community 57]]

## God Nodes (most connected - your core abstractions)
1. `package:flutter_riverpod/flutter_riverpod.dart` - 58 edges
2. `../../main.dart` - 51 edges
3. `../../l10n/gen/app_localizations.dart` - 44 edges
4. `package:flutter/material.dart` - 38 edges
5. `../auth/auth_provider.dart` - 37 edges
6. `package:dio/dio.dart` - 34 edges
7. `../theme/app_theme.dart` - 21 edges
8. `package:go_router/go_router.dart` - 15 edges
9. `dart:async` - 9 edges
10. `../theme/widgets.dart` - 9 edges

## Surprising Connections (you probably didn't know these)
- `firebase_options.dart` --defines--> `DefaultFirebaseOptions`  [EXTRACTED]
  main.dart → firebase_options.dart
- `firebase_options.dart` --defines--> `UnsupportedError`  [EXTRACTED]
  main.dart → firebase_options.dart
- `../../main.dart` --defines--> `MainShell`  [EXTRACTED]
  src/features/cascade_screen.dart → main.dart
- `../../main.dart` --defines--> `_BuzonTabIcon`  [EXTRACTED]
  src/features/cascade_screen.dart → main.dart
- `../../main.dart` --defines--> `VibraApp`  [EXTRACTED]
  src/features/cascade_screen.dart → main.dart

## Communities (60 total, 5 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.04
Nodes (51): Align, _bubbleMargin, build, _buildEmptyState, _buildEphemeralBubble, _buildEphemeralExpiredCard, _buildEphemeralSentCard, _buildErrorState (+43 more)

### Community 1 - "Community 1"
Cohesion: 0.04
Nodes (50): build, _buildError, _buildForm, _buildLabel, _buildPhotoSection, _buildPrivacyRow, _buildSaveBar, Center (+42 more)

### Community 2 - "Community 2"
Cohesion: 0.04
Nodes (47): _avatarInitial, build, _buildChipsRow, _buildEmptyState, _buildErrorState, _buildFabs, _buildLocationBanner, _buildPlaceholder (+39 more)

### Community 3 - "Community 3"
Cohesion: 0.04
Nodes (45): _applyRoam, _applySearch, _backToMyLocation, build, _buildCitySearchBar, _buildGrid, _buildLocationIndicator, _buildMiniMap (+37 more)

### Community 4 - "Community 4"
Cohesion: 0.05
Nodes (38): app_theme.dart, AlbumCarousel, _AlbumPlaceholder, AlbumUpdateBanner, AlbumUpdatesEmptyState, Align, build, Center (+30 more)

### Community 5 - "Community 5"
Cohesion: 0.05
Nodes (38): _ageFromBirthdate, build, _buildExpectativasSection, _buildNearbyPlaceholder, _buildPhotoPlaceholder, _buildSaludSection, _buildSocialSection, _buildStatsSection (+30 more)

### Community 6 - "Community 6"
Cohesion: 0.06
Nodes (33): build, Center, CirclesScreen, _CirclesScreenState, _GroupTile, initState, InkWell, _refresh (+25 more)

### Community 7 - "Community 7"
Cohesion: 0.06
Nodes (31): _ActionButton, build, _buildActiveScreen, _buildEndedScreen, _buildIncomingScreen, CallScreen, _CallScreenState, dispose (+23 more)

### Community 8 - "Community 8"
Cohesion: 0.07
Nodes (26): api_client.dart, auth_service.dart, createAuthClient, AuthNotifier, AuthService, AuthState, build, copyWith (+18 more)

### Community 9 - "Community 9"
Cohesion: 0.08
Nodes (26): ../auth/google_sign_in_service.dart, ../auth/models.dart, build, dispose, Expanded, LoginScreen, _LoginScreenState, Scaffold (+18 more)

### Community 10 - "Community 10"
Cohesion: 0.07
Nodes (27): _BoostBadge, _BoostButton, _BoostButtonState, build, _buildBody, _buildChip, _buildStatsChips, _buildTribesChips (+19 more)

### Community 11 - "Community 11"
Cohesion: 0.07
Nodes (27): _advanceToNext, build, Center, dispose, Duration, Expanded, _getStoryDuration, _goToNextGroup (+19 more)

### Community 12 - "Community 12"
Cohesion: 0.07
Nodes (26): AlbumCarousel, _AlbumsTab, AlbumUpdatesEmptyState, _BandejaTab, _BandejaTabState, _BoostFab, build, Center (+18 more)

### Community 13 - "Community 13"
Cohesion: 0.07
Nodes (24): AlbumDetailScreen, _AlbumDetailScreenState, AlbumPhoto, build, _buildBody, Center, Container, _contentType (+16 more)

### Community 14 - "Community 14"
Cohesion: 0.09
Nodes (22): app_localizations.dart, ahorra, albumesActualizadosPlural, AppLocalizationsEn, editProfileCountSelected, editProfileCountTrips, memberCount, precioContinuar (+14 more)

### Community 15 - "Community 15"
Cohesion: 0.09
Nodes (18): SecureTokenStorage, TokenStorage, RevenueCatService, configure, RevenueCatService, build, PresenceModeNotifier, build (+10 more)

### Community 16 - "Community 16"
Cohesion: 0.09
Nodes (22): ../albums/shared_albums_provider.dart, Album, AlbumCarousel, _AlbumPlaceholder, AlbumsScreen, _AlbumsScreenState, _AlbumTile, build (+14 more)

### Community 17 - "Community 17"
Cohesion: 0.09
Nodes (22): app_localizations_en.dart, app_localizations_es.dart, ahorra, albumesActualizadosPlural, AppLocalizations, _AppLocalizationsDelegate, AppLocalizationsEn, AppLocalizationsEs (+14 more)

### Community 18 - "Community 18"
Cohesion: 0.1
Nodes (19): _BoostRow, _BoostRowState, build, ClipRRect, Container, Divider, Drawer, _DrawerListTile (+11 more)

### Community 19 - "Community 19"
Cohesion: 0.1
Nodes (19): build, _buildBody, _buildEditForm, _buildStatRow, _buildTextField, _buildView, Center, dispose (+11 more)

### Community 20 - "Community 20"
Cohesion: 0.11
Nodes (18): ../boost/boost_service.dart, build, Center, dispose, _hasEntitlement, Icon, initState, InterestScreen (+10 more)

### Community 21 - "Community 21"
Cohesion: 0.11
Nodes (17): ../billing/billing_providers.dart, ../billing/models.dart, ../billing/revenuecat_providers.dart, build, _buildBody, Center, _ErrorRetry, Exception (+9 more)

### Community 22 - "Community 22"
Cohesion: 0.12
Nodes (15): build, _buildCaptureUI, _buildPreviewUI, _CaptureButton, Center, CreateStoryScreen, _CreateStoryScreenState, dispose (+7 more)

### Community 23 - "Community 23"
Cohesion: 0.12
Nodes (15): AddTripScreen, _AddTripScreenState, build, dispose, initState, ListTile, _remove, SafeArea (+7 more)

### Community 24 - "Community 24"
Cohesion: 0.12
Nodes (15): build, Center, Column, Container, Icon, Padding, RefreshIndicator, _RightNowCard (+7 more)

### Community 25 - "Community 25"
Cohesion: 0.13
Nodes (14): build, _bump, Divider, initState, InkWell, _localizedTitle, _MultiSelectSheet, _MultiSelectSheetState (+6 more)

### Community 26 - "Community 26"
Cohesion: 0.14
Nodes (13): build, dispose, Divider, initState, Padding, Scaffold, _scrollTo, _sectionHeader (+5 more)

### Community 27 - "Community 27"
Cohesion: 0.14
Nodes (13): build, Center, Dismissible, _EmptyView, _ErrorView, Icon, _PhrasesList, PhrasesScreen (+5 more)

### Community 28 - "Community 28"
Cohesion: 0.15
Nodes (13): appRedirect, Badge, build, _BuzonTabIcon, didChangeAppLifecycleState, dispose, initState, MainShell (+5 more)

### Community 29 - "Community 29"
Cohesion: 0.15
Nodes (12): build, Center, Icon, ListTile, RefreshIndicator, Scaffold, SessionsScreen, _shortDate (+4 more)

### Community 30 - "Community 30"
Cohesion: 0.15
Nodes (12): build, copyWith, _equal, _humanizeError, _listEq, loadFrom, ProfileEditNotifier, ProfileEditState (+4 more)

### Community 31 - "Community 31"
Cohesion: 0.18
Nodes (10): BlocksListScreen, _BlocksListScreenState, build, _buildBody, Center, Container, initState, Scaffold (+2 more)

### Community 32 - "Community 32"
Cohesion: 0.18
Nodes (10): build, DiscreetIconPickerScreen, _DiscreetIconPickerScreenState, Icon, _IconOption, initState, InkWell, Scaffold (+2 more)

### Community 33 - "Community 33"
Cohesion: 0.18
Nodes (7): billing_service.dart, BillingService, BillingService, Place, PlacesService, Tier3SettingsService, package:dio/dio.dart

### Community 34 - "Community 34"
Cohesion: 0.2
Nodes (9): BorderSide, build, dispose, PinScreen, _PinScreenState, Scaffold, SizedBox, SnackBar (+1 more)

### Community 35 - "Community 35"
Cohesion: 0.22
Nodes (6): GeocodingService, ReportService, TapsCount, TapsCountService, package:flutter_riverpod/flutter_riverpod.dart, package:geocoding/geocoding.dart

### Community 36 - "Community 36"
Cohesion: 0.22
Nodes (6): ../auth/auth_provider.dart, SharedAlbum, SharedAlbumsService, Boost, BoostService, UnreadCountService

### Community 37 - "Community 37"
Cohesion: 0.25
Nodes (7): DefaultFirebaseOptions, UnsupportedError, formatDistance, _trimTrailingZero, firebase_options.dart, package:firebase_core/firebase_core.dart, package:flutter/foundation.dart

### Community 38 - "Community 38"
Cohesion: 0.25
Nodes (7): AdMobAdProvider, AdProvider, createAdProvider, createNativeAd, SizedBox, StubAdProvider, package:google_mobile_ads/google_mobile_ads.dart

### Community 39 - "Community 39"
Cohesion: 0.25
Nodes (7): build, initState, PracticesScreen, _PracticesScreenState, Scaffold, _update, package:app/src/theme/widgets.dart

### Community 40 - "Community 40"
Cohesion: 0.25
Nodes (7): build, initState, Scaffold, _update, VaccinesScreen, _VaccinesScreenState, package:app/l10n/gen/app_localizations.dart

### Community 41 - "Community 41"
Cohesion: 0.25
Nodes (7): build, Container, Scaffold, SecurityScreen, SizedBox, _tipCard, ../theme/app_theme.dart

### Community 42 - "Community 42"
Cohesion: 0.29
Nodes (6): Color, dark, TextStyle, VibraTheme, package:flutter/material.dart, package:google_fonts/google_fonts.dart

### Community 43 - "Community 43"
Cohesion: 0.33
Nodes (5): _ensureInitialized, NsfwResult, NsfwService, override, package:nsfw_detector_flutter/nsfw_detector_flutter.dart

### Community 44 - "Community 44"
Cohesion: 0.33
Nodes (5): AuthException, LoginData, RegisterData, TokenPair, toString

### Community 45 - "Community 45"
Cohesion: 0.33
Nodes (5): GoogleSignInResult, GoogleSignInService, initialize, package:firebase_auth/firebase_auth.dart, package:google_sign_in/google_sign_in.dart

### Community 46 - "Community 46"
Cohesion: 0.33
Nodes (5): _doGetCurrentPosition, _doGetLastKnownPosition, LocationService, _requestPermission, package:geolocator/geolocator.dart

### Community 47 - "Community 47"
Cohesion: 0.4
Nodes (4): Conversation, copyWith, Message, MessageReaction

### Community 48 - "Community 48"
Cohesion: 0.4
Nodes (4): PushService, _registerToken, dart:io, package:firebase_messaging/firebase_messaging.dart

### Community 49 - "Community 49"
Cohesion: 0.4
Nodes (4): formatLastSeen, PresenceService, UserStatus, presence_mode_provider.dart

### Community 50 - "Community 50"
Cohesion: 0.5
Nodes (3): Plan, PlanPrice, Subscription

### Community 51 - "Community 51"
Cohesion: 0.5
Nodes (3): RoamLocation, RoamService, set

### Community 52 - "Community 52"
Cohesion: 0.5
Nodes (3): ProfileViewer, ViewedMeCountService, ViewedMeService

## Knowledge Gaps
- **856 isolated node(s):** `DefaultFirebaseOptions`, `UnsupportedError`, `MainShell`, `_BuzonTabIcon`, `VibraApp` (+851 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.