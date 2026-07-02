import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_http_client.dart';
import '../../widgets/admin_layout.dart';

class UserFullProfile {
  final String id;
  final String email;
  final bool emailVerified;
  final String status;
  final String role;
  final String createdAt;
  final String? displayName;
  final String? bio;
  final String? profilePhotoUrl;

  UserFullProfile({
    required this.id,
    required this.email,
    required this.emailVerified,
    required this.status,
    required this.role,
    required this.createdAt,
    this.displayName,
    this.bio,
    this.profilePhotoUrl,
  });

  factory UserFullProfile.fromJson(Map<String, dynamic> json) {
    return UserFullProfile(
      id:              json['id']               as String? ?? '',
      email:           json['email']            as String? ?? '',
      emailVerified:   json['email_verified']   as bool?   ?? false,
      status:          json['status']           as String? ?? 'unknown',
      role:            json['role']             as String? ?? 'user',
      createdAt:       json['created_at']       as String? ?? '',
      displayName:     json['display_name']     as String?,
      bio:             json['bio']              as String?,
      profilePhotoUrl: json['profile_photo_url'] as String?,
    );
  }
}

final userDetailProvider =
    FutureProvider.autoDispose.family<UserFullProfile, String>(
        (ref, userId) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/users/$userId');
  final userJson =
      (response.data as Map<String, dynamic>)['user'] as Map<String, dynamic>;
  return UserFullProfile.fromJson(userJson);
});

class UserDetailScreen extends ConsumerWidget {
  final String userId;

  const UserDetailScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userDetailProvider(userId));

    return AdminLayout(
      selectedIndex: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 24, 12),
            child: Row(
              children: [
                const BackButton(),
                const Text(
                  'User Detail',
                  style: TextStyle(
                    color: AdminTheme.kText,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Content ───────────────────────────────────────────────────────
          Expanded(
            child: userAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 40, color: AdminTheme.kRed),
                    const SizedBox(height: 12),
                    Text(
                      'Failed to load user: $error',
                      style:
                          const TextStyle(color: AdminTheme.kMuted, fontSize: 14),
                    ),
                  ],
                ),
              ),
              data: (user) => _buildProfile(context, ref, user),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfile(
      BuildContext context, WidgetRef ref, UserFullProfile user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AdminTheme.kCard,
              borderRadius: BorderRadius.circular(8),
              border: const Border.fromBorderSide(
                BorderSide(color: AdminTheme.kBorder),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AdminTheme.kAccentBg,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AdminTheme.kAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      user.email.isNotEmpty
                          ? user.email[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: AdminTheme.kAccent,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.email,
                        style: const TextStyle(
                          color: AdminTheme.kText,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (user.displayName != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          user.displayName!,
                          style: const TextStyle(
                              color: AdminTheme.kMuted, fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _InfoChip(label: user.role),
                          const SizedBox(width: 8),
                          _StatusChip(status: user.status),
                          const SizedBox(width: 8),
                          if (user.emailVerified)
                            const _InfoChip(
                              label: 'Verified',
                              color: AdminTheme.kGreen,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Created ${_fmtDate(user.createdAt)}',
                        style: const TextStyle(
                            color: AdminTheme.kMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bio card
          if (user.bio != null && user.bio!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AdminTheme.kCard,
                borderRadius: BorderRadius.circular(8),
                border: const Border.fromBorderSide(
                  BorderSide(color: AdminTheme.kBorder),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bio',
                    style: TextStyle(
                      color: AdminTheme.kMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    user.bio!,
                    style: const TextStyle(
                        color: AdminTheme.kText, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],

          // Actions
          const SizedBox(height: 24),
          const Text(
            'ACTIONS',
            style: TextStyle(
              color: AdminTheme.kMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ActionButton(
                label: 'Activate',
                icon: Icons.check_circle_outline,
                color: AdminTheme.kGreen,
                onPressed: () => _performAction(context, ref, userId, 'activate'),
              ),
              _ActionButton(
                label: 'Suspend',
                icon: Icons.pause_circle_outline,
                color: AdminTheme.kOrange,
                onPressed: () =>
                    _showReasonDialog(context, ref, userId, 'suspend'),
              ),
              _ActionButton(
                label: 'Ban',
                icon: Icons.block_outlined,
                color: AdminTheme.kRed,
                onPressed: () =>
                    _showReasonDialog(context, ref, userId, 'ban'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showReasonDialog(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String action,
  ) async {
    final reasonController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            '${action[0].toUpperCase()}${action.substring(1)} User'),
        content: TextField(
          controller: reasonController,
          style: const TextStyle(color: AdminTheme.kText),
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Enter reason for this action',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(reasonController.text),
            style: FilledButton.styleFrom(
              backgroundColor: action == 'ban' ? AdminTheme.kRed : AdminTheme.kOrange,
              foregroundColor: Colors.white,
            ),
            child: Text(
                '${action[0].toUpperCase()}${action.substring(1)}'),
          ),
        ],
      ),
    );

    if (result != null && context.mounted) {
      await _performAction(context, ref, userId, action, reason: result);
    }
  }

  Future<void> _performAction(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String action, {
    String? reason,
  }) async {
    try {
      final client = ref.read(adminHttpClientProvider);
      final Map<String, dynamic>? body;
      if (action == 'ban' || action == 'suspend') {
        body = {'reason': reason ?? ''};
      } else {
        body = null;
      }

      await client.dio.post('/admin/users/$userId/$action', data: body);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User ${action}d successfully'),
            backgroundColor: AdminTheme.kGreen,
          ),
        );
        ref.invalidate(userDetailProvider(userId));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        final msg = e.response?.data is Map
            ? ((e.response!.data as Map)['error'] ?? 'Action failed')
                .toString()
            : 'Action failed. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AdminTheme.kRed),
        );
      }
    }
  }

  String _fmtDate(String iso) {
    if (iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${_p(dt.month)}-${_p(dt.day)}';
    } catch (_) {
      return iso.length > 10 ? iso.substring(0, 10) : iso;
    }
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

// ── Chips ─────────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final String label;
  final Color color;

  const _InfoChip({required this.label, this.color = AdminTheme.kMuted});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color = switch (status) {
      'active'    => AdminTheme.kGreen,
      'suspended' => AdminTheme.kOrange,
      'banned'    => AdminTheme.kRed,
      _           => AdminTheme.kMuted,
    };
    final String label = switch (status) {
      'active'    => 'Active',
      'suspended' => 'Suspended',
      'banned'    => 'Banned',
      _           => status,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Action button ─────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 15),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        textStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      onPressed: onPressed,
    );
  }
}
