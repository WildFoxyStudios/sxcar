/// DTO classes that mirror the Rust backend's PlanDto / PriceDto /
/// SubscriptionDto. Keep these in sync with `backend/crates/api/src/billing/*`.
library;

class Plan {
  final String code;
  final String name;
  final int tier;
  final String? description;
  final bool active;
  final List<String> features;
  final List<PlanPrice> prices;

  const Plan({
    required this.code,
    required this.name,
    required this.tier,
    required this.description,
    required this.active,
    required this.features,
    required this.prices,
  });

  factory Plan.fromJson(Map<String, dynamic> json) => Plan(
        code: json['code'] as String,
        name: json['name'] as String,
        tier: (json['tier'] as num).toInt(),
        description: json['description'] as String?,
        active: (json['active'] as bool?) ?? true,
        features: ((json['features'] as List<dynamic>?) ?? const [])
            .map((e) => e as String)
            .toList(),
        prices: ((json['prices'] as List<dynamic>?) ?? const [])
            .map((e) => PlanPrice.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// Find the first price for a given period. Returns null if not found.
  PlanPrice? priceFor(String period) {
    for (final p in prices) {
      if (p.period == period) return p;
    }
    return null;
  }
}

class PlanPrice {
  final String id; // uuid string
  final String countryCode;
  final String currency;
  final String period; // 'monthly' | 'yearly'
  final int amountMinor; // cents

  const PlanPrice({
    required this.id,
    required this.countryCode,
    required this.currency,
    required this.period,
    required this.amountMinor,
  });

  factory PlanPrice.fromJson(Map<String, dynamic> json) => PlanPrice(
        id: json['id'] as String,
        countryCode: json['country_code'] as String,
        currency: json['currency'] as String,
        period: json['period'] as String,
        amountMinor: (json['amount_minor'] as num).toInt(),
      );

  /// Human-readable price, e.g. "€8.99".
  String get formatted {
    final major = amountMinor ~/ 100;
    final minor = amountMinor % 100;
    final minorStr = minor.toString().padLeft(2, '0');
    return '€$major.$minorStr';
  }
}

class Subscription {
  final String id;
  final String planCode;
  final String planName;
  final String priceId;
  final String period;
  final int periodDays;
  final String status; // 'active'
  final String source; // 'simulated'
  final DateTime startedAt;
  final DateTime expiresAt;
  final int daysRemaining;

  const Subscription({
    required this.id,
    required this.planCode,
    required this.planName,
    required this.priceId,
    required this.period,
    required this.periodDays,
    required this.status,
    required this.source,
    required this.startedAt,
    required this.expiresAt,
    required this.daysRemaining,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
        id: json['id'] as String,
        planCode: json['plan_code'] as String,
        planName: json['plan_name'] as String,
        priceId: json['price_id'] as String,
        period: json['period'] as String,
        periodDays: (json['period_days'] as num).toInt(),
        status: json['status'] as String,
        source: json['source'] as String,
        startedAt: DateTime.parse(json['started_at'] as String),
        expiresAt: DateTime.parse(json['expires_at'] as String),
        daysRemaining: (json['days_remaining'] as num).toInt(),
      );
}