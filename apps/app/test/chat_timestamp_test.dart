import 'package:flutter_test/flutter_test.dart';

// Import the source file where the now-static method lives.
// We test the static method directly instead of the widget.
import 'package:app/src/features/chat_screen.dart';

void main() {
  group('ChatScreen.shouldShowTimestamp', () {
    test('returns true at index 0', () {
      expect(ChatScreen.shouldShowTimestamp(0), true);
    });

    test('returns true every 10 messages', () {
      expect(ChatScreen.shouldShowTimestamp(10), true);
      expect(ChatScreen.shouldShowTimestamp(20), true);
    });

    test('returns false for non-milestone indices', () {
      expect(ChatScreen.shouldShowTimestamp(1), false);
      expect(ChatScreen.shouldShowTimestamp(5), false);
      expect(ChatScreen.shouldShowTimestamp(11), false);
    });
  });
}
