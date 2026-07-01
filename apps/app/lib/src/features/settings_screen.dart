import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';

/// Settings screen with notification prefs, privacy toggles, blocked users,
/// and account actions.  Parameterized by [initialTab].
class SettingsScreen extends ConsumerStatefulWidget {
  final String initialTab;

  const SettingsScreen({super.key, this.initialTab = 'notifications'});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Notification preferences
  bool _newMessages = false;
  bool _newTaps = false;
  bool _promotions = false;
  bool _notifPrefsLoading = true;
  String? _notifPrefsError;

  // Privacy local toggles
  bool _showDistance = true;
  bool _showOnlineStatus = true;
  bool _discreetMode = false;

  // Blocked users
  List<Map<String, dynamic>> _blockedUsers = [];
  bool _blocksLoading = true;
  String? _blocksError;

  // Tab index mapping
  int get _initialIndex {
    switch (widget.initialTab) {
      case 'privacy':
        return 1;
      case 'blocks':
        return 2;
      default:
        return 0;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: _initialIndex,
    );
    _loadNotificationPreferences();
    _loadBlockedUsers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- Notification Preferences ---

  Future<void> _loadNotificationPreferences() async {
    setState(() {
      _notifPrefsLoading = true;
      _notifPrefsError = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get<Map<String, dynamic>>(
        '/notifications/preferences',
      );
      final data = response.data!;
      setState(() {
        _newMessages = (data['new_messages'] as bool?) ?? false;
        _newTaps = (data['new_taps'] as bool?) ?? false;
        _promotions = (data['promotions'] as bool?) ?? false;
        _notifPrefsLoading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _notifPrefsLoading = false;
        _notifPrefsError =
            'Failed to load: ${e.response?.statusCode ?? e.message}';
      });
    } catch (e) {
      setState(() {
        _notifPrefsLoading = false;
        _notifPrefsError = 'Failed to load: $e';
      });
    }
  }

  Future<void> _updateNotificationPreference(String key, bool value) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.put<Map<String, dynamic>>(
        '/notifications/preferences',
        data: {key: value},
      );
      // Optimistic update already applied via setState in the SwitchListTile
    } on DioException catch (e) {
      // Revert on failure
      _loadNotificationPreferences();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update: ${e.response?.statusCode ?? e.message}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      _loadNotificationPreferences();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- Blocked Users ---

  Future<void> _loadBlockedUsers() async {
    setState(() {
      _blocksLoading = true;
      _blocksError = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get<Map<String, dynamic>>('/blocks');
      final blocksJson = response.data!['blocks'] as List<dynamic>;
      setState(() {
        _blockedUsers = blocksJson
            .map((b) => b as Map<String, dynamic>)
            .toList();
        _blocksLoading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _blocksLoading = false;
        _blocksError = 'Failed to load: ${e.response?.statusCode ?? e.message}';
      });
    } catch (e) {
      setState(() {
        _blocksLoading = false;
        _blocksError = 'Failed to load: $e';
      });
    }
  }

  Future<void> _unblockUser(String userId) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/blocks/$userId');
      setState(() {
        _blockedUsers.removeWhere((b) => b['user_id'] == userId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User unblocked'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unblock: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- Account Actions ---

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authStateProvider.notifier).logout();
    }
  }

  void _deleteAccount() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete Account'),
        content: const Text('This feature is not yet available.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: theme.colorScheme.primary,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Notifications'),
            Tab(text: 'Privacy'),
            Tab(text: 'Blocks'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNotificationsTab(theme),
          _buildPrivacyTab(theme),
          _buildBlocksTab(theme),
        ],
      ),
    );
  }

  // --- Saved Phrases shortcut ---

  /// A shortcut to the saved phrases screen, rendered at the top of the
  /// notifications tab so it's always visible.
  Widget _buildPhrasesShortcut(ThemeData theme) {
    return Card(
      color: const Color(0xFF1A1A1A),
      child: ListTile(
        leading: const Icon(Icons.chat_bubble_outline, color: Colors.white70),
        title: const Text('Saved Phrases'),
        subtitle: const Text(
          'Quick chat lines you can reuse',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () => context.push('/settings/phrases'),
      ),
    );
  }

  /// A shortcut to the active sessions / devices screen.
  Widget _buildSessionsShortcut(ThemeData theme) {
    return Card(
      color: const Color(0xFF1A1A1A),
      child: ListTile(
        leading: const Icon(Icons.devices, color: Colors.white70),
        title: const Text('Active Sessions'),
        subtitle: const Text(
          'Devices signed in to your account',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () => context.push('/settings/sessions'),
      ),
    );
  }

  // --- Notifications Tab ---

  Widget _buildNotificationsTab(ThemeData theme) {
    if (_notifPrefsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_notifPrefsError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _notifPrefsError!,
              style: const TextStyle(color: Colors.red, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadNotificationPreferences,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildPhrasesShortcut(theme),
        _buildSessionsShortcut(theme),
        const SizedBox(height: 16),
        Card(
          color: const Color(0xFF1A1A1A),
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('New Messages'),
                subtitle: const Text(
                  'Get notified when someone sends you a message',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                value: _newMessages,
                activeThumbColor: theme.colorScheme.primary,
                onChanged: (val) {
                  setState(() => _newMessages = val);
                  _updateNotificationPreference('new_messages', val);
                },
              ),
              const Divider(height: 1, color: Color(0xFF2A2A2A)),
              SwitchListTile(
                title: const Text('New Taps'),
                subtitle: const Text(
                  'Get notified when someone taps you',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                value: _newTaps,
                activeThumbColor: theme.colorScheme.primary,
                onChanged: (val) {
                  setState(() => _newTaps = val);
                  _updateNotificationPreference('new_taps', val);
                },
              ),
              const Divider(height: 1, color: Color(0xFF2A2A2A)),
              SwitchListTile(
                title: const Text('Promotions'),
                subtitle: const Text(
                  'Receive promotional offers and updates',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                value: _promotions,
                activeThumbColor: theme.colorScheme.primary,
                onChanged: (val) {
                  setState(() => _promotions = val);
                  _updateNotificationPreference('promotions', val);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Privacy Tab ---

  Widget _buildPrivacyTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFF1A1A1A),
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Show Distance'),
                subtitle: const Text(
                  'Display your distance to other users',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                value: _showDistance,
                activeThumbColor: theme.colorScheme.primary,
                onChanged: (val) {
                  setState(() => _showDistance = val);
                },
              ),
              const Divider(height: 1, color: Color(0xFF2A2A2A)),
              SwitchListTile(
                title: const Text('Show Online Status'),
                subtitle: const Text(
                  'Let others see when you are online',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                value: _showOnlineStatus,
                activeThumbColor: theme.colorScheme.primary,
                onChanged: (val) {
                  setState(() => _showOnlineStatus = val);
                },
              ),
              const Divider(height: 1, color: Color(0xFF2A2A2A)),
              SwitchListTile(
                title: const Text('Discreet Mode'),
                subtitle: const Text(
                  'Hide your profile photo from the grid',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                value: _discreetMode,
                activeThumbColor: theme.colorScheme.primary,
                onChanged: (val) {
                  setState(() => _discreetMode = val);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Blocks Tab ---

  Widget _buildBlocksTab(ThemeData theme) {
    if (_blocksLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_blocksError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _blocksError!,
              style: const TextStyle(color: Colors.red, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadBlockedUsers,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_blockedUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block, size: 64, color: Colors.grey.shade600),
            const SizedBox(height: 16),
            Text(
              'No blocked users',
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'When you block someone, they will appear here.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFF1A1A1A),
          child: Column(
            children: _blockedUsers.asMap().entries.map((entry) {
              final idx = entry.key;
              final user = entry.value;
              final userId = user['user_id'] as String? ?? '';
              final displayName =
                  user['display_name'] as String? ?? 'Unknown User';
              final reason = user['reason'] as String?;

              return Column(
                children: [
                  if (idx > 0)
                    const Divider(height: 1, color: Color(0xFF2A2A2A)),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.grey.shade700,
                      child: Text(
                        (displayName.isNotEmpty ? displayName[0] : '?')
                            .toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(displayName),
                    subtitle: reason != null
                        ? Text(
                            reason,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          )
                        : null,
                    trailing: TextButton(
                      onPressed: () => _unblockUser(userId),
                      child: const Text(
                        'Unblock',
                        style: TextStyle(color: Color(0xFFF4C542)),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 24),

        // Account section
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'ACCOUNT',
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.grey,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Card(
          color: const Color(0xFF1A1A1A),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: _logout,
              ),
              const Divider(height: 1, color: Color(0xFF2A2A2A)),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text(
                  'Delete Account',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: _deleteAccount,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
