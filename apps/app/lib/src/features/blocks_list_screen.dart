import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/gen/app_localizations.dart';
import '../auth/auth_provider.dart';
import '../theme/app_theme.dart';

/// Standalone blocked-users list. Replaces the old Blocks tab of settings.
class BlocksListScreen extends ConsumerStatefulWidget {
  const BlocksListScreen({super.key});

  @override
  ConsumerState<BlocksListScreen> createState() => _BlocksListScreenState();
}

class _BlocksListScreenState extends ConsumerState<BlocksListScreen> {
  List<Map<String, dynamic>> _blocks = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get<Map<String, dynamic>>('/blocks');
      final list = (response.data!['blocks'] as List<dynamic>)
          .map((b) => b as Map<String, dynamic>)
          .toList();
      if (!mounted) return;
      setState(() {
        _blocks = list;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error: ${e.response?.statusCode ?? e.message}';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _unblock(String userId) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/blocks/$userId');
      if (!mounted) return;
      setState(() => _blocks.removeWhere((b) => b['user_id'] == userId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User unblocked')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        title: Text(l10n.desbloquearUsuarios),
        backgroundColor: VibraTheme.kBg,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    if (_blocks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
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
                child: const Icon(Icons.block,
                    color: VibraTheme.kTextSecondary, size: 36),
              ),
              const SizedBox(height: 20),
              Text(
                'No hay usuarios bloqueados',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _blocks.length,
      itemBuilder: (_, i) {
        final user = _blocks[i];
        final displayName =
            user['display_name'] as String? ?? 'Unknown user';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: VibraTheme.kSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _unblock(user['user_id'] as String),
                child: const Text(
                  'Desbloquear',
                  style: TextStyle(color: VibraTheme.kBrandPrimary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}