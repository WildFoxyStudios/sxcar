import 'package:flutter_test/flutter_test.dart';
import 'fake_token_storage.dart';

void main() {
  group('TokenStorage', () {
    late FakeTokenStorage storage;

    setUp(() {
      storage = FakeTokenStorage();
    });

    test('starts with null tokens', () async {
      expect(await storage.getAccessToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
    });

    test('saveTokens stores both tokens', () async {
      await storage.saveTokens(access: 'access123', refresh: 'refresh456');
      expect(await storage.getAccessToken(), equals('access123'));
      expect(await storage.getRefreshToken(), equals('refresh456'));
    });

    test('clearTokens removes both tokens', () async {
      await storage.saveTokens(access: 'access123', refresh: 'refresh456');
      await storage.clearTokens();
      expect(await storage.getAccessToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
    });

    test('saveTokens overwrites previous tokens', () async {
      await storage.saveTokens(access: 'old_access', refresh: 'old_refresh');
      await storage.saveTokens(access: 'new_access', refresh: 'new_refresh');
      expect(await storage.getAccessToken(), equals('new_access'));
      expect(await storage.getRefreshToken(), equals('new_refresh'));
    });
  });
}
