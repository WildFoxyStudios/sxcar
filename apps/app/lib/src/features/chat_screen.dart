import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
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

  // Voice recording state
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordingFilePath;

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
      } else if (type == 'reaction') {
        final messageId = json['message_id'] as String?;
        final userId = json['user_id'] as String?;
        final emoji = json['emoji'] as String?;
        if (messageId == null || userId == null) return;
        final idx = _messages.indexWhere((m) => m.id == messageId);
        if (idx == -1) return; // silently ignore unknown messages
        final msg = _messages[idx];
        // Remove any existing reaction by this user, then add if non-null
        final newReactions = List<MessageReaction>.from(msg.reactions)
          ..removeWhere((r) => r.userId == userId);
        if (emoji != null) {
          newReactions.add(MessageReaction(userId: userId, emoji: emoji));
        }
        if (mounted) {
          setState(() {
            _messages[idx] = msg.copyWith(reactions: newReactions);
          });
        }
      } else if (type == 'unsend') {
        final messageId = json['message_id'] as String?;
        if (messageId == null) return;
        final idx = _messages.indexWhere((m) => m.id == messageId);
        if (idx == -1) return;
        if (mounted) {
          setState(() {
            _messages[idx] = _messages[idx].copyWith(
              unsentAt: DateTime.now().toIso8601String(),
            );
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

  /// Start recording a voice message.
  Future<void> _startRecording() async {
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied')),
      );
      return;
    }

    final dir = await _tempDir();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(const RecordConfig(), path: path);
    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _recordingFilePath = path;
    });
  }

  /// Stop recording and send the voice message.
  Future<void> _stopRecording() async {
    final path = _recordingFilePath;
    setState(() => _isRecording = false);
    _recordingFilePath = null;

    if (path == null) return;

    try {
      final chatService = ref.read(chatServiceProvider);
      await chatService.sendVoiceMessage(widget.conversationId, path);
      if (!mounted) return;

      final authState = ref.read(authStateProvider);
      final optimistic = Message(
        id: '',
        conversationId: widget.conversationId,
        senderId: authState.userId ?? '',
        kind: 'audio',
        createdAt: DateTime.now().toIso8601String(),
      );
      setState(() => _messages.add(optimistic));
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send voice message: $e')),
      );
    }
  }

  /// Get a temporary directory for recording.
  Future<Directory> _tempDir() async {
    return Directory.systemTemp.createTemp('voice_');
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
    final l10n = AppLocalizations.of(context);

    if (_isRecording) {
      // Recording state: stop button + red pulsing indicator
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: VibraTheme.kSurface,
          border: Border(top: BorderSide(color: VibraTheme.kDivider)),
        ),
        child: SafeArea(
          child: Row(
            children: [
              // Recording indicator
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n?.chatRecording ?? 'Recording…',
                style: const TextStyle(
                  color: VibraTheme.kTextPrimary,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              // Stop button
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: VibraTheme.kError,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.stop, color: Colors.white, size: 18),
                  onPressed: _stopRecording,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
      );
    }

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
            // Mic icon — starts voice recording
            IconButton(
              icon: const Icon(Icons.mic,
                  color: VibraTheme.kTextMuted, size: 22),
              onPressed: _startRecording,
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

  // Voice playback state
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;
  String? _audioUrl;
  StreamSubscription? _playerStateSub;
  StreamSubscription? _playerPositionSub;

  @override
  void initState() {
    super.initState();
    final message = widget.message;
    final key = message.mediaKey ?? '';
    if (message.kind == 'photo' && key.isNotEmpty) {
      _urlFuture =
          ref.read(chatServiceProvider).getMediaUrl(key);
    } else if (message.kind == 'audio' && key.isNotEmpty) {
      _initAudio();
    }
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _playerPositionSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initAudio() async {
    final key = widget.message.mediaKey ?? '';
    try {
      final url = await ref.read(chatServiceProvider).getMediaUrl(key, kind: 'album');
      if (!mounted) return;
      setState(() => _audioUrl = url);

      // Listen for state changes
      _playerStateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
        if (!mounted) return;
        setState(() => _isPlaying = state == PlayerState.playing);
      });

      // Listen for position updates
      _playerPositionSub = _audioPlayer.onPositionChanged.listen((pos) {
        if (!mounted) return;
        setState(() => _audioPosition = pos);
      });

      // Get duration when available
      final dur = await _audioPlayer.getDuration();
      if (dur != null && mounted) {
        setState(() => _audioDuration = dur);
      }
    } catch (_) {
      // Audio URL fetch failed — bubble will show broken state
    }
  }

  Future<void> _togglePlayback() async {
    if (_audioUrl == null) return;
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(UrlSource(_audioUrl!));
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isMe = widget.isMe;

    // If the message was unsent, show a placeholder instead of the original
    // content regardless of kind.
    if (message.unsentAt != null) {
      final placeholder = AppLocalizations.of(context)?.chatUnsentMessage ?? '[Message unsent]';
      return Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: _bubbleMargin(isMe),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: VibraTheme.kSurfaceElevated.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: VibraTheme.kDivider.withValues(alpha: 0.3)),
              ),
              child: Text(
                placeholder,
                style: const TextStyle(
                  color: VibraTheme.kTextSecondary,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        ],
      );
    }

    Widget bubble;
    switch (message.kind) {
      case 'photo':
        bubble = _buildPhotoBubble(context, isMe);
        break;
      case 'ephemeral_photo':
        bubble = _buildEphemeralBubble(context, isMe);
        break;
      case 'audio':
        bubble = _buildVoiceBubble(isMe);
        break;
      default:
        bubble = _buildTextBubble(isMe);
    }

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onLongPress: () => _showActionPicker(context, ref),
          child: bubble,
        ),
        if (message.reactions.isNotEmpty) _buildReactionChips(context, isMe),
      ],
    );
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

  // ── Voice bubble ─────────────────────────────────────────────────────────────

  Widget _buildVoiceBubble(bool isMe) {
    final l10n = AppLocalizations.of(context);
    final displayDuration = _audioDuration > Duration.zero
        ? _formatDuration(_audioDuration)
        : _formatDuration(_audioPosition);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: _bubbleMargin(isMe),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Play / pause button
            GestureDetector(
              onTap: _togglePlayback,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isMe
                      ? VibraTheme.kAccent
                      : VibraTheme.kAccent.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n?.chatVoiceMessage ?? 'Voice message',
                  style: TextStyle(
                    color: isMe ? VibraTheme.kAccent : VibraTheme.kTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  displayDuration,
                  style: TextStyle(
                    color: isMe
                        ? VibraTheme.kAccent.withValues(alpha: 0.7)
                        : VibraTheme.kTextSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
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

  // ── Action picker (reactions + unsend) ─────────────────────────────────────

  static const _kReactionEmojis = ['❤️', '😂', '👍', '😮', '😢', '🔥'];

  void _showActionPicker(BuildContext context, WidgetRef ref) {
    final myId = ref.read(authStateProvider).userId ?? '';
    final message = widget.message;
    final isMe = widget.isMe;
    final existing =
        message.reactions.where((r) => r.userId == myId).firstOrNull;

    showModalBottomSheet(
      context: context,
      backgroundColor: VibraTheme.kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Emoji reaction row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _kReactionEmojis.map((emoji) {
                  final selected = existing?.emoji == emoji;
                  return GestureDetector(
                    onTap: () {
                      Navigator.of(ctx).pop();
                      final service = ref.read(chatServiceProvider);
                      if (selected) {
                        service.removeReaction(message.id);
                      } else {
                        service.setReaction(message.id, emoji);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: selected
                            ? VibraTheme.kAccent.withValues(alpha: 0.2)
                            : null,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(emoji,
                          style: const TextStyle(fontSize: 28)),
                    ),
                  );
                }).toList(),
              ),
              // Unsend option for own messages (only if not already unsent)
              if (isMe && message.unsentAt == null) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Divider(color: VibraTheme.kDivider),
                ),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _unsendMessage(context, ref);
                    },
                    icon: const Icon(Icons.undo, color: VibraTheme.kError, size: 20),
                    label: Text(
                      AppLocalizations.of(context)?.chatUnsend ?? 'Unsend',
                      style: const TextStyle(color: VibraTheme.kError),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _unsendMessage(BuildContext context, WidgetRef ref) {
    final message = widget.message;
    final service = ref.read(chatServiceProvider);
    service.unsendMessage(message.id).catchError((_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to unsend message')),
        );
      }
    });
  }

  Widget _buildReactionChips(BuildContext context, bool isMe) {
    final myId = ref.read(authStateProvider).userId ?? '';

    // Aggregate reactions: emoji -> list of userIds
    final Map<String, List<String>> agg = {};
    for (final r in widget.message.reactions) {
      agg.putIfAbsent(r.emoji, () => []);
      agg[r.emoji]!.add(r.userId);
    }

    return Padding(
      padding: EdgeInsets.only(
        top: 2,
        left: isMe ? 60 : 0,
        right: isMe ? 0 : 60,
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        direction: Axis.horizontal,
        children: agg.entries.map((entry) {
          final emoji = entry.key;
          final reactors = entry.value;
          final count = reactors.length;
          final isMine = reactors.contains(myId);

          return GestureDetector(
            onTap: isMine
                ? () {
                    final service = ref.read(chatServiceProvider);
                    service.removeReaction(widget.message.id);
                  }
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isMine
                    ? VibraTheme.kAccent.withValues(alpha: 0.2)
                    : VibraTheme.kChip,
                borderRadius: BorderRadius.circular(12),
                border: isMine
                    ? Border.all(
                        color: VibraTheme.kAccent.withValues(alpha: 0.4),
                        width: 1)
                    : null,
              ),
              child: Text(
                count > 1 ? '$emoji $count' : emoji,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          );
        }).toList(),
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
