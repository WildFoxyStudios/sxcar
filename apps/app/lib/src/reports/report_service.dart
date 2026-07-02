import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// Reasons a user can pick when reporting someone. Sent as the `reason` string.
const List<String> kReportReasons = [
  'Spam',
  'Harassment',
  'Fake profile',
  'Offensive content',
  'Underage',
  'Other',
];

/// REST client for the user-facing `/reports` endpoint.
class ReportService {
  final Dio _dio;

  ReportService(this._dio);

  /// POST /reports — report a user's profile/photo/message.
  /// [targetKind] must be 'profile', 'photo', or 'message'.
  Future<void> report({
    required String targetUserId,
    String targetKind = 'profile',
    String? targetId,
    String? reason,
  }) async {
    final data = <String, dynamic>{
      'target_user_id': targetUserId,
      'target_kind': targetKind,
    };
    if (targetId != null) data['target_id'] = targetId;
    if (reason != null) data['reason'] = reason;
    await _dio.post<Map<String, dynamic>>('/reports', data: data);
  }
}

/// Riverpod provider for the ReportService.
final reportServiceProvider = Provider<ReportService>((ref) {
  final dio = ref.watch(dioProvider);
  return ReportService(dio);
});
