import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/chat/models.dart';

void main() {
  // ── MessageReaction ──────────────────────────────────────────────────────

  group('MessageReaction.fromJson', () {
    test('parses user_id and emoji', () {
      final r = MessageReaction.fromJson({
        'user_id': 'user-a',
        'emoji': '❤️',
      });

      expect(r.userId, 'user-a');
      expect(r.emoji, '❤️');
    });

    test('is const-constructible', () {
      const r = MessageReaction(userId: 'u1', emoji: '👍');
      expect(r.userId, 'u1');
      expect(r.emoji, '👍');
    });
  });

  // ── Message reactions field ──────────────────────────────────────────────

  group('Message.reactions — fromJson', () {
    test('parses reactions array when present', () {
      final json = {
        'id': 'msg-1',
        'conversation_id': 'conv-1',
        'sender_id': 'user-a',
        'kind': 'text',
        'body': 'hello',
        'created_at': '2025-01-01T12:00:00Z',
        'reactions': [
          {'user_id': 'user-b', 'emoji': '❤️'},
          {'user_id': 'user-c', 'emoji': '😂'},
        ],
      };

      final m = Message.fromJson(json);

      expect(m.reactions, hasLength(2));
      expect(m.reactions[0].userId, 'user-b');
      expect(m.reactions[0].emoji, '❤️');
      expect(m.reactions[1].userId, 'user-c');
      expect(m.reactions[1].emoji, '😂');
    });

    test('defaults to empty list when reactions absent', () {
      final json = {
        'id': 'msg-2',
        'conversation_id': 'conv-1',
        'sender_id': 'user-a',
        'kind': 'text',
        'created_at': '2025-01-01T12:00:00Z',
      };

      final m = Message.fromJson(json);

      expect(m.reactions, isEmpty);
    });

    test('handles empty reactions array', () {
      final json = {
        'id': 'msg-3',
        'conversation_id': 'conv-1',
        'sender_id': 'user-a',
        'kind': 'text',
        'created_at': '2025-01-01T12:00:00Z',
        'reactions': <dynamic>[],
      };

      final m = Message.fromJson(json);

      expect(m.reactions, isEmpty);
    });
  });

  group('Message.reactions — fromWebSocketJson', () {
    test('defaults to empty list', () {
      final json = {
        'id': 'ws-1',
        'conversation_id': 'conv-1',
        'sender_id': 'user-a',
        'body': 'hi',
        'sent_at': '2025-01-01T12:00:00Z',
      };

      final m = Message.fromWebSocketJson(json);

      expect(m.reactions, isEmpty);
    });
  });

  // ── Message.copyWith ─────────────────────────────────────────────────────

  group('Message.copyWith', () {
    test('replaces reactions when provided', () {
      final m = Message(
        id: 'msg-1',
        conversationId: 'conv-1',
        senderId: 'user-a',
        kind: 'text',
        body: 'hi',
        createdAt: '2025-01-01T12:00:00Z',
      );

      final updated = m.copyWith(reactions: [
        const MessageReaction(userId: 'user-b', emoji: '👍'),
      ]);

      expect(updated.reactions, hasLength(1));
      expect(updated.reactions.first.emoji, '👍');
    });

    test('preserves other fields when only reactions change', () {
      final m = Message(
        id: 'msg-1',
        conversationId: 'conv-1',
        senderId: 'user-a',
        kind: 'text',
        body: 'hello world',
        createdAt: '2025-01-01T12:00:00Z',
      );

      final updated = m.copyWith(reactions: const []);

      expect(updated.id, 'msg-1');
      expect(updated.body, 'hello world');
      expect(updated.kind, 'text');
    });

    test('keeps existing reactions when reactions arg is null', () {
      final m = Message(
        id: 'msg-1',
        conversationId: 'conv-1',
        senderId: 'user-a',
        kind: 'text',
        body: 'hi',
        createdAt: '2025-01-01T12:00:00Z',
        reactions: const [MessageReaction(userId: 'u1', emoji: '❤️')],
      );

      final updated = m.copyWith();

      expect(updated.reactions, hasLength(1));
      expect(updated.reactions.first.emoji, '❤️');
    });
  });
}
