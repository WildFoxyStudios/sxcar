import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// Health-related fields from GET/PUT /profile/health.
///
/// All three fields are optional in both directions. [toJson] omits any
/// field that was never set so PUT payloads stay minimal.
class HealthInfo {
  final String? hivStatus;
  final String? lastTestedOn; // YYYY-MM-DD
  final bool? prep;

  const HealthInfo({
    this.hivStatus,
    this.lastTestedOn,
    this.prep,
  });

  factory HealthInfo.fromJson(Map<String, dynamic> json) {
    return HealthInfo(
      hivStatus: json['hiv_status'] as String?,
      lastTestedOn: json['last_tested_on'] as String?,
      prep: json['prep'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (hivStatus != null) m['hiv_status'] = hivStatus;
    if (lastTestedOn != null) m['last_tested_on'] = lastTestedOn;
    if (prep != null) m['prep'] = prep;
    return m;
  }
}

/// REST client for `/profile/health`.
class HealthService {
  final Dio _dio;

  HealthService(this._dio);

  /// GET /profile/health — returns the user's health fields.
  /// On 404 (no health record yet) returns an empty [HealthInfo].
  Future<HealthInfo> fetchHealth() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/profile/health');
      return HealthInfo.fromJson(response.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const HealthInfo();
      }
      rethrow;
    }
  }

  /// PUT /profile/health — updates the user's health fields.
  Future<void> updateHealth(HealthInfo info) async {
    await _dio.put('/profile/health', data: info.toJson());
  }
}

final healthServiceProvider = Provider<HealthService>((ref) {
  final dio = ref.watch(dioProvider);
  return HealthService(dio);
});

/// FutureProvider for the user's health record.
final healthInfoProvider = FutureProvider<HealthInfo>((ref) async {
  final service = ref.watch(healthServiceProvider);
  return service.fetchHealth();
});