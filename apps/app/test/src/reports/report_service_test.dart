import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/reports/report_service.dart';

void main() {
  test('report POSTs target + kind + reason to /reports', () async {
    final adapter = _CapturingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final service = ReportService(dio);

    await service.report(
      targetUserId: 'user-9',
      targetKind: 'profile',
      reason: 'Harassment',
    );

    expect(adapter.lastPath, '/reports');
    expect(adapter.lastMethod, 'POST');
    final body = jsonDecode(adapter.lastBody!) as Map<String, dynamic>;
    expect(body['target_user_id'], 'user-9');
    expect(body['target_kind'], 'profile');
    expect(body['reason'], 'Harassment');
  });

  test('report omits null optional fields', () async {
    final adapter = _CapturingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final service = ReportService(dio);

    await service.report(targetUserId: 'u1');

    final body = jsonDecode(adapter.lastBody!) as Map<String, dynamic>;
    expect(body.containsKey('target_id'), isFalse);
    expect(body.containsKey('reason'), isFalse);
    expect(body['target_kind'], 'profile');
  });

  test('kReportReasons has the expected options', () {
    expect(kReportReasons, contains('Harassment'));
    expect(kReportReasons, contains('Fake profile'));
    expect(kReportReasons, contains('Underage'));
  });
}

class _CapturingAdapter implements HttpClientAdapter {
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
    lastBody = options.data == null ? null : jsonEncode(options.data);
    return ResponseBody.fromString(
      '{"id":"r1"}',
      201,
      headers: const {
        'content-type': ['application/json'],
      },
    );
  }
}
