class AdminConfig {
  /// Override at build time with:
  ///   --dart-define=ADMIN_API_URL=https://my-custom-api.com
  static const String apiUrl = String.fromEnvironment(
    'ADMIN_API_URL',
    defaultValue: 'https://api.turnend.win',
  );
  static const Duration httpTimeout = Duration(seconds: 30);
}
