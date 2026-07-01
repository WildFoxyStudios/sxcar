import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/auth/jwt_utils.dart';

/// Build an unsigned JWT with the given payload (signature is ignored on the
/// client — we only decode `sub`).
String _makeToken(Map<String, dynamic> payload) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final header = seg({'alg': 'HS256', 'typ': 'JWT'});
  final body = seg(payload);
  return '$header.$body.sig';
}

void main() {
  test('jwtSubject decodes the sub claim', () {
    final token = _makeToken({'sub': 'user-42', 'exp': 999});
    expect(jwtSubject(token), 'user-42');
  });

  test('jwtSubject returns null for null / malformed tokens', () {
    expect(jwtSubject(null), isNull);
    expect(jwtSubject('not-a-jwt'), isNull);
    expect(jwtSubject('a.b'), isNull);
  });

  test('jwtSubject returns null when there is no sub claim', () {
    final token = _makeToken({'exp': 999});
    expect(jwtSubject(token), isNull);
  });
}
