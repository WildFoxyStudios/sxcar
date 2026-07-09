import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';
import '../media/media_service.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class StoryJson {
  final String id;
  final String userId;
  final String mediaKey;
  final String mediaType;
  final String? caption;
  final String? displayName;
  final String? avatarKey;
  final String createdAt;
  final String expiresAt;
  final bool viewed;
  final int viewCount;

  const StoryJson({
    required this.id,
    required this.userId,
    required this.mediaKey,
    required this.mediaType,
    this.caption,
    this.displayName,
    this.avatarKey,
    required this.createdAt,
    required this.expiresAt,
    required this.viewed,
    required this.viewCount,
  });

  factory StoryJson.fromJson(Map<String, dynamic> json) {
    return StoryJson(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      mediaKey: json['media_key'] as String,
      mediaType: json['media_type'] as String,
      caption: json['caption'] as String?,
      displayName: json['display_name'] as String?,
      avatarKey: json['avatar_key'] as String?,
      createdAt: json['created_at'] as String,
      expiresAt: json['expires_at'] as String,
      viewed: json['viewed'] as bool? ?? false,
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class StoryGroup {
  final String userId;
  final String? displayName;
  final String? avatarKey;
  final List<StoryJson> stories;
  final bool allViewed;

  const StoryGroup({
    required this.userId,
    this.displayName,
    this.avatarKey,
    required this.stories,
    required this.allViewed,
  });

  factory StoryGroup.fromJson(Map<String, dynamic> json) {
    return StoryGroup(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String?,
      avatarKey: json['avatar_key'] as String?,
      stories: (json['stories'] as List)
          .map((e) => StoryJson.fromJson(e as Map<String, dynamic>))
          .toList(),
      allViewed: json['all_viewed'] as bool? ?? false,
    );
  }
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Service for fetching, creating, viewing, and deleting stories.
class StoryService {
  final Dio _client;
  final MediaService _mediaService;

  StoryService(this._client, this._mediaService);

  /// Get all active stories for the current user and their connections.
  Future<Map<String, dynamic>> getStories() async {
    final res = await _client.get('/stories');
    final data = res.data as Map<String, dynamic>?;
    return data ?? const <String, dynamic>{};
  }

  /// Create a new story.
  Future<Map<String, dynamic>> createStory({
    required String mediaKey,
    required String mediaType,
    String? caption,
  }) async {
    final res = await _client.post('/stories', data: {
      'media_key': mediaKey,
      'media_type': mediaType,
      if (caption != null && caption.isNotEmpty) 'caption': caption,
    });
    return (res.data as Map<String, dynamic>?) ?? const <String, dynamic>{};
  }

  /// Delete a story.
  Future<void> deleteStory(String storyId) async {
    await _client.delete('/stories/$storyId');
  }

  /// Mark a story as viewed.
  Future<void> viewStory(String storyId) async {
    await _client.post('/stories/$storyId/view');
  }

  /// Get a presigned upload URL for story media.
  Future<UploadUrl> getUploadUrl({String? ext}) async {
    return _mediaService.getUploadUrl(kind: 'story', ext: ext);
  }

  /// Upload bytes to R2 via presigned URL.
  Future<void> uploadToR2(String putUrl, Uint8List bytes,
      {String contentType = 'image/jpeg'}) async {
    await _mediaService.uploadToR2(putUrl, bytes, contentType: contentType);
  }
}

// ---------------------------------------------------------------------------
// Riverpod providers
// ---------------------------------------------------------------------------

final storyServiceProvider = Provider<StoryService>((ref) {
  final dio = ref.watch(dioProvider);
  final mediaService = ref.watch(mediaServiceProvider);
  return StoryService(dio, mediaService);
});

final mediaServiceProvider = Provider<MediaService>((ref) {
  final dio = ref.watch(dioProvider);
  return MediaService(dio);
});

/// Provider that fetches all active stories (grouped by user).
final storiesListProvider = FutureProvider<List<StoryGroup>>((ref) async {
  final service = ref.watch(storyServiceProvider);
  final data = await service.getStories();
  final groups = ((data['grouped'] as List?) ?? const [])
      .map((e) => StoryGroup.fromJson(e as Map<String, dynamic>))
      .toList();
  return groups;
});

/// A refreshable provider — call ref.invalidate(storiesListProvider) to reload.
