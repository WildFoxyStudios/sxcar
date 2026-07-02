import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../theme/admin_theme.dart';
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
      id:            json['id']             as String? ?? '',
      email:         json['email']          as String? ?? '',
      emailVerified: json['email_verified'] as bool?   ?? false,
      status:        json['status']         as String? ?? 'unknown',
      role:          json['role']           as String? ?? 'user',
      createdAt:     json['created_at']     as String? ?? '',
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
      users:    usersList,
      total:    json['total'] as int? ?? 0,
      byStatus: byStatusList,
    );
  }
}

final userListProvider =
    FutureProvider.autoDispose.family<UserListResponse, String>(
        (ref, query) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/users', queryParameters: {
    'q':      query,
    'limit':  '20',
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
    setState(() => _currentQuery = query.trim());
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(userListProvider(_currentQuery));

    return AdminLayout(
      selectedIndex: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Row(
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Users',
                      style: TextStyle(
                        color: AdminTheme.kText,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Manage platform accounts',
                      style: TextStyle(color: AdminTheme.kMuted, fontSize: 12),
                    ),
                  ],
                ),
                const Spacer(),
                usersAsync.maybeWhen(
                  data: (r) => Text(
                    '${r.total} total',
                    style: const TextStyle(color: AdminTheme.kMuted, fontSize: 12),
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
          ),

          // ── Search bar ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: AdminTheme.kText, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search by email…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  contentPadding: EdgeInsets.zero,
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            _onSearch('');
                          },
                        )
                      : null,
                ),
                onSubmitted: _onSearch,
                onChanged: (v) {
                  if (v.isEmpty && _currentQuery.isNotEmpty) {
                    _onSearch('');
                  }
                  setState(() {});
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Table ─────────────────────────────────────────────────────────
          Expanded(
            child: usersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _errorState(error.toString()),
              data: (response) => _buildTable(context, response),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState(String error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40, color: AdminTheme.kRed),
          const SizedBox(height: 12),
          Text(
            'Failed to load users: $error',
            style: const TextStyle(color: AdminTheme.kMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context, UserListResponse response) {
    if (response.users.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search, size: 40, color: AdminTheme.kMuted),
            SizedBox(height: 12),
            Text(
              'No users found.',
              style: TextStyle(color: AdminTheme.kMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Table header
        Container(
          height: 40,
          decoration: const BoxDecoration(
            color: AdminTheme.kSurface,
            border: Border(
              bottom: BorderSide(color: AdminTheme.kBorder),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: const Row(
            children: [
              Expanded(
                flex: 5,
                child: _ColHeader('EMAIL'),
              ),
              SizedBox(width: 110, child: _ColHeader('STATUS')),
              SizedBox(width: 80,  child: _ColHeader('ROLE')),
              SizedBox(width: 170, child: _ColHeader('CREATED')),
              SizedBox(width: 48),
            ],
          ),
        ),
        // Table body
        Expanded(
          child: ListView.builder(
            itemCount: response.users.length,
            itemBuilder: (ctx, i) {
              final user = response.users[i];
              return _UserTableRow(user: user);
            },
          ),
        ),
        // Footer
        Container(
          height: 36,
          decoration: const BoxDecoration(
            color: AdminTheme.kSurface,
            border: Border(top: BorderSide(color: AdminTheme.kBorder)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Text(
                'Showing ${response.users.length} of ${response.total} users',
                style: const TextStyle(
                  color: AdminTheme.kMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Column header ─────────────────────────────────────────────────────────────

class _ColHeader extends StatelessWidget {
  final String label;
  const _ColHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: const TextStyle(
          color: AdminTheme.kMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

// ── User table row ────────────────────────────────────────────────────────────

class _UserTableRow extends StatefulWidget {
  final UserRow user;
  const _UserTableRow({required this.user});

  @override
  State<_UserTableRow> createState() => _UserTableRowState();
}

class _UserTableRowState extends State<_UserTableRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => context.push('/users/${widget.user.id}'),
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: _hovered
                ? AdminTheme.kBorder.withValues(alpha: 0.5)
                : Colors.transparent,
            border: const Border(
              bottom: BorderSide(color: AdminTheme.kBorder, width: 0.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AdminTheme.kAccentBg,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          widget.user.email.isNotEmpty
                              ? widget.user.email[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: AdminTheme.kAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.user.email,
                        style: const TextStyle(
                          color: AdminTheme.kText,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 110,
                child: _StatusChip(status: widget.user.status),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  widget.user.role,
                  style: const TextStyle(
                    color: AdminTheme.kMuted,
                    fontSize: 12,
                  ),
                ),
              ),
              SizedBox(
                width: 170,
                child: Text(
                  _fmtDate(widget.user.createdAt),
                  style: const TextStyle(
                    color: AdminTheme.kMuted,
                    fontSize: 12,
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                child: Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: _hovered ? AdminTheme.kMuted : AdminTheme.kBorder,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(String iso) {
    if (iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.length > 10 ? iso.substring(0, 10) : iso;
    }
  }
}

// ── Status chip (shared) ─────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, String label) = switch (status) {
      'active'    => (AdminTheme.kGreen,  AdminTheme.kGreen.withValues(alpha: 0.12),  'Active'),
      'suspended' => (AdminTheme.kOrange, AdminTheme.kOrange.withValues(alpha: 0.12), 'Suspended'),
      'banned'    => (AdminTheme.kRed,    AdminTheme.kRed.withValues(alpha: 0.12),    'Banned'),
      _           => (AdminTheme.kMuted,  AdminTheme.kBorder,                         status),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
