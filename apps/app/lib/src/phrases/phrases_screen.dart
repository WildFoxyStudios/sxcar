import '../theme/app_theme.dart';
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

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) {
    // The controller lives inside _AddPhraseDialog's State so it is disposed
    // in State.dispose (after the route is fully removed), never mid-animation.
    return showDialog<void>(
      context: context,
      builder: (ctx) => _AddPhraseDialog(ref: ref, hostContext: context),
    );
  }
}

/// Add-phrase dialog. Owns its own [TextEditingController] so disposal happens
/// safely in [State.dispose] rather than immediately after `showDialog`.
class _AddPhraseDialog extends StatefulWidget {
  final WidgetRef ref;

  /// The screen context, used for the SnackBar after the dialog pops.
  final BuildContext hostContext;

  const _AddPhraseDialog({required this.ref, required this.hostContext});

  @override
  State<_AddPhraseDialog> createState() => _AddPhraseDialogState();
}

class _AddPhraseDialogState extends State<_AddPhraseDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final text = _controller.text.trim();
    Navigator.of(context).pop();
    final hostContext = widget.hostContext;
    try {
      final service = widget.ref.read(phrasesServiceProvider);
      await service.add(text);
      widget.ref.invalidate(phrasesProvider);
      if (hostContext.mounted) {
        ScaffoldMessenger.of(hostContext).showSnackBar(
          const SnackBar(content: Text('Phrase added')),
        );
      }
    } catch (e) {
      if (hostContext.mounted) {
        ScaffoldMessenger.of(hostContext).showSnackBar(
          SnackBar(
            content: Text('Failed to add: $e'),
            backgroundColor: VibraTheme.kError,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: VibraTheme.kSurface,
      title: const Text('Add Phrase'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
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
        color: VibraTheme.kChip,
        indent: 16,
        endIndent: 16,
      ),
      itemBuilder: (context, index) {
        final phrase = phrases[index];
        return Dismissible(
          key: ValueKey(phrase.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: VibraTheme.kError,
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
                    backgroundColor: VibraTheme.kError,
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
            backgroundColor: VibraTheme.kError,
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
            Icon(Icons.chat_bubble_outline, size: 64, color: VibraTheme.kTextSecondary),
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
              style: TextStyle(color: VibraTheme.kTextSecondary, fontSize: 13),
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
          const Icon(Icons.error_outline, color: VibraTheme.kError, size: 48),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: VibraTheme.kError),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
