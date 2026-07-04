import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// One album shared with the current user.
///
/// Field shape mirrors the backend `AlbumResponse` returned by
/// `GET /albums/shared` (see `backend/crates/api/src/albums.rs`). The brief
/// originally guessed `thumbnail_url`, `shared_by_*`, and `shared_at`, but
/// the backend doesn't enrich shared-album rows with sharer info — the
/// response only contains album-level fields plus `created_at`.
class SharedAlbum {
  final String id;
  final String? name;
  final String? description;
  final bool isPrivate;
  final int photoCount;
  final String? coverPhotoUrl;
  final String createdAt;

  const SharedAlbum({
    required this.id,
    required this.name,
    required this.description,
    required this.isPrivate,
    required this.photoCount,
    required this.coverPhotoUrl,
    required this.createdAt,
  });

  factory SharedAlbum.fromJson(Map<String, dynamic> json) {
    return SharedAlbum(
      id: json['id'] as String,
      name: json['name'] as String?,
      description: json['description'] as String?,
      isPrivate: (json['is_private'] as bool?) ?? false,
      photoCount: (json['photo_count'] as num?)?.toInt() ?? 0,
      coverPhotoUrl: json['cover_photo_url'] as String?,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

/// REST client for `GET /albums/shared`.
class SharedAlbumsService {
  final Dio _dio;

  SharedAlbumsService(this._dio);

  /// GET /albums/shared — albums other users have shared with the current user.
  Future<List<SharedAlbum>> fetchSharedAlbums() async {
    final response = await _dio.get<Map<String, dynamic>>('/albums/shared');
    final data = response.data!;
    final list = (data['albums'] as List<dynamic>?) ?? const [];
    return list
        .map((a) => SharedAlbum.fromJson(a as Map<String, dynamic>))
        .toList();
  }
}

final sharedAlbumsServiceProvider = Provider<SharedAlbumsService>((ref) {
  final dio = ref.watch(dioProvider);
  return SharedAlbumsService(dio);
});

/// FutureProvider for the list of shared albums (carousel on chat list screen).
final sharedAlbumsProvider = FutureProvider<List<SharedAlbum>>((ref) async {
  final service = ref.watch(sharedAlbumsServiceProvider);
  return service.fetchSharedAlbums();
});