import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../boost/boost_service.dart';
import '../profile_views/viewed_me_provider.dart';
import '../theme/app_theme.dart';
import 'profile_screen.dart' show UserProfile;

/// You screen — own profile, stats, tribes, settings, logout.
class YouScreen extends ConsumerStatefulWidget {
  const YouScreen({super.key});

  @override
  ConsumerState<YouScreen> createState() => _YouScreenState();
}

class _YouScreenState extends ConsumerState<YouScreen> {
  UserProfile? _profile;
  bool _isLoading = true;
  String? _error;

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
      final response = await dio.get<Map<String, dynamic>>('/profile');
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

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VibraTheme.kSurface,
        title: const Text('Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Logout',
                style: TextStyle(color: VibraTheme.kError)),
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
        backgroundColor: VibraTheme.kSurface,
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

  int? _calculateAge(String? birthdate) {
    if (birthdate == null) return null;
    try {
      final parts = birthdate.split('-');
      if (parts.length != 3) return null;
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);
      final now = DateTime.now();
      var age = now.year - year;
      if (now.month < month || (now.month == month && now.day < day)) {
        age--;
      }
      return age;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('You'),
      ),
      body: _buildBody(theme, authState),
    );
  }

  Widget _buildBody(ThemeData theme, AuthState authState) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                style: TextStyle(color: Colors.red.shade300, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadProfile,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final p = _profile!;
    final emailPrefix = p.email.split('@').first;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Profile photo
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Center(
              child: CircleAvatar(
                radius: 60,
                backgroundColor: VibraTheme.kSurface,
                backgroundImage: p.profilePhotoUrl != null
                    ? NetworkImage(p.profilePhotoUrl!)
                    : null,
                child: p.profilePhotoUrl == null
                    ? Text(
                        (p.displayName ?? emailPrefix)[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 40,
                          color: VibraTheme.kAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
            ),
            const _BoostBadge(),
          ],
        ),
        const SizedBox(height: 16),

        // Display name
        if (p.displayName != null && p.displayName!.isNotEmpty)
          Text(
            p.displayName!,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),

        // Email
        Text(
          '@$emailPrefix',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.grey,
            fontSize: 13,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 12),

        // Boost button
        Center(
          child: const _BoostButton(),
        ),

        // Bio
        if (p.bio != null && p.bio!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            p.bio!,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],

        const SizedBox(height: 20),

        // Stats chips
        _buildStatsChips(theme, p),
        const SizedBox(height: 16),

        // Tribes chips
        if (p.tribes.isNotEmpty) ...[
          _buildTribesChips(theme, p),
          const SizedBox(height: 16),
        ],

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

        // Viewed Me section
        _ViewedMeSection(),
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

        // Settings card
        Card(
          color: VibraTheme.kSurface,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_outlined,
                    color: VibraTheme.kTextSecondary),
                title: const Text('Notifications'),
                trailing: const Icon(Icons.chevron_right,
                    color: VibraTheme.kTextMuted),
                onTap: () =>
                    context.push('/settings?tab=notifications'),
              ),
              const Divider(height: 1, color: VibraTheme.kDivider),
              ListTile(
                leading: const Icon(Icons.lock_outline,
                    color: VibraTheme.kTextSecondary),
                title: const Text('Privacy'),
                trailing: const Icon(Icons.chevron_right,
                    color: VibraTheme.kTextMuted),
                onTap: () => context.push('/settings?tab=privacy'),
              ),
              const Divider(height: 1, color: VibraTheme.kDivider),
              ListTile(
                leading: const Icon(Icons.block,
                    color: VibraTheme.kTextSecondary),
                title: const Text('Blocked Users'),
                trailing: const Icon(Icons.chevron_right,
                    color: VibraTheme.kTextMuted),
                onTap: () => context.push('/settings?tab=blocks'),
              ),
              const Divider(height: 1, color: VibraTheme.kDivider),
              ListTile(
                leading:
                    const Icon(Icons.logout, color: VibraTheme.kError),
                title: const Text(
                  'Logout',
                  style: TextStyle(color: VibraTheme.kError),
                ),
                onTap: _logout,
              ),
              const Divider(height: 1, color: VibraTheme.kDivider),
              ListTile(
                leading: const Icon(Icons.delete_forever,
                    color: VibraTheme.kError),
                title: const Text(
                  'Delete Account',
                  style: TextStyle(color: VibraTheme.kError),
                ),
                onTap: _deleteAccount,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsChips(ThemeData theme, UserProfile p) {
    final chips = <Widget>[];

    final age = _calculateAge(p.birthdate);
    if (age != null) {
      chips.add(_buildChip('$age', Icons.cake_outlined));
    }
    if (p.heightCm != null) {
      chips.add(_buildChip('${p.heightCm} cm', Icons.height));
    }
    if (p.weightKg != null) {
      chips.add(_buildChip('${p.weightKg} kg', Icons.monitor_weight_outlined));
    }
    if (p.bodyType != null) {
      chips.add(_buildChip(p.bodyType!, Icons.fitness_center));
    }
    if (p.position != null) {
      chips.add(_buildChip(p.position!, Icons.sync_alt));
    }
    if (p.relationshipStatus != null) {
      chips.add(_buildChip(p.relationshipStatus!, Icons.favorite_outline));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
  }

  Widget _buildChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: VibraTheme.kSurface,
        borderRadius: BorderRadius.circular(VibraTheme.kRadiusChip),
        border: Border.all(color: VibraTheme.kDivider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: VibraTheme.kTextMuted),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
                color: VibraTheme.kTextPrimary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildTribesChips(ThemeData theme, UserProfile p) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: p.tribes.map((t) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: VibraTheme.kAccent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(VibraTheme.kRadiusChip),
            border: Border.all(
              color: VibraTheme.kAccent.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            t,
            style: const TextStyle(
              color: VibraTheme.kAccent,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Boost button — shown in the You screen. When inactive, tap to activate.
/// When active, shows the "BOOSTED" badge with minutes remaining.
class _BoostButton extends ConsumerStatefulWidget {
  const _BoostButton();

  @override
  ConsumerState<_BoostButton> createState() => _BoostButtonState();
}

class _BoostButtonState extends ConsumerState<_BoostButton> {
  bool _activating = false;

  Future<void> _activate() async {
    setState(() => _activating = true);
    try {
      final service = ref.read(boostServiceProvider);
      await service.activate();
      ref.invalidate(activeBoostProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Boosted for 30 min!'),
            backgroundColor: VibraTheme.kAccent,
          ),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to boost: ${e.response?.statusCode ?? e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to boost: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeAsync = ref.watch(activeBoostProvider);
    final active = activeAsync is AsyncData<Boost?> ? activeAsync.value : null;

    if (active != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt, color: theme.colorScheme.primary, size: 18),
            const SizedBox(width: 6),
            Text(
              'BOOSTED · ${active.minutesRemaining}m left',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: 200,
      child: FilledButton.icon(
        onPressed: _activating ? null : _activate,
        icon: _activating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              )
            : const Icon(Icons.bolt),
        label: Text(_activating ? 'Boosting...' : 'Boost'),
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

/// "BOOSTED" badge overlaid on the profile photo. Visible only when active.
class _BoostBadge extends ConsumerWidget {
  const _BoostBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAsync = ref.watch(activeBoostProvider);
    final theme = Theme.of(context);
    final active =
        activeAsync is AsyncData<Boost?> ? activeAsync.value : null;

    if (active == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.bolt, color: Colors.black, size: 14),
          SizedBox(width: 2),
          Text(
            'BOOSTED',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Viewed Me" section on the YouScreen. Shows up to 10 recent profile
/// viewers with a circular avatar + name. Empty-state when no viewers.
class _ViewedMeSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final viewersAsync = ref.watch(viewedMeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'VIEWED ME',
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.grey,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Card(
          color: VibraTheme.kSurface,
          child: viewersAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Could not load viewers',
                  style: TextStyle(color: Colors.grey.shade400),
                ),
              ),
            ),
            data: (viewers) {
              if (viewers.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 24, horizontal: 16),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.visibility_off_outlined,
                            size: 36, color: VibraTheme.kTextMuted),
                        const SizedBox(height: 8),
                        const Text(
                          'No one has viewed you yet',
                          style: TextStyle(
                              color: VibraTheme.kTextSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final limited = viewers.take(10).toList();

              return Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 8, horizontal: 8),
                child: SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: limited.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final viewer = limited[index];
                      return _ViewerTile(viewer: viewer);
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Single circular avatar tile for a profile viewer.
class _ViewerTile extends StatelessWidget {
  final ProfileViewer viewer;

  const _ViewerTile({required this.viewer});

  @override
  Widget build(BuildContext context) {
    final displayName = viewer.displayName ?? 'Anonymous';

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.push('/profile/${viewer.viewerId}'),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: VibraTheme.kSurface,
              backgroundImage: viewer.profilePhotoUrl != null
                  ? NetworkImage(viewer.profilePhotoUrl!)
                  : null,
              child: viewer.profilePhotoUrl == null
                  ? Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 18,
                        color: VibraTheme.kAccent,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
