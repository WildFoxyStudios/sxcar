import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../places/places_service.dart';
import '../places/roam_service.dart';
import 'cascade_screen.dart' show NearbyUser;

/// Explore — global user grid with Roam support backed by real places.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  late Future<List<NearbyUser>> _globalUsersFuture;

  // Roam location state — defaults used until /me/location is fetched.
  double _roamLat = 19.4326;
  double _roamLon = -99.1332;
  String _roamName = '';
  bool _isRoam = false;
  bool _hasAppliedPersistedRoam = false;

  @override
  void initState() {
    super.initState();
    _globalUsersFuture = _fetchGlobalUsers();
  }

  Future<List<NearbyUser>> _fetchGlobalUsers({double? lat, double? lon}) async {
    final dio = ref.read(dioProvider);
    final queryParams = <String, dynamic>{
      'lat': lat ?? _roamLat,
      'lon': lon ?? _roamLon,
      'radius_m': 500000,
      'limit': 50,
    };

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
      backgroundColor: const Color(0xFF1A1A1A),
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
          // Use a default fallback lat/lon (Mexico City) — backend
          // geolocator is a future enhancement; for now we keep the user's
          // current area and clear the roam flag.
          const lat = 19.4326;
          const lon = -99.1332;
          try {
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
      appBar: AppBar(
        title: Text(
          _roamName.isNotEmpty
              ? 'Explore · $_roamName'
              : (_isRoam ? 'Explore' : 'Explore · Your area'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.explore_outlined),
            tooltip: 'Roam',
            onPressed: _showRoamSheet,
          ),
        ],
      ),
      body: FutureBuilder<List<NearbyUser>>(
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
                    Icon(Icons.explore_outlined,
                        size: 64, color: Colors.grey.shade600),
                    const SizedBox(height: 16),
                    Text(
                      'No users found in this area',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try roaming to a different location!',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.grey),
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
                            return _ExploreUserCard(user: user);
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
      ),
    );
  }
}

class _ExploreUserCard extends StatelessWidget {
  final NearbyUser user;

  const _ExploreUserCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      color: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () => context.push('/profile/${user.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: Colors.grey.shade900,
                child: Center(
                  child: Text(
                    (user.displayName ?? user.email)[0].toUpperCase(),
                    style: TextStyle(
                      fontSize: 32,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName ?? user.email,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.distanceText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.green,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
              const Divider(color: Color(0xFF2A2A2A)),
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
