import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/settings/tier3_settings_service.dart';

void main() {
  test('getIdleReminderHours parses an int', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _StubAdapter(body: '{"hours":24}');
    final service = Tier3SettingsService(dio);

    expect(await service.getIdleReminderHours(), 24);
  });

  test('getIdleReminderHours returns null when off', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _StubAdapter(body: '{"hours":null}');
    final service = Tier3SettingsService(dio);

    expect(await service.getIdleReminderHours(), isNull);
  });

  test('setIdleReminderHours PUTs the hours body', () async {
    final adapter = _StubAdapter(body: '{"ok":true,"hours":12}');
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final service = Tier3SettingsService(dio);

    await service.setIdleReminderHours(12);

    expect(adapter.lastPath, '/me/idle-reminder');
    expect(adapter.lastMethod, 'PUT');
    expect(adapter.lastBody, contains('12'));
  });
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({required this.body});
  final String body;
  String? lastPath;
  String? lastMethod;
  String? lastBody;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    lastPath = options.path;
    lastMethod = options.method;
    lastBody = options.data?.toString();
    return ResponseBody.fromString(
      body,
      200,
      headers: const {
        'content-type': ['application/json'],
      },
    );
  }
}
