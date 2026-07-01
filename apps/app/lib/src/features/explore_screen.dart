import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import 'cascade_screen.dart' show NearbyUser;

/// Explore — global user grid with larger radius and Roam stub.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  late Future<List<NearbyUser>> _globalUsersFuture;

  @override
  void initState() {
    super.initState();
    _globalUsersFuture = _fetchGlobalUsers();
  }

  Future<List<NearbyUser>> _fetchGlobalUsers({double? lat, double? lon}) async {
    final dio = ref.read(dioProvider);
    final queryParams = <String, dynamic>{
      'lat': lat ?? 19.4326,
      'lon': lon ?? -99.1332,
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

  void _showRoamDialog() {
    final latController = TextEditingController();
    final lonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Roam'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter coordinates to explore a different location.'),
            const SizedBox(height: 16),
            TextField(
              controller: latController,
              decoration: const InputDecoration(
                labelText: 'Latitude',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lonController,
              decoration: const InputDecoration(
                labelText: 'Longitude',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final lat = double.tryParse(latController.text);
              final lon = double.tryParse(lonController.text);
              if (lat != null && lon != null) {
                Navigator.of(ctx).pop();
                setState(() {
                  _globalUsersFuture = _fetchGlobalUsers(lat: lat, lon: lon);
                });
              }
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore'),
        actions: [
          IconButton(
            icon: const Icon(Icons.explore_outlined),
            tooltip: 'Roam',
            onPressed: _showRoamDialog,
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
            return const Center(child: Text('No users found'));
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
