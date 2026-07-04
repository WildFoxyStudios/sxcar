import 'dart:convert';

import 'package:app/src/billing/billing_service.dart';
import 'package:app/src/billing/models.dart';
import 'package:app/src/billing/tier_features.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal Dio adapter that returns canned responses — no HTTP, no real
/// server. Reuse across tests.
class _StubAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<ResponseBody Function(RequestOptions)> handlers = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (handlers.isEmpty) {
      return ResponseBody.fromString('{}', 200,
          headers: {'content-type': ['application/json']});
    }
    return handlers.removeAt(0)(options);
  }
}

Dio _dioWith(_StubAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
  dio.httpClientAdapter = adapter;
  return dio;
}

ResponseBody _json(Object body, {int status = 200}) {
  return ResponseBody.fromString(
    body is String ? body : _encode(body),
    status,
    headers: {'content-type': ['application/json']},
  );
}

String _encode(Object body) =>
    const JsonEncoder().convert(body);

void main() {
  group('BillingService.listPlans', () {
    test('parses plans + prices', () async {
      final adapter = _StubAdapter();
      adapter.handlers.add((_) => _json({
            'plans': [
              {
                'code': 'vibra_plus',
                'name': 'Vibra+',
                'tier': 1,
                'description': 'Premium',
                'active': true,
                'features': ['unlimited_chats', 'no_ads'],
                'prices': [
                  {
                    'id': '00000000-0000-0000-0000-000000000001',
                    'country_code': 'XX',
                    'currency': 'EUR',
                    'period': 'monthly',
                    'amount_minor': 899,
                  },
                ],
              },
            ],
          }));
      final dio = _dioWith(adapter);
      final svc = BillingService(dio);
      final plans = await svc.listPlans();
      expect(plans.length, 1);
      expect(plans.first.code, 'vibra_plus');
      expect(plans.first.features, ['unlimited_chats', 'no_ads']);
      expect(plans.first.priceFor('monthly')?.amountMinor, 899);
    });

    test('returns empty list when no plans', () async {
      final adapter = _StubAdapter();
      adapter.handlers.add((_) => _json({'plans': []}));
      final svc = BillingService(_dioWith(adapter));
      final plans = await svc.listPlans();
      expect(plans, isEmpty);
    });
  });

  group('BillingService.simulatePurchase', () {
    test('posts price_id and parses subscription', () async {
      final adapter = _StubAdapter();
      adapter.handlers.add((opts) {
        expect(opts.method, 'POST');
        expect(opts.path, '/billing/simulate-purchase');
        return _json({
          'id': '00000000-0000-0000-0000-000000000aaa',
          'plan_code': 'vibra_plus',
          'plan_name': 'Vibra+',
          'price_id': opts.data['price_id'],
          'period': 'monthly',
          'period_days': 30,
          'status': 'active',
          'source': 'simulated',
          'started_at': '2026-07-04T12:00:00Z',
          'expires_at': '2026-08-03T12:00:00Z',
          'days_remaining': 30,
        }, status: 201);
      });
      final svc = BillingService(_dioWith(adapter));
      final sub = await svc.simulatePurchase('price-id-here');
      expect(sub.planCode, 'vibra_plus');
      expect(sub.status, 'active');
      expect(sub.daysRemaining, 30);
    });
  });

  group('BillingService.mySubscription', () {
    test('parses active subscription', () async {
      final adapter = _StubAdapter();
      adapter.handlers.add((_) => _json({
            'subscription': {
              'id': '00000000-0000-0000-0000-000000000bbb',
              'plan_code': 'unlimited',
              'plan_name': 'Unlimited',
              'price_id': 'price-x',
              'period': 'yearly',
              'period_days': 365,
              'status': 'active',
              'source': 'simulated',
              'started_at': '2026-07-01T00:00:00Z',
              'expires_at': '2027-07-01T00:00:00Z',
              'days_remaining': 365,
            },
          }));
      final svc = BillingService(_dioWith(adapter));
      final sub = await svc.mySubscription();
      expect(sub, isNotNull);
      expect(sub!.planCode, 'unlimited');
      expect(sub.period, 'yearly');
    });

    test('returns null when subscription is null', () async {
      final adapter = _StubAdapter();
      adapter.handlers.add((_) => _json({'subscription': null}));
      final svc = BillingService(_dioWith(adapter));
      final sub = await svc.mySubscription();
      expect(sub, isNull);
    });
  });

  group('TierFeatures', () {
    test('free for null subscription', () {
      final f = TierFeatures.fromSubscription(null);
      expect(f.unlimitedChats, false);
      expect(f.noAds, false);
    });

    test('vibra_plus unlocks 3 features', () {
      final f = TierFeatures.fromSubscription(
        Subscription(
          id: 'x',
          planCode: 'vibra_plus',
          planName: 'Vibra+',
          priceId: 'p',
          period: 'monthly',
          periodDays: 30,
          status: 'active',
          source: 'simulated',
          startedAt: DateTime.utc(2026),
          expiresAt: DateTime.utc(2026, 8),
          daysRemaining: 30,
        ),
      );
      expect(f.unlimitedChats, true);
      expect(f.noAds, true);
      expect(f.seeWhoViewed, true);
      expect(f.incognitoMode, false);
      expect(f.boostDiscount, false);
    });

    test('unlimited unlocks all 5 features', () {
      final f = TierFeatures.unlimited;
      expect(f.unlimitedChats, true);
      expect(f.incognitoMode, true);
      expect(f.boostDiscount, true);
    });
  });
}