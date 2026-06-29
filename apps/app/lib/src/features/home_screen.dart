import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final email = authState.email ?? 'User';

    return Scaffold(
      appBar: AppBar(title: const Text('proyecto-X')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Welcome to proyecto-X',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              email,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => context.go('/profile'),
              child: const Text('My Profile'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go('/albums'),
              child: const Text('Albums'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go('/grid'),
              child: const Text('Nearby'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                await ref.read(authStateProvider.notifier).logout();
              },
              child: const Text('Logout'),
            ),
          ],
        ),
      ),
    );
  }
}
