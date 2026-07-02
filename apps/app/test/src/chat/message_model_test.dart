import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/chat/models.dart';

void main() {
  // ── Message.fromJson ────────────────────────────────────────────────────────

  group('Message.fromJson — text message', () {
    test('parses required fields', () {
      final json = {
        'id': 'msg-1',
        'conversation_id': 'conv-1',
        'sender_id': 'user-a',
        'kind': 'text',
        'body': 'hello',
        'created_at': '2025-01-01T12:00:00Z',
      };

      final m = Message.fromJson(json);

      expect(m.id, 'msg-1');
      expect(m.conversationId, 'conv-1');
      expect(m.senderId, 'user-a');
      expect(m.kind, 'text');
      expect(m.body, 'hello');
      expect(m.createdAt, '2025-01-01T12:00:00Z');
    });

    test('media + viewed fields are null when absent', () {
      final json = {
        'id': 'msg-1',
        'conversation_id': 'conv-1',
        'sender_id': 'user-a',
        'kind': 'text',
        'created_at': '2025-01-01T12:00:00Z',
      };

      final m = Message.fromJson(json);

      expect(m.mediaKey, isNull);
      expect(m.mediaType, isNull);
      expect(m.readAt, isNull);
      expect(m.ephemeralViewedAt, isNull);
    });
  });

  group('Message.fromJson — photo message', () {
    test('parses media_key and media_type', () {
      final json = {
        'id': 'msg-2',
        'conversation_id': 'conv-1',
        'sender_id': 'user-a',
        'kind': 'photo',
        'created_at': '2025-01-01T12:00:00Z',
        'media_key': 'album/abc123.jpg',
        'media_type': 'photo',
      };

      final m = Message.fromJson(json);

      expect(m.kind, 'photo');
      expect(m.mediaKey, 'album/abc123.jpg');
      expect(m.mediaType, 'photo');
      expect(m.ephemeralViewedAt, isNull);
    });

    test('parses read_at when present', () {
      final json = {
        'id': 'msg-3',
        'conversation_id': 'conv-1',
        'sender_id': 'user-a',
        'kind': 'photo',
        'created_at': '2025-01-01T12:00:00Z',
        'media_key': 'album/xyz.jpg',
        'media_type': 'photo',
        'read_at': '2025-01-01T13:00:00Z',
      };

      final m = Message.fromJson(json);

      expect(m.readAt, '2025-01-01T13:00:00Z');
    });
  });

  group('Message.fromJson — ephemeral_photo message', () {
    test('parses ephemeral_viewed_at when present', () {
      final json = {
        'id': 'msg-4',
        'conversation_id': 'conv-1',
        'sender_id': 'user-b',
        'kind': 'ephemeral_photo',
        'created_at': '2025-01-01T12:00:00Z',
        'media_key': 'album/eph1.jpg',
        'media_type': 'photo',
        'ephemeral_viewed_at': '2025-01-01T14:00:00Z',
      };

      final m = Message.fromJson(json);

      expect(m.kind, 'ephemeral_photo');
      expect(m.mediaKey, 'album/eph1.jpg');
      expect(m.ephemeralViewedAt, '2025-01-01T14:00:00Z');
    });

    test('ephemeral_viewed_at is null for un-viewed ephemeral', () {
      final json = {
        'id': 'msg-5',
        'conversation_id': 'conv-1',
        'sender_id': 'user-b',
        'kind': 'ephemeral_photo',
        'created_at': '2025-01-01T12:00:00Z',
        'media_key': 'album/eph2.jpg',
        'media_type': 'photo',
      };

      final m = Message.fromJson(json);

      expect(m.ephemeralViewedAt, isNull);
    });
  });

  // ── Message.fromWebSocketJson ───────────────────────────────────────────────

  group('Message.fromWebSocketJson', () {
    test('uses kind from payload instead of hardcoding "text"', () {
      final json = {
        'id': 'ws-1',
        'conversation_id': 'conv-1',
        'sender_id': 'user-c',
        'kind': 'photo',
        'sent_at': '2025-01-01T12:00:00Z',
        'media_key': 'album/ws.jpg',
        'media_type': 'photo',
      };

      final m = Message.fromWebSocketJson(json);

      expect(m.kind, 'photo');
      expect(m.mediaKey, 'album/ws.jpg');
      expect(m.mediaType, 'photo');
    });

    test('defaults kind to "text" when absent from payload', () {
      final json = {
        'id': 'ws-2',
        'conversation_id': 'conv-1',
        'sender_id': 'user-c',
        'body': 'hi',
        'sent_at': '2025-01-01T12:00:00Z',
      };

      final m = Message.fromWebSocketJson(json);

      expect(m.kind, 'text');
    });

    test('viewed fields are always null (REST-only)', () {
      final json = {
        'id': 'ws-3',
        'conversation_id': 'conv-1',
        'sender_id': 'user-c',
        'kind': 'ephemeral_photo',
        'sent_at': '2025-01-01T12:00:00Z',
        'media_key': 'album/eph3.jpg',
        'media_type': 'photo',
      };

      final m = Message.fromWebSocketJson(json);

      expect(m.readAt, isNull,
          reason: 'WS payload never includes read_at');
      expect(m.ephemeralViewedAt, isNull,
          reason: 'WS payload never includes ephemeral_viewed_at');
    });

    test('parses media_key from ephemeral_photo WS message', () {
      final json = {
        'id': 'ws-4',
        'conversation_id': 'conv-2',
        'sender_id': 'user-d',
        'kind': 'ephemeral_photo',
        'sent_at': '2025-06-01T10:00:00Z',
        'media_key': 'album/secret.jpg',
        'media_type': 'photo',
      };

      final m = Message.fromWebSocketJson(json);

      expect(m.kind, 'ephemeral_photo');
      expect(m.mediaKey, 'album/secret.jpg');
      expect(m.ephemeralViewedAt, isNull);
    });
  });
}
