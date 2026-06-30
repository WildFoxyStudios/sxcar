import 'package:firebase_auth/firebase_auth.dart'
    show FirebaseAuth, FirebaseAuthException, GoogleAuthProvider, OAuthCredential;
import 'package:google_sign_in/google_sign_in.dart';

/// Native Google Sign-In via Google Play Services (no browser on Android).
///
/// Flow: GoogleSignIn (native dialog) → Google ID token →
/// FirebaseAuth credential → OAuthCredential.idToken (for backend verification).
class GoogleSignInService {
  final FirebaseAuth _auth;

  GoogleSignInService() : _auth = FirebaseAuth.instance;

  bool get isSupported => !const bool.fromEnvironment('dart.library.js');

  Future<void> initialize() async {
    await GoogleSignIn.instance.initialize();
  }

  /// Opens the native Google Sign-In dialog and returns the ID token for
  /// backend verification via POST /auth/oauth/google.
  Future<GoogleSignInResult> signIn() async {
    try {
      await initialize();

      // Step 1: Native Google Sign-In dialog (Google Play Services, no browser)
      final googleAccount = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleAccount.authentication;
      final googleIdToken = googleAuth.idToken;
      if (googleIdToken == null) {
        return const GoogleSignInResult.error('No Google ID token returned');
      }

      // Step 2: Sign in to Firebase with the Google credential (idToken only, v7)
      final googleCredential = GoogleAuthProvider.credential(
        idToken: googleIdToken,
      );
      final userCredential = await _auth.signInWithCredential(googleCredential);

      // Step 3: Get the underlying Google OAuth ID token for backend verification
      final oauthCred = userCredential.credential;
      final backendIdToken = (oauthCred is OAuthCredential)
          ? (oauthCred.idToken ?? googleIdToken)
          : googleIdToken;

      return GoogleSignInResult.success(
        idToken: backendIdToken,
        email: googleAccount.email,
        displayName: googleAccount.displayName,
        photoUrl: googleAccount.photoUrl,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'canceled' || e.code == 'user-cancelled') {
        return const GoogleSignInResult.cancelled();
      }
      return GoogleSignInResult.error(e.message ?? 'Auth error: ${e.code}');
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('kSignInCanceledError') || msg.contains('canceled')) {
        return const GoogleSignInResult.cancelled();
      }
      return GoogleSignInResult.error(msg);
    }
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }
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
