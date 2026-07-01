import 'dart:convert';

/// Decode the `sub` (subject / user id) claim from a JWT access token
/// without verifying the signature (the server already did that; the client
/// only needs the id to know which items are its own).
///
/// Returns null if the token is malformed or has no `sub` claim.
String? jwtSubject(String? token) {
  if (token == null) return null;
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    var payload = parts[1];
    // Base64Url without padding — pad to a multiple of 4.
    payload = payload.padRight(payload.length + (4 - payload.length % 4) % 4, '=');
    final decoded = utf8.decode(base64Url.decode(payload));
    final json = jsonDecode(decoded) as Map<String, dynamic>;
    return json['sub'] as String?;
  } catch (_) {
    return null;
  }
}
