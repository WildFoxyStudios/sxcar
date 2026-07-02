import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../chat/chat_service.dart';
import '../presence/presence_service.dart';
import '../reports/report_service.dart';
import '../theme/app_theme.dart';
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
      await dio.post('/taps', data: {
        'to_user_id': widget.userId,
        'tap_type': 'wave',
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
        await dio.post('/blocks',
            data: {'user_id': widget.userId, 'reason': null});
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

  Future<void> _showReportSheet() async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: VibraTheme.kSurface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Report this user',
                style: TextStyle(
                  color: VibraTheme.kTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final r in kReportReasons)
              ListTile(
                title: Text(r,
                    style:
                        const TextStyle(color: VibraTheme.kTextPrimary)),
                onTap: () => Navigator.of(ctx).pop(r),
              ),
          ],
        ),
      ),
    );
    if (reason == null) return;
    try {
      await ref.read(reportServiceProvider).report(
            targetUserId: widget.userId,
            targetKind: 'profile',
            reason: reason,
          );
      messenger.showSnackBar(
        const SnackBar(content: Text('Report submitted. Thank you.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to submit report')),
      );
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
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
                  child: const Icon(Icons.error_outline,
                      size: 36, color: VibraTheme.kError),
                ),
                const SizedBox(height: 20),
                Text(_error!,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: VibraTheme.kTextPrimary),
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loadProfile,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final p = _profile!;
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Hero photo header ──────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 380,
            pinned: true,
            backgroundColor: Colors.black,
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Photo or placeholder
                  if (p.profilePhotoUrl != null)
                    Image.network(
                      p.profilePhotoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _buildPhotoPlaceholder(p),
                    )
                  else
                    _buildPhotoPlaceholder(p),
                  // Bottom gradient to fade into scaffold background
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 120,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xFF0D0D0D)],
                        ),
                      ),
                    ),
                  ),
                  // Verified badge overlay (top right of photo)
                  if (p.isVerified)
                    Positioned(
                      top: 60,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: VibraTheme.kAccent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified, color: Colors.black, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Verified',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Profile content ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name row + verified inline
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          p.displayName ?? p.email,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: VibraTheme.kTextPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (p.isVerified)
                        const Icon(Icons.verified,
                            color: VibraTheme.kAccent, size: 22),
                    ],
                  ),

                  // Age
                  if (p.birthdate != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _calculateAge(p.birthdate!),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: VibraTheme.kTextSecondary,
                      ),
                    ),
                  ],

                  // Presence badge (online dot + last-seen)
                  _PresenceBadge(userId: p.id),

                  const SizedBox(height: 20),

                  // ── Action bar ─────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: VibraTheme.kSurface,
                      borderRadius:
                          BorderRadius.circular(VibraTheme.kRadiusCard),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ActionButton(
                          icon: Icons.chat_bubble_outline,
                          label: 'Chat',
                          color: VibraTheme.kAccent,
                          onPressed: _startChat,
                        ),
                        _ActionButton(
                          icon: Icons.local_fire_department,
                          label: 'Tap',
                          color: Colors.deepOrange,
                          onPressed: _sendTap,
                        ),
                        _ActionButton(
                          icon: _isFavorited
                              ? Icons.star
                              : Icons.star_border_outlined,
                          label: 'Favorite',
                          color: _isFavorited
                              ? VibraTheme.kAccent
                              : VibraTheme.kTextSecondary,
                          onPressed: _toggleFavorite,
                        ),
                        _ActionButton(
                          icon: Icons.block,
                          label: 'Block',
                          color: _isBlocked
                              ? VibraTheme.kError
                              : VibraTheme.kTextSecondary,
                          onPressed: _toggleBlock,
                        ),
                        _ActionButton(
                          icon: Icons.flag_outlined,
                          label: 'Report',
                          color: VibraTheme.kTextMuted,
                          onPressed: _showReportSheet,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── About ──────────────────────────────────────────────────
                  if (p.bio != null && p.bio!.isNotEmpty) ...[
                    _sectionHeader('About'),
                    const SizedBox(height: 8),
                    Text(
                      p.bio!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: VibraTheme.kTextPrimary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Stats ──────────────────────────────────────────────────
                  _sectionHeader('Stats'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: VibraTheme.kSurface,
                      borderRadius:
                          BorderRadius.circular(VibraTheme.kRadiusCard),
                    ),
                    child: Column(
                      children: [
                        _buildStatTile(theme, 'Height',
                            p.heightCm != null ? '${p.heightCm} cm' : null,
                            Icons.height),
                        _buildStatTile(theme, 'Weight',
                            p.weightKg != null ? '${p.weightKg} kg' : null,
                            Icons.monitor_weight_outlined),
                        _buildStatTile(
                            theme, 'Body Type', p.bodyType, Icons.fitness_center),
                        _buildStatTile(theme, 'Relationship',
                            p.relationshipStatus, Icons.favorite_outline),
                        _buildStatTile(
                            theme, 'Position', p.position, Icons.sync_alt),
                        _buildStatTile(
                            theme, 'Ethnicity', p.ethnicity, Icons.people_outline),
                        _buildStatTile(
                            theme, 'Pronouns', p.pronouns, Icons.person_outline),
                      ].where((w) => w is! SizedBox).toList(),
                    ),
                  ),

                  // ── Tribes ────────────────────────────────────────────────
                  if (p.tribes.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _sectionHeader('Tribes'),
                    const SizedBox(height: 8),
                    _buildChipWrap(p.tribes, VibraTheme.kAccent),
                  ],

                  // ── Looking for ───────────────────────────────────────────
                  if (p.lookingFor.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _sectionHeader('Looking for'),
                    const SizedBox(height: 8),
                    _buildChipWrap(
                        p.lookingFor, VibraTheme.kTextSecondary),
                  ],

                  // ── Tags ──────────────────────────────────────────────────
                  if (p.tags.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _sectionHeader('Tags'),
                    const SizedBox(height: 8),
                    _buildChipWrap(p.tags, VibraTheme.kTextSecondary),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: VibraTheme.kTextMuted,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  /// Stat row inside the stats card — skipped when value is null/empty.
  Widget _buildStatTile(
      ThemeData theme, String label, String? value, IconData icon) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 16, color: VibraTheme.kTextMuted),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                    color: VibraTheme.kTextSecondary, fontSize: 13),
              ),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                    color: VibraTheme.kTextPrimary, fontSize: 13),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: VibraTheme.kDivider, indent: 44),
      ],
    );
  }

  Widget _buildChipWrap(List<String> items, Color accent) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(VibraTheme.kRadiusChip),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Text(
            item,
            style: TextStyle(
              color: accent == VibraTheme.kAccent
                  ? VibraTheme.kAccent
                  : VibraTheme.kTextPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPhotoPlaceholder(UserProfile p) {
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
          (p.displayName ?? p.email)[0].toUpperCase(),
          style: const TextStyle(
            fontSize: 80,
            color: VibraTheme.kTextMuted,
            fontWeight: FontWeight.bold,
          ),
        ),
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

/// Icon + label action button used in the profile action bar.
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
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small badge showing online / last-seen status for a user. Uses the
/// `userStatusProvider` family from the presence module.
class _PresenceBadge extends ConsumerWidget {
  final String userId;

  const _PresenceBadge({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(userStatusProvider(userId));
    return statusAsync.when(
      loading: () => const SizedBox(height: 20),
      error: (_, _) => const SizedBox(height: 20),
      data: (status) {
        final label = formatLastSeen(status);
        if (label.isEmpty) return const SizedBox(height: 20);
        final color =
            status.isOnline ? VibraTheme.kOnline : VibraTheme.kTextMuted;
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(color: color, fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }
}
