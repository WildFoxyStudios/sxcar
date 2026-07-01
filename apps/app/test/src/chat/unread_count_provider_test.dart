import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/chat/unread_count_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockConversationsAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> conversations;
  final int? errorStatus;

  _MockConversationsAdapter({
    this.conversations = const [],
    this.errorStatus,
  });

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
      jsonEncode({'conversations': conversations}),
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
  group('UnreadCountService', () {
    test('fetchUnread returns 0 for empty conversations', () async {
      final dio = Dio()
        ..httpClientAdapter = _MockConversationsAdapter(conversations: []);
      final service = UnreadCountService(dio);

      final count = await service.fetchUnread();

      expect(count, equals(0));
    });

    test('fetchUnread sums unread across conversations', () async {
      final dio = Dio()
        ..httpClientAdapter = _MockConversationsAdapter(conversations: [
          {
            'conversation_id': 'c1',
            'other_user_id': 'u1',
            'unread_count': 3,
          },
          {
            'conversation_id': 'c2',
            'other_user_id': 'u2',
            'unread_count': 5,
          },
          {
            'conversation_id': 'c3',
            'other_user_id': 'u3',
            'unread_count': 0,
          },
        ]);
      final service = UnreadCountService(dio);

      final count = await service.fetchUnread();

      expect(count, equals(8));
    });

    test('fetchUnread treats null unread as 0', () async {
      final dio = Dio()
        ..httpClientAdapter = _MockConversationsAdapter(conversations: [
          {
            'conversation_id': 'c1',
            'other_user_id': 'u1',
          },
          {
            'conversation_id': 'c2',
            'other_user_id': 'u2',
            'unread_count': 2,
          },
        ]);
      final service = UnreadCountService(dio);

      final count = await service.fetchUnread();

      expect(count, equals(2));
    });

    test('fetchUnread returns 0 on error (graceful fallback)', () async {
      final dio = Dio()
        ..httpClientAdapter = _MockConversationsAdapter(errorStatus: 500);
      final service = UnreadCountService(dio);

      final count = await service.fetchUnread();

      expect(count, equals(0));
    });
  });
}