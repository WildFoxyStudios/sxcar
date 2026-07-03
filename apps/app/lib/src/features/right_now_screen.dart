import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';
import '../rightnow/rightnow_service.dart';
import '../theme/app_theme.dart';

/// Right Now — dedicated tab screen for short-lived nearby "Right Now" intents.
///
/// Displays the active feed in a vertical list (cards) and provides a FAB to
/// post a new intent. Extracted from ExploreScreen (T2) so it lives in its
/// own shell tab at `/right-now`.
class RightNowScreen extends ConsumerWidget {
  const RightNowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        backgroundColor: VibraTheme.kBg,
        title: const Text(
          'Right Now',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPostSheet(context, ref),
        backgroundColor: VibraTheme.kRightNow,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.water_drop),
        label: const Text('Right Now'),
      ),
      body: const _RightNowFeed(),
    );
  }

  void _showPostSheet(BuildContext context, WidgetRef ref) {
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    int minutes = 60;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VibraTheme.kSurface,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Post Right Now',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLength: 140,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: '¿Qué estás haciendo ahora mismo?',
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        'Expira en:',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<int>(
                        value: minutes,
                        dropdownColor: VibraTheme.kSurface,
                        style: const TextStyle(color: Colors.white),
                        items: const [
                          DropdownMenuItem(value: 30, child: Text('30 min')),
                          DropdownMenuItem(value: 60, child: Text('1 hora')),
                          DropdownMenuItem(
                              value: 120, child: Text('2 horas')),
                        ],
                        onChanged: (v) => setSheet(() => minutes = v ?? 60),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: VibraTheme.kRightNow,
                      ),
                      onPressed: () async {
                        final text = controller.text.trim();
                        if (text.isEmpty) return;
                        Navigator.of(ctx).pop();
                        try {
                          await ref
                              .read(rightNowServiceProvider)
                              .create(text, minutes);
                          ref.invalidate(rightNowFeedProvider);
                          messenger.showSnackBar(const SnackBar(
                              content: Text('Publicado en Right Now')));
                        } catch (_) {
                          messenger.showSnackBar(const SnackBar(
                              content: Text('No se pudo publicar')));
                        }
                      },
                      child: const Text('Publicar'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Full feed widget — vertical list of active Right Now intents.
class _RightNowFeed extends ConsumerWidget {
  const _RightNowFeed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(rightNowFeedProvider);
    final currentUserId = ref.watch(authStateProvider).userId;

    return feedAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text(
              'No se pudo cargar el feed',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => ref.invalidate(rightNowFeedProvider),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
      data: (intents) {
        if (intents.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.water_drop_outlined,
                    size: 56, color: VibraTheme.kRightNow),
                SizedBox(height: 16),
                Text(
                  'Nadie por aquí ahora mismo',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Sé el primero en publicar',
                  style: TextStyle(color: VibraTheme.kTextSecondary),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          color: VibraTheme.kRightNow,
          onRefresh: () async => ref.invalidate(rightNowFeedProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: intents.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final intent = intents[index];
              final isMine = intent.userId == currentUserId;
              return _RightNowCard(
                intent: intent,
                isMine: isMine,
                onDelete: isMine
                    ? () async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await ref
                              .read(rightNowServiceProvider)
                              .delete(intent.id);
                          ref.invalidate(rightNowFeedProvider);
                        } catch (_) {
                          messenger.showSnackBar(const SnackBar(
                              content: Text('No se pudo eliminar')));
                        }
                      }
                    : null,
              );
            },
          ),
        );
      },
    );
  }
}

class _RightNowCard extends StatelessWidget {
  final RightNowIntent intent;
  final bool isMine;
  final VoidCallback? onDelete;

  const _RightNowCard({
    required this.intent,
    required this.isMine,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isMine
            ? VibraTheme.kRightNow.withValues(alpha: 0.12)
            : VibraTheme.kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMine
              ? VibraTheme.kRightNow.withValues(alpha: 0.4)
              : Colors.transparent,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.water_drop, color: VibraTheme.kRightNow, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              intent.body,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
          if (isMine && onDelete != null)
            GestureDetector(
              onTap: onDelete,
              child: const Icon(Icons.close,
                  color: VibraTheme.kTextSecondary, size: 18),
            ),
        ],
      ),
    );
  }
}
