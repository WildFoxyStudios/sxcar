import 'package:dio/dio.dart';
import 'models.dart';

/// HTTP client for the /billing/* endpoints. Mirrors the Rust backend
/// from T1.3/T1.4.
class BillingService {
  final Dio _dio;
  BillingService(this._dio);

  /// Public: no auth header required.
  Future<List<Plan>> listPlans() async {
    final response = await _dio.get<Map<String, dynamic>>('/billing/plans');
    final data = response.data!;
    final plans = (data['plans'] as List<dynamic>?) ?? const [];
    return plans
        .map((e) => Plan.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /billing/simulate-purchase — creates a new subscription for the
  /// current user. The Dio instance must already have an auth token
  /// configured via the auth interceptor.
  Future<Subscription> simulatePurchase(String priceId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/billing/simulate-purchase',
      data: {'price_id': priceId},
    );
    return Subscription.fromJson(response.data!);
  }

  /// GET /billing/me — returns the user's currently-active subscription,
  /// or null if none.
  Future<Subscription?> mySubscription() async {
    final response =
        await _dio.get<Map<String, dynamic>>('/billing/me');
    final data = response.data!;
    final sub = data['subscription'];
    if (sub == null) return null;
    return Subscription.fromJson(sub as Map<String, dynamic>);
  }
}