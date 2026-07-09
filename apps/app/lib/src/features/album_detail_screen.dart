import '../theme/app_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../l10n/gen/app_localizations.dart';
import '../auth/auth_provider.dart';
import '../media/media_service.dart';

/// Model for a photo in an album.
class AlbumPhoto {
  final String id;
  final String r2Key;
  final String? blurKey;
  final bool isNsfw;
  final int position;
  final String photoUrl;

  const AlbumPhoto({
    required this.id,
    required this.r2Key,
    this.blurKey,
    required this.isNsfw,
    required this.position,
    required this.photoUrl,
  });

  factory AlbumPhoto.fromJson(Map<String, dynamic> json) {
    return AlbumPhoto(
      id: json['id'] as String,
      r2Key: json['r2_key'] as String,
      photoUrl: json['photo_url'] as String,
      blurKey: json['blur_key'] as String?,
      isNsfw: json['is_nsfw'] as bool? ?? false,
      position: json['position'] as int? ?? 0,
    );
  }
}

/// Screen showing album details with a photo grid.
class AlbumDetailScreen extends ConsumerStatefulWidget {
  final String albumId;

  const AlbumDetailScreen({super.key, required this.albumId});

  @override
  ConsumerState<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends ConsumerState<AlbumDetailScreen> {
  Map<String, dynamic>? _album;
  List<AlbumPhoto>? _photos;
  bool _isLoading = true;
  bool _isUploading = false;
  bool _isNotFound = false;
  String? _errorDetail;

  @override
  void initState() {
    super.initState();
    _loadAlbum();
  }

  Future<void> _loadAlbum() async {
    setState(() {
      _isLoading = true;
      _isNotFound = false;
      _errorDetail = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final response =
          await dio.get<Map<String, dynamic>>('/albums/${widget.albumId}');
      if (response.data == null) {
        throw Exception('Empty response from server');
      }
      final data = response.data!;
      final album = data['album'] as Map<String, dynamic>?;
      if (album == null) {
        throw Exception('Missing album in response');
      }
      final photosJson = data['photos'] as List<dynamic>? ?? [];
      final photos = photosJson
          .map((p) => AlbumPhoto.fromJson(p as Map<String, dynamic>))
          .toList();

      if (!mounted) return;
      setState(() {
        _album = album;
        _photos = photos;
        _isLoading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (e.response?.statusCode == 404) {
          _isNotFound = true;
        } else {
          _errorDetail = '${e.response?.statusCode ?? e.message}';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorDetail = '$e';
      });
    }
  }

  Future<void> _addPhotos() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();

    if (pickedFiles.isEmpty || !mounted) return;

    setState(() => _isUploading = true);

    try {
      final dio = ref.read(dioProvider);
      final mediaService = MediaService(dio);
      final List<String> r2Keys = [];

      for (final file in pickedFiles) {
        final bytes = await file.readAsBytes();
        final ext = file.path.split('.').lastOrNull;

        // Get presigned URL from backend
        final uploadUrl =
            await mediaService.getUploadUrl(kind: 'album', ext: ext);

        // Upload to R2
        await mediaService.uploadToR2(
          uploadUrl.putUrl,
          bytes,
          contentType: _contentType(ext),
        );

        r2Keys.add(uploadUrl.key);
      }

      // Add all uploaded photos to album
      await dio.post(
        '/albums/${widget.albumId}/photos',
        data: {'photo_keys': r2Keys},
      );

      // Reload album photos
      await _loadAlbum();
    } on DioException catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.album_add_error(
                '${e.response?.statusCode ?? e.message}')),
            backgroundColor: VibraTheme.kError,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.album_add_error('$e')),
            backgroundColor: VibraTheme.kError,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  String _contentType(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final albumName = _album?['name'] as String? ?? l10n.album_title_fallback;

    return Scaffold(
      appBar: AppBar(
        title: Text(albumName),
        actions: [
          if (!_isLoading && _album != null)
            IconButton(
              icon: _isUploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate),
              onPressed: _isUploading ? null : _addPhotos,
              tooltip: l10n.album_add_photos,
            ),
        ],
      ),
      body: _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isNotFound || _errorDetail != null) {
      final errorText =
          _isNotFound ? l10n.album_not_found : l10n.album_load_error(_errorDetail!);

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: VibraTheme.kError),
            const SizedBox(height: 16),
            Text(errorText, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadAlbum,
              child: Text(l10n.album_retry),
            ),
          ],
        ),
      );
    }

    final photos = _photos ?? [];

    if (photos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.photo_library_outlined, size: 64, color: VibraTheme.kTextSecondary),
            const SizedBox(height: 16),
            Text(
              l10n.album_no_photos,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _addPhotos,
              icon: const Icon(Icons.add_photo_alternate),
              label: Text(l10n.album_add_photos),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final photo = photos[index];
        return GestureDetector(
          onTap: () => _showPhotoPreview(photo),
          child: Image.network(
            photo.photoUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image),
            ),
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showPhotoPreview(AlbumPhoto photo) {
    showDialog(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: InteractiveViewer(
                  child: Image.network(
                    photo.photoUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image,
                      size: 64,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.album_close),
              ),
            ],
          ),
        );
      },
    );
  }
}
