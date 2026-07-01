import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sessions_service.dart';

/// Screen listing the current user's active login sessions (devices),
/// each revocable — Grindr Tier 3 "multiple instances" management.
class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Active Sessions')),
      body: sessions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              const Text('Failed to load sessions'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(sessionsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No active sessions'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(sessionsProvider),
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final s = list[index];
                return ListTile(
                  leading: const Icon(Icons.devices, color: Color(0xFFF4C542)),
                  title: Text(
                    s.deviceId != null ? 'Device ${s.deviceId}' : 'Unknown device',
                  ),
                  subtitle: Text('Signed in: ${_shortDate(s.issuedAt)}'),
                  trailing: TextButton(
                    onPressed: () => _confirmRevoke(context, ref, s),
                    child: const Text('Log out'),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _shortDate(String iso) {
    // Server sends e.g. "2026-07-01 19:40:51.975572 +00:00:00" — take the date.
    final space = iso.indexOf(' ');
    return space > 0 ? iso.substring(0, space) : iso;
  }

  Future<void> _confirmRevoke(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out this device?'),
        content: const Text(
          'This will end the session on that device. It will need to sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(sessionsServiceProvider).revoke(session.id);
      ref.invalidate(sessionsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Device logged out')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to log out device')),
      );
    }
  }
}
