import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/profile_views/viewed_me_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockViewsAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> viewers;
  final int? errorStatus;

  _MockViewsAdapter({this.viewers = const [], this.errorStatus});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (errorStatus != null) {
      return ResponseBody.fromString(
        '{"error":"server"}',
        errorStatus!,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode({'viewers': viewers}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('ProfileViewer', () {
    test('fromJson parses all fields', () {
      final v = ProfileViewer.fromJson({
        'viewer_id': '00000000-0000-0000-0000-000000000001',
        'viewed_at': '2026-06-30T15:30:00Z',
        'display_name': 'Bob',
        'profile_photo_url': 'https://cdn.example.com/bob.jpg',
      });

      expect(v.viewerId, equals('00000000-0000-0000-0000-000000000001'));
      expect(v.viewedAt, equals('2026-06-30T15:30:00Z'));
      expect(v.displayName, equals('Bob'));
      expect(v.profilePhotoUrl, equals('https://cdn.example.com/bob.jpg'));
    });

    test('fromJson handles null display_name and photo_url', () {
      final v = ProfileViewer.fromJson({
        'viewer_id': 'id-1',
        'viewed_at': '2026-06-30T15:30:00Z',
      });

      expect(v.displayName, isNull);
      expect(v.profilePhotoUrl, isNull);
    });
  });

  group('ViewedMeService', () {
    test('fetchViewers returns parsed list', () async {
      final dio = Dio()
        ..httpClientAdapter = _MockViewsAdapter(viewers: [
          {
            'viewer_id': 'id-1',
            'viewed_at': '2026-06-30T15:30:00Z',
            'display_name': 'Bob',
            'profile_photo_url': null,
          },
          {
            'viewer_id': 'id-2',
            'viewed_at': '2026-06-30T16:00:00Z',
            'display_name': null,
            'profile_photo_url': null,
          },
        ]);

      final service = ViewedMeService(dio);
      final viewers = await service.fetchViewers();

      expect(viewers.length, equals(2));
      expect(viewers[0].viewerId, equals('id-1'));
      expect(viewers[0].displayName, equals('Bob'));
      expect(viewers[1].displayName, isNull);
    });

    test('fetchViewers returns empty list on no viewers', () async {
      final dio = Dio()..httpClientAdapter = _MockViewsAdapter();
      final service = ViewedMeService(dio);

      final viewers = await service.fetchViewers();

      expect(viewers, isEmpty);
    });

    test('fetchViewers rethrows on error', () async {
      final dio = Dio()
        ..httpClientAdapter = _MockViewsAdapter(errorStatus: 500);

      final service = ViewedMeService(dio);

      expect(
        () => service.fetchViewers(),
        throwsA(isA<DioException>()),
      );
    });
  });
}