// ignore_for_file: use_null_aware_elements

import 'dart:typed_data';
import 'package:dio/dio.dart';

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
}
