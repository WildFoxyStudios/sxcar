/// HTTP client for the /me/premium endpoint.
///
/// Returns the user's current subscription tier and resolved feature flags.
/// This is the source of truth for feature gating on the frontend.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

// ─── Data model ───────────────────────────────────────────────────────────────

/// All feature flags exposed by the backend's `GET /me/premium`.
class PremiumStatus {
  final String tier; // "free", "xtra", "unlimited"
  final PremiumFeatures features;

  const PremiumStatus({
    this.tier = 'free',
    this.features = const PremiumFeatures(),
  });

  factory PremiumStatus.fromJson(Map<String, dynamic> json) {
    return PremiumStatus(
      tier: json['tier'] as String? ?? 'free',
      features: PremiumFeatures.fromJson(
        json['features'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class PremiumFeatures {
  final bool unlimitedGrid;
  final bool noAds;
  final bool incognitoMode;
  final bool readReceipts;
  final bool travelPass;
  final bool prioritySupport;
  final bool advancedFilters;
  final int maxTribes;
  final int maxProfilesGrid;

  const PremiumFeatures({
    this.unlimitedGrid = false,
    this.noAds = false,
    this.incognitoMode = false,
    this.readReceipts = false,
    this.travelPass = false,
    this.prioritySupport = false,
    this.advancedFilters = false,
    this.maxTribes = 1,
    this.maxProfilesGrid = 50,
  });

  factory PremiumFeatures.fromJson(Map<String, dynamic> json) {
    return PremiumFeatures(
      unlimitedGrid: json['unlimited_grid'] as bool? ?? false,
      noAds: json['no_ads'] as bool? ?? false,
      incognitoMode: json['incognito_mode'] as bool? ?? false,
      readReceipts: json['read_receipts'] as bool? ?? false,
      travelPass: json['travel_pass'] as bool? ?? false,
      prioritySupport: json['priority_support'] as bool? ?? false,
      advancedFilters: json['advanced_filters'] as bool? ?? false,
      maxTribes: json['max_tribes'] as int? ?? 1,
      maxProfilesGrid: json['max_profiles_grid'] as int? ?? 50,
    );
  }
}

// ─── Known feature keys (for canAccess) ───────────────────────────────────────

/// Convenience constants for feature names passed to [PremiumService.canAccess].
class PremiumFeature {
  static const unlimitedGrid = 'unlimitedGrid';
  static const noAds = 'noAds';
  static const incognitoMode = 'incognitoMode';
  static const readReceipts = 'readReceipts';
  static const travelPass = 'travelPass';
  static const prioritySupport = 'prioritySupport';
  static const advancedFilters = 'advancedFilters';
}

// ─── HTTP Service ─────────────────────────────────────────────────────────────

class PremiumService {
  final Dio _dio;
  PremiumService(this._dio);

  /// GET /me/premium
  Future<PremiumStatus> fetchPremiumStatus() async {
    final response = await _dio.get<Map<String, dynamic>>('/me/premium');
    return PremiumStatus.fromJson(response.data!);
  }
}

// ─── Riverpod providers ───────────────────────────────────────────────────────

final premiumServiceProvider = Provider<PremiumService>((ref) {
  final dio = ref.watch(dioProvider);
  return PremiumService(dio);
});

/// The user's current premium status.
/// Returns `PremiumStatus(tier: 'free')` when unauthenticated or on error.
final premiumStatusProvider = FutureProvider<PremiumStatus>((ref) async {
  final auth = ref.watch(authStateProvider);
  if (auth.status != AuthStatus.authenticated) {
    return const PremiumStatus();
  }
  final service = ref.watch(premiumServiceProvider);
  try {
    return await service.fetchPremiumStatus();
  } on DioException {
    return const PremiumStatus();
  }
});

/// Convenience: refetch premium status (after a purchase, for example).
Future<PremiumStatus> refreshPremiumStatus(Ref ref) {
  ref.invalidate(premiumStatusProvider);
  return ref.read(premiumStatusProvider.future);
}
