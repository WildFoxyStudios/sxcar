import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/albums/shared_albums_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubAdapter implements HttpClientAdapter {
  final int? errorStatus;
  final List<Map<String, dynamic>> albums;

  _StubAdapter({this.errorStatus, this.albums = const []});

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
      jsonEncode({'albums': albums}),
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
  group('SharedAlbum', () {
    test('fromJson parses all fields', () {
      final album = SharedAlbum.fromJson({
        'id': '00000000-0000-0000-0000-000000000001',
        'name': 'Vacation 2026',
        'description': 'Beach pics',
        'is_private': true,
        'photo_count': 12,
        'cover_photo_url': 'https://cdn.example.com/cover.jpg',
        'created_at': '2026-06-30T15:30:00Z',
      });

      expect(album.id, equals('00000000-0000-0000-0000-000000000001'));
      expect(album.name, equals('Vacation 2026'));
      expect(album.description, equals('Beach pics'));
      expect(album.isPrivate, isTrue);
      expect(album.photoCount, equals(12));
      expect(album.coverPhotoUrl, equals('https://cdn.example.com/cover.jpg'));
      expect(album.createdAt, equals('2026-06-30T15:30:00Z'));
    });

    test('fromJson handles nulls and missing fields', () {
      final album = SharedAlbum.fromJson({'id': 'id-1'});

      expect(album.name, isNull);
      expect(album.description, isNull);
      expect(album.isPrivate, isFalse);
      expect(album.photoCount, equals(0));
      expect(album.coverPhotoUrl, isNull);
      expect(album.createdAt, equals(''));
    });
  });

  group('SharedAlbumsService', () {
    test('fetchSharedAlbums returns parsed list', () async {
      final dio = Dio()
        ..options.baseUrl = 'http://test'
        ..httpClientAdapter = _StubAdapter(albums: [
          {
            'id': 'id-1',
            'name': 'A',
            'is_private': false,
            'photo_count': 3,
          },
          {
            'id': 'id-2',
            'name': null,
            'is_private': true,
            'photo_count': 0,
          },
        ]);

      final service = SharedAlbumsService(dio);
      final result = await service.fetchSharedAlbums();

      expect(result.length, equals(2));
      expect(result[0].id, equals('id-1'));
      expect(result[0].name, equals('A'));
      expect(result[0].photoCount, equals(3));
      expect(result[1].name, isNull);
      expect(result[1].isPrivate, isTrue);
    });

    test('fetchSharedAlbums returns empty list when no albums', () async {
      final dio = Dio()
        ..options.baseUrl = 'http://test'
        ..httpClientAdapter = _StubAdapter();

      final service = SharedAlbumsService(dio);
      final result = await service.fetchSharedAlbums();

      expect(result, isEmpty);
    });

    test('fetchSharedAlbums rethrows on error', () async {
      final dio = Dio()
        ..options.baseUrl = 'http://test'
        ..httpClientAdapter = _StubAdapter(errorStatus: 500);

      final service = SharedAlbumsService(dio);

      expect(
        () => service.fetchSharedAlbums(),
        throwsA(isA<DioException>()),
      );
    });
  });
}