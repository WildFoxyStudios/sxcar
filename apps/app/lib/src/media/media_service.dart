// ignore_for_file: use_null_aware_elements

import 'dart:typed_data';
import 'package:dio/dio.dart';

/// Model for a single gallery photo entry from the backend.
class GalleryPhoto {
  final String id;
  final String url;
  final bool isPrimary;
  final int position;

  const GalleryPhoto({
    required this.id,
    required this.url,
    required this.isPrimary,
    required this.position,
  });

  factory GalleryPhoto.fromJson(Map<String, dynamic> json) {
    return GalleryPhoto(
      id: json['id'] as String,
      url: json['url'] as String,
      isPrimary: json['is_primary'] as bool,
      position: json['position'] as int,
    );
  }
}

/// Model for a presigned upload URL response from the backend.
class UploadUrl {
  final String key;
  final String bucket;
  final String putUrl;
  final String getUrl;
  final int expiresIn;

  const UploadUrl({
    required this.key,
    required this.bucket,
    required this.putUrl,
    required this.getUrl,
    required this.expiresIn,
  });

  factory UploadUrl.fromJson(Map<String, dynamic> json) {
    return UploadUrl(
      key: json['key'] as String,
      bucket: json['bucket'] as String,
      putUrl: json['put_url'] as String,
      getUrl: json['get_url'] as String,
      expiresIn: json['expires_in'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'bucket': bucket,
        'put_url': putUrl,
        'get_url': getUrl,
        'expires_in': expiresIn,
      };
}

/// Service for uploading media files through R2 presigned URLs.
///
/// Uses the authenticated [Dio] client (with auth interceptor) for backend
/// requests and a separate client for direct R2 PUT uploads (defaults to a
/// fresh unauthenticated [Dio] if not provided).
class MediaService {
  final Dio _client;
  final Dio _r2Client;

  MediaService(this._client, {Dio? r2Client}) : _r2Client = r2Client ?? Dio();

  /// Get a presigned upload URL from the backend.
  Future<UploadUrl> getUploadUrl({
    required String kind,
    String? ext,
  }) async {
    final res = await _client.post('/media/upload-url', data: {
      'kind': kind,
      if (ext != null) 'ext': ext,
    });
    return UploadUrl.fromJson(res.data as Map<String, dynamic>);
  }

  /// Upload file bytes to R2 via presigned PUT URL.
  Future<void> uploadToR2(
    String putUrl,
    Uint8List bytes, {
    String contentType = 'image/jpeg',
  }) async {
    await _r2Client.put(
      putUrl,
      data: bytes,
      options: Options(headers: {'Content-Type': contentType}),
    );
  }

  /// Fetch all gallery photos for the current user.
  /// Returns photos ordered primary-first then by position.
  Future<List<GalleryPhoto>> listPhotos() async {
    final res = await _client.get<Map<String, dynamic>>('/media/photos');
    final photosJson = (res.data!['photos'] as List<dynamic>);
    return photosJson
        .cast<Map<String, dynamic>>()
        .map(GalleryPhoto.fromJson)
        .toList();
  }

  /// Delete a gallery photo by id.
  Future<void> deletePhoto(String id) async {
    await _client.delete('/media/photos/$id');
  }

  /// Set a gallery photo as the primary profile photo.
  Future<void> setPrimaryPhoto(String id) async {
    await _client.put('/media/photos/$id/primary');
  }

  /// Create a gallery photo entry after uploading to R2.
  Future<void> createPhoto({
    required String r2Key,
    bool isNsfw = false,
  }) async {
    await _client.post('/media/photos', data: {
      'r2_key': r2Key,
      'is_nsfw': isNsfw,
    });
  }
}
