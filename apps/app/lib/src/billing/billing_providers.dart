import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';
import 'billing_service.dart';
import 'models.dart';

/// Singleton BillingService wired to the shared Dio.
final billingServiceProvider = Provider<BillingService>((ref) {
  final dio = ref.watch(dioProvider);
  return BillingService(dio);
});

/// All plans from the backend. Public — safe to fetch while logged-out.
final plansProvider = FutureProvider<List<Plan>>((ref) async {
  final service = ref.watch(billingServiceProvider);
  return service.listPlans();
});

/// The current user's active subscription, or null. Auto-refreshes on
/// auth-state changes (logged out → null, logged in → fetched).
final mySubscriptionProvider = FutureProvider<Subscription?>((ref) async {
  // Watch authStateProvider so logged-out state is reflected immediately.
  final auth = ref.watch(authStateProvider);
  if (auth.status != AuthStatus.authenticated) return null;
  final service = ref.watch(billingServiceProvider);
  try {
    return await service.mySubscription();
  } on DioException {
    return null;
  }
});

/// Convenience: refetch the user's subscription (after a purchase).
Future<Subscription?> refreshMySubscription(Ref ref) {
  ref.invalidate(mySubscriptionProvider);
  return ref.read(mySubscriptionProvider.future);
}