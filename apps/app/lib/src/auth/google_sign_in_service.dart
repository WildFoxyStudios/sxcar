import 'package:google_sign_in/google_sign_in.dart';

/// Wraps the Google Sign-In SDK (v7+) to produce an ID token for the backend.
///
/// Uses the singleton [GoogleSignIn.instance] API. Call [initialize] before
/// [signIn].
class GoogleSignInService {
  GoogleSignInService();

  bool _initialized = false;

  /// Initialize the Google Sign-In SDK. Must be called once before [signIn].
  Future<void> initialize() async {
    if (_initialized) return;
    const serverClientId = '619557571626-6jmhkf95t4vh5cpsnek7vhnu55l7cnnf.apps.googleusercontent.com';
    await GoogleSignIn.instance.initialize(
      serverClientId: serverClientId,
    );
    _initialized = true;
  }

  /// Returns `true` if Google Sign-In is available on this platform.
  bool get isSupported => !const bool.fromEnvironment('dart.library.js');

  /// Initiates the Google Sign-In flow and returns the ID token.
  ///
  /// The returned [idToken] is a JWT signed by Google that the backend
  /// verifies via Google's tokeninfo endpoint.
  ///
  /// Falls back with a clear error if [serverClientId] is not configured.
  Future<GoogleSignInResult> signIn() async {
    try {
      await initialize();
      final account = await GoogleSignIn.instance.authenticate();
      final auth = account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        return const GoogleSignInResult.error('No ID token returned');
      }
      return GoogleSignInResult.success(
        idToken: idToken,
        email: account.email,
        displayName: account.displayName,
        photoUrl: account.photoUrl,
      );
    } on Exception catch (e) {
      if (e.toString().contains('kSignInCanceledError')) {
        return const GoogleSignInResult.cancelled();
      }
      return GoogleSignInResult.error(e.toString());
    }
  }

  /// Sign out from Google (revokes app permission locally).
  Future<void> signOut() => GoogleSignIn.instance.signOut();
}

class GoogleSignInResult {
  final String? idToken;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final String? error;
  final bool cancelled;

  const GoogleSignInResult.success({
    required this.idToken,
    this.email,
    this.displayName,
    this.photoUrl,
  })  : error = null,
        cancelled = false;

  const GoogleSignInResult.cancelled()
      : idToken = null,
        email = null,
        displayName = null,
        photoUrl = null,
        error = null,
        cancelled = true;

  const GoogleSignInResult.error(this.error)
      : idToken = null,
        email = null,
        displayName = null,
        photoUrl = null,
        cancelled = false;

  bool get isSuccess => idToken != null;
}
