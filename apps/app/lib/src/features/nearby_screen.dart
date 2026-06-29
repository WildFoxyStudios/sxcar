import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby')),
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
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _nearbyUsersFuture = _fetchNearbyUsers();
                      });
                    },
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

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final user = users[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    (user.displayName ?? user.email)[0].toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                title: Text(user.displayName ?? user.email),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (user.bio != null && user.bio!.isNotEmpty)
                      Text(
                        user.bio!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      user.distanceText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
