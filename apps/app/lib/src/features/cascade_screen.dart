import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../auth/auth_provider.dart';
import '../location/location_service.dart';
import '../presence/presence_service.dart';
import '../theme/app_theme.dart';

/// Model for a user in the cascade grid.
class NearbyUser {
  final String id;
  final String email;
  final String? displayName;
  final String? bio;
  final String? profilePhotoId;
  final String? profilePhotoUrl;
  final double distanceM;
  final bool isVerified;

  const NearbyUser({
    required this.id,
    required this.email,
    this.displayName,
    this.bio,
    this.profilePhotoId,
    this.profilePhotoUrl,
    required this.distanceM,
    this.isVerified = false,
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
    );
  }

  String get distanceText {
    if (distanceM < 1000) {
      return '${distanceM.round()} m';
    }
    return '${(distanceM / 1000).toStringAsFixed(1)} km';
  }
}

/// Common tribe options for filter chips.
const _kTribes = [
  'Bear', 'Otter', 'Twink', 'Jock', 'Daddy', 'Geek',
  'Muscle', 'Chub', 'Leather', 'Trans', 'Queer',
];

/// Common body type options.
const _kBodyTypes = [
  'Slim', 'Average', 'Athletic', 'Muscular', 'Curvy', 'Stocky', 'Large',
];

/// Common looking-for / intent options.
const _kLookingFor = [
  'Chat', 'Friends', 'Dates', 'Relationship', 'Networking', 'Right Now',
];

/// Cascade — the main screen showing nearby users in a 3-column grid.
///
/// Full-bleed photo cards, gradient scrim, name/distance/online overlay,
/// verified badge slot, shimmer skeleton loaders, polished empty state.
class CascadeScreen extends ConsumerStatefulWidget {
  const CascadeScreen({super.key});

  @override
  ConsumerState<CascadeScreen> createState() => _CascadeScreenState();
}

class _CascadeScreenState extends ConsumerState<CascadeScreen> {
  late Future<List<NearbyUser>> _nearbyUsersFuture;

  // Filter state
  RangeValues _ageRange = const RangeValues(18, 99);
  Set<String> _selectedTribes = {};
  String? _bodyType;
  String? _lookingFor;
  String _searchQuery = '';
  double _distanceKm = 5; // Default 5 km radius
  Position? _lastPosition;
  bool _locationDenied = false;

  @override
  void initState() {
    super.initState();
    _nearbyUsersFuture = _initAndFetch();
  }

  /// Fetches GPS position first, updates cached state, then fetches users.
  Future<List<NearbyUser>> _initAndFetch() async {
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

  Future<List<NearbyUser>> _fetchNearbyUsers() async {
    final pos = _lastPosition;
    // Return empty list immediately when GPS is unavailable — the build()
    // method will show the "enable location" banner instead.
    if (pos == null) return const [];
    final dio = ref.read(dioProvider);
    final lat = pos.latitude;
    final lon = pos.longitude;
    final radiusM = (_distanceKm * 1000).round();

    final queryParams = <String, dynamic>{
      'lat': lat,
      'lon': lon,
      'radius_m': radiusM,
      'limit': 50,
    };

    // Add filter parameters if set
    if (_ageRange.start > 18) {
      queryParams['min_age'] = _ageRange.start.round();
    }
    if (_ageRange.end < 99) {
      queryParams['max_age'] = _ageRange.end.round();
    }
    if (_selectedTribes.isNotEmpty) {
      queryParams['tribe'] = _selectedTribes.join(',');
    }
    if (_bodyType != null && _bodyType!.isNotEmpty) {
      queryParams['body_type'] = _bodyType;
    }
    if (_lookingFor != null && _lookingFor!.isNotEmpty) {
      queryParams['looking_for'] = _lookingFor;
    }
    if (_searchQuery.isNotEmpty) {
      queryParams['q'] = _searchQuery;
    }

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
    });
  }

  bool get _hasActiveFilters =>
      _ageRange.start > 18 ||
      _ageRange.end < 99 ||
      _selectedTribes.isNotEmpty ||
      _bodyType != null ||
      _lookingFor != null ||
      _searchQuery.isNotEmpty ||
      _distanceKm != 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Vibra',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: theme.colorScheme.primary,
          ),
        ),
        actions: [
          if (_hasActiveFilters)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear filters',
              onPressed: () {
                setState(() {
                  _ageRange = const RangeValues(18, 99);
                  _selectedTribes = {};
                  _bodyType = null;
                  _lookingFor = null;
                  _searchQuery = '';
                  _distanceKm = 5;
                  _nearbyUsersFuture = _fetchNearbyUsers();
                });
              },
            ),
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: _hasActiveFilters ? theme.colorScheme.primary : null,
            ),
            onPressed: () => _showFilterSheet(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Location denied banner
          if (_locationDenied) _buildLocationBanner(),
          // Active filter chips summary
          if (_hasActiveFilters) _buildActiveFilterChips(),
          // User grid
          Expanded(
            child: FutureBuilder<List<NearbyUser>>(
              future: _nearbyUsersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildShimmerGrid();
                }

                if (snapshot.hasError) {
                  return _buildErrorState(theme);
                }

                final users = snapshot.data ?? [];
                if (users.isEmpty) {
                  return _buildEmptyState(theme);
                }

                return RefreshIndicator(
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
                      });
                    }
                  },
                  child: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.all(8),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.75,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final user = users[index];
                              return _UserCard(
                                user: user,
                                onTap: () => context.push('/profile/${user.id}'),
                              );
                            },
                            childCount: users.length,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Shimmer skeleton grid shown while fetching users.
  Widget _buildShimmerGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.75,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: 9,
      itemBuilder: (_, _) => Shimmer.fromColors(
        baseColor: VibraTheme.kSurface,
        highlightColor: VibraTheme.kSurfaceElevated,
        child: Container(
          decoration: BoxDecoration(
            color: VibraTheme.kSurface,
            borderRadius: BorderRadius.circular(VibraTheme.kRadiusCard),
          ),
        ),
      ),
    );
  }

  /// Polished error state.
  Widget _buildErrorState(ThemeData theme) {
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
              'Failed to load nearby users',
              style: theme.textTheme.titleMedium?.copyWith(
                color: VibraTheme.kTextPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _refresh,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  /// Polished empty state.
  Widget _buildEmptyState(ThemeData theme) {
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
              'No one nearby yet',
              style: theme.textTheme.titleLarge?.copyWith(
                color: VibraTheme.kTextPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try Explore to see people everywhere!',
              style: VibraTheme.bodySecondary,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Banner shown when the user has denied location permission.
  Widget _buildLocationBanner() {
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
          const Expanded(
            child: Text(
              'Enable location to see people nearby',
              style: TextStyle(color: VibraTheme.kTextPrimary, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => Geolocator.openAppSettings(),
            style: TextButton.styleFrom(
              foregroundColor: VibraTheme.kAccent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Removable active-filter chip row.
  Widget _buildActiveFilterChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          if (_ageRange.start > 18 || _ageRange.end < 99)
            Chip(
              label: Text('Age ${_ageRange.start.round()}-${_ageRange.end.round()}'),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () {
                setState(() {
                  _ageRange = const RangeValues(18, 99);
                  _nearbyUsersFuture = _fetchNearbyUsers();
                });
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          for (final tribe in _selectedTribes)
            Chip(
              label: Text(tribe),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () {
                setState(() {
                  _selectedTribes = Set.from(_selectedTribes)..remove(tribe);
                  _nearbyUsersFuture = _fetchNearbyUsers();
                });
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          if (_bodyType != null)
            Chip(
              label: Text(_bodyType!),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () {
                setState(() {
                  _bodyType = null;
                  _nearbyUsersFuture = _fetchNearbyUsers();
                });
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          if (_lookingFor != null)
            Chip(
              label: Text(_lookingFor!),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () {
                setState(() {
                  _lookingFor = null;
                  _nearbyUsersFuture = _fetchNearbyUsers();
                });
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          if (_searchQuery.isNotEmpty)
            Chip(
              label: Text('"$_searchQuery"'),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () {
                setState(() {
                  _searchQuery = '';
                  _nearbyUsersFuture = _fetchNearbyUsers();
                });
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    RangeValues localAge = _ageRange;
    Set<String> localTribes = Set.from(_selectedTribes);
    String? localBodyType = _bodyType;
    String? localLookingFor = _lookingFor;
    double localDistanceKm = _distanceKm;
    final searchController = TextEditingController(text: _searchQuery);

    showModalBottomSheet(
      context: context,
      backgroundColor: VibraTheme.kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
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
                  'Filters',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // --- Distance slider ---
                Text(
                  'Distance: ${localDistanceKm.round()} km',
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
                  onChanged: (v) => setSheetState(() => localDistanceKm = v),
                ),
                const SizedBox(height: 12),

                // --- Age range slider ---
                Text(
                  'Age Range: ${localAge.start.round()} - ${localAge.end.round()}',
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

                // --- Tribe multi-select chips ---
                Text('Tribe', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _kTribes.map((tribe) {
                    final selected = localTribes.contains(tribe);
                    return FilterChip(
                      label: Text(tribe, style: const TextStyle(fontSize: 12)),
                      selected: selected,
                      selectedColor: VibraTheme.kAccent.withValues(alpha: 0.2),
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

                // --- Body type dropdown ---
                Text('Body Type', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  key: ValueKey('body_type_${localBodyType ?? "none"}'),
                  initialValue: localBodyType,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  hint: const Text('Any'),
                  items: _kBodyTypes
                      .map((bt) => DropdownMenuItem(value: bt, child: Text(bt)))
                      .toList(),
                  onChanged: (v) => setSheetState(() => localBodyType = v),
                ),
                const SizedBox(height: 12),

                // --- Looking for dropdown ---
                Text('Looking For', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  key: ValueKey('looking_for_${localLookingFor ?? "none"}'),
                  initialValue: localLookingFor,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  hint: const Text('Any'),
                  items: _kLookingFor
                      .map((lf) => DropdownMenuItem(value: lf, child: Text(lf)))
                      .toList(),
                  onChanged: (v) => setSheetState(() => localLookingFor = v),
                ),
                const SizedBox(height: 12),

                // --- Search text field ---
                Text('Search', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    hintText: 'Name, bio...',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: (v) {},
                ),
                const SizedBox(height: 24),

                // --- Action buttons ---
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
                        child: const Text('Reset'),
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
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-bleed photo card with gradient scrim, name/distance/online overlay,
/// and an optional verified badge in the top-right corner.
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
        borderRadius: BorderRadius.circular(VibraTheme.kRadiusCard),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background: network photo or gradient placeholder
            if (user.profilePhotoUrl != null)
              Image.network(
                user.profilePhotoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _buildPlaceholder(),
              )
            else
              _buildPlaceholder(),

            // Bottom gradient scrim (transparent → near-black)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 72,
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

            // Name + distance overlay (bottom left)
            Positioned(
              left: 6,
              right: 18,
              bottom: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user.displayName ?? user.email,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(blurRadius: 4, color: Color(0x99000000)),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    user.distanceText,
                    style: const TextStyle(
                      color: VibraTheme.kTextSecondary,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),

            // Online dot (bottom right corner)
            Positioned(
              right: 5,
              bottom: 9,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: isOnline ? VibraTheme.kOnline : VibraTheme.kTextMuted,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
              ),
            ),

            // Verified badge (top right) — shown when user.isVerified
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
          ],
        ),
      ),
    );
  }

  /// Gradient placeholder shown when no profile photo is available.
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
