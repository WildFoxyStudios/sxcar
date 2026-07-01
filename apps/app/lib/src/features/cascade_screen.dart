import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';

/// Model for a user in the cascade grid.
class NearbyUser {
  final String id;
  final String email;
  final String? displayName;
  final String? bio;
  final String? profilePhotoId;
  final double distanceM;

  const NearbyUser({
    required this.id,
    required this.email,
    this.displayName,
    this.bio,
    this.profilePhotoId,
    required this.distanceM,
  });

  factory NearbyUser.fromJson(Map<String, dynamic> json) {
    return NearbyUser(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String?,
      bio: json['bio'] as String?,
      profilePhotoId: json['profile_photo_id'] as String?,
      distanceM: (json['distance_m'] as num).toDouble(),
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
/// Replaces the old NearbyScreen. Each card shows a photo placeholder,
/// display name, distance, and a green online indicator dot.
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

  @override
  void initState() {
    super.initState();
    _nearbyUsersFuture = _fetchNearbyUsers();
  }

  Future<List<NearbyUser>> _fetchNearbyUsers() async {
    final dio = ref.read(dioProvider);
    const lat = 19.4326;
    const lon = -99.1332;
    const radiusM = 5000;

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
      _nearbyUsersFuture = _fetchNearbyUsers();
    });
  }

  /// Build the active filter chips summary bar below the AppBar title.
  bool get _hasActiveFilters =>
      _ageRange.start > 18 ||
      _ageRange.end < 99 ||
      _selectedTribes.isNotEmpty ||
      _bodyType != null ||
      _lookingFor != null ||
      _searchQuery.isNotEmpty;

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
          // Active filter chips summary
          if (_hasActiveFilters)
            Container(
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
            ),
          // User grid
          Expanded(
            child: FutureBuilder<List<NearbyUser>>(
              future: _nearbyUsersFuture,
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
                          'Failed to load nearby users',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _refresh,
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
                          Icon(Icons.public, size: 64, color: Colors.grey.shade600),
                          const SizedBox(height: 16),
                          Text(
                            'No one nearby yet',
                            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Try Explore to see people everywhere!',
                            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
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
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    // Local copies so changes are discarded on Cancel
    RangeValues localAge = _ageRange;
    Set<String> localTribes = Set.from(_selectedTribes);
    String? localBodyType = _bodyType;
    String? localLookingFor = _lookingFor;
    final searchController = TextEditingController(text: _searchQuery);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
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

                // --- Age range slider ---
                Text('Age Range: ${localAge.start.round()} - ${localAge.end.round()}',
                    style: Theme.of(context).textTheme.bodyMedium),
                RangeSlider(
                  values: localAge,
                  min: 18,
                  max: 99,
                  divisions: 81,
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
                      selectedColor: Theme.of(context).colorScheme.primary.withAlpha(80),
                      checkmarkColor: Colors.white,
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

class _UserCard extends StatelessWidget {
  final NearbyUser user;
  final VoidCallback onTap;

  const _UserCard({required this.user, required this.onTap});

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
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Photo area
            Expanded(
              child: Stack(
                children: [
                  Container(
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
                  // Online indicator dot
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Info area
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
                  Row(
                    children: [
                      Icon(Icons.location_on,
                          size: 10, color: Colors.grey.shade500),
                      const SizedBox(width: 2),
                      Text(
                        user.distanceText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.green,
                          fontSize: 10,
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
    );
  }
}
