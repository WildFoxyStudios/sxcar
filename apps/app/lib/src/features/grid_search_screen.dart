import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../location/location_service.dart';
import '../places/places_service.dart';
import '../places/roam_service.dart';
import '../../l10n/gen/app_localizations.dart';
import '../settings/settings_providers.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'cascade_screen.dart' show NearbyUser;

/// Explore — global user grid with Roam support backed by real places.
class GridSearchScreen extends ConsumerStatefulWidget {
  const GridSearchScreen({super.key});

  @override
  ConsumerState<GridSearchScreen> createState() => _GridSearchScreenState();
}

class _GridSearchScreenState extends ConsumerState<GridSearchScreen> {
  late Future<List<NearbyUser>> _globalUsersFuture;
  final TextEditingController _searchController = TextEditingController();

  // Roam location state — defaults used until /me/location is fetched.
  double _roamLat = 19.4326;
  double _roamLon = -99.1332;
  bool _isRoam = false;
  String _roamName = '';
  bool _hasAppliedPersistedRoam = false;

  @override
  void initState() {
    super.initState();
    _globalUsersFuture = _fetchGlobalUsers();
    _applyRealLocationDefault();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Re-run the global query with the current search text.
  void _applySearch() {
    setState(() {
      _globalUsersFuture = _fetchGlobalUsers();
    });
  }

  /// On first load, if the user has NOT set a persisted Roam location, use the
  /// device's real GPS as the default center instead of the hardcoded fallback.
  Future<void> _applyRealLocationDefault() async {
    final pos = await ref.read(currentPositionProvider.future);
    if (pos == null || !mounted) return;
    // Roam-persisted location (applied via ref.listen in build) wins.
    if (_hasAppliedPersistedRoam && _isRoam) return;
    setState(() {
      _roamLat = pos.latitude;
      _roamLon = pos.longitude;
      _globalUsersFuture = _fetchGlobalUsers(lat: pos.latitude, lon: pos.longitude);
    });
  }

  Future<List<NearbyUser>> _fetchGlobalUsers({double? lat, double? lon}) async {
    final dio = ref.read(dioProvider);
    final queryParams = <String, dynamic>{
      'lat': lat ?? _roamLat,
      'lon': lon ?? _roamLon,
      'radius_m': 500000,
      'limit': 50,
    };
    final q = _searchController.text.trim();
    if (q.isNotEmpty) queryParams['q'] = q;

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

  /// Apply a new roam location and refresh the grid.
  void _applyRoam({
    required double lat,
    required double lon,
    String? name,
    bool isRoam = true,
  }) {
    setState(() {
      _roamLat = lat;
      _roamLon = lon;

      _roamName = name ?? '';
      _isRoam = isRoam;
      _globalUsersFuture = _fetchGlobalUsers(lat: lat, lon: lon);
    });
  }

  void _showRoamSheet() {
    final outerMessenger = ScaffoldMessenger.of(context);
    final outerContext = context;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VibraTheme.kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _RoamBottomSheet(
        onPickPlace: (place) async {
          try {
            final roam = ref.read(roamServiceProvider);
            await roam.set(
              lat: place.lat,
              lon: place.lon,
              name: place.name,
              isRoam: true,
            );
            ref.invalidate(roamLocationProvider);
            if (!outerContext.mounted) return;
            Navigator.of(ctx).pop();
            _applyRoam(
              lat: place.lat,
              lon: place.lon,
              name: place.name,
              isRoam: true,
            );
            outerMessenger.showSnackBar(
              SnackBar(content: Text('Roaming to ${place.name}')),
            );
          } catch (e) {
            if (outerContext.mounted) {
              outerMessenger.showSnackBar(
                SnackBar(
                  content: Text('Failed to set roam: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
        onUseRealLocation: () async {
          // Read the device's REAL GPS position (falls back to last-known
          // inside the provider). If unavailable, keep whatever we had.
          try {
            final pos = await ref.read(currentPositionProvider.future);
            if (pos == null) {
              if (outerContext.mounted) {
                Navigator.of(ctx).pop();
                outerMessenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Location unavailable — enable GPS permission in settings'),
                  ),
                );
              }
              return;
            }
            final lat = pos.latitude;
            final lon = pos.longitude;
            final roam = ref.read(roamServiceProvider);
            await roam.setRealLocation(lat: lat, lon: lon);
            ref.invalidate(roamLocationProvider);
            if (!outerContext.mounted) return;
            Navigator.of(ctx).pop();
            _applyRoam(lat: lat, lon: lon, name: '', isRoam: false);
            outerMessenger.showSnackBar(
              const SnackBar(content: Text('Using your real location')),
            );
          } catch (e) {
            if (outerContext.mounted) {
              outerMessenger.showSnackBar(
                SnackBar(
                  content: Text('Failed: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Load persisted roam on first build, then apply once.
    ref.listen<AsyncValue<RoamLocation?>>(roamLocationProvider, (prev, next) {
      if (_hasAppliedPersistedRoam) return;
      if (next is AsyncData<RoamLocation?>) {
        _hasAppliedPersistedRoam = true;
        final loc = next.value;
        if (loc != null) {
          _applyRoam(
            lat: loc.lat,
            lon: loc.lon,
            name: loc.name,
            isRoam: loc.isRoam,
          );
        }
      }
    });

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        backgroundColor: VibraTheme.kBg,
        titleSpacing: 0,
        title: Container(
          height: 44,
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: VibraTheme.kChip,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText:
                        AppLocalizations.of(context)!.explorarMasPerfiles,
                    hintStyle:
                        const TextStyle(color: VibraTheme.kTextSecondary),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _applySearch(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          // When roaming, surface the active location name so the user knows
          // the grid is NOT centered on their real position.
          if (_isRoam && _roamName.isNotEmpty)
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: VibraTheme.kChip,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _roamName,
                  style: const TextStyle(
                      color: VibraTheme.kYellow,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          IconButton(
            icon: Icon(
              Icons.explore_outlined,
              color: _isRoam ? VibraTheme.kYellow : Colors.white,
            ),
            tooltip: 'Roam',
            onPressed: _showRoamSheet,
          ),
        ],
      ),
      body: _buildGrid(theme),
    );
  }

  Widget _buildGrid(ThemeData theme) {
    return FutureBuilder<List<NearbyUser>>(
        future: _globalUsersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load global users',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => setState(() {
                      _globalUsersFuture = _fetchGlobalUsers();
                    }),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final users = snapshot.data ?? [];
          if (users.isEmpty) {
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
                        Icons.explore_outlined,
                        size: 36,
                        color: VibraTheme.kAccent,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No users found in this area',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: VibraTheme.kTextPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try roaming to a different location!',
                      style: VibraTheme.bodySecondary,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => setState(() {
              _globalUsersFuture = _fetchGlobalUsers();
            }),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.zero,
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.91,
                          crossAxisSpacing: 1.5,
                          mainAxisSpacing: 1.5,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final user = users[index];
                            // T5.10: read units once per build, pass to every
                            // tile. Using `ref` is fine here — this is inside a
                            // `ConsumerStatefulWidget` State.build.
                            final units = ref.watch(unitsProvider);
                            return _ExploreUserCard(user: user, units: units);
                          },
                          childCount: users.length,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );
  }

}



/// Full-bleed photo card matching the Cascade grid style (no online dot
/// since Explore shows global users where real-time status is less relevant).
class _ExploreUserCard extends StatelessWidget {
  final NearbyUser user;
  final int units; // 0=metric, 1=imperial (from unitsProvider)

  const _ExploreUserCard({required this.user, required this.units});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/profile/${user.id}'),
      child: ClipRRect(
        borderRadius: BorderRadius.zero,
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

            // Bottom gradient scrim
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

            // Name + distance overlay (bottom)
            Positioned(
              left: 6,
              right: 6,
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
                    user.distanceLabel(units),
                    style: const TextStyle(
                      color: VibraTheme.kTextSecondary,
                      fontSize: 9,
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
                  child: const Icon(Icons.check, color: Colors.black, size: 11),
                ),
              ),

            // NUEVO badge (top left) — T5.10: shown for accounts < 7 days old.
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

/// Roam bottom sheet: lists saved places + add-new form + use-real button.
class _RoamBottomSheet extends ConsumerStatefulWidget {
  final void Function(Place place) onPickPlace;
  final VoidCallback onUseRealLocation;

  const _RoamBottomSheet({
    required this.onPickPlace,
    required this.onUseRealLocation,
  });

  @override
  ConsumerState<_RoamBottomSheet> createState() => _RoamBottomSheetState();
}

class _RoamBottomSheetState extends ConsumerState<_RoamBottomSheet> {
  bool _showAddForm = false;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _latController = TextEditingController();
  final _lonController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  Future<void> _submitNewPlace() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final lat = double.tryParse(_latController.text.trim());
    final lon = double.tryParse(_lonController.text.trim());
    if (lat == null || lon == null) return;

    setState(() => _submitting = true);
    try {
      final service = ref.read(placesServiceProvider);
      final place = await service.add(_nameController.text.trim(), lat, lon);
      ref.invalidate(placesProvider);
      if (!mounted) return;
      setState(() {
        _showAddForm = false;
        _nameController.clear();
        _latController.clear();
        _lonController.clear();
      });
      widget.onPickPlace(place);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add place: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placesAsync = ref.watch(placesProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.explore, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Roam',
                    style: theme.textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Choose a saved place or use your real location.',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: widget.onUseRealLocation,
                icon: const Icon(Icons.my_location),
                label: const Text('Use real location'),
              ),
              const SizedBox(height: 16),
              const Divider(color: VibraTheme.kDivider),
              const SizedBox(height: 8),
              placesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Failed to load places: $e',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
                data: (places) {
                  if (places.isEmpty && !_showAddForm) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No saved places yet.',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  if (places.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    children: places
                        .map(
                          (p) => ListTile(
                            leading: const Icon(Icons.place, color: Colors.white70),
                            title: Text(p.name),
                            subtitle: Text(
                              '${p.lat.toStringAsFixed(4)}, ${p.lon.toStringAsFixed(4)}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            onTap: () => widget.onPickPlace(p),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 8),
              if (!_showAddForm)
                TextButton.icon(
                  onPressed: () => setState(() => _showAddForm = true),
                  icon: const Icon(Icons.add),
                  label: const Text('Add new place'),
                )
              else
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _latController,
                        decoration: const InputDecoration(
                          labelText: 'Latitude',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        validator: (v) {
                          final n = double.tryParse((v ?? '').trim());
                          if (n == null) return 'Must be a number';
                          if (n < -90 || n > 90) return 'Range: -90..90';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _lonController,
                        decoration: const InputDecoration(
                          labelText: 'Longitude',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        validator: (v) {
                          final n = double.tryParse((v ?? '').trim());
                          if (n == null) return 'Must be a number';
                          if (n < -180 || n > 180) return 'Range: -180..180';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _submitting
                                  ? null
                                  : () => setState(() {
                                        _showAddForm = false;
                                        _nameController.clear();
                                        _latController.clear();
                                        _lonController.clear();
                                      }),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed:
                                  _submitting ? null : _submitNewPlace,
                              child: _submitting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Add & Roam'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
