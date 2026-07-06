import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../chat/chat_service.dart';
import '../theme/app_theme.dart';
import '../../l10n/gen/app_localizations.dart';

/// Screen listing all group conversations (Circles) for the current user.
class CirclesScreen extends ConsumerStatefulWidget {
  const CirclesScreen({super.key});

  @override
  ConsumerState<CirclesScreen> createState() => _CirclesScreenState();
}

class _CirclesScreenState extends ConsumerState<CirclesScreen> {
  late Future<List<Map<String, dynamic>>> _groupsFuture;

  @override
  void initState() {
    super.initState();
    _groupsFuture = ref.read(chatServiceProvider).listGroups();
  }

  void _refresh() {
    setState(() {
      _groupsFuture = ref.read(chatServiceProvider).listGroups();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        backgroundColor: VibraTheme.kBg,
        title: Text(l10n.circlesTitle),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add, color: VibraTheme.kAccent),
            tooltip: l10n.createGroup,
            onPressed: () async {
              await context.push('/inbox/create-group');
              _refresh();
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _groupsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: VibraTheme.kAccent),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  '${l10n.errorCargandoConversaciones}: ${snapshot.error}',
                  style: const TextStyle(color: VibraTheme.kError),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final groups = snapshot.data ?? [];
          if (groups.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: VibraTheme.kSurface,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.groups,
                        size: 32, color: VibraTheme.kTextMuted),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noGroupsYet,
                    style: const TextStyle(
                      color: VibraTheme.kTextPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await context.push('/inbox/create-group');
                      _refresh();
                    },
                    icon: const Icon(Icons.group_add, size: 18),
                    label: Text(l10n.createGroup),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              _refresh();
            },
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: groups.length,
              itemBuilder: (_, i) {
                final group = groups[i];
                return _GroupTile(
                  groupId: group['group_id'] as String,
                  name: group['name'] as String? ?? 'Group',
                  memberCount: (group['member_count'] as num?)?.toInt() ?? 0,
                  lastMessage: group['last_message_preview'] as String?,
                  lastMessageAt: group['last_message_at'] as String?,
                  onTap: () {
                    context.push('/inbox/${group['group_id']}');
                  },
                  onInfoTap: () async {
                    await context.push(
                      '/inbox/group-info/${group['group_id']}',
                    );
                    _refresh();
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final String groupId;
  final String name;
  final int memberCount;
  final String? lastMessage;
  final String? lastMessageAt;
  final VoidCallback onTap;
  final VoidCallback onInfoTap;

  const _GroupTile({
    required this.groupId,
    required this.name,
    required this.memberCount,
    this.lastMessage,
    this.lastMessageAt,
    required this.onTap,
    required this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: VibraTheme.kAccent.withValues(alpha: 0.15),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'G',
                style: const TextStyle(
                  color: VibraTheme.kAccent,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
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
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: onInfoTap,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.info_outline,
                              color: VibraTheme.kTextMuted, size: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '$memberCount members',
                        style: const TextStyle(
                          color: VibraTheme.kTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (lastMessage != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            lastMessage!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: VibraTheme.kTextSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
