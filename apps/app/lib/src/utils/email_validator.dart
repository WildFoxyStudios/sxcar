/// Simple email validation that was previously done via Rust FFI.
///
/// Checks that the string contains `@` and a domain with at least one dot.
/// This is intentionally lenient — the backend performs full validation
/// and sends a verification email; the client-side check is a UX guard
/// against obvious typos.
bool validateEmail({required String email}) {
  final trimmed = email.trim();
  if (trimmed.isEmpty) return false;
  final atIndex = trimmed.indexOf('@');
  if (atIndex <= 0 || atIndex == trimmed.length - 1) return false;
  final domain = trimmed.substring(atIndex + 1);
  return domain.contains('.') && !domain.startsWith('.') && !domain.endsWith('.');
}
