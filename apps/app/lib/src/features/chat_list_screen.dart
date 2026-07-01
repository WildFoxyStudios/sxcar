import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../chat/chat_service.dart';
import '../chat/models.dart';

/// Screen that lists all conversations for the current user.
class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  late Future<List<Conversation>> _conversationsFuture;

  @override
  void initState() {
    super.initState();
    _conversationsFuture = _fetchConversations();
  }

  Future<List<Conversation>> _fetchConversations() async {
    final chatService = ref.read(chatServiceProvider);
    return chatService.listConversations();
  }

  void _refresh() {
    setState(() {
      _conversationsFuture = _fetchConversations();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: FutureBuilder<List<Conversation>>(
        future: _conversationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load conversations',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _refresh,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final conversations = snapshot.data ?? [];

          if (conversations.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade600),
                    const SizedBox(height: 16),
                    Text(
                      'No conversations yet',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Find someone in Cascade and say hi!',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: conversations.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final conv = conversations[index];
              return Dismissible(
                key: Key(conv.conversationId),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.red,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) async {
                  try {
                    final chatService = ref.read(chatServiceProvider);
                    await chatService.deleteConversation(conv.conversationId);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Conversation deleted')),
                      );
                    }
                    _refresh();
                  } catch (e) {
                    _refresh();
                  }
                },
                child: _ConversationTile(
                  conversation: conv,
                  onTap: () {
                    context.push('/inbox/${conv.conversationId}');
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = conversation.otherDisplayName ?? 'Unknown';
    final lastMessage = conversation.lastMessagePreview;
    final hasUnread = conversation.unreadCount > 0;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          displayName[0].toUpperCase(),
          style: TextStyle(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
      title: Text(
        displayName,
        style: TextStyle(
          fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: lastMessage != null
          ? Text(
              lastMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
              ),
            )
          : null,
      trailing: hasUnread
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${conversation.unreadCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}
