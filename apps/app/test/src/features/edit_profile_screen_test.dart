import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/edit_profile_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockEditProfileAdapter implements HttpClientAdapter {
  final Map<String, dynamic>? initialHealth;
  final List<String> putPaths = [];
  final List<Map<String, dynamic>> putBodies = [];

  _MockEditProfileAdapter({this.initialHealth});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'GET' && options.path == '/profile') {
      final body = jsonEncode({
        'user': {
          'id': '00000000-0000-0000-0000-000000000001',
          'email': 'test@example.com',
          'email_verified': true,
          'status': 'active',
          'role': 'user',
          'created_at': '2025-01-01T00:00:00Z',
          'display_name': 'TestUser',
          'bio': 'Hello!',
          'birthdate': null,
          'height_cm': 180,
          'weight_kg': 75,
          'body_type': null,
          'relationship_status': null,
          'position': null,
          'ethnicity': null,
          'pronouns': null,
          'profile_photo_id': null,
          'profile_photo_url': null,
          'tribes': <String>[],
          'looking_for': <String>[],
          'meet_at': <String>[],
          'tags': <String>[],
        },
      });
      return ResponseBody.fromString(
        body,
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.method == 'GET' && options.path == '/profile/health') {
      if (initialHealth == null) {
        return ResponseBody.fromString(
          '{"error":"not found"}',
          404,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      return ResponseBody.fromString(
        jsonEncode(initialHealth),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.method == 'PUT' && options.path == '/profile') {
      putPaths.add(options.path);
      // Echo back the same user; don't try to parse data.
      final body = jsonEncode({
        'user': {
          'id': '00000000-0000-0000-0000-000000000001',
          'email': 'test@example.com',
          'email_verified': true,
          'status': 'active',
          'role': 'user',
          'created_at': '2025-01-01T00:00:00Z',
          'display_name': 'TestUser',
          'bio': 'Hello!',
          'birthdate': null,
          'height_cm': 180,
          'weight_kg': 75,
          'profile_photo_id': null,
          'profile_photo_url': null,
          'tribes': <String>[],
          'looking_for': <String>[],
          'meet_at': <String>[],
          'tags': <String>[],
        },
      });
      return ResponseBody.fromString(
        body,
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.method == 'PUT' && options.path == '/profile/health') {
      putPaths.add(options.path);
      Map<String, dynamic>? captured;
      if (options.data is Map) {
        captured = options.data as Map<String, dynamic>;
      } else if (options.data is String) {
        try {
          captured = jsonDecode(options.data as String) as Map<String, dynamic>;
        } catch (_) {}
      }
      if (captured != null) putBodies.add(captured);
      return ResponseBody.fromString(
        jsonEncode(initialHealth ??
            {'hiv_status': null, 'last_tested_on': null, 'prep': null}),
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

void main() {
  group('EditProfileScreen — Health section', () {
    testWidgets('renders Health section with HIV dropdown, date, PrEP toggle',
        (tester) async {
      final adapter = _MockEditProfileAdapter();
      final dio = Dio()..httpClientAdapter = adapter;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: EditProfileScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Scroll the ListView manually since `find.byType(Scrollable).first`
      // can pick up unrelated scrollables (e.g. from a hidden date picker).
      await tester.drag(find.byType(ListView), const Offset(0, -1500));
      await tester.pumpAndSettle();

      expect(find.text('HEALTH'), findsOneWidget);
      expect(find.text('HIV Status'), findsOneWidget);
      expect(find.text('Last Tested On'), findsOneWidget);
      expect(find.text('Not set'), findsOneWidget);
      expect(find.text('On PrEP'), findsOneWidget);
    });

    testWidgets('pre-fills HIV status and last tested date from backend',
        (tester) async {
      final adapter = _MockEditProfileAdapter(initialHealth: {
        'hiv_status': 'Negative',
        'last_tested_on': '2026-01-15',
        'prep': true,
      });
      final dio = Dio()..httpClientAdapter = adapter;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: EditProfileScreen()),
        ),
      );

      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -1500));
      await tester.pumpAndSettle();

      expect(find.text('2026-01-15'), findsOneWidget);
    });

    testWidgets('toggling PrEP switch updates state', (tester) async {
      final adapter = _MockEditProfileAdapter();
      final dio = Dio()..httpClientAdapter = adapter;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: EditProfileScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Scroll to bring the PrEP Switch into view.
      await tester.drag(find.byType(ListView), const Offset(0, -1500));
      await tester.pumpAndSettle();

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);

      Switch widget = tester.widget(switchFinder);
      expect(widget.value, isFalse);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      widget = tester.widget(switchFinder);
      expect(widget.value, isTrue);
    });

    testWidgets('saving triggers PUT /profile/health', (tester) async {
      final adapter = _MockEditProfileAdapter();
      final dio = Dio()..httpClientAdapter = adapter;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: EditProfileScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Scroll to the Switch, toggle PrEP on
      await tester.drag(find.byType(ListView), const Offset(0, -1500));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // Scroll to the Save button and tap it
      await tester.drag(find.byType(ListView), const Offset(0, -1500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(adapter.putPaths.contains('/profile'), isTrue);
      expect(adapter.putPaths.contains('/profile/health'), isTrue);

      final healthPut = adapter.putBodies.firstWhere(
        (b) => b.containsKey('prep'),
        orElse: () => {},
      );
      expect(healthPut['prep'], isTrue);
    });
  });
}