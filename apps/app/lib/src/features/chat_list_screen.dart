import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../chat/chat_service.dart';
import '../chat/models.dart';
import '../albums/shared_albums_provider.dart';
import '../theme/widgets.dart';
import '../theme/app_theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../boost/boost_service.dart';
import 'circles_screen.dart';

/// Buzón screen — Grindr-style inbox with two tabs:
///
///   • Bandeja — list of conversations, with album-update banner + filter
///     chips above the list.
///   • Álbumes — horizontal carousel of albums shared with the user.
///
/// A Boost FAB sits on top of both tabs.
class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();

  /// Converts an ISO-8601 timestamp to a human-readable relative time string.
  ///
  /// Rules:
  ///   - < 1 min → l10n.justNow
  ///   - < 60 min → l10n.minAgo(minutes)
  ///   - same day → HH:mm
  ///   - yesterday → l10n.yesterday
  ///   - < 7 days → l10n.daysAgo(days)
  ///   - older → dd/MM/yyyy
  static String relativeTime(String iso, AppLocalizations l10n,
      {DateTime? clockNow}) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = clockNow ?? DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) {
        return l10n.justNow;
      }
      if (diff.inHours < 1) {
        return l10n.minAgo(diff.inMinutes);
      }

      // Same calendar day (regardless of hour difference crossing midnight)
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return DateFormat('HH:mm').format(dt);
      }

      final yesterday = DateTime(now.year, now.month, now.day - 1);
      if (dt.year == yesterday.year &&
          dt.month == yesterday.month &&
          dt.day == yesterday.day) {
        return l10n.yesterday;
      }

      if (diff.inDays < 7) {
        return l10n.daysAgo(diff.inDays);
      }

      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (_) {
      return '';
    }
  }
}

class _ChatListScreenState extends ConsumerState<ChatListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        backgroundColor: VibraTheme.kBg,
        title: Text(l10n.bandejaDeEntrada),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: VibraTheme.kBrandPrimary,
          indicatorWeight: 2,
          labelColor: VibraTheme.kTextPrimary,
          unselectedLabelColor: VibraTheme.kTextSecondary,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: [
            Tab(text: l10n.bandejaDeEntrada),
            Tab(text: l10n.circlesTitle),
            Tab(text: l10n.albumes),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _BandejaTab(
            onGoToAlbums: () => _tabController.animateTo(2),
          ),
          const CirclesScreen(),
          const _AlbumsTab(),
        ],
      ),
      floatingActionButton: const _BoostFab(),
    );
  }
}

// ---------------------------------------------------------------------------
// Bandeja (conversations) tab
// ---------------------------------------------------------------------------

class _BandejaTab extends ConsumerStatefulWidget {
  /// Switches the parent screen to the Álbumes tab when the album-update
  /// banner is tapped.
  final VoidCallback onGoToAlbums;

  const _BandejaTab({required this.onGoToAlbums});

  @override
  ConsumerState<_BandejaTab> createState() => _BandejaTabState();
}

class _BandejaTabState extends ConsumerState<_BandejaTab> {
  late Future<List<Conversation>> _conversationsFuture;

  /// Unread-only filter, hoisted here so it actually drives the rendered list.
  ///
  /// The previous _FilterChipsRow held this state internally and never
  /// plumbed it into the FutureBuilder, so the chip was visual-only.
  bool _soloNoLeido = false;

  @override
  void initState() {
    super.initState();
    _conversationsFuture = ref.read(chatServiceProvider).listConversations();
  }

  /// Re-fetches conversations and re-assigns [_conversationsFuture] so the
  /// FutureBuilder rebuilds. Used after returning from a chat (which may have
  /// marked messages read / sent a new message) and by pull-to-refresh.
  Future<void> _fetchConversations() {
    final future =
        ref.read(chatServiceProvider).listConversations();
    setState(() => _conversationsFuture = future);
    return future;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sharedAlbumsAsync = ref.watch(sharedAlbumsProvider);

    return Column(
      children: [
        // Album-update banner above chips — only when there are shared albums.
        //
        // SharedAlbum has no "updated since last seen" field, so the count is
        // the total shared-album count (the banner label already reads
        // "album(s) updated", the closest honest existing l10n). Tapping it
        // switches to the Álbumes tab where the carousel lives.
        sharedAlbumsAsync.when(
          data: (albums) => AlbumUpdateBanner(
            count: albums.length,
            onTap: widget.onGoToAlbums,
          ),
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        ),

        // Unread filter chip. The "En línea" chip was removed: Conversation
        // exposes no online/presence flag, so filtering by it would have been
        // a no-op (or would require fabricating data).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              FilterChipPill(
                label: l10n.noLeido,
                icon: Icons.circle,
                active: _soloNoLeido,
                onTap: () => setState(() => _soloNoLeido = !_soloNoLeido),
              ),
            ],
          ),
        ),

        const Divider(height: 1, color: VibraTheme.kDivider),

        // Conversation list
        Expanded(
          child: FutureBuilder<List<Conversation>>(
            future: _conversationsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _ErrorRetry(
                    message: l10n.errorCargandoConversaciones);
              }
              var conversations = snapshot.data ?? const [];
              if (_soloNoLeido) {
                conversations = conversations
                    .where((c) => c.unreadCount > 0)
                    .toList(growable: false);
              }
              if (conversations.isEmpty) {
                return Center(
                  child: Text(
                    l10n.noConversationsYet,
                    style: const TextStyle(color: VibraTheme.kTextSecondary),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () => _fetchConversations(),
                child: ListView.builder(
                  itemCount: conversations.length,
                  itemBuilder: (_, i) => _ConversationTile(
                    conversation: conversations[i],
                    onOpened: _fetchConversations,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback? onOpened;
  const _ConversationTile({required this.conversation, this.onOpened});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final displayName = conversation.displayTitle;
    final isGroup = conversation.isGroup;
    final lastMessage = conversation.lastMessagePreview ?? '';
    return InkWell(
      onTap: () async {
        await context.push(
            '/inbox/${conversation.conversationId}', extra: conversation);
        onOpened?.call();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: isGroup
                  ? VibraTheme.kAccent.withValues(alpha: 0.15)
                  : VibraTheme.kSurface,
              child: isGroup
                  ? const Icon(Icons.groups, color: VibraTheme.kAccent, size: 22)
                  : Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: VibraTheme.kTextPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: VibraTheme.kTextPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (conversation.lastMessageAt != null)
                        Text(
                          ChatListScreen.relativeTime(
                              conversation.lastMessageAt!, l10n),
                          style: const TextStyle(
                            color: VibraTheme.kTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VibraTheme.kTextSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (conversation.unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: const BoxDecoration(
                  color: VibraTheme.kBrandPrimary,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
                child: Text(
                  '${conversation.unreadCount}',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Álbumes tab
// ---------------------------------------------------------------------------

class _AlbumsTab extends ConsumerWidget {
  const _AlbumsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final sharedAlbumsAsync = ref.watch(sharedAlbumsProvider);

    return sharedAlbumsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _ErrorRetry(
        message: l10n.errorCargandoAlbumesCompartidos,
        onRetry: () => ref.invalidate(sharedAlbumsProvider),
      ),
      data: (albums) {
        if (albums.isEmpty) {
          return const AlbumUpdatesEmptyState();
        }
        return AlbumCarousel(
          albums: albums,
          onTap: (id) => context.push('/albums/$id'),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Boost FAB
// ---------------------------------------------------------------------------

class _BoostFab extends ConsumerWidget {
  const _BoostFab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return FloatingActionButton.extended(
      backgroundColor: VibraTheme.kSurface,
      foregroundColor: VibraTheme.kBrandPrimary,
      onPressed: () async {
        try {
          await ref.read(boostServiceProvider).activate();
          ref.invalidate(activeBoostProvider);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.you_boosted_snackbar)),
            );
          }
        } catch (_) {}
      },
      icon: const Icon(Icons.bolt),
      label: Text(
        l10n.boost,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error retry helper
// ---------------------------------------------------------------------------

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _ErrorRetry({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(color: VibraTheme.kError)),
          const SizedBox(height: 12),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(l10n.reintentar),
            ),
        ],
      ),
    );
  }
}