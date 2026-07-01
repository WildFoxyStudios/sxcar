import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';

/// Model for a tap received from another user.
class ReceivedTap {
  final String id;
  final String senderId;
  final String? senderDisplayName;
  final String? senderPhotoUrl;
  final String kind;
  final String createdAt;

  const ReceivedTap({
    required this.id,
    required this.senderId,
    this.senderDisplayName,
    this.senderPhotoUrl,
    required this.kind,
    required this.createdAt,
  });

  factory ReceivedTap.fromJson(Map<String, dynamic> json) {
    return ReceivedTap(
      id: json['id'] as String,
      senderId: json['sender_id'] as String,
      senderDisplayName: json['sender_display_name'] as String?,
      senderPhotoUrl: json['sender_photo_url'] as String?,
      kind: json['kind'] as String? ?? '👋',
      createdAt: json['created_at'] as String,
    );
  }
}

/// Model for a favorited user.
class FavoriteUser {
  final String id;
  final String userId;
  final String? displayName;
  final String? photoUrl;

  const FavoriteUser({
    required this.id,
    required this.userId,
    this.displayName,
    this.photoUrl,
  });

  factory FavoriteUser.fromJson(Map<String, dynamic> json) {
    return FavoriteUser(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String?,
      photoUrl: json['photo_url'] as String?,
    );
  }
}

/// Interest screen combining Taps (received) and Favorites.
class InterestScreen extends ConsumerStatefulWidget {
  const InterestScreen({super.key});

  @override
  ConsumerState<InterestScreen> createState() => _InterestScreenState();
}

class _InterestScreenState extends ConsumerState<InterestScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Future<List<ReceivedTap>> _tapsFuture;
  late Future<List<FavoriteUser>> _favoritesFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tapsFuture = _fetchTaps();
    _favoritesFuture = _fetchFavorites();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<List<ReceivedTap>> _fetchTaps() async {
    final dio = ref.read(dioProvider);
    final response =
        await dio.get<Map<String, dynamic>>('/taps/received');
    final data = response.data!;
    final tapsJson = data['taps'] as List<dynamic>;
    return tapsJson
        .map((t) => ReceivedTap.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  Future<List<FavoriteUser>> _fetchFavorites() async {
    final dio = ref.read(dioProvider);
    final response = await dio.get<Map<String, dynamic>>('/favorites');
    final data = response.data!;
    final favsJson = data['favorites'] as List<dynamic>;
    return favsJson
        .map((f) => FavoriteUser.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Interest'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: theme.colorScheme.primary,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Taps'),
            Tab(text: 'Favorites'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTapsList(theme),
          _buildFavoritesList(theme),
        ],
      ),
    );
  }

  Widget _buildTapsList(ThemeData theme) {
    return FutureBuilder<List<ReceivedTap>>(
      future: _tapsFuture,
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
                const Text('Failed to load taps'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => setState(() {
                    _tapsFuture = _fetchTaps();
                  }),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final taps = snapshot.data ?? [];
        if (taps.isEmpty) {
          return const Center(child: Text('No taps yet'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(8),
          itemCount: taps.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final tap = taps[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.grey.shade800,
                child: Text(
                  tap.kind,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              title: Text(tap.senderDisplayName ?? 'Unknown'),
              subtitle: Text(tap.kind),
              onTap: () => context.push('/profile/${tap.senderId}'),
            );
          },
        );
      },
    );
  }

  Widget _buildFavoritesList(ThemeData theme) {
    return FutureBuilder<List<FavoriteUser>>(
      future: _favoritesFuture,
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
                const Text('Failed to load favorites'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => setState(() {
                    _favoritesFuture = _fetchFavorites();
                  }),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final favorites = snapshot.data ?? [];
        if (favorites.isEmpty) {
          return const Center(child: Text('No favorites yet'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(8),
          itemCount: favorites.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final fav = favorites[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.grey.shade800,
                child: Text(
                  (fav.displayName ?? '?')[0].toUpperCase(),
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(fav.displayName ?? 'Unknown'),
              trailing: const Icon(Icons.star, color: Color(0xFFF4C542)),
              onTap: () => context.push('/profile/${fav.userId}'),
            );
          },
        );
      },
    );
  }
}
