import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../main.dart' show mainScaffoldKey;
import '../auth/auth_provider.dart';
import '../boost/boost_service.dart';
import '../location/location_service.dart';
import '../presence/presence_service.dart';
import '../travel/travel_pass_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import '../settings/settings_providers.dart';
import '../utils/distance_format.dart';
import 'edit_profile/sheets.dart' show showPositionSheet;
import 'profile_drawer.dart' show ownProfileProvider;
import 'profile_screen.dart' show UserProfile;
import 'story_service.dart';
import 'story_viewer_screen.dart';

/// Model for a user in the nearby grid (also used by the Discover section).
/// Fields `age` and `topTribe` are returned by the `/discover` endpoint and
/// are null for `/grid/nearby` responses.
class NearbyUser {
  final String id;
  final String email;
  final String? displayName;
  final String? bio;
  final String? profilePhotoId;
  final String? profilePhotoUrl;
  final double distanceM;
  final bool isVerified;
  final String? createdAt; // ISO 8601 from /grid/nearby users[i].created_at (T5.2 idx, T5.8 M1)
  final int? age; // From /discover
  final String? topTribe; // From /discover

  const NearbyUser({
    required this.id,
    required this.email,
    this.displayName,
    this.bio,
    this.profilePhotoId,
    this.profilePhotoUrl,
    required this.distanceM,
    this.isVerified = false,
    this.createdAt,
    this.age,
    this.topTribe,
  });

  factory NearbyUser.fromJson(Map<String, dynamic> json) {
    return NearbyUser(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String?,
      bio: json['bio'] as String?,
      profilePhotoId: json['profile_photo_id'] as String?,
      profilePhotoUrl: json['profile_photo_url'] as String?,
      distanceM: (json['distance_m'] as num).toDouble(),
      isVerified: json['verified'] == true,
      createdAt: json['created_at'] as String?,
      age: json['age'] as int?,
      topTribe: json['top_tribe'] as String?,
    );
  }

  /// True when the user account is < 7 days old (NUEVO badge gate).
  bool get isNew {
    final iso = createdAt;
    if (iso == null || iso.isEmpty) return false;
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return false;
    return DateTime.now().difference(parsed).inDays < 7;
  }

  /// Distance label — delegates to the shared `formatDistance` utility
  /// (T5.6) so the cascade, grid search, and any future screen stay consistent.
  /// Caller passes the units int (0=metric, 1=imperial) from
  /// `unitsProvider` (T5.6 + T5.9). T5.10 removed the legacy no-arg
  /// `distanceText` getter; all callers now thread `units` explicitly.
  String distanceLabel(int units) => formatDistance(distanceM.round(), units);
}

/// Default filter options (hardcoded fallback if the API is unreachable).
const _kDefaultTribes = [
  'Bear', 'Otter', 'Twink', 'Jock', 'Daddy', 'Geek',
  'Muscle', 'Chub', 'Leather', 'Trans', 'Queer',
];

const _kDefaultBodyTypes = [
  'Slim', 'Average', 'Athletic', 'Muscular', 'Curvy', 'Stocky', 'Large',
];

const _kDefaultLookingFor = [
  'Chat', 'Friends', 'Dates', 'Relationship', 'Networking', 'Right Now',
];

/// Navegar — the main screen showing nearby users in a 3-column full-bleed
/// grid, Grindr-style header (avatar + search pill), filter chips, upsell
/// band after row 2, and Boost / Right Now FABs.
class NavegarScreen extends ConsumerStatefulWidget {
  const NavegarScreen({super.key});

  @override
  ConsumerState<NavegarScreen> createState() => _NavegarScreenState();
}

class _NavegarScreenState extends ConsumerState<NavegarScreen> {
  late Future<List<NearbyUser>> _nearbyUsersFuture;
  Future<List<NearbyUser>>? _discoverUsersFuture;

  // ── Filter state (kept from original CascadeScreen) ────────────────────────
  RangeValues _ageRange = const RangeValues(18, 99);
  Set<String> _selectedTribes = {};
  String? _bodyType;
  String? _lookingFor;
  String _searchQuery = '';
  double _distanceKm = 5;
  Position? _lastPosition;
  bool _locationDenied = false;

  // ── New state (T3) ─────────────────────────────────────────────────────────
  bool _showFavoritesOnly = false;
  bool _onlineOnly = false;
  Set<String> _favoriteIds = {};

  // ── New state (T5.9) ───────────────────────────────────────────────────────
  // heartbeats-based "right now" filter (last_seen_at < now-30min).
  // Distinct from the /right-now PAGE (a separate feature) which stays
  // reachable from the Boost/Right Now FAB.
  bool _rightNow = false;

  // ── New state (G1) ─────────────────────────────────────────────────────────
  bool _photosOnly = false;
  String? _position; // backend enum value (lowercase, e.g. 'bottom', 'top')
  bool _notChatted = false;

  // ── Travel Pass state ───────────────────────────────────────────────────────
  TravelPass? _travelPass;
  bool _travelPassLoaded = false;

  // ── Filter sheet controller (lifted to avoid leak) ─────────────────────────
  final TextEditingController _filterSearchController = TextEditingController();

  // ── Dynamic filter options (fetched from /meta/filters on init) ──────────
  List<String> _tribes = _kDefaultTribes;
  List<String> _bodyTypes = _kDefaultBodyTypes;
  List<String> _lookingForOptions = _kDefaultLookingFor;

  @override
  void initState() {
    super.initState();
    _nearbyUsersFuture = _initAndFetch();
    _discoverUsersFuture = _initAndFetchDiscover();
    _loadFavorites();
    _loadFilterOptions();
    _loadTravelPass();
  }

  @override
  void dispose() {
    _filterSearchController.dispose();
    super.dispose();
  }

  /// Load the current active travel pass from the server.
  Future<void> _loadTravelPass() async {
    try {
      await ref.read(authReadyProvider.future);
      final service = ref.read(travelPassServiceProvider);
      final tp = await service.getCurrent();
      if (!mounted) return;
      setState(() {
        _travelPass = tp;
        _travelPassLoaded = true;
        if (tp != null) {
          // Re-fetch with travel pass coordinates
          _nearbyUsersFuture = _fetchNearbyUsers(
            overrideLat: tp.lat,
            overrideLon: tp.lon,
          );
          _discoverUsersFuture = _fetchDiscoverUsers(
            overrideLat: tp.lat,
            overrideLon: tp.lon,
          );
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _travelPassLoaded = true);
    }
  }

  /// Waits for auth, fetches GPS, then fetches nearby users.
  Future<List<NearbyUser>> _initAndFetch() async {
    await ref.read(authReadyProvider.future);
    final service = ref.read(locationServiceProvider);
    final pos = await service.getCurrentPosition() ??
        await service.getLastKnownPosition();
    if (mounted) {
      setState(() {
        _lastPosition = pos;
        _locationDenied = pos == null;
      });
    }
    return _fetchNearbyUsers();
  }

  /// Loads the user's favorites list from the API (client-side filter support).
  void _loadFavorites() async {
    try {
      await ref.read(authReadyProvider.future);
      final dio = ref.read(dioProvider);
      final resp = await dio.get<Map<String, dynamic>>('/favorites');
      final favsJson = (resp.data!['favorites'] as List<dynamic>);
      if (mounted) {
        setState(() {
          _favoriteIds = favsJson
              .map((f) => (f as Map<String, dynamic>)['user_id'] as String)
              .toSet();

        });
      }
    } catch (_) {
      debugPrint('[NavegarScreen] error: loading favorites failed');
      // Favorites are optional — the chip simply filters nothing on failure.
    }
  }

  /// Fetches filter options from /meta/filters on startup.
  /// Falls back to hardcoded defaults if the API is unreachable.
  void _loadFilterOptions() async {
    try {
      await ref.read(authReadyProvider.future);
      final dio = ref.read(dioProvider);
      final resp = await dio.get<Map<String, dynamic>>('/meta/filters');
      final data = resp.data!;
      if (mounted) {
        setState(() {
          _tribes = (data['tribes'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList() ??
              _kDefaultTribes;
          _bodyTypes = (data['body_types'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList() ??
              _kDefaultBodyTypes;
          _lookingForOptions = (data['looking_for'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList() ??
              _kDefaultLookingFor;
        });
      }
    } catch (_) {
      debugPrint('[NavegarScreen] error: loading filter options failed');
      // API unreachable — keep the hardcoded defaults.
    }
  }

  /// Initializes and fetches the Discover feed (waits for auth).
  Future<List<NearbyUser>> _initAndFetchDiscover() async {
    await ref.read(authReadyProvider.future);
    return _fetchDiscoverUsers();
  }

  /// Fetches curated user profiles from GET /discover.
  /// Returns an empty list on failure (silently — the strip simply won't show).
  Future<List<NearbyUser>> _fetchDiscoverUsers({
    double? overrideLat,
    double? overrideLon,
  }) async {
    // Use override coordinates (travel pass) if provided, otherwise use GPS.
    double lat;
    double lon;
    if (overrideLat != null && overrideLon != null) {
      lat = overrideLat;
      lon = overrideLon;
    } else if (_lastPosition != null) {
      lat = _lastPosition!.latitude;
      lon = _lastPosition!.longitude;
    } else {
      // No cached position — try to obtain one ourselves.
      final service = ref.read(locationServiceProvider);
      final pos = await service.getCurrentPosition() ??
          await service.getLastKnownPosition();
      if (pos == null) return const [];
      lat = pos.latitude;
      lon = pos.longitude;
    }
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get<Map<String, dynamic>>(
        '/discover',
        queryParameters: {
          'lat': lat,
          'lon': lon,
          'radius_m': 50000,
        },
      );
      final data = response.data!;
      final usersJson = data['users'] as List<dynamic>;
      return usersJson
          .map((u) => NearbyUser.fromJson(u as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[NavegarScreen] error: loading discover failed: $e');
      return const [];
    }
  }

  Future<List<NearbyUser>> _fetchNearbyUsers({
    double? overrideLat,
    double? overrideLon,
  }) async {
    final dio = ref.read(dioProvider);
    final radiusM = (_distanceKm * 1000).round();

    // Use override coordinates (travel pass) if provided, otherwise use GPS.
    final effectiveLat = overrideLat ?? _lastPosition?.latitude;
    final effectiveLon = overrideLon ?? _lastPosition?.longitude;
    if (effectiveLat == null || effectiveLon == null) return const [];

    final queryParams = <String, dynamic>{
      'lat': effectiveLat,
      'lon': effectiveLon,
      'radius_m': radiusM,
      'limit': 50,
    };

    if (_ageRange.start > 18) queryParams['min_age'] = _ageRange.start.round();
    if (_ageRange.end < 99) queryParams['max_age'] = _ageRange.end.round();
    if (_selectedTribes.isNotEmpty) {
      queryParams['tribe'] = _selectedTribes.join(',');
    }
    if (_bodyType != null && _bodyType!.isNotEmpty) {
      queryParams['body_type'] = _bodyType;
    }
    if (_lookingFor != null && _lookingFor!.isNotEmpty) {
      queryParams['looking_for'] = _lookingFor;
    }
    if (_searchQuery.isNotEmpty) queryParams['q'] = _searchQuery;
    if (_showFavoritesOnly) queryParams['favorites_only'] = true; // T5.9: server-side
    if (_onlineOnly) queryParams['online_only'] = true;
    if (_rightNow) queryParams['right_now'] = true; // T5.9: heartbeats-based filter
    if (_photosOnly) queryParams['photos_only'] = true; // G1
    if (_position != null && _position!.isNotEmpty) {
      queryParams['position'] = _position!.toLowerCase(); // G1
    }
    if (_notChatted) queryParams['not_chatted'] = true; // G1

    final response = await dio.get<Map<String, dynamic>>(
      '/grid/nearby',
      queryParameters: queryParams,
    );

    final data = response.data!;
    final usersJson = data['users'] as List<dynamic>;
    return usersJson
        .map((u) => NearbyUser.fromJson(u as Map<String, dynamic>))
        .toList();
  }

  void _refresh() {
    setState(() {
      _nearbyUsersFuture = _initAndFetch();
      _discoverUsersFuture = _initAndFetchDiscover();
    });
  }

  bool get _hasActiveFilters =>
      _ageRange.start > 18 ||
      _ageRange.end < 99 ||
      _selectedTribes.isNotEmpty ||
      _bodyType != null ||
      _lookingFor != null ||
      _searchQuery.isNotEmpty ||
      _distanceKm != 5 ||
      _showFavoritesOnly ||
      _onlineOnly ||
      _rightNow || // T5.9: chip-active state propagates to filtros-band highlight
      _photosOnly || // G1
      _position != null || // G1
      _notChatted; // G1

  void _toggleFavorites() {
    setState(() {
      _showFavoritesOnly = !_showFavoritesOnly;
      // T5.9: refetch so the server-side `favorites_only=true` actually runs.
      // Without this, the chip flips but the API still returns the full set
      // (the old client-side filter via _favoriteIds was the only path).
      _nearbyUsersFuture = _fetchNearbyUsers();
    });
  }

  void _toggleOnlineOnly() {
    setState(() {
      _onlineOnly = !_onlineOnly;
      _nearbyUsersFuture = _fetchNearbyUsers();
    });
  }

  // T5.9: toggles the heartbeats-based "right now" filter (last_seen_at
  // within 30min). Distinct from the `/right-now` page, which is reachable
  // from the FAB and is for posting explicit `right_now_intents`.
  void _toggleRightNow() {
    setState(() {
      _rightNow = !_rightNow;
      _nearbyUsersFuture = _fetchNearbyUsers();
    });
  }

  // G1: toggles the photos-only filter (only users with a profile photo).
  void _togglePhotosOnly() {
    setState(() {
      _photosOnly = !_photosOnly;
      _nearbyUsersFuture = _fetchNearbyUsers();
    });
  }

  // G1: toggles the not-chatted filter (only users never chatted with).
  void _toggleNotChatted() {
    setState(() {
      _notChatted = !_notChatted;
      _nearbyUsersFuture = _fetchNearbyUsers();
    });
  }

  // G1: opens the position selector sheet.
  // First tap → opens sheet; if a value is selected, stores it and refetches.
  // Tapping again when active clears the filter.
  void _pickPosition(BuildContext context) {
    if (_position != null) {
      setState(() {
        _position = null;
        _nearbyUsersFuture = _fetchNearbyUsers();
      });
      return;
    }
    showPositionSheet(context).then((picked) {
      if (picked != null && mounted) {
        setState(() {
          _position = picked;
          _nearbyUsersFuture = _fetchNearbyUsers();
        });
      }
    });
  }

  Future<void> _handleBoost() async {
    final activeAsync = ref.read(activeBoostProvider);
    Boost? existingBoost;
    if (activeAsync is AsyncData<Boost?>) {
      existingBoost = activeAsync.value;
    }
    if (existingBoost != null) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.you_boost_active(existingBoost.minutesRemaining),
            ),
          ),
        );
      }
      return;
    }
    try {
      await ref.read(boostServiceProvider).activate();
      ref.invalidate(activeBoostProvider);
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.you_boosted_snackbar),
            backgroundColor: VibraTheme.kAccentPulse,
          ),
        );
      }
    } catch (_) {
      debugPrint('[NavegarScreen] error: activating boost');
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.you_boosted_snackbar)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final profileAsync = ref.watch(ownProfileProvider);

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      floatingActionButton: _buildFabs(context),
      body: RefreshIndicator(
        color: VibraTheme.kAccent,
        onRefresh: () async {
          final service = ref.read(locationServiceProvider);
          final pos = await service.getCurrentPosition() ??
              await service.getLastKnownPosition();
          if (mounted) {
            setState(() {
              _lastPosition = pos;
              _locationDenied = pos == null;
              _nearbyUsersFuture = _fetchNearbyUsers();
              _discoverUsersFuture = _fetchDiscoverUsers();
            });
          }
        },
        child: FutureBuilder<List<NearbyUser>>(
          future: _nearbyUsersFuture,
          builder: (context, snapshot) {
            final isLoading =
                snapshot.connectionState == ConnectionState.waiting;
            final hasError = snapshot.hasError;
            final rawUsers = snapshot.data ?? [];
            final users = _showFavoritesOnly
                ? rawUsers
                    .where((u) => _favoriteIds.contains(u.id))
                    .toList()
                : rawUsers;

            return CustomScrollView(
              slivers: [
                // ── Header SliverAppBar ──────────────────────────────────
                _buildSliverAppBar(l10n, profileAsync, context),

                // ── Stories bar (G12) ────────────────────────────────────
                SliverToBoxAdapter(
                  child: _buildStoriesBar(context),
                ),

                // ── Discover strip (curated profiles, horizontal) ───────
                SliverToBoxAdapter(
                  child: _buildDiscoverStrip(context),
                ),

                // ── Location denied banner ───────────────────────────────
                if (_locationDenied)
                  SliverToBoxAdapter(child: _buildLocationBanner()),

                // ── Travel Pass banner ────────────────────────────────────
                if (_travelPass != null)
                  SliverToBoxAdapter(child: _buildTravelPassBanner(l10n)),

                // ── Filter chips row ─────────────────────────────────────
                SliverToBoxAdapter(
                  child: _buildChipsRow(l10n, context),
                ),

                // ── Content: shimmer | error | empty | grid ──────────────
                if (isLoading)
                  // Shimmer skeleton as a sliver grid
                  SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 1.5,
                      crossAxisSpacing: 1.5,
                      childAspectRatio: 0.91,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, _) => Shimmer.fromColors(
                        baseColor: VibraTheme.kSurface,
                        highlightColor: VibraTheme.kSurfaceElevated,
                        child: Container(color: VibraTheme.kSurface),
                      ),
                      childCount: 9,
                    ),
                  )
                else if (hasError)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildErrorState(Theme.of(context)),
                  )
                else if (users.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(Theme.of(context)),
                  )
                else ...[
                  // First 6 users (rows 1–2)
                  SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 1.5,
                      crossAxisSpacing: 1.5,
                      childAspectRatio: 0.91,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (ctx, index) {
                        final user = users[index];
                        return _UserCard(
                          user: user,
                          onTap: () => ctx.push('/profile/${user.id}'),
                        );
                      },
                      childCount: users.length < 6 ? users.length : 6,
                    ),
                  ),

                  // Upsell band — inserted after row 2
                  if (users.length >= 6)
                    SliverToBoxAdapter(
                      child: _buildUpsellBand(l10n, context),
                    ),

                  // Remaining users (row 3+)
                  if (users.length > 6)
                    SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 1.5,
                        crossAxisSpacing: 1.5,
                        childAspectRatio: 0.91,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (ctx, index) {
                          final user = users[index + 6];
                          return _UserCard(
                            user: user,
                            onTap: () => ctx.push('/profile/${user.id}'),
                          );
                        },
                        childCount: users.length - 6,
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildSliverAppBar(
    AppLocalizations l10n,
    AsyncValue<UserProfile?> profileAsync,
    BuildContext context,
  ) {
    final profile =
        profileAsync.maybeWhen(data: (p) => p, orElse: () => null);
    final photoUrl = profile?.profilePhotoUrl;
    final initials = _avatarInitial(profile);

    return SliverAppBar(
      pinned: true,
      backgroundColor: VibraTheme.kBg,
      toolbarHeight: 64,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            // Avatar with online dot → opens ProfileDrawer
            GestureDetector(
              onTap: () => mainScaffoldKey.currentState?.openDrawer(),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: VibraTheme.kSurface,
                      foregroundImage:
                          photoUrl != null ? NetworkImage(photoUrl) : null,
                      child: Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    // Online dot
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: VibraTheme.kOnline,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.black, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 10),

            // Search pill → GridSearchScreen
            Expanded(
              child: GestureDetector(
                onTap: () => context.push('/grid-search'),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: const BoxDecoration(
                    color: VibraTheme.kChip,
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_outlined,
                        size: 18,
                        color: VibraTheme.kTextSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.explorarMasPerfiles,
                        style: const TextStyle(
                          color: VibraTheme.kTextSecondary,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _avatarInitial(UserProfile? p) {
    if (p == null) return '?';
    final name = p.displayName ?? p.email;
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  // ── Stories bar (G12) ──────────────────────────────────────────────────────

  Widget _buildStoriesBar(BuildContext context) {
    final storiesAsync = ref.watch(storiesListProvider);

    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: storiesAsync.when(
        data: (groups) {
          if (groups.isEmpty) return const SizedBox.shrink();
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: groups.length + 1, // +1 for the add button
            itemBuilder: (context, index) {
              if (index == 0) {
                // My story — add button
                return _StoryAvatar(
                  isAddButton: true,
                  onTap: () => context.push('/create-story'),
                );
              }
              final group = groups[index - 1];
              return _StoryAvatar(
                avatarKey: group.avatarKey,
                displayName: group.displayName ?? AppLocalizations.of(context)!.usuarioFallback,
                hasUnviewed: !group.allViewed,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StoryViewerScreen(
                        groups: groups,
                        initialGroupIndex: index - 1,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
        loading: () => const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (_, _) => const SizedBox.shrink(),
      ),
    );
  }

  // ── Discover strip (curated user cards, horizontal scroll) ─────────────────

  /// Horizontal scrollable strip of curated profile cards from /discover.
  /// Only renders when the future resolves to a non-empty list.
  Widget _buildDiscoverStrip(BuildContext context) {
    return FutureBuilder<List<NearbyUser>>(
      future: _discoverUsersFuture,
      builder: (context, snapshot) {
        final users = snapshot.data ?? [];
        if (users.isEmpty) return const SizedBox.shrink();
        final l10n = AppLocalizations.of(context)!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                l10n.discover,
                style: const TextStyle(
                  color: VibraTheme.kTextPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(
              height: 180,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final user = users[index];
                  return _DiscoverCard(
                    user: user,
                    onTap: () => context.push('/profile/${user.id}'),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Chips row ──────────────────────────────────────────────────────────────

  Widget _buildChipsRow(AppLocalizations l10n, BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          FilterChipPill(
            icon: Icons.tune,
            label: l10n.filtros,
            active: _hasActiveFilters,
            onTap: () => _showFilterSheet(context),
          ),
          const SizedBox(width: 8),
          FilterChipPill(
            icon: Icons.star,
            label: l10n.favoritos,
            active: _showFavoritesOnly,
            onTap: _toggleFavorites,
          ),
          const SizedBox(width: 8),
          FilterChipPill(
            label: l10n.enLinea,
            active: _onlineOnly,
            onTap: _toggleOnlineOnly,
          ),
          const SizedBox(width: 8),
          FilterChipPill(
            icon: Icons.bolt,
            label: l10n.filterRightNow, // T5.7 key: 'Ahora' / 'Right now'
            active: _rightNow,
            onTap: _toggleRightNow,
          ),
          const SizedBox(width: 8),
          // G1: Con foto filter chip
          FilterChipPill(
            icon: Icons.photo,
            label: l10n.filterPhotosOnly,
            active: _photosOnly,
            onTap: _togglePhotosOnly,
          ),
          const SizedBox(width: 8),
          // G1: Sin chatear filter chip
          FilterChipPill(
            label: l10n.filterNotChatted,
            active: _notChatted,
            onTap: _toggleNotChatted,
          ),
          const SizedBox(width: 8),
          // G1: Posición filter chip (opens selector sheet; tap again to clear)
          FilterChipPill(
            label: _position != null
                ? '${l10n.filterPosition}: $_position'
                : l10n.filterPosition,
            active: _position != null,
            onTap: () => _pickPosition(context),
          ),
        ],
      ),
    );
  }

  // ── Upsell band ────────────────────────────────────────────────────────────

  Widget _buildUpsellBand(AppLocalizations l10n, BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/tienda'),
      child: Container(
        height: 56,
        color: VibraTheme.kBg,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Text(
              l10n.verMasPerfiles,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward, color: Colors.white),
          ],
        ),
      ),
    );
  }

  // ── FABs (Boost + Right Now) ───────────────────────────────────────────────

  Widget _buildFabs(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Boost pill
        GestureDetector(
          onTap: _handleBoost,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: VibraTheme.kBg,
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              border: Border.all(color: VibraTheme.kAccentPulse, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLocalizations.of(context)!.boost,
                  style: const TextStyle(
                    color: VibraTheme.kAccentPulse,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.bolt, color: VibraTheme.kAccentPulse, size: 18),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Right Now pill
        GestureDetector(
          onTap: () => context.go('/right-now'),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: VibraTheme.kBg,
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              border: Border.all(color: VibraTheme.kAccentGlow, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLocalizations.of(context)!.right_now_title,
                  style: const TextStyle(
                    color: VibraTheme.kAccentGlow,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.water_drop, color: VibraTheme.kAccentGlow, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── State helpers ──────────────────────────────────────────────────────────

  Widget _buildErrorState(ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: VibraTheme.kSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 36,
                color: VibraTheme.kError,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.navegarFailedToLoad,
              style: theme.textTheme.titleMedium?.copyWith(
                color: VibraTheme.kTextPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _refresh,
              child: Text(l10n.reintentar),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: VibraTheme.kSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.people_outline,
                size: 36,
                color: VibraTheme.kAccent,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.navegarNoOneNearby,
              style: theme.textTheme.titleLarge?.copyWith(
                color: VibraTheme.kTextPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.navegarExpandRadius,
              style: VibraTheme.bodySecondary,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationBanner() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      color: VibraTheme.kSurface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(
            Icons.location_off,
            color: VibraTheme.kAccent,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.navegarEnableLocation,
              style: const TextStyle(color: VibraTheme.kTextPrimary, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => Geolocator.openAppSettings(),
            style: TextButton.styleFrom(
              foregroundColor: VibraTheme.kAccent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(l10n.abrirAjustes),
          ),
        ],
      ),
    );
  }

  /// Travel Pass banner: shows active virtual location and expiry.
  Widget _buildTravelPassBanner(AppLocalizations l10n) {
    final tp = _travelPass;
    if (tp == null) return const SizedBox.shrink();
    final cityLabel = tp.cityName ??
        '${tp.lat.toStringAsFixed(4)}, ${tp.lon.toStringAsFixed(4)}';
    final hoursRemaining = tp.expiresInHours.toStringAsFixed(1);
    return Container(
      width: double.infinity,
      color: VibraTheme.kSurface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.flight_takeoff, size: 18, color: VibraTheme.kBrandPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.travelPassBanner(cityLabel),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  l10n.travelPassExpires(hoursRemaining),
                  style: const TextStyle(
                    color: VibraTheme.kTextSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              final service = ref.read(travelPassServiceProvider);
              service.delete().then((_) {
                if (!mounted) return;
                setState(() {
                  _travelPass = null;
                  _nearbyUsersFuture = _fetchNearbyUsers();
                  _discoverUsersFuture = _fetchDiscoverUsers();
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.travelPassCancelled)),
                );
              }).catchError((e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.travelPassFailedToCancel),
                    backgroundColor: VibraTheme.kError,
                  ),
                );
              });
            },
            style: TextButton.styleFrom(
              foregroundColor: VibraTheme.kAccent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(
              l10n.travelPassBackToMyLocation,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ── Filter sheet (UNCHANGED from original CascadeScreen) ──────────────────

  void _showFilterSheet(BuildContext context) {
    RangeValues localAge = _ageRange;
    Set<String> localTribes = Set.from(_selectedTribes);
    String? localBodyType = _bodyType;
    String? localLookingFor = _lookingFor;
    double localDistanceKm = _distanceKm;
    // Reuse the state-level controller (reset to current query before opening).
    _filterSearchController.text = _searchQuery;
    final searchController = _filterSearchController;

    showModalBottomSheet(
      context: context,
      backgroundColor: VibraTheme.kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final l10n = AppLocalizations.of(context)!;
          return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.filtros,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Distance slider
                Text(
                  l10n.filterDistanceLabel(localDistanceKm.round()),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Slider(
                  key: const Key('distance_slider'),
                  value: localDistanceKm,
                  min: 1,
                  max: 50,
                  divisions: 49,
                  label: '${localDistanceKm.round()} km',
                  activeColor: VibraTheme.kAccent,
                  onChanged: (v) =>
                      setSheetState(() => localDistanceKm = v),
                ),
                const SizedBox(height: 12),

                // Age range slider
                Text(
                  l10n.filterAgeRange(localAge.start.round(), localAge.end.round()),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                RangeSlider(
                  values: localAge,
                  min: 18,
                  max: 99,
                  divisions: 81,
                  activeColor: VibraTheme.kAccent,
                  labels: RangeLabels(
                    localAge.start.round().toString(),
                    localAge.end.round().toString(),
                  ),
                  onChanged: (v) => setSheetState(() => localAge = v),
                ),
                const SizedBox(height: 12),

                // Tribe multi-select
                Text(l10n.filterTribeLabel, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _tribes.map((tribe) {
                    final selected = localTribes.contains(tribe);
                    return FilterChip(
                      label:
                          Text(tribe, style: const TextStyle(fontSize: 12)),
                      selected: selected,
                      selectedColor:
                          VibraTheme.kAccent.withValues(alpha: 0.2),
                      checkmarkColor: VibraTheme.kAccent,
                      onSelected: (val) {
                        setSheetState(() {
                          if (val) {
                            localTribes.add(tribe);
                          } else {
                            localTribes.remove(tribe);
                          }
                        });
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),

                // Body type dropdown
                Text(l10n.editProfileFieldBodyType,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  key: ValueKey('body_type_${localBodyType ?? "none"}'),
                  initialValue: localBodyType,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  hint: Text(l10n.filterAny),
                  items: _bodyTypes
                      .map((bt) =>
                          DropdownMenuItem(value: bt, child: Text(bt)))
                      .toList(),
                  onChanged: (v) => setSheetState(() => localBodyType = v),
                ),
                const SizedBox(height: 12),

                // Looking for dropdown
                Text(l10n.editProfileFieldLookingFor,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  key: ValueKey('looking_for_${localLookingFor ?? "none"}'),
                  initialValue: localLookingFor,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  hint: Text(l10n.filterAny),
                  items: _lookingForOptions
                      .map((lf) =>
                          DropdownMenuItem(value: lf, child: Text(lf)))
                      .toList(),
                  onChanged: (v) =>
                      setSheetState(() => localLookingFor = v),
                ),
                const SizedBox(height: 12),

                // Search text field
                Text(l10n.filterSearchLabel,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: l10n.filterSearchHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: (v) {},
                ),
                const SizedBox(height: 24),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setSheetState(() {
                            localAge = const RangeValues(18, 99);
                            localTribes = {};
                            localBodyType = null;
                            localLookingFor = null;
                            localDistanceKm = 5;
                            searchController.clear();
                          });
                        },
                        child: Text(l10n.filterReset),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            _ageRange = localAge;
                            _selectedTribes = localTribes;
                            _bodyType = localBodyType;
                            _lookingFor = localLookingFor;
                            _distanceKm = localDistanceKm;
                            _searchQuery = searchController.text.trim();
                            _nearbyUsersFuture = _fetchNearbyUsers();
                          });
                          Navigator.pop(ctx);
                        },
                        child: Text(l10n.filterApply),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
        },
      ),
    );
  }
}

// ── _UserCard ─────────────────────────────────────────────────────────────────

/// Full-bleed photo card — no border radius, gradient scrim bottom 40%,
/// online dot + name overlay bottom-left.
class _UserCard extends ConsumerWidget {
  final NearbyUser user;
  final VoidCallback onTap;

  const _UserCard({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(userStatusProvider(user.id));
    final isOnline = statusAsync.maybeWhen(
      data: (s) => s.isOnline,
      orElse: () => false,
    );

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo
            if (user.profilePhotoUrl != null)
              Image.network(
                user.profilePhotoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _buildPlaceholder(),
              )
            else
              _buildPlaceholder(),

            // Bottom gradient scrim (40% of tile height)
            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: 0.4,
                  widthFactor: 1.0,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0xD9000000),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Online dot + name overlay (bottom-left)
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isOnline
                          ? VibraTheme.kOnline
                          : VibraTheme.kTextMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      user.displayName ?? user.email,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(
                            blurRadius: 4,
                            color: Color(0x99000000),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Verified badge (top right)
            if (user.isVerified)
              Positioned(
                top: 5,
                right: 5,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: VibraTheme.kAccent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.black,
                    size: 11,
                  ),
                ),
              ),

            // NUEVO badge (top left) — T5.9: shown for accounts < 7 days old.
            // Shared widget (T5.13) — see apps/app/lib/src/theme/widgets.dart.
            if (user.isNew)
              Positioned(
                top: 5,
                left: 5,
                child: const NUEVOBadge.small(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [VibraTheme.kSurface, VibraTheme.kSurfaceElevated],
        ),
      ),
      child: Center(
        child: Text(
          (user.displayName ?? user.email)[0].toUpperCase(),
          style: const TextStyle(
            fontSize: 28,
            color: VibraTheme.kTextMuted,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stories avatar widget (G12)
// ---------------------------------------------------------------------------

class _StoryAvatar extends StatelessWidget {
  final bool isAddButton;
  final String? avatarKey;
  final String? displayName;
  final bool hasUnviewed;
  final VoidCallback onTap;

  const _StoryAvatar({
    this.isAddButton = false,
    this.avatarKey,
    this.displayName,
    this.hasUnviewed = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar circle with colored border
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isAddButton
                      ? VibraTheme.kAccent
                      : hasUnviewed
                          ? VibraTheme.kAccent
                          : VibraTheme.kTextMuted.withValues(alpha: 0.3),
                  width: 2.5,
                ),
              ),
              child: isAddButton
                  ? const Icon(Icons.add, color: VibraTheme.kAccent, size: 28)
                  : CircleAvatar(
                      radius: 28,
                      backgroundColor: VibraTheme.kSurface,
                      backgroundImage: avatarKey != null
                          ? NetworkImage(
                              'https://api.turnend.win/media/get-url?key=$avatarKey&kind=profile')
                          : null,
                      child: avatarKey == null
                          ? const Icon(Icons.person,
                              color: VibraTheme.kTextMuted, size: 28)
                          : null,
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              displayName ?? (isAddButton ? AppLocalizations.of(context)!.tuLabel : ''),
              style: const TextStyle(
                color: VibraTheme.kTextSecondary,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Discover card widget — circular photo, name, age, distance, top tribe
// ---------------------------------------------------------------------------

/// Card for the horizontal Discover strip.
/// Shows a circular profile photo, display name, age, distance, and top tribe.
class _DiscoverCard extends ConsumerWidget {
  final NearbyUser user;
  final VoidCallback onTap;

  const _DiscoverCard({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitsProvider);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: VibraTheme.kSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Circular profile photo
            CircleAvatar(
              radius: 36,
              backgroundColor: VibraTheme.kSurfaceElevated,
              backgroundImage: user.profilePhotoUrl != null
                  ? NetworkImage(user.profilePhotoUrl!)
                  : null,
              child: user.profilePhotoUrl == null
                  ? Text(
                      (user.displayName ?? user.email)[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 28,
                        color: VibraTheme.kTextMuted,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            // Display name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                user.displayName ?? user.email,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 2),
            // Age + distance
            Text(
              _discoverSubtitle(user, units),
              style: const TextStyle(
                color: VibraTheme.kTextSecondary,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            // Top tribe
            if (user.topTribe != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  user.topTribe!,
                  style: const TextStyle(
                    color: VibraTheme.kAccent,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Formats the subtitle line: "25 · 500 m" or just the distance if age is null.
  String _discoverSubtitle(NearbyUser user, int units) {
    final dist = user.distanceLabel(units);
    if (user.age != null) {
      return '${user.age} · $dist';
    }
    return dist;
  }
}
