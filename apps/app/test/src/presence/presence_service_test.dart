import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/presence/presence_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockPresenceAdapter implements HttpClientAdapter {
  final Map<String, Map<String, dynamic>> userStatus = {
    'online-user': {'is_online': true, 'last_seen_at': '2026-01-01T00:00:00Z'},
    'offline-user': {
      'is_online': false,
      'last_seen_at': '2025-12-31T23:00:00Z',
    },
  };
  bool heartbeatCalled = false;
  int heartbeatCallCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/heartbeat' && options.method == 'POST') {
      heartbeatCalled = true;
      heartbeatCallCount++;
      return ResponseBody.fromString(
        '{}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    final regExp = RegExp(r'^/users/([^/]+)/status$');
    final match = regExp.firstMatch(options.path);
    if (options.method == 'GET' && match != null) {
      final userId = match.group(1)!;
      final status = userStatus[userId];
      if (status == null) {
        return ResponseBody.fromString(
          '{"error":"not found"}',
          404,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      return ResponseBody.fromString(
        jsonEncode(status),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromString(
      '{}',
      404,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('PresenceService', () {
    test('heartbeat POSTs to /heartbeat', () async {
      final adapter = _MockPresenceAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = PresenceService(dio);

      await service.sendHeartbeat();

      expect(adapter.heartbeatCalled, isTrue);
      expect(adapter.heartbeatCallCount, equals(1));
    });

    test('getStatus returns is_online true for online user', () async {
      final dio = Dio()..httpClientAdapter = _MockPresenceAdapter();
      final service = PresenceService(dio);

      final status = await service.getStatus('online-user');

      expect(status.isOnline, isTrue);
      expect(status.lastSeenAt, equals('2026-01-01T00:00:00Z'));
    });

    test('getStatus returns is_online false for offline user', () async {
      final dio = Dio()..httpClientAdapter = _MockPresenceAdapter();
      final service = PresenceService(dio);

      final status = await service.getStatus('offline-user');

      expect(status.isOnline, isFalse);
      expect(status.lastSeenAt, equals('2025-12-31T23:00:00Z'));
    });

    test('getStatus returns isOnline false on error', () async {
      final dio = Dio()..httpClientAdapter = _MockPresenceAdapter();
      final service = PresenceService(dio);

      final status = await service.getStatus('missing-user');

      expect(status.isOnline, isFalse);
      expect(status.lastSeenAt, isNull);
    });
  });

  group('UserStatus', () {
    test('fromJson parses is_online and last_seen_at', () {
      final status = UserStatus.fromJson({
        'is_online': true,
        'last_seen_at': '2026-06-01T12:00:00Z',
      });

      expect(status.isOnline, isTrue);
      expect(status.lastSeenAt, equals('2026-06-01T12:00:00Z'));
    });

    test('fromJson handles missing last_seen_at', () {
      final status = UserStatus.fromJson({
        'is_online': false,
      });

      expect(status.isOnline, isFalse);
      expect(status.lastSeenAt, isNull);
    });
  });

  group('formatLastSeen', () {
    test('returns "Online" when isOnline is true', () {
      final status = UserStatus(isOnline: true, lastSeenAt: null);
      expect(formatLastSeen(status), equals('Online'));
    });

    test('returns "Just now" for recent last_seen', () {
      final now = DateTime.now();
      final status = UserStatus(
        isOnline: false,
        lastSeenAt: now.subtract(const Duration(seconds: 30)).toIso8601String(),
      );
      expect(formatLastSeen(status), equals('Just now'));
    });

    test('returns "Active 5m ago" for ~5 minute last_seen', () {
      final now = DateTime.now();
      final status = UserStatus(
        isOnline: false,
        lastSeenAt: now.subtract(const Duration(minutes: 5)).toIso8601String(),
      );
      expect(formatLastSeen(status), equals('Active 5m ago'));
    });

    test('returns "Active 2h ago" for ~2 hour last_seen', () {
      final now = DateTime.now();
      final status = UserStatus(
        isOnline: false,
        lastSeenAt: now.subtract(const Duration(hours: 2)).toIso8601String(),
      );
      expect(formatLastSeen(status), equals('Active 2h ago'));
    });

    test('returns "Active 3d ago" for ~3 day last_seen', () {
      final now = DateTime.now();
      final status = UserStatus(
        isOnline: false,
        lastSeenAt: now.subtract(const Duration(days: 3)).toIso8601String(),
      );
      expect(formatLastSeen(status), equals('Active 3d ago'));
    });

    test('returns empty string when offline and no last_seen', () {
      final status = UserStatus(isOnline: false, lastSeenAt: null);
      expect(formatLastSeen(status), equals(''));
    });

    test('returns empty string when last_seen is malformed', () {
      final status = UserStatus(isOnline: false, lastSeenAt: 'not-a-date');
      expect(formatLastSeen(status), equals(''));
    });
  });
}