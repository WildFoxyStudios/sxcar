import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// Model returned by GET /profile/verify/status.
class VerificationStatus {
  final bool verified;
  final bool pending;

  const VerificationStatus({required this.verified, required this.pending});

  factory VerificationStatus.fromJson(Map<String, dynamic> json) {
    return VerificationStatus(
      verified: json['verified'] as bool? ?? false,
      pending: json['pending'] as bool? ?? false,
    );
  }
}

/// Service that wraps the verification endpoints.
class VerificationService {
  final Dio _client;

  const VerificationService(this._client);

  /// GET /profile/verify/status → [VerificationStatus].
  Future<VerificationStatus> getStatus() async {
    final res =
        await _client.get<Map<String, dynamic>>('/profile/verify/status');
    return VerificationStatus.fromJson(res.data!);
  }

  /// POST /profile/verify { photo_key } — submit a verification selfie.
  Future<void> submit(String photoKey) async {
    await _client.post<void>(
      '/profile/verify',
      data: {'photo_key': photoKey},
    );
  }
}

/// Provider for [VerificationService]. Uses the shared authenticated [Dio].
final verificationServiceProvider = Provider<VerificationService>((ref) {
  return VerificationService(ref.watch(dioProvider));
});

/// FutureProvider that fetches the current verification status.
/// Invalidate with `ref.invalidate(verificationStatusProvider)` to refresh.
final verificationStatusProvider =
    FutureProvider<VerificationStatus>((ref) async {
  return ref.read(verificationServiceProvider).getStatus();
});
