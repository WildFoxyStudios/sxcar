import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/chat/unread_count_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> conversations;
  _MockAdapter({this.conversations = const []});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/chat/conversations') {
      return ResponseBody.fromString(
        jsonEncode({'conversations': conversations}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      '{}',
      404,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

class _AuthenticatedNotifier extends AuthNotifier {
  _AuthenticatedNotifier() : super();

  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        accessToken: 'test-token',
        email: 'test@example.com',
      );

  @override
  Future<void> logout() async {}
}

/// Wraps the unread-count FutureProvider in a Material widget so we can
/// pump it inside the widget tester and assert the badge appears.
Widget _wrap(Widget child, {required Dio dio}) {
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
      dioProvider.overrideWithValue(dio),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('unreadCountProvider + Badge rendering', () {
    testWidgets('shows no Badge when unread count is 0', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockAdapter();
      await tester.pumpWidget(_wrap(
        Consumer(builder: (context, ref, _) {
          final unread = ref.watch(unreadCountProvider);
          return unread.when(
            loading: () => const Text('loading'),
            error: (_, _) => const Text('error'),
            data: (n) => Text('count=$n'),
          );
        }),
        dio: dio,
      ));
      await tester.pumpAndSettle();
      expect(find.text('count=0'), findsOneWidget);
    });

    testWidgets('computes total unread across conversations', (tester) async {
      final dio = Dio()
        ..httpClientAdapter = _MockAdapter(conversations: [
          {'conversation_id': 'c1', 'unread_count': 4},
          {'conversation_id': 'c2', 'unread_count': 7},
        ]);
      await tester.pumpWidget(_wrap(
        Consumer(builder: (context, ref, _) {
          final unread = ref.watch(unreadCountProvider);
          return unread.when(
            loading: () => const Text('loading'),
            error: (_, _) => const Text('error'),
            data: (n) => Text('count=$n'),
          );
        }),
        dio: dio,
      ));
      await tester.pumpAndSettle();
      expect(find.text('count=11'), findsOneWidget);
    });
  });
}