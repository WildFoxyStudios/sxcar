import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/profile_screen.dart' show UserProfile;

enum ProfileEditStatus { idle, saving, saved, error }

class ProfileEditState {
  final UserProfile? original;
  final UserProfile? draft;
  final ProfileEditStatus status;
  final String? errorMessage;

  const ProfileEditState({
    this.original,
    this.draft,
    this.status = ProfileEditStatus.idle,
    this.errorMessage,
  });

  bool get isDirty =>
      original != null && draft != null && !_equal(original!, draft!);
  bool get isSaving => status == ProfileEditStatus.saving;

  ProfileEditState copyWith({
    UserProfile? original,
    UserProfile? draft,
    ProfileEditStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ProfileEditState(
      original: original ?? this.original,
      draft: draft ?? this.draft,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  static bool _equal(UserProfile a, UserProfile b) {
    // Cheap structural compare of the fields users can edit. Avoids requiring
    // deep Map equality on `details` for the common case (UI uses isDirty for
    // a button label, not for security).
    return a.displayName == b.displayName &&
        a.bio == b.bio &&
        a.birthdate == b.birthdate &&
        a.heightCm == b.heightCm &&
        a.weightKg == b.weightKg &&
        a.bodyType == b.bodyType &&
        a.relationshipStatus == b.relationshipStatus &&
        a.position == b.position &&
        a.ethnicity == b.ethnicity &&
        a.pronouns == b.pronouns &&
        _listEq(a.tribes, b.tribes) &&
        _listEq(a.lookingFor, b.lookingFor) &&
        _listEq(a.meetAt, b.meetAt) &&
        _listEq(a.tags, b.tags) &&
        a.showAge == b.showAge &&
        a.showRole == b.showRole &&
        a.showTribes == b.showTribes &&
        a.showPosition == b.showPosition &&
        a.showEthnicity == b.showEthnicity &&
        a.showRelationshipStatus == b.showRelationshipStatus &&
        a.showSocialLinks == b.showSocialLinks;
  }

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Async loader that fetches the current profile so the provider can init.
final currentProfileProvider = FutureProvider<UserProfile>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get<Map<String, dynamic>>('/profile');
  return UserProfile.fromJson(res.data!['user'] as Map<String, dynamic>);
});

class ProfileEditNotifier extends Notifier<ProfileEditState> {
  @override
  ProfileEditState build() {
    // Seed with empty state; the screen calls loadFrom() after fetching current.
    return const ProfileEditState();
  }

  /// Hydrate the draft from a freshly-fetched current profile.
  void loadFrom(UserProfile current) {
    state = ProfileEditState(
      original: current,
      draft: current,
      status: ProfileEditStatus.idle,
    );
  }

  /// Replace a single editable field on the draft. Accepts a partial
  /// UserProfile via the copyWith-like setter; passes through unchanged for
  /// other fields.
  void updateDraft(UserProfile Function(UserProfile current) mutator) {
    final draft = state.draft;
    if (draft == null) return;
    state = state.copyWith(
      draft: mutator(draft),
      status: ProfileEditStatus.idle,
      clearError: true,
    );
  }

  /// Persist the draft to the backend. Updates `original` on success.
  Future<void> save() async {
    final draft = state.draft;
    if (draft == null) return;
    state = state.copyWith(
        status: ProfileEditStatus.saving, clearError: true);
    try {
      final dio = ref.read(dioProvider);
      final body = _buildBody(draft);
      final res = await dio.put<Map<String, dynamic>>(
        '/profile',
        data: body,
      );
      final saved = UserProfile.fromJson(
          res.data!['user'] as Map<String, dynamic>);
      state = ProfileEditState(
        original: saved,
        draft: saved,
        status: ProfileEditStatus.saved,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        status: ProfileEditStatus.error,
        errorMessage: _humanizeError(e),
      );
    } catch (e) {
      state = state.copyWith(
        status: ProfileEditStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  void resetDraft() {
    if (state.original == null) return;
    state = ProfileEditState(
      original: state.original,
      draft: state.original,
      status: ProfileEditStatus.idle,
      errorMessage: null,
    );
  }

  Map<String, dynamic> _buildBody(UserProfile p) {
    final body = <String, dynamic>{
      if (p.displayName != null) 'display_name': p.displayName,
      if (p.bio != null) 'bio': p.bio,
      if (p.birthdate != null) 'birthdate': p.birthdate,
      if (p.heightCm != null) 'height_cm': p.heightCm,
      if (p.weightKg != null) 'weight_kg': p.weightKg,
      if (p.bodyType != null) 'body_type': p.bodyType,
      if (p.relationshipStatus != null)
        'relationship_status': p.relationshipStatus,
      if (p.position != null) 'position': p.position,
      if (p.ethnicity != null) 'ethnicity': p.ethnicity,
      if (p.pronouns != null) 'pronouns': p.pronouns,
      'tribes': p.tribes,
      'looking_for': p.lookingFor,
      'meet_at': p.meetAt,
      'tags': p.tags,
      'show_age': p.showAge,
      'show_role': p.showRole,
      'show_tribes': p.showTribes,
      'show_position': p.showPosition,
      'show_ethnicity': p.showEthnicity,
      'show_relationship_status': p.showRelationshipStatus,
      'show_social_links': p.showSocialLinks,
    };
    // Explicit null in 'details' is a 422 validation error on the backend.
    // Only include it when the value is non-null.
    if (p.details != null) {
      body['details'] = p.details;
    }
    return body;
  }

  String _humanizeError(DioException e) {
    final code = e.response?.statusCode;
    if (code == 413) return 'Detalles demasiado grandes (máx 8 KB).';
    if (code == 422) return 'Datos inválidos.';
    if (code == 401) return 'Sesión expirada.';
    if (code == 500) return 'Error del servidor. Intenta de nuevo.';
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Tiempo de conexión agotado. Verifica tu conexión.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Sin conexión. Verifica tu internet.';
    }
    if (code != null) return 'Error al guardar (HTTP $code).';
    return 'Error de red (${e.type.name}). Verifica tu conexión.';
  }
}

final profileEditProvider =
    NotifierProvider<ProfileEditNotifier, ProfileEditState>(
        ProfileEditNotifier.new);