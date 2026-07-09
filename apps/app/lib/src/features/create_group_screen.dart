import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../chat/chat_service.dart';
import '../theme/app_theme.dart';
import '../../l10n/gen/app_localizations.dart';

/// Screen for creating a new group (Circle) conversation.
///
/// The user enters a group name and selects members from a searchable list
/// of users. Currently uses manual UUID entry for simplicity; in production
/// this would integrate with a user search endpoint.
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final _memberIdController = TextEditingController();
  final List<String> _memberIds = [];
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _memberIdController.dispose();
    super.dispose();
  }

  void _addMember() {
    final id = _memberIdController.text.trim();
    if (id.isEmpty || _memberIds.contains(id)) return;
    setState(() {
      _memberIds.add(id);
    });
    _memberIdController.clear();
  }

  void _removeMember(String id) {
    setState(() {
      _memberIds.remove(id);
    });
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _memberIds.isEmpty) return;

    setState(() => _creating = true);

    try {
      final chatService = ref.read(chatServiceProvider);
      await chatService.createGroup(name: name, memberIds: _memberIds);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)?.groupCreated ?? 'Group created'),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.errorGenerico(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        backgroundColor: VibraTheme.kBg,
        title: Text(l10n.createGroup),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Group name field
            Text(
              l10n.groupName,
              style: const TextStyle(
                color: VibraTheme.kTextSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: VibraTheme.kSurfaceElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _nameController,
                style: const TextStyle(
                    color: VibraTheme.kTextPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: l10n.groupNameHint,
                  hintStyle: const TextStyle(
                      color: VibraTheme.kTextMuted, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Member selection
            Text(
              l10n.addMembers,
              style: const TextStyle(
                color: VibraTheme.kTextSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),

            // Member input
            Row(
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
                          color: VibraTheme.kTextPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: l10n.userIdHint,
                        hintStyle: const TextStyle(
                            color: VibraTheme.kTextMuted, fontSize: 14),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    icon: const Icon(Icons.add, color: Colors.black, size: 20),
                    onPressed: _addMember,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Member chips
            if (_memberIds.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _memberIds.map((id) {
                  return Chip(
                    label: Text(
                      id.length > 12 ? '${id.substring(0, 12)}…' : id,
                      style: const TextStyle(
                          color: VibraTheme.kTextPrimary, fontSize: 12),
                    ),
                    backgroundColor: VibraTheme.kChip,
                    deleteIcon: const Icon(Icons.close,
                        color: VibraTheme.kTextMuted, size: 16),
                    onDeleted: () => _removeMember(id),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  );
                }).toList(),
              ),

            const Spacer(),

            // Create button
            ElevatedButton(
              onPressed:
                  (_nameController.text.trim().isNotEmpty && _memberIds.isNotEmpty && !_creating)
                      ? _createGroup
                      : null,
              child: _creating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : Text(l10n.createGroup),
            ),
          ],
        ),
      ),
    );
  }
}
