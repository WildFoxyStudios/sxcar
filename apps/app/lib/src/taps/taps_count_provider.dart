import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// Aggregate tap count response from `GET /taps/count`.
///
/// Backend returns `{count: N, types: {fire: n, wave: n, ...}}` —
/// `types` omits keys for zero counts.
class TapsCount {
  final int total;
  final Map<String, int> byType;

  const TapsCount({required this.total, required this.byType});

  factory TapsCount.fromJson(Map<String, dynamic> json) {
    final raw = json['types'] as Map<String, dynamic>? ?? const {};
    final byType = <String, int>{
      for (final entry in raw.entries)
        entry.key: (entry.value as num).toInt(),
    };
    return TapsCount(
      total: (json['count'] as num).toInt(),
      byType: byType,
    );
  }
}

/// REST client for `GET /taps/count`.
class TapsCountService {
  final Dio _dio;

  TapsCountService(this._dio);

  Future<TapsCount> fetchCount() async {
    final response = await _dio.get<Map<String, dynamic>>('/taps/count');
    return TapsCount.fromJson(response.data!);
  }
}

final tapsCountServiceProvider = Provider<TapsCountService>((ref) {
  final dio = ref.watch(dioProvider);
  return TapsCountService(dio);
});

/// FutureProvider for the tap count aggregate. Used by the Interest screen
/// taps counter and the chat banner.
final tapsCountProvider = FutureProvider<TapsCount>((ref) async {
  final service = ref.watch(tapsCountServiceProvider);
  return service.fetchCount();
});