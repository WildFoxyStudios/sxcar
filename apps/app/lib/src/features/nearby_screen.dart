import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';

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

class NearbyScreen extends ConsumerStatefulWidget {
  const NearbyScreen({super.key});

  @override
  ConsumerState<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends ConsumerState<NearbyScreen> {
  late Future<List<NearbyUser>> _nearbyUsersFuture;

  @override
  void initState() {
    super.initState();
    _nearbyUsersFuture = _fetchNearbyUsers();
  }

  Future<List<NearbyUser>> _fetchNearbyUsers() async {
    final dio = ref.read(dioProvider);
    // Default location: Mexico City (same as test coordinates)
    const lat = 19.4326;
    const lon = -99.1332;
    const radiusM = 5000;

    final response = await dio.get<Map<String, dynamic>>(
      '/grid/nearby',
      queryParameters: {
        'lat': lat,
        'lon': lon,
        'radius_m': radiusM,
        'limit': 50,
      },
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Vibra',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: Color(0xFFFF6B00),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Search coming soon')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterSheet(context),
          ),
        ],
      ),
      body: FutureBuilder<List<NearbyUser>>(
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
            return const Center(
              child: Text('No users found nearby'),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
                return GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return _NearbyUserCard(user: user);
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
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
            const Text('Age range and tribe filters coming soon.'),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NearbyUserCard extends StatelessWidget {
  final NearbyUser user;

  const _NearbyUserCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/profile/${user.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Photo area
            Expanded(
              child: Container(
                color: theme.colorScheme.primaryContainer
                    .withValues(alpha: 0.3),
                child: _buildAvatar(theme),
              ),
            ),
            // Info area
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName ?? user.email,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 12, color: Colors.grey),
                      const SizedBox(width: 2),
                      Text(
                        user.distanceText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                      const Spacer(),
                      // Online indicator dot
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
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

  Widget _buildAvatar(ThemeData theme) {
    // TODO: Show profile photo when URL is available
    // Use: Image.network('$apiUrl/photos/${user.profilePhotoId}', fit: BoxFit.cover)
    return Center(
      child: Text(
        (user.displayName ?? user.email)[0].toUpperCase(),
        style: TextStyle(
          fontSize: 32,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
