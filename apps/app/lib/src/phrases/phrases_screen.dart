import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'phrases_service.dart';

/// Saved chat phrases screen. List, add, delete, reorder.
class PhrasesScreen extends ConsumerWidget {
  const PhrasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phrasesAsync = ref.watch(phrasesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Phrases'),
      ),
      body: phrasesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: 'Failed to load: $e',
          onRetry: () => ref.invalidate(phrasesProvider),
        ),
        data: (phrases) => phrases.isEmpty
            ? const _EmptyView()
            : _PhrasesList(phrases: phrases),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Add Phrase'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Phrase text',
              border: OutlineInputBorder(),
            ),
            maxLength: 200,
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Phrase cannot be empty';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final text = controller.text.trim();
              Navigator.of(ctx).pop();
              try {
                final service = ref.read(phrasesServiceProvider);
                await service.add(text);
                ref.invalidate(phrasesProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Phrase added')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to add: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _PhrasesList extends ConsumerWidget {
  final List<Phrase> phrases;

  const _PhrasesList({required this.phrases});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: phrases.length,
      separatorBuilder: (_, _) => const Divider(
        height: 1,
        color: Color(0xFF2A2A2A),
        indent: 16,
        endIndent: 16,
      ),
      itemBuilder: (context, index) {
        final phrase = phrases[index];
        return Dismissible(
          key: ValueKey(phrase.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) async {
            try {
              final service = ref.read(phrasesServiceProvider);
              await service.delete(phrase.id);
              ref.invalidate(phrasesProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Phrase deleted')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to delete: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
                // Restore item by re-invalidating.
                ref.invalidate(phrasesProvider);
              }
            }
          },
          child: ListTile(
            title: Text(phrase.text),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 20),
                  tooltip: 'Move up',
                  onPressed: index == 0
                      ? null
                      : () => _reorder(context, ref, index, index - 1),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward, size: 20),
                  tooltip: 'Move down',
                  onPressed: index == phrases.length - 1
                      ? null
                      : () => _reorder(context, ref, index, index + 1),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _reorder(
    BuildContext context,
    WidgetRef ref,
    int from,
    int to,
  ) async {
    final newOrder = [...phrases];
    final moved = newOrder.removeAt(from);
    newOrder.insert(to, moved);

    try {
      final service = ref.read(phrasesServiceProvider);
      await service.reorder(newOrder.map((p) => p.id).toList());
      ref.invalidate(phrasesProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reorder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade600),
            const SizedBox(height: 16),
            Text(
              'No saved phrases',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a phrase to reuse it in your chats.',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
