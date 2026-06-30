import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      emailVerified: json['email_verified'] as bool? ?? false,
      status: json['status'] as String? ?? 'unknown',
      role: json['role'] as String? ?? 'user',
      createdAt: json['created_at'] as String? ?? '',
      displayName: json['display_name'] as String?,
      bio: json['bio'] as String?,
      profilePhotoUrl: json['profile_photo_url'] as String?,
    );
  }
}

final userDetailProvider = FutureProvider.autoDispose.family<UserFullProfile, String>((ref, userId) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/users/$userId');
  final userJson = (response.data as Map<String, dynamic>)['user'] as Map<String, dynamic>;
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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const BackButton(),
                Text(
                  'User Detail',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: userAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Failed to load user: $error'),
                    ],
                  ),
                ),
                data: (user) => _buildProfile(context, ref, user),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfile(BuildContext context, WidgetRef ref, UserFullProfile user) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 40,
                    child: Text(
                      user.email.isNotEmpty ? user.email[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.email,
                            style: Theme.of(context).textTheme.titleLarge),
                        if (user.displayName != null) ...[
                          const SizedBox(height: 4),
                          Text('Display: ${user.displayName}',
                              style: Theme.of(context).textTheme.bodyMedium),
                        ],
                        const SizedBox(height: 4),
                        Text('Role: ${user.role}  |  Status: ${user.status}',
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 4),
                        Text('Created: ${user.createdAt}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (user.bio != null && user.bio!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bio', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(user.bio!),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('Actions', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ActionButton(
                label: 'Activate',
                icon: Icons.check_circle,
                color: Colors.green,
                onPressed: () => _performAction(context, ref, userId, 'activate'),
              ),
              _ActionButton(
                label: 'Suspend',
                icon: Icons.pause_circle,
                color: Colors.orange,
                onPressed: () => _showReasonDialog(context, ref, userId, 'suspend'),
              ),
              _ActionButton(
                label: 'Ban',
                icon: Icons.block,
                color: Colors.red,
                onPressed: () => _showReasonDialog(context, ref, userId, 'ban'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showReasonDialog(
      BuildContext context, WidgetRef ref, String userId, String action) async {
    final reasonController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${action[0].toUpperCase()}${action.substring(1)} User'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Enter reason for this action',
            border: OutlineInputBorder(),
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
            child: Text(action[0].toUpperCase() + action.substring(1)),
          ),
        ],
      ),
    );

    if (result != null && context.mounted) {
      await _performAction(context, ref, userId, action, reason: result);
    }
  }

  Future<void> _performAction(
      BuildContext context, WidgetRef ref, String userId, String action,
      {String? reason}) async {
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
            content: Text('User ${action}ed successfully'),
            backgroundColor: Colors.green,
          ),
        );
        ref.invalidate(userDetailProvider(userId));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        final msg = e.response?.data is Map
            ? ((e.response!.data as Map)['error'] ?? 'Action failed').toString()
            : 'Action failed. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }
}

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
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
