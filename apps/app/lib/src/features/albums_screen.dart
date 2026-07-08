import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../albums/shared_albums_provider.dart';
import '../auth/auth_provider.dart';
import '../../l10n/gen/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// Model for an album from the backend response.
class Album {
  final String id;
  final String? name;
  final String? description;
  final bool isPrivate;
  final int photoCount;
  final String? coverPhotoUrl;
  final String createdAt;

  const Album({
    required this.id,
    this.name,
    this.description,
    required this.isPrivate,
    required this.photoCount,
    this.coverPhotoUrl,
    required this.createdAt,
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'] as String,
      name: json['name'] as String?,
      description: json['description'] as String?,
      isPrivate: json['is_private'] as bool? ?? false,
      photoCount: json['photo_count'] as int? ?? 0,
      coverPhotoUrl: json['cover_photo_url'] as String?,
      createdAt: json['created_at'] as String,
    );
  }
}

/// Screen that lists albums owned by the authenticated user.
class AlbumsScreen extends ConsumerStatefulWidget {
  const AlbumsScreen({super.key});

  @override
  ConsumerState<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends ConsumerState<AlbumsScreen> {
  List<Album>? _albums;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get<Map<String, dynamic>>('/albums');
      final albumsJson = response.data!['albums'] as List<dynamic>;
      final albums = albumsJson
          .map((a) => Album.fromJson(a as Map<String, dynamic>))
          .toList();

      if (!mounted) return;
      setState(() {
        _albums = albums;
        _isLoading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load albums: ${e.response?.statusCode ?? e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load albums: $e';
      });
    }
  }

  Future<void> _showCreateDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    bool isPrivate = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.albumCreateTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: l10n.albumNameLabel,
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: l10n.albumDescriptionOptional,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                title: Text(l10n.albumPrivateLabel),
                value: isPrivate,
                onChanged: (v) => setDialogState(() => isPrivate = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancelar),
            ),
            FilledButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  Navigator.of(ctx).pop(true);
                }
              },
              child: Text(l10n.albumCreateButton),
            ),
          ],
        ),
      ),
    );

    if (result != true || nameController.text.trim().isEmpty) return;

    try {
      final dio = ref.read(dioProvider);
      final body = <String, dynamic>{
        'name': nameController.text.trim(),
        'description': descriptionController.text.trim().isEmpty
            ? null
            : descriptionController.text.trim(),
        'is_private': isPrivate,
      };
      await dio.post<Map<String, dynamic>>('/albums', data: body);
      await _loadAlbums();
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.albumFailedToCreateSimple}: ${e.response?.statusCode ?? e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.albumFailedToCreateSimple),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Opens the share sheet — a TextField-based user_id picker.
  Future<void> _showShareSheet(Album album) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VibraTheme.kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.compartirAlbum, // "Compartir álbum"
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.seleccionarUsuarios, // "Seleccionar usuarios"
                style: const TextStyle(
                    color: VibraTheme.kTextSecondary, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: l10n.userIdHint,
                  hintStyle: const TextStyle(color: VibraTheme.kTextTertiary),
                ),
              ),
              const SizedBox(height: 16),
              YellowPillButton(
                label: l10n.compartirAlbum,
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        );
      },
    );

    if (result != true) return;
    final userId = controller.text.trim();
    if (userId.isEmpty) return;

    try {
      final dio = ref.read(dioProvider);
      await dio.post<Map<String, dynamic>>(
        '/albums/${album.id}/share',
        data: {'user_id': userId},
      );
      // Invalidate shared-albums cache so "Mis compartidos" updates.
      ref.invalidate(sharedAlbumsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.archivoCompartido)),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${l10n.errorAlCompartir}: ${e.response?.statusCode ?? e.message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteAlbum(Album album) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.eliminarAlbum),
        content: Text(l10n.confirmarEliminarAlbum),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancelar),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.eliminar),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/albums/${album.id}');
      await _loadAlbums();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${l10n.errorAlEliminar}: ${e.response?.statusCode ?? e.message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.misShares)),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
      body: _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    return RefreshIndicator(
      onRefresh: _loadAlbums,
      child: CustomScrollView(
        slivers: [
          // ── Mis compartidos carousel ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      l10n.misShares,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 110,
                    child: Consumer(
                      builder: (_, ref, _) {
                        final shared = ref.watch(sharedAlbumsProvider);
                        return shared.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (_, _) => const SizedBox.shrink(),
                          data: (albums) {
                            if (albums.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16),
                                child: Text(
                                  l10n.noHayActualizaciones,
                                  style: const TextStyle(
                                      color: VibraTheme.kTextSecondary),
                                ),
                              );
                            }
                            return AlbumCarousel(
                              albums: albums,
                              onTap: (id) => context.push('/albums/$id'),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── My albums header ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                l10n.misAlbumesHeader,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          // ── Body (loading / error / empty / grid) ──
          ..._buildAlbumsSliver(l10n),
        ],
      ),
    );
  }

  List<Widget> _buildAlbumsSliver(AppLocalizations l10n) {
    if (_isLoading) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loadAlbums,
                  child: Text(l10n.reintentar),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    final albums = _albums ?? [];
    if (albums.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.photo_album,
                    size: 64, color: VibraTheme.kTextSecondary),
                const SizedBox(height: 16),
                Text(
                  l10n.noTienesAlbumes,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.tocaMasParaCrearAlbum,
                  style: const TextStyle(color: VibraTheme.kTextSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.all(12),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.85,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _AlbumTile(
              album: albums[i],
              onTap: () => context.push('/albums/${albums[i].id}'),
              onShare: () => _showShareSheet(albums[i]),
              onDelete: () => _deleteAlbum(albums[i]),
            ),
            childCount: albums.length,
          ),
        ),
      ),
    ];
  }
}

class _AlbumTile extends StatelessWidget {
  final Album album;
  final VoidCallback onTap;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const _AlbumTile({
    required this.album,
    required this.onTap,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: () => _showMenu(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Cover image or placeholder
            album.coverPhotoUrl != null
                ? Image.network(
                    album.coverPhotoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _AlbumPlaceholder(),
                  )
                : const _AlbumPlaceholder(),
            // Gradient overlay for readability
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),
            // Name + count overlay at bottom
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    album.name ?? l10n.albumSinTitulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '${album.photoCount}',
                    style: const TextStyle(
                      color: VibraTheme.kTextSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            // Private badge
            if (album.isPrivate)
              const Positioned(
                top: 4,
                right: 4,
                child: Icon(Icons.lock, color: Colors.white, size: 14),
              ),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: VibraTheme.kSurface,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.share, color: Colors.white),
            title: Text(l10n.compartirAlbum,
                style: const TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(ctx);
              onShare();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline,
                color: VibraTheme.kBadgeRed),
            title: Text(l10n.eliminarAlbum,
                style: const TextStyle(color: VibraTheme.kBadgeRed)),
            onTap: () {
              Navigator.pop(ctx);
              onDelete();
            },
          ),
        ],
      ),
    );
  }
}

class _AlbumPlaceholder extends StatelessWidget {
  const _AlbumPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: VibraTheme.kChip,
      child: const Icon(Icons.photo_album_outlined,
          color: VibraTheme.kTextSecondary, size: 28),
    );
  }
}
