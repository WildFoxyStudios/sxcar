import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/admin_http_client.dart';
import '../../widgets/admin_layout.dart';

class UserRow {
  final String id;
  final String email;
  final bool emailVerified;
  final String status;
  final String role;
  final String createdAt;

  UserRow({
    required this.id,
    required this.email,
    required this.emailVerified,
    required this.status,
    required this.role,
    required this.createdAt,
  });

  factory UserRow.fromJson(Map<String, dynamic> json) {
    return UserRow(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      emailVerified: json['email_verified'] as bool? ?? false,
      status: json['status'] as String? ?? 'unknown',
      role: json['role'] as String? ?? 'user',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

class UserListResponse {
  final List<UserRow> users;
  final int total;
  final List<Map<String, dynamic>> byStatus;

  UserListResponse({
    required this.users,
    required this.total,
    required this.byStatus,
  });

  factory UserListResponse.fromJson(Map<String, dynamic> json) {
    final usersList = (json['users'] as List<dynamic>?)
            ?.map((e) => UserRow.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final byStatusList = (json['by_status'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
    return UserListResponse(
      users: usersList,
      total: json['total'] as int? ?? 0,
      byStatus: byStatusList,
    );
  }
}

final userListProvider = FutureProvider.autoDispose.family<UserListResponse, String>((ref, query) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/users', queryParameters: {
    'q': query,
    'limit': '20',
    'offset': '0',
  });
  return UserListResponse.fromJson(response.data as Map<String, dynamic>);
});

class UserListScreen extends ConsumerStatefulWidget {
  const UserListScreen({super.key});

  @override
  ConsumerState<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends ConsumerState<UserListScreen> {
  final _searchController = TextEditingController();
  String _currentQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    setState(() {
      _currentQuery = query.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(userListProvider(_currentQuery));

    return AdminLayout(
      selectedIndex: 1,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Users',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by email...',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearch('');
                        },
                      )
                    : null,
              ),
              onSubmitted: _onSearch,
              onChanged: (value) {
                if (value.isEmpty && _currentQuery.isNotEmpty) {
                  _onSearch('');
                }
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: usersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Failed to load users: $error'),
                    ],
                  ),
                ),
                data: (response) => _buildUserList(context, response),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserList(BuildContext context, UserListResponse response) {
    if (response.users.isEmpty) {
      return const Center(child: Text('No users found.'));
    }

    return ListView.builder(
      itemCount: response.users.length,
      itemBuilder: (context, index) {
        final user = response.users[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              child: Text(user.email.isNotEmpty
                  ? user.email[0].toUpperCase()
                  : '?'),
            ),
            title: Text(user.email),
            subtitle: Text('Created: ${user.createdAt}'),
            trailing: _statusBadge(user.status),
            onTap: () => context.push('/users/${user.id}'),
          ),
        );
      },
    );
  }

  Widget _statusBadge(String status) {
    final (Color color, String label) = switch (status) {
      'active' => (Colors.green, 'Active'),
      'suspended' => (Colors.orange, 'Suspended'),
      'banned' => (Colors.red, 'Banned'),
      _ => (Colors.grey, status),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
