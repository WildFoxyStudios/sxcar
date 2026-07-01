import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import 'albums_screen.dart' show Album;
import 'profile_screen.dart' show UserProfile;

/// You screen — own profile + albums + settings + logout.
class YouScreen extends ConsumerStatefulWidget {
  const YouScreen({super.key});

  @override
  ConsumerState<YouScreen> createState() => _YouScreenState();
}

class _YouScreenState extends ConsumerState<YouScreen> {
  UserProfile? _profile;
  List<Album>? _albums;
  bool _isLoadingProfile = true;
  bool _isLoadingAlbums = true;
  String? _profileError;
  String? _albumsError;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadAlbums();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoadingProfile = true;
      _profileError = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get<Map<String, dynamic>>('/profile');
      final userJson = response.data!['user'] as Map<String, dynamic>;
      final profile = UserProfile.fromJson(userJson);

      setState(() {
        _profile = profile;
        _isLoadingProfile = false;
      });
    } on DioException catch (e) {
      setState(() {
        _isLoadingProfile = false;
        _profileError =
            'Failed to load profile: ${e.response?.statusCode ?? e.message}';
      });
    } catch (e) {
      setState(() {
        _isLoadingProfile = false;
        _profileError = 'Failed to load profile: $e';
      });
    }
  }

  Future<void> _loadAlbums() async {
    setState(() {
      _isLoadingAlbums = true;
      _albumsError = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get<Map<String, dynamic>>('/albums');
      final albumsJson = response.data!['albums'] as List<dynamic>;
      final albums = albumsJson
          .map((a) => Album.fromJson(a as Map<String, dynamic>))
          .toList();

      setState(() {
        _albums = albums;
        _isLoadingAlbums = false;
      });
    } on DioException catch (e) {
      setState(() {
        _isLoadingAlbums = false;
        _albumsError =
            'Failed to load albums: ${e.response?.statusCode ?? e.message}';
      });
    } catch (e) {
      setState(() {
        _isLoadingAlbums = false;
        _albumsError = 'Failed to load albums: $e';
      });
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authStateProvider.notifier).logout();
    }
  }

  void _deleteAccount() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete Account'),
        content: const Text('This feature is not yet available.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('You'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile section
          _buildProfileSection(theme, authState),
          const SizedBox(height: 24),

          // Edit Profile button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/edit-profile'),
              icon: const Icon(Icons.edit),
              label: const Text('Edit Profile'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                side: BorderSide(color: theme.colorScheme.primary),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Albums section header
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'MY ALBUMS',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
          ),

          // Albums mini-grid
          _buildAlbumsGrid(theme),
          const SizedBox(height: 24),

          // Settings section header
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'SETTINGS',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
          ),

          // Settings list
          Card(
            color: const Color(0xFF1A1A1A),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    'Logout',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: _logout,
                ),
                const Divider(height: 1, color: Color(0xFF2A2A2A)),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text(
                    'Delete Account',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: _deleteAccount,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection(ThemeData theme, AuthState authState) {
    if (_isLoadingProfile) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_profileError != null) {
      return Center(
        child: Column(
          children: [
            Text(_profileError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadProfile,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Profile photo
        CircleAvatar(
          radius: 48,
          backgroundColor: Colors.grey.shade800,
          child: Text(
            (_profile?.displayName ?? authState.email ?? 'U')[0].toUpperCase(),
            style: TextStyle(
              fontSize: 32,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Display name
        if (_profile?.displayName != null)
          Text(
            _profile!.displayName!,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),

        // Email
        Text(
          authState.email ?? (_profile?.email ?? 'User'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.grey,
          ),
        ),

        // Bio
        if (_profile?.bio != null && _profile!.bio!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _profile!.bio!,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildAlbumsGrid(ThemeData theme) {
    if (_isLoadingAlbums) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_albumsError != null) {
      return Text(
        _albumsError!,
        style: const TextStyle(color: Colors.red, fontSize: 12),
      );
    }

    final albums = _albums ?? [];
    if (albums.isEmpty) {
      return GestureDetector(
        onTap: () => context.push('/albums'),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              'Tap to manage albums',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 120,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: albums.length.clamp(0, 6),
        itemBuilder: (context, index) {
          final album = albums[index];
          return GestureDetector(
            onTap: () => context.push('/albums/${album.id}'),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  album.name ?? 'Album',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
