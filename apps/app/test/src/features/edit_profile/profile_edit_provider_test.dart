import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/features/edit_profile/profile_edit_provider.dart';
import 'package:app/src/features/profile_screen.dart';

UserProfile _makeProfile({
  String? displayName,
  String? bio,
  List<String> tribes = const [],
  Map<String, dynamic> details = const {},
}) =>
    UserProfile(
      id: 'u1',
      email: 'a@b.com',
      emailVerified: true,
      status: 'active',
      role: 'user',
      createdAt: '2024-01-01T00:00:00Z',
      displayName: displayName,
      bio: bio,
      tribes: tribes,
      details: details,
    );

class _FakeDioInterceptor extends Interceptor {
  final Map<String, dynamic>? responseBody;
  final int statusCode;
  _FakeDioInterceptor(this.responseBody, {this.statusCode = 200});

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) {
    if (responseBody != null) {
      handler.resolve(Response(
        requestOptions: options,
        data: responseBody,
        statusCode: statusCode,
      ));
    } else {
      handler.next(options);
    }
  }
}

Dio _fakeDio(Map<String, dynamic>? body, {int statusCode = 200}) {
  final dio = Dio();
  dio.interceptors.add(_FakeDioInterceptor(body, statusCode: statusCode));
  return dio;
}

void main() {
  group('ProfileEditNotifier', () {
    test('loadFrom seeds state with original=current, draft=current', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(profileEditProvider.notifier);
      final p = _makeProfile(displayName: 'Alex');
      notifier.loadFrom(p);
      final s = container.read(profileEditProvider);
      expect(s.original?.displayName, 'Alex');
      expect(s.draft?.displayName, 'Alex');
      expect(s.status, ProfileEditStatus.idle);
      expect(s.isDirty, isFalse);
    });

    test('updateDraft mutates draft only; original unchanged', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(profileEditProvider.notifier);
      final p = _makeProfile(displayName: 'Alex');
      notifier.loadFrom(p);
      notifier.updateDraft(
          (d) => UserProfile(
                id: d.id,
                email: d.email,
                emailVerified: d.emailVerified,
                status: d.status,
                role: d.role,
                createdAt: d.createdAt,
                displayName: 'Alex2',
                bio: d.bio,
                tribes: d.tribes,
                details: d.details,
              ));
      final s = container.read(profileEditProvider);
      expect(s.draft?.displayName, 'Alex2');
      expect(s.original?.displayName, 'Alex');
      expect(s.isDirty, isTrue);
    });

    test('resetDraft restores draft=original; isDirty=false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(profileEditProvider.notifier);
      final p = _makeProfile(displayName: 'Alex', tribes: const ['bear']);
      notifier.loadFrom(p);
      notifier.updateDraft(
          (d) => UserProfile(
                id: d.id,
                email: d.email,
                emailVerified: d.emailVerified,
                status: d.status,
                role: d.role,
                createdAt: d.createdAt,
                displayName: d.displayName,
                bio: d.bio,
                tribes: const ['bear', 'otter'],
                details: d.details,
              ));
      notifier.resetDraft();
      final s = container.read(profileEditProvider);
      expect(s.draft?.tribes, ['bear']);
      expect(s.isDirty, isFalse);
    });
  });
}