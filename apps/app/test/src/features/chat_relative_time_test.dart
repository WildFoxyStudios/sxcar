import 'package:app/l10n/gen/app_localizations_en.dart';
import 'package:app/src/features/chat_list_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = AppLocalizationsEn();

  group('ChatListScreen.relativeTime', () {
    test('less than 1 minute returns "Just now"', () {
      final now = DateTime.now();
      final iso = now.subtract(const Duration(seconds: 30)).toIso8601String();
      expect(ChatListScreen.relativeTime(iso, l10n), 'Just now');
    });

    test('less than 60 minutes returns "Xm ago"', () {
      final now = DateTime.now();
      final iso = now.subtract(const Duration(minutes: 5)).toIso8601String();
      expect(ChatListScreen.relativeTime(iso, l10n), '5m ago');
    });

    test('same day returns HH:mm format', () {
      final now = DateTime.now();
      // 08:30 today is always in the past relative to `now`
      final dt = DateTime(now.year, now.month, now.day, 8, 30);
      final iso = dt.toIso8601String();
      expect(ChatListScreen.relativeTime(iso, l10n), '08:30');
    });

    test('yesterday returns "Yesterday"', () {
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1, 14, 0);
      final iso = yesterday.toIso8601String();
      expect(ChatListScreen.relativeTime(iso, l10n), 'Yesterday');
    });

    test('less than 7 days returns "Xd ago"', () {
      final now = DateTime.now();
      final iso = now.subtract(const Duration(days: 3)).toIso8601String();
      expect(ChatListScreen.relativeTime(iso, l10n), '3d ago');
    });

    test('older than 7 days returns dd/MM/yyyy format', () {
      // 15 January 2024, local time
      final dt = DateTime(2024, 1, 15, 10, 0);
      final iso = dt.toIso8601String();
      expect(ChatListScreen.relativeTime(iso, l10n), '15/01/2024');
    });

    test('invalid ISO string returns empty string', () {
      expect(ChatListScreen.relativeTime('not-a-date', l10n), '');
    });
  });
}
