import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../auth/auth_provider.dart';
import '../chat/chat_service.dart';
import '../chat/models.dart';
import '../media/media_service.dart';
import '../nsfw/nsfw_service.dart';
import '../theme/app_theme.dart';
import '../../l10n/gen/app_localizations.dart';

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

  // Typing indicator state
  bool _peerTyping = false;
  Timer? _peerTypingTimer;
  DateTime? _lastTypingSent;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _connectWebSocket();
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _peerTypingTimer?.cancel();
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
      } else if (type == 'typing') {
        final convId = json['conversation_id'] as String?;
        final userId = json['user_id'] as String?;
        final myId = ref.read(authStateProvider).userId;
        if (convId == widget.conversationId && userId != myId) {
          _peerTypingTimer?.cancel();
          setState(() => _peerTyping = true);
          _peerTypingTimer = Timer(const Duration(seconds: 4), () {
            if (mounted) setState(() => _peerTyping = false);
          });
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
      senderId: authState.userId ?? '',
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

  /// Pick a photo from the gallery, show a preview sheet, then upload and send.
  Future<void> _pickAndSendPhoto() async {
    final picker = ImagePicker();
    final XFile? file =
        await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    if (!mounted) return;

    final Uint8List bytes = await file.readAsBytes();
    if (!mounted) return;

    // On-device NSFW check before showing the send sheet.
    final nsfwResult =
        await ref.read(nsfwServiceProvider).check(bytes.toList());
    if (!mounted) return;
    if (nsfwResult.isNsfw) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This image appears to violate our content guidelines.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show preview bottom sheet; returns the "view once" toggle value,
    // or null if the user dismissed without sending.
    final bool? viewOnce = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VibraTheme.kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PhotoSendSheet(imageBytes: bytes),
    );

    if (viewOnce == null || !mounted) return;

    // Upload to R2 then send message.
    try {
      final dio = ref.read(dioProvider);
      final mediaService = MediaService(dio);
      final uploadUrl = await mediaService.getUploadUrl(kind: 'album');
      await mediaService.uploadToR2(uploadUrl.putUrl, bytes);
      if (!mounted) return;

      final chatService = ref.read(chatServiceProvider);
      await chatService.sendPhotoMessage(
        widget.conversationId,
        mediaKey: uploadUrl.key,
        ephemeral: viewOnce,
      );
      if (!mounted) return;

      // Optimistic bubble for the sender.
      final authState = ref.read(authStateProvider);
      final optimistic = Message(
        id: '',
        conversationId: widget.conversationId,
        senderId: authState.userId ?? '',
        kind: viewOnce ? 'ephemeral_photo' : 'photo',
        createdAt: DateTime.now().toIso8601String(),
        mediaKey: uploadUrl.key,
        mediaType: 'photo',
      );
      setState(() => _messages.add(optimistic));
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send photo: $e')),
      );
    }
  }

  String? _currentUserId() {
    return ref.read(authStateProvider).userId;
  }

  /// Throttled handler for compose-field changes: fires a typing frame at most
  /// once every ~3 s while the field is non-empty.
  void _onTypingChanged(String value) {
    if (value.isEmpty) return;
    final now = DateTime.now();
    if (_lastTypingSent == null ||
        now.difference(_lastTypingSent!) >= const Duration(seconds: 3)) {
      _lastTypingSent = now;
      final chatService = ref.read(chatServiceProvider);
      chatService.sendTyping(widget.conversationId);
    }
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

          // ── Typing indicator ──────────────────────────────────────────────
          if (_peerTyping) _buildTypingIndicator(context),

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

  Widget _buildTypingIndicator(BuildContext context) {
    final text = AppLocalizations.of(context)?.chatTyping ?? 'typing…';
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: VibraTheme.kTextSecondary,
          fontSize: 12,
        ),
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
            // Attach icon — opens image picker
            IconButton(
              icon: const Icon(Icons.attach_file,
                  color: VibraTheme.kTextMuted, size: 22),
              onPressed: _pickAndSendPhoto,
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
                  onChanged: _onTypingChanged,
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

// ─────────────────────────────────────────────────────────────────────────────
// Message bubble
// ─────────────────────────────────────────────────────────────────────────────

/// Chat bubble — handles text, photo, and ephemeral-photo kinds.
///
/// Converted to [ConsumerStatefulWidget] so that:
/// - Photo bubbles can lazily fetch their presigned URL once via the service.
/// - Ephemeral bubbles can track local-view state for the tap-to-expire flow.
class _MessageBubble extends ConsumerStatefulWidget {
  final Message message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  ConsumerState<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<_MessageBubble> {
  /// Whether the current user viewed the ephemeral photo in this session.
  bool _locallyViewed = false;

  /// Cached presigned-URL future for photo bubbles (set once in initState).
  Future<String>? _urlFuture;

  @override
  void initState() {
    super.initState();
    if (widget.message.kind == 'photo') {
      final key = widget.message.mediaKey ?? '';
      if (key.isNotEmpty) {
        _urlFuture =
            ref.read(chatServiceProvider).getMediaUrl(key);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isMe = widget.isMe;

    switch (message.kind) {
      case 'photo':
        return _buildPhotoBubble(context, isMe);
      case 'ephemeral_photo':
        return _buildEphemeralBubble(context, isMe);
      default:
        return _buildTextBubble(isMe);
    }
  }

  // ── Text bubble ────────────────────────────────────────────────────────────

  Widget _buildTextBubble(bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: _bubbleMargin(isMe),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
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
                  color: VibraTheme.kAccent.withValues(alpha: 0.3), width: 1)
              : null,
        ),
        child: Text(
          widget.message.body ?? '',
          style: TextStyle(
            color: isMe ? VibraTheme.kAccent : VibraTheme.kTextPrimary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  // ── Photo bubble ───────────────────────────────────────────────────────────

  Widget _buildPhotoBubble(BuildContext context, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: _bubbleMargin(isMe),
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          color: VibraTheme.kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: VibraTheme.kDivider),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: FutureBuilder<String>(
            future: _urlFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: VibraTheme.kAccent),
                );
              }
              if (snap.hasError || !snap.hasData) {
                return const Center(
                  child: Icon(Icons.broken_image,
                      color: VibraTheme.kTextMuted, size: 40),
                );
              }
              return GestureDetector(
                onTap: () => _openFullScreen(context, snap.data!),
                child: Image.network(
                  snap.data!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(Icons.broken_image,
                        color: VibraTheme.kTextMuted),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Ephemeral bubble ───────────────────────────────────────────────────────

  Widget _buildEphemeralBubble(BuildContext context, bool isMe) {
    // Sender always sees a neutral "sent" card — they can never re-open it.
    if (isMe) {
      return _buildEphemeralSentCard();
    }

    // Recipient: expired if the server already recorded a view OR we viewed it
    // in this session.
    final isExpired =
        widget.message.ephemeralViewedAt != null || _locallyViewed;
    if (isExpired) {
      return _buildEphemeralExpiredCard(isMe);
    }

    return _buildTapToViewCard(context);
  }

  Widget _buildTapToViewCard(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => _onTapEphemeral(context),
        child: Container(
          margin: _bubbleMargin(false),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: VibraTheme.kSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: VibraTheme.kAccent, width: 1.5),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_fire_department,
                  color: VibraTheme.kAccent, size: 20),
              SizedBox(width: 8),
              Text(
                'Tap to view once',
                style: TextStyle(
                  color: VibraTheme.kAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEphemeralSentCard() {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: _bubbleMargin(true),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: VibraTheme.kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: VibraTheme.kDivider),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, color: VibraTheme.kTextMuted, size: 18),
            SizedBox(width: 8),
            Text(
              'View-once photo sent',
              style: TextStyle(color: VibraTheme.kTextSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEphemeralExpiredCard(bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: _bubbleMargin(isMe),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: VibraTheme.kSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.do_not_disturb_alt,
                color: VibraTheme.kTextMuted, size: 18),
            SizedBox(width: 8),
            Text(
              'Photo expired',
              style: TextStyle(color: VibraTheme.kTextMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ── Ephemeral tap flow ─────────────────────────────────────────────────────

  Future<void> _onTapEphemeral(BuildContext context) async {
    final message = widget.message;
    final chatService = ref.read(chatServiceProvider);
    // Capture Navigator before any await to satisfy BuildContext-across-async-gap lint.
    final navigator = Navigator.of(context);

    // Mark as viewed on the server first.
    bool firstView = false;
    try {
      firstView = await chatService.markEphemeralViewed(
        message.conversationId,
        message.id,
      );
    } catch (_) {
      // If the server call fails, do not reveal the photo.
      return;
    }

    if (!mounted) return;

    if (!firstView) {
      // Already viewed on another device; collapse to expired state.
      setState(() => _locallyViewed = true);
      return;
    }

    // Fetch presigned URL and open full-screen viewer.
    String url;
    try {
      url = await chatService.getMediaUrl(message.mediaKey ?? '');
    } catch (_) {
      if (!mounted) return;
      setState(() => _locallyViewed = true);
      return;
    }

    if (!mounted) return;

    // Show photo full-screen; when the user closes it, collapse to expired.
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => _FullScreenPhotoViewer(url: url),
      ),
    );

    if (!mounted) return;
    setState(() => _locallyViewed = true);
  }

  void _openFullScreen(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullScreenPhotoViewer(url: url),
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  EdgeInsets _bubbleMargin(bool isMe) {
    return EdgeInsets.only(
      top: 3,
      bottom: 3,
      left: isMe ? 60 : 0,
      right: isMe ? 0 : 60,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Photo send sheet
// ─────────────────────────────────────────────────────────────────────────────

/// Bottom sheet shown before sending a photo.
///
/// Displays a preview of [imageBytes] and lets the user toggle
/// "View once" mode. Pops with `true` (view once) or `false` (normal photo).
class _PhotoSendSheet extends StatefulWidget {
  final Uint8List imageBytes;

  const _PhotoSendSheet({required this.imageBytes});

  @override
  State<_PhotoSendSheet> createState() => _PhotoSendSheetState();
}

class _PhotoSendSheetState extends State<_PhotoSendSheet> {
  bool _viewOnce = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: VibraTheme.kDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Preview
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: Image.memory(
                widget.imageBytes,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // View-once toggle row
          Row(
            children: [
              const Icon(Icons.local_fire_department,
                  color: VibraTheme.kAccent, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'View once',
                  style: TextStyle(
                    color: VibraTheme.kTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Switch(
                value: _viewOnce,
                onChanged: (v) => setState(() => _viewOnce = v),
                activeThumbColor: VibraTheme.kAccent,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Send button — pops with the toggle value
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(_viewOnce),
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen photo viewer
// ─────────────────────────────────────────────────────────────────────────────

/// Full-screen photo viewer used for both normal and ephemeral photos.
///
/// Ephemeral: the calling bubble marks the photo as expired *after* this
/// route is popped (the caller listens to the returned Future).
class _FullScreenPhotoViewer extends StatelessWidget {
  final String url;

  const _FullScreenPhotoViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: Image.network(
          url,
          fit: BoxFit.contain,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return const Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            );
          },
          errorBuilder: (_, _, _) => const Icon(
            Icons.broken_image,
            color: Colors.white54,
            size: 64,
          ),
        ),
      ),
    );
  }
}
