import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// A user who recently viewed the current user's profile.
class ProfileViewer {
  final String viewerId;
  final String viewedAt;
  final String? displayName;
  final String? profilePhotoUrl;

  const ProfileViewer({
    required this.viewerId,
    required this.viewedAt,
    this.displayName,
    this.profilePhotoUrl,
  });

  factory ProfileViewer.fromJson(Map<String, dynamic> json) {
    return ProfileViewer(
      viewerId: json['viewer_id'] as String,
      viewedAt: json['viewed_at'] as String,
      displayName: json['display_name'] as String?,
      profilePhotoUrl: json['profile_photo_url'] as String?,
    );
  }
}

/// REST client for the `/profile/views` endpoint.
class ViewedMeService {
  final Dio _dio;

  ViewedMeService(this._dio);

  /// GET /profile/views — recent viewers of the current user's profile.
  /// Throws DioException on transport errors so callers can surface UI state.
  Future<List<ProfileViewer>> fetchViewers() async {
    final response = await _dio.get<Map<String, dynamic>>('/profile/views');
    final data = response.data!;
    final list = data['viewers'] as List<dynamic>;
    return list
        .map((v) => ProfileViewer.fromJson(v as Map<String, dynamic>))
        .toList();
  }
}

/// Riverpod provider for the ViewedMeService.
final viewedMeServiceProvider = Provider<ViewedMeService>((ref) {
  final dio = ref.watch(dioProvider);
  return ViewedMeService(dio);
});

/// FutureProvider for the list of recent profile viewers.
final viewedMeProvider = FutureProvider<List<ProfileViewer>>((ref) async {
  final service = ref.watch(viewedMeServiceProvider);
  return service.fetchViewers();
});