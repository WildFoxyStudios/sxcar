import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../chat/chat_service.dart';
import '../chat/models.dart';
import '../auth/auth_provider.dart';
import '../theme/app_theme.dart';

/// Real-time chat screen with WebSocket connection.
class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;

  const ChatScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  List<Message> _messages = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _connectWebSocket();
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _connectWebSocket() {
    final chatService = ref.read(chatServiceProvider);
    chatService.connectWebSocket();

    _wsSubscription = chatService.messageStream.listen((json) {
      if (!mounted) return;
      final type = json['type'] as String?;
      if (type == 'message') {
        final message = Message.fromWebSocketJson(json);
        if (message.conversationId == widget.conversationId) {
          setState(() {
            _messages.add(message);
          });
          _scrollToBottom();
        }
      }
    });
  }

  Future<void> _loadMessages() async {
    try {
      final chatService = ref.read(chatServiceProvider);
      final messages = await chatService.getMessages(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _messages = List<Message>.from(messages);
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _scrollToBottom() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();

    // Optimistic message
    final authState = ref.read(authStateProvider);
    final optimistic = Message(
      id: '',
      conversationId: widget.conversationId,
      senderId: authState.accessToken ?? '',
      kind: 'text',
      body: text,
      createdAt: DateTime.now().toIso8601String(),
    );

    setState(() {
      _messages.add(optimistic);
    });
    _scrollToBottom();

    try {
      final chatService = ref.read(chatServiceProvider);
      await chatService.sendMessage(widget.conversationId, text);
    } catch (_) {
      // Message will be replaced when WS broadcasts it back
    }
  }

  String? _currentUserId() {
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        backgroundColor: VibraTheme.kSurface,
        title: const Text('Chat'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: VibraTheme.kDivider),
        ),
      ),
      body: Column(
        children: [
          // ── Message list ─────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: VibraTheme.kAccent))
                : _error != null
                    ? _buildErrorState(theme)
                    : _messages.isEmpty
                        ? _buildEmptyState(theme)
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 16),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
                              final isMe =
                                  message.senderId == _currentUserId();
                              final showTimestamp = _shouldShowTimestamp(
                                  index);
                              return Column(
                                children: [
                                  if (showTimestamp)
                                    _buildTimestamp(message.createdAt),
                                  _MessageBubble(
                                      message: message, isMe: isMe),
                                ],
                              );
                            },
                          ),
          ),

          // ── Input bar ─────────────────────────────────────────────────────
          _buildInputBar(theme),
        ],
      ),
    );
  }

  /// Show a timestamp divider every 10 messages or at the first message.
  bool _shouldShowTimestamp(int index) {
    if (index == 0) return true;
    return false;
  }

  Widget _buildTimestamp(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return const SizedBox.shrink();
    final now = DateTime.now();
    String label;
    if (now.difference(dt).inDays == 0) {
      label =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else {
      label =
          '${dt.day}/${dt.month}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: VibraTheme.kTextMuted,
          fontSize: 11,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                  color: VibraTheme.kSurface, shape: BoxShape.circle),
              child: const Icon(Icons.error_outline,
                  size: 32, color: VibraTheme.kError),
            ),
            const SizedBox(height: 16),
            Text('Failed to load messages',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: VibraTheme.kTextPrimary)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadMessages();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
                color: VibraTheme.kSurface, shape: BoxShape.circle),
            child: const Icon(Icons.chat_bubble_outline,
                size: 32, color: VibraTheme.kAccent),
          ),
          const SizedBox(height: 16),
          const Text(
            'No messages yet',
            style: TextStyle(
                color: VibraTheme.kTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Say hi to start the conversation!',
            style: TextStyle(color: VibraTheme.kTextSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: VibraTheme.kSurface,
        border: Border(top: BorderSide(color: VibraTheme.kDivider)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Attach icon
            IconButton(
              icon: const Icon(Icons.attach_file,
                  color: VibraTheme.kTextMuted, size: 22),
              onPressed: () {
                // Attachment feature placeholder — no-op for now
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const SizedBox(width: 6),
            // Text input
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: VibraTheme.kSurfaceElevated,
                  borderRadius:
                      BorderRadius.circular(VibraTheme.kRadiusInput * 2),
                ),
                child: TextField(
                  controller: _textController,
                  style: const TextStyle(
                      color: VibraTheme.kTextPrimary, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(
                        color: VibraTheme.kTextMuted, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Send button
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: VibraTheme.kAccent,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send,
                    color: Colors.black, size: 18),
                onPressed: _sendMessage,
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chat bubble — sent messages are accent-tinted, received are dark grey.
class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    // Media messages (images/video) render as rounded thumbnails
    if (message.kind == 'image' || message.kind == 'video') {
      return _buildMediaBubble(context);
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 3,
          bottom: 3,
          left: isMe ? 60 : 0,
          right: isMe ? 0 : 60,
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          // Sent: slight accent tint; Received: dark surface
          color: isMe
              ? VibraTheme.kAccent.withValues(alpha: 0.15)
              : VibraTheme.kSurfaceElevated,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft:
                isMe ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight:
                isMe ? const Radius.circular(4) : const Radius.circular(16),
          ),
          border: isMe
              ? Border.all(
                  color: VibraTheme.kAccent.withValues(alpha: 0.3),
                  width: 1)
              : null,
        ),
        child: Text(
          message.body ?? '',
          style: TextStyle(
            color: isMe
                ? VibraTheme.kAccent
                : VibraTheme.kTextPrimary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildMediaBubble(BuildContext context) {
    final url = message.body ?? '';
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 3,
          bottom: 3,
          left: isMe ? 60 : 0,
          right: isMe ? 0 : 60,
        ),
        width: 180,
        height: 180,
        decoration: BoxDecoration(
          color: VibraTheme.kSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: url.isNotEmpty
              ? Image.network(url, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Center(
                        child: Icon(Icons.broken_image,
                            color: VibraTheme.kTextMuted),
                      ))
              : const Center(
                  child: Icon(Icons.image_outlined,
                      color: VibraTheme.kTextMuted, size: 40)),
        ),
      ),
    );
  }
}
