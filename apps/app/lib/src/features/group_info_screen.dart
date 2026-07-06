import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';
import '../chat/chat_service.dart';
import '../theme/app_theme.dart';
import '../../l10n/gen/app_localizations.dart';

/// Screen showing group details: name, member list, add/remove members.
class GroupInfoScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupInfoScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  String? _error;
  final _memberIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _memberIdController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    try {
      final chatService = ref.read(chatServiceProvider);
      final members = await chatService.listGroupMembers(widget.groupId);
      if (!mounted) return;
      setState(() {
        _members = members;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _addMember() async {
    final id = _memberIdController.text.trim();
    if (id.isEmpty) return;

    try {
      final chatService = ref.read(chatServiceProvider);
      await chatService.addGroupMember(widget.groupId, id);
      _memberIdController.clear();
      _loadMembers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding member: $e')),
      );
    }
  }

  Future<void> _removeMember(String userId) async {
    try {
      final chatService = ref.read(chatServiceProvider);
      await chatService.removeGroupMember(widget.groupId, userId);
      _loadMembers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error removing member: $e')),
      );
    }
  }

  Future<void> _leaveGroup() async {
    final myId = ref.read(authStateProvider).userId;
    if (myId == null) return;
    await _removeMember(myId);
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final myId = ref.read(authStateProvider).userId;

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        backgroundColor: VibraTheme.kBg,
        title: Text(l10n.groupInfo),
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _leaveGroup,
            icon: const Icon(Icons.exit_to_app,
                color: VibraTheme.kError, size: 18),
            label: Text(
              l10n.leaveGroup,
              style: const TextStyle(color: VibraTheme.kError, fontSize: 13),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: VibraTheme.kAccent))
          : _error != null
              ? Center(
                  child: Text('Error: $_error',
                      style: const TextStyle(color: VibraTheme.kError)),
                )
              : Column(
                  children: [
                    // Member count
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text(
                        l10n.memberCount(_members.length),
                        style: const TextStyle(
                          color: VibraTheme.kTextSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: VibraTheme.kDivider),

                    // Add member input
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: VibraTheme.kSurfaceElevated,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: TextField(
                                controller: _memberIdController,
                                style: const TextStyle(
                                    color: VibraTheme.kTextPrimary,
                                    fontSize: 14),
                                decoration: const InputDecoration(
                                  hintText: 'user_id (UUID)',
                                  hintStyle: TextStyle(
                                      color: VibraTheme.kTextMuted,
                                      fontSize: 14),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: const BoxDecoration(
                              color: VibraTheme.kAccent,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.person_add,
                                  color: Colors.black, size: 20),
                              onPressed: _addMember,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 40, minHeight: 40),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: VibraTheme.kDivider),

                    // Member list
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _members.length,
                        itemBuilder: (_, i) {
                          final member = _members[i];
                          final userId =
                              member['user_id'] as String? ?? '';
                          final displayName =
                              member['display_name'] as String?;
                          final isMe = userId == myId;

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: VibraTheme.kSurface,
                              child: Text(
                                (displayName ?? '?')[0].toUpperCase(),
                                style: const TextStyle(
                                  color: VibraTheme.kTextPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            title: Text(
                              displayName ?? userId,
                              style: const TextStyle(
                                color: VibraTheme.kTextPrimary,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              isMe ? 'You' : userId,
                              style: const TextStyle(
                                color: VibraTheme.kTextSecondary,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: isMe
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.remove_circle_outline,
                                        color: VibraTheme.kError, size: 20),
                                    onPressed: () => _removeMember(userId),
                                  ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
