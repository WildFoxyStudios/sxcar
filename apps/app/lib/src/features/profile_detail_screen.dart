import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../chat/chat_service.dart';
import 'profile_screen.dart' show UserProfile;

/// Full-screen profile of another user with action buttons.
///
/// Accessed by tapping a user card in Cascade, Interest, or Explore.
class ProfileDetailScreen extends ConsumerStatefulWidget {
  final String userId;

  const ProfileDetailScreen({super.key, required this.userId});

  @override
  ConsumerState<ProfileDetailScreen> createState() =>
      _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends ConsumerState<ProfileDetailScreen> {
  UserProfile? _profile;
  bool _isLoading = true;
  String? _error;
  bool _isFavorited = false;
  bool _isBlocked = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final response = await dio
          .get<Map<String, dynamic>>('/profile/${widget.userId}');
      final userJson = response.data!['user'] as Map<String, dynamic>;
      final profile = UserProfile.fromJson(userJson);

      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _isLoading = false;
        _error =
            'Failed to load profile: ${e.response?.statusCode ?? e.message}';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to load profile: $e';
      });
    }
  }

  Future<void> _sendTap() async {
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/taps/send', data: {
        'recipient_id': widget.userId,
        'kind': '👋',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tap sent!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send tap: $e')),
        );
      }
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      final dio = ref.read(dioProvider);
      if (_isFavorited) {
        await dio.delete('/favorites/${widget.userId}');
      } else {
        await dio.post('/favorites', data: {'user_id': widget.userId});
      }
      setState(() => _isFavorited = !_isFavorited);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _toggleBlock() async {
    try {
      final dio = ref.read(dioProvider);
      if (_isBlocked) {
        await dio.delete('/blocks/${widget.userId}');
      } else {
        await dio.post('/blocks', data: {'blocked_user_id': widget.userId});
      }
      setState(() => _isBlocked = !_isBlocked);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isBlocked ? 'User blocked' : 'User unblocked'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _startChat() async {
    try {
      final chatService = ref.read(chatServiceProvider);
      final conversationId =
          await chatService.createConversation(widget.userId);
      if (mounted) {
        context.push('/inbox/$conversationId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start chat: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadProfile,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final p = _profile!;
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Photo header
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: Colors.black,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: Colors.grey.shade900,
                child: Center(
                  child: Text(
                    (p.displayName ?? p.email)[0].toUpperCase(),
                    style: TextStyle(
                      fontSize: 64,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name and age
                  Text(
                    p.displayName ?? p.email,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (p.birthdate != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _calculateAge(p.birthdate!),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Action buttons row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ActionButton(
                        icon: Icons.chat,
                        label: 'Chat',
                        color: theme.colorScheme.primary,
                        onPressed: _startChat,
                      ),
                      _ActionButton(
                        icon: Icons.local_fire_department,
                        label: 'Tap',
                        color: Colors.orange,
                        onPressed: _sendTap,
                      ),
                      _ActionButton(
                        icon: _isFavorited ? Icons.star : Icons.star_border,
                        label: 'Favorite',
                        color: _isFavorited
                            ? const Color(0xFFF4C542)
                            : Colors.grey,
                        onPressed: _toggleFavorite,
                      ),
                      _ActionButton(
                        icon: _isBlocked ? Icons.block : Icons.block,
                        label: 'Block',
                        color: _isBlocked ? Colors.red : Colors.grey,
                        onPressed: _toggleBlock,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // About section
                  if (p.bio != null && p.bio!.isNotEmpty) ...[
                    Text(
                      'About',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(p.bio!, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 16),
                  ],

                  // Stats
                  Text(
                    'Stats',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildStatRow(theme, 'Height',
                      p.heightCm != null ? '${p.heightCm} cm' : null),
                  _buildStatRow(theme, 'Weight',
                      p.weightKg != null ? '${p.weightKg} kg' : null),
                  _buildStatRow(theme, 'Body Type', p.bodyType),
                  _buildStatRow(theme, 'Relationship', p.relationshipStatus),
                  _buildStatRow(theme, 'Position', p.position),
                  _buildStatRow(theme, 'Ethnicity', p.ethnicity),
                  _buildStatRow(theme, 'Pronouns', p.pronouns),

                  if (p.tribes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Tribes',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: p.tribes
                          .map((t) => Chip(
                                label: Text(t),
                                backgroundColor: Colors.grey.shade800,
                                labelStyle: const TextStyle(color: Colors.white),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ))
                          .toList(),
                    ),
                  ],

                  if (p.lookingFor.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Looking for',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: p.lookingFor
                          .map((t) => Chip(
                                label: Text(t),
                                backgroundColor: Colors.grey.shade800,
                                labelStyle: const TextStyle(color: Colors.white),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ))
                          .toList(),
                    ),
                  ],

                  if (p.tags.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Tags',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: p.tags
                          .map((t) => Chip(
                                label: Text(t),
                                backgroundColor: Colors.grey.shade800,
                                labelStyle: const TextStyle(color: Colors.white),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ))
                          .toList(),
                    ),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(ThemeData theme, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  String _calculateAge(String birthdate) {
    try {
      final parts = birthdate.split('-');
      if (parts.length != 3) return '';
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);
      final now = DateTime.now();
      var age = now.year - year;
      if (now.month < month ||
          (now.month == month && now.day < day)) {
        age--;
      }
      return '$age years old';
    } catch (_) {
      return '';
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon, color: color),
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.1),
            padding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
