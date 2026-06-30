import 'package:firebase_auth/firebase_auth.dart'
    show FirebaseAuth, FirebaseAuthException, GoogleAuthProvider, OAuthCredential;

/// Wraps Firebase Auth for Google Sign-In. Uses the already-configured
/// Firebase project (foxy-85ecb) from [firebase_options.dart].
class GoogleSignInService {
  final FirebaseAuth _auth;

  GoogleSignInService() : _auth = FirebaseAuth.instance;

  /// Returns `true` if Google Sign-In is available on this platform.
  bool get isSupported => !const bool.fromEnvironment('dart.library.js');

  /// Initiates the Google Sign-In flow via Firebase Auth and returns the ID token.
  ///
  /// The returned [idToken] is a JWT signed by Google that the backend
  /// verifies via Google's tokeninfo endpoint (RealOAuthVerifier).
  Future<GoogleSignInResult> signIn() async {
    try {
      final provider = GoogleAuthProvider();
      // Force account selection even if already signed in
      provider.setCustomParameters({'prompt': 'select_account'});
      final credential = await _auth.signInWithProvider(provider);
      // Get the Google ID token from the OAuthCredential for backend verification.
      // Fall back to Firebase ID token if the underlying Google token isn't exposed.
      String? idToken = credential.credential is OAuthCredential
          ? (credential.credential as OAuthCredential).idToken
          : null;
      idToken ??= await credential.user?.getIdToken();
      if (idToken == null) {
        return const GoogleSignInResult.error('No ID token returned from Firebase Auth');
      }
      return GoogleSignInResult.success(
        idToken: idToken,
        email: credential.user?.email,
        displayName: credential.user?.displayName,
        photoUrl: credential.user?.photoURL,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'canceled' || e.code == 'user-cancelled') {
        return const GoogleSignInResult.cancelled();
      }
      return GoogleSignInResult.error(e.message ?? 'Firebase Auth error: ${e.code}');
    } catch (e) {
      return GoogleSignInResult.error(e.toString());
    }
  }

  /// Sign out from Firebase Auth.
  Future<void> signOut() => _auth.signOut();
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
