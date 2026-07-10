import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PIN secure storage', () {
    const pinKey = 'settings_pin_code';
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (MethodCall call) async {
              calls.add(call);
              if (call.method == 'read') return '1234'; // simulate stored PIN
              if (call.method == 'write') return null;
              if (call.method == 'delete') return null;
              return null;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            null,
          );
    });

    test('write stores PIN via secure storage', () async {
      final storage = const FlutterSecureStorage();
      await storage.write(key: pinKey, value: '5678');
      final writeCall = calls.firstWhere((c) => c.method == 'write');
      expect(writeCall.arguments['key'], pinKey);
      expect(writeCall.arguments['value'], '5678');
    });

    test('read retrieves PIN via secure storage', () async {
      final storage = const FlutterSecureStorage();
      final pin = await storage.read(key: pinKey);
      expect(pin, '1234');
      final readCall = calls.firstWhere((c) => c.method == 'read');
      expect(readCall.arguments['key'], pinKey);
    });
  });
}
