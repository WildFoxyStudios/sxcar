import 'dart:io' show Platform;
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// Top-level background message handler.
///
/// Firebase Messaging requires this to be a top-level (not class member)
/// function annotated with @pragma('vm:entry-point') so the AOT compiler
/// keeps it alive.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Keep this minimal — Firebase is already initialized at this point by the
  // plugin itself. Just log so we can verify receipt in logcat.
  debugPrint('[FCM] background: messageId=${message.messageId}');
}

/// Service that obtains an FCM token and registers it with the backend.
///
/// **Testability:** pass [tokenOverride] to skip all FirebaseMessaging SDK
/// calls. The test VM cannot initialize the Firebase runtime, so this seam
/// lets tests inject a fake token and still exercise the HTTP registration
/// logic without touching native code.
class PushService {
  final Dio _dio;
  bool _listenersRegistered = false;

  PushService(this._dio);

  /// Initialises Firebase Messaging and registers the FCM token.
  ///
  /// Safe to call multiple times (token refresh re-registers automatically).
  /// No-op on web. On the test VM, pass [tokenOverride] to skip Firebase.
  Future<void> initAndRegister({String? tokenOverride}) async {
    // Web does not support firebase_messaging the same way; skip gracefully.
    if (kIsWeb) return;

    try {
      String? token;

      if (tokenOverride != null) {
        // ── Test / injection path ──────────────────────────────────────────
        // Caller supplied a fake token — skip ALL Firebase SDK calls so this
        // method is safe to call on the Dart VM (no Firebase native runtime).
        token = tokenOverride;
      } else {
        // ── Production path ────────────────────────────────────────────────
        // Request notification permission (Android 13+ POST_NOTIFICATIONS,
        // iOS alert/badge/sound).
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );

        token = await FirebaseMessaging.instance.getToken();

        // Register listeners once — prevent accumulation on re-auth.
        if (!_listenersRegistered) {
          // Re-register whenever the token is rotated by FCM.
          FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);

          // Foreground message handler: log + (future) in-app banner.
          // We deliberately do NOT add flutter_local_notifications here
          // (that is a separate dependency beyond G2 scope).
          FirebaseMessaging.onMessage.listen((RemoteMessage message) {
            final n = message.notification;
            debugPrint('[FCM] foreground: ${n?.title} — ${n?.body}');
          });

          _listenersRegistered = true;
        }
      }

      if (token != null) {
        await _registerToken(token);
      }
    } catch (e) {
      // Log but never crash — push is non-critical.
      debugPrint('[FCM] initAndRegister error: $e');
    }
  }

  /// POSTs the token to `POST /notifications/register`.
  Future<void> _registerToken(String token) async {
    try {
      // Platform.isIOS is safe on mobile VMs (including test VMs on Linux/macOS
      // where it returns false, giving 'android' — which is correct for tests).
      final platform = Platform.isIOS ? 'ios' : 'android';
      await _dio.post<void>(
        '/notifications/register',
        data: {'device_token': token, 'platform': platform},
      );
      debugPrint('[FCM] token registered (${token.length > 10 ? "${token.substring(0, 10)}..." : token})');
    } catch (e) {
      debugPrint('[FCM] register error: $e');
    }
  }
}

/// Riverpod provider — constructed with the auth-injected Dio from [dioProvider].
final pushServiceProvider = Provider<PushService>((ref) {
  final dio = ref.watch(dioProvider);
  return PushService(dio);
});
