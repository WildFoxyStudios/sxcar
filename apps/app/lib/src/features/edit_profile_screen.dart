import 'dart:async';

import 'package:app/l10n/gen/app_localizations.dart';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/edit_profile/add_trip_screen.dart';
import 'package:app/src/features/edit_profile/practices_screen.dart';
import 'package:app/src/features/edit_profile/profile_edit_provider.dart';
import 'package:app/src/features/edit_profile/sheets.dart';
import 'package:app/src/features/edit_profile/vaccines_screen.dart';
import 'package:app/src/features/profile_drawer.dart' show ownProfileProvider;
import 'package:app/src/features/profile_screen.dart' show UserProfile;
import 'package:app/src/health/health_service.dart';
import 'package:app/src/media/media_service.dart';
import 'package:app/src/models/profile_options.dart';
import 'package:app/src/nsfw/nsfw_service.dart';
import 'package:app/src/premium/premium_gate.dart';
import 'package:app/src/premium/premium_service.dart';
import 'package:app/src/theme/app_theme.dart';
import 'package:app/src/theme/widgets.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

/// Full editing form for the user's own profile at route /edit-profile.
///
/// Rewrite (T4.10): Riverpod-backed state for non-health fields via
/// [ProfileEditNotifier]; health fields (HIV / last tested / PrEP) remain
/// local because the provider does not handle /profile/health. Wires the
/// 11 T4.7 selector sheets, 3 T4.8 details sub-screens, T4.5 i18n keys and
/// VibraTheme v3 tokens.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  // ── Local state for fields NOT yet routed through ProfileEditProvider ────
  bool _isLoading = true;
  String? _error;
  bool _isSavingHealth = false;

  // ── Gallery state ─────────────────────────────────────────────────────────
  List<GalleryPhoto> _galleryPhotos = [];
  bool _isLoadingGallery = false;
  bool _isUploadingGallery = false;

  // Text controllers for the remaining inline text fields (displayName, bio,
  // ethnicity, pronouns). They are pushed into the draft on every change so
  // the provider stays the single source of truth for save().
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();

  // Health fields — T4.9 did not extend the provider, so they stay local.
  String? _hivStatus;
  DateTime? _lastTestedOn;
  bool? _prep;

  // Per-section collapsed state for ExpansionTile (T6.1).
  // True = collapsed. Defaults: essentials expanded, optional collapsed.
  final Map<String, bool> _collapsedSections = {
    'basicInfo': false,        // always expanded (most-used)
    'appearance': false,       // always expanded (most-used)
    'tribes': true,            // collapsed by default
    'lookingFor': true,        // collapsed by default
    'likes': true,             // collapsed by default (Vaccines + Trips live here)
    'practices': true,         // NEW section, collapsed by default
    'health': false,           // always expanded (PrEP switch tested)
    'privacy': true,           // collapsed by default
  };

  @override
  void initState() {
    super.initState();
    _loadProfile();
    unawaited(_loadGallery());
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get<Map<String, dynamic>>('/profile');
      final userJson = response.data!['user'] as Map<String, dynamic>;
      final profile = UserProfile.fromJson(userJson);

      // Hydrate the Riverpod-backed edit provider.
      ref.read(profileEditProvider.notifier).loadFrom(profile);

      if (!mounted) return;
      setState(() {
        _displayNameController.text = profile.displayName ?? '';
        _bioController.text = profile.bio ?? '';
        _isLoading = false;
        // Load health separately so a /profile/health 404 does not block
        // the main form.
        unawaited(_loadHealth());
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error =
            'Failed to load profile: ${e.response?.statusCode ?? e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load profile: $e';
      });
    }
  }

  Future<void> _loadHealth() async {
    try {
      final service = ref.read(healthServiceProvider);
      final info = await service.fetchHealth();
      if (!mounted) return;
      setState(() {
        _hivStatus = info.hivStatus;
        _prep = info.prep;
        if (info.lastTestedOn != null) {
          try {
            _lastTestedOn = DateTime.parse(info.lastTestedOn!);
          } catch (_) {
            _lastTestedOn = null;
          }
        }
      });
    } catch (_) {
      // Best-effort — leave health fields null if endpoint fails.
    }
  }

  // ── Gallery methods ───────────────────────────────────────────────────────

  Future<void> _loadGallery() async {
    setState(() => _isLoadingGallery = true);
    try {
      final svc = MediaService(ref.read(dioProvider));
      final photos = await svc.listPhotos();
      if (!mounted) return;
      setState(() {
        _galleryPhotos = photos;
        _isLoadingGallery = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingGallery = false);
    }
  }

  Future<void> _addGalleryPhoto() async {
    if (_galleryPhotos.length >= 6) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n?.galleryMaxReached ?? 'Límite de 6 fotos alcanzado'),
          backgroundColor: VibraTheme.kBadgeRed,
        ),
      );
      return;
    }

    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;
    if (!mounted) return;               // guard: widget may be disposed while picker was open

    setState(() => _isUploadingGallery = true);

    try {
      final bytes = await picked.readAsBytes();

      // On-device NSFW check before upload.
      final nsfwResult = await ref.read(nsfwServiceProvider).check(bytes);
      if (!mounted) return;
      if (nsfwResult.isNsfw) {
        setState(() => _isUploadingGallery = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This image appears to violate our content guidelines.',
            ),
            backgroundColor: VibraTheme.kBadgeRed,
          ),
        );
        return;
      }

      final mediaService = MediaService(ref.read(dioProvider));
      final uploadUrl = await mediaService.getUploadUrl(kind: 'profile');
      if (!mounted) return;
      await mediaService.uploadToR2(uploadUrl.putUrl, bytes);
      if (!mounted) return;
      await mediaService.createPhoto(r2Key: uploadUrl.key);
      if (!mounted) return;
      await _loadGallery();
      if (!mounted) return;
      ref.invalidate(ownProfileProvider);
      setState(() => _isUploadingGallery = false);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingGallery = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Photo upload failed: ${e.response?.statusCode ?? e.message}',
          ),
          backgroundColor: VibraTheme.kBadgeRed,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingGallery = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Photo upload failed: $e'),
          backgroundColor: VibraTheme.kBadgeRed,
        ),
      );
    }
  }

  Future<void> _setPhotoPrimary(String id) async {
    try {
      await MediaService(ref.read(dioProvider)).setPrimaryPhoto(id);
      if (!mounted) return;
      await _loadGallery();
      if (!mounted) return;
      ref.invalidate(ownProfileProvider);
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.response?.statusCode ?? e.message}'),
          backgroundColor: VibraTheme.kBadgeRed,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: VibraTheme.kBadgeRed,
        ),
      );
    }
  }

  Future<void> _deletePhoto(String id) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n?.galleryDelete ?? 'Eliminar foto'),
        content: Text(l10n?.galleryDeleteConfirm ?? '¿Eliminar esta foto?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n?.cancelar ?? 'Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n?.galleryDelete ?? 'Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await MediaService(ref.read(dioProvider)).deletePhoto(id);
      if (!mounted) return;
      await _loadGallery();
      if (!mounted) return;
      ref.invalidate(ownProfileProvider);
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.response?.statusCode ?? e.message}'),
          backgroundColor: VibraTheme.kBadgeRed,
        ),
      );
    }
  }

  /// Mirror a text controller value into the draft without disturbing any
  /// other field.
  void _pushTextToDraft() {
    final notifier = ref.read(profileEditProvider.notifier);
    notifier.updateDraft(
      (p) => UserProfile(
        id: p.id,
        email: p.email,
        emailVerified: p.emailVerified,
        status: p.status,
        role: p.role,
        createdAt: p.createdAt,
        profilePhotoId: p.profilePhotoId,
        profilePhotoKey: p.profilePhotoKey,
        profilePhotoUrl: p.profilePhotoUrl,
        isVerified: p.isVerified,
        displayName: _displayNameController.text.isEmpty
            ? null
            : _displayNameController.text,
        bio: _bioController.text.isEmpty ? null : _bioController.text,
        birthdate: p.birthdate,
        heightCm: p.heightCm,
        weightKg: p.weightKg,
        bodyType: p.bodyType,
        relationshipStatus: p.relationshipStatus,
        position: p.position,
        ethnicity: p.ethnicity,
        pronouns: p.pronouns,
        tribes: p.tribes,
        lookingFor: p.lookingFor,
        meetAt: p.meetAt,
        tags: p.tags,
        details: p.details,
        showAge: p.showAge,
        showRole: p.showRole,
        showTribes: p.showTribes,
        showPosition: p.showPosition,
        showEthnicity: p.showEthnicity,
        showRelationshipStatus: p.showRelationshipStatus,
        showSocialLinks: p.showSocialLinks,
      ),
    );
  }

  Future<void> _saveAll() async {
    // Push latest text values into the draft before persisting.
    _pushTextToDraft();

    await ref.read(profileEditProvider.notifier).save();
    final stateAfter = ref.read(profileEditProvider);
    if (stateAfter.status == ProfileEditStatus.error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              stateAfter.errorMessage ?? 'Failed to save.'),
          backgroundColor: VibraTheme.kBadgeRed,
        ),
      );
      return;
    }

    // Invalidate the cached own-profile provider so the header, drawer,
    // and other screens re-fetch the updated profile (name, bio, photo, etc).
    ref.invalidate(ownProfileProvider);

    // Show confirmation immediately on profile save success.
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n?.editProfileSaved ?? 'Profile updated'),
        backgroundColor: VibraTheme.kSuccess,
      ),
    );

    // Health PUT — best-effort, does not block confirmation or pop.
    unawaited(_saveHealth(silent: true));

    // Pop only if a GoRouter is in scope (skip in widget tests).
    try {
      if (GoRouter.maybeOf(context) != null) {
        context.pop();
      }
    } catch (_) {
      // GoRouter not present; just stay on screen.
    }
  }

  Future<bool> _saveHealth({bool silent = false}) async {
    setState(() => _isSavingHealth = true);
    try {
      final service = ref.read(healthServiceProvider);
      final lastTestedStr = _lastTestedOn == null
          ? null
          : '${_lastTestedOn!.year.toString().padLeft(4, '0')}-${_lastTestedOn!.month.toString().padLeft(2, '0')}-${_lastTestedOn!.day.toString().padLeft(2, '0')}';
      await service.updateHealth(HealthInfo(
        hivStatus: _hivStatus,
        lastTestedOn: lastTestedStr,
        prep: _prep,
      ));
      if (!mounted) return true;
      setState(() => _isSavingHealth = false);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Health info saved!'),
            backgroundColor: VibraTheme.kSuccess,
          ),
        );
      }
      return true;
    } on DioException catch (e) {
      if (!mounted) return false;
      setState(() => _isSavingHealth = false);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to save health: ${e.response?.statusCode ?? e.message}',
            ),
            backgroundColor: VibraTheme.kBadgeRed,
          ),
        );
      }
      return false;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _isSavingHealth = false);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save health: $e'),
            backgroundColor: VibraTheme.kBadgeRed,
          ),
        );
      }
      return false;
    }
  }

  Future<void> _pickLastTestedDate() async {
    final now = DateTime.now();
    final initial = _lastTestedOn ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1980),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() => _lastTestedOn = picked);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _updateDraftField(UserProfile Function(UserProfile) mutator) {
    ref.read(profileEditProvider.notifier).updateDraft(mutator);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n?.editProfileTitle ?? 'Edit Profile')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildForm(),
      bottomNavigationBar: _buildSaveBar(),
    );
  }

  Widget _buildError() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline,
              size: 48, color: VibraTheme.kBadgeRed),
          const SizedBox(height: 16),
          Text(
            _error!,
            style: const TextStyle(color: VibraTheme.kBadgeRed),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loadProfile,
            child: Text(l10n?.reintentar ?? 'Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveBar() {
    final state = ref.watch(profileEditProvider);
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(VibraTheme.kPadPage),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: (state.isSaving || _isSavingHealth) ? null : _saveAll,
            style: ElevatedButton.styleFrom(
              backgroundColor: VibraTheme.kBrandPrimary,
              foregroundColor: Colors.black,
              disabledBackgroundColor: VibraTheme.kBrandPrimary,
              disabledForegroundColor: Colors.black,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: (state.isSaving || _isSavingHealth)
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : Text(
                    l10n?.editProfileSave ?? 'Save',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final state = ref.watch(profileEditProvider);
    final draft = state.draft;
    final l10n = AppLocalizations.of(context);

    if (draft == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(VibraTheme.kPadPage),
      children: [
        _buildPhotoSection(),
        const SizedBox(height: 24),

        // ── Basics ────────────────────────────────────────────────────────
        _CollapsibleSection(
          title: (l10n?.editProfileSectionBasics ?? 'Basic info').toUpperCase(),
          collapsed: _collapsedSections['basicInfo']!,
          onExpansionChanged: (_) {},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel(l10n?.editProfileFieldDisplayName ?? 'Display Name'),
              const SizedBox(height: 4),
              TextField(
                controller: _displayNameController,
                onChanged: (_) => _pushTextToDraft(),
                style: const TextStyle(color: VibraTheme.kTextPrimary),
                decoration: _inputDecoration(l10n?.editProfilePlaceholderDisplayName ?? 'Your display name'),
              ),
              const SizedBox(height: 12),
              _buildLabel(l10n?.editProfileFieldBio ?? 'Bio'),
              const SizedBox(height: 4),
              TextField(
                controller: _bioController,
                maxLines: 3,
                onChanged: (_) => _pushTextToDraft(),
                style: const TextStyle(color: VibraTheme.kTextPrimary),
                decoration: _inputDecoration(l10n?.editProfilePlaceholderBio ?? 'Tell people about yourself'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Appearance ────────────────────────────────────────────────────
        _CollapsibleSection(
          title:
              (l10n?.editProfileSectionAppearance ?? 'Appearance').toUpperCase(),
          collapsed: _collapsedSections['appearance']!,
          onExpansionChanged: (_) {},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSelectorListTile<String>(
                label: l10n?.editProfileFieldHeight ?? 'Height',
                current: draft.heightCm?.toString(),
                placeholder: l10n?.editProfilePlaceholderHeight ?? 'Select height',
                onTap: () async {
                  final picked =
                      await showHeightSheet(context, currentCm: draft.heightCm);
                  if (picked != null) {
                    _updateDraftField((p) => _copyWithHeight(p, picked));
                  }
                },
              ),
              _buildSelectorListTile<String>(
                label: l10n?.editProfileFieldWeight ?? 'Weight',
                current: draft.weightKg?.toString(),
                placeholder: l10n?.editProfilePlaceholderWeight ?? 'Select weight',
                onTap: () async {
                  final picked =
                      await showWeightSheet(context, currentKg: draft.weightKg);
                  if (picked != null) {
                    _updateDraftField((p) => _copyWithWeight(p, picked));
                  }
                },
              ),
              _buildSelectorListTile<String>(
                label: l10n?.editProfileFieldBodyType ?? 'Body Type',
                current: draft.bodyType,
                placeholder: l10n?.editProfilePlaceholderBodyType ?? 'Select body type',
                onTap: () async {
                  final picked = await showBodyTypeSheet(
                      context, current: draft.bodyType);
                  if (picked != null) {
                    _updateDraftField((p) => _copyWith(p, bodyType: picked));
                  }
                },
              ),
              _buildSelectorListTile<String>(
                label: l10n?.editProfileFieldEthnicity ?? 'Ethnicity',
                current: draft.ethnicity,
                placeholder: l10n?.editProfilePlaceholderEthnicity ?? 'Select ethnicity',
                onTap: () async {
                  final picked =
                      await showEthnicitySheet(context, current: draft.ethnicity);
                  if (picked != null) {
                    _updateDraftField((p) => _copyWith(p, ethnicity: picked));
                  }
                },
              ),
              _buildSelectorListTile<String>(
                label: l10n?.editProfileFieldPronouns ?? 'Pronouns',
                current: draft.pronouns,
                placeholder: l10n?.editProfilePlaceholderPronouns ?? 'Select pronouns',
                onTap: () async {
                  final picked =
                      await showPronounsSheet(context, current: draft.pronouns);
                  if (picked != null) {
                    _updateDraftField((p) => _copyWith(p, pronouns: picked));
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Tribes ────────────────────────────────────────────────────────
        _CollapsibleSection(
          title: (l10n?.editProfileSectionTribes ?? 'Tribes').toUpperCase(),
          collapsed: _collapsedSections['tribes']!,
          onExpansionChanged: (v) =>
              setState(() => _collapsedSections['tribes'] = !v),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tribes selection — gated by premium tier max_tribes limit
              Builder(builder: (context) {
                final premiumAsync = ref.read(premiumStatusProvider);
                final data = premiumAsync is AsyncData ? premiumAsync.value : null;
                final maxTribes = data?.features.maxTribes ?? 1;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ChipMultiSelect(
                      options: kTribeOptions,
                      selected: draft.tribes.toSet(),
                      onChanged: (next) {
                        if (next.length > maxTribes) {
                          // Show upgrade prompt
                          showPremiumComparisonSheet(context);
                          return;
                        }
                        _updateDraftField(
                            (p) => _copyWith(p, tribes: next.toList()));
                      },
                    ),
                    if (draft.tribes.length >= maxTribes)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: GestureDetector(
                          onTap: () => showPremiumComparisonSheet(context),
                          child: Text(
                            maxTribes == 1
                                ? 'Upgrade to Xtra for up to 3 tribes'
                                : 'Upgrade to Unlimited for unlimited tribes',
                            style: const TextStyle(
                              color: VibraTheme.kBrandPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Looking for ───────────────────────────────────────────────────
        _CollapsibleSection(
          title:
              (l10n?.editProfileSectionLookingFor ?? "What I'm looking for")
                  .toUpperCase(),
          collapsed: _collapsedSections['lookingFor']!,
          onExpansionChanged: (v) =>
              setState(() => _collapsedSections['lookingFor'] = !v),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSelectorListTile<String>(
                label: l10n?.editProfileFieldLookingFor ?? 'Looking For',
                current: draft.lookingFor.isEmpty
                    ? null
                    : draft.lookingFor.join(', '),
                placeholder: l10n?.editProfilePlaceholderLookingFor ?? 'Select what you are looking for',
                onTap: () async {
                  final picked = await showLookingForSheet(
                    context,
                    current: draft.lookingFor.toSet(),
                  );
                  if (picked != null) {
                    _updateDraftField(
                        (p) => _copyWith(p, lookingFor: picked.toList()));
                  }
                },
              ),
              _buildSelectorListTile<String>(
                label: l10n?.editProfileFieldMeetAt ?? 'Meet At',
                current:
                    draft.meetAt.isEmpty ? null : draft.meetAt.join(', '),
                placeholder: l10n?.editProfilePlaceholderMeetAt ?? 'Select where to meet',
                onTap: () async {
                  final picked = await showMeetAtSheet(
                    context,
                    current: draft.meetAt.toSet(),
                  );
                  if (picked != null) {
                    _updateDraftField(
                        (p) => _copyWith(p, meetAt: picked.toList()));
                  }
                },
              ),
              _buildSelectorListTile<String>(
                label: l10n?.editProfileFieldPosition ?? 'Position',
                current: draft.position,
                placeholder: l10n?.editProfilePlaceholderPosition ?? 'Select position',
                onTap: () async {
                  final picked =
                      await showPositionSheet(context, current: draft.position);
                  if (picked != null) {
                    _updateDraftField((p) => _copyWith(p, position: picked));
                  }
                },
              ),
              _buildSelectorListTile<String>(
                label: l10n?.editProfileFieldRelationshipStatus ?? 'Relationship Status',
                current: draft.relationshipStatus,
                placeholder: l10n?.editProfilePlaceholderRelationshipStatus ?? 'Select relationship status',
                onTap: () async {
                  final picked = await showRelationshipSheet(
                    context,
                    current: draft.relationshipStatus,
                  );
                  if (picked != null) {
                    _updateDraftField(
                        (p) => _copyWith(p, relationshipStatus: picked));
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Likes ─────────────────────────────────────────────────────────
        _CollapsibleSection(
          title: (l10n?.editProfileSectionLikes ?? 'What I like').toUpperCase(),
          collapsed: _collapsedSections['likes']!,
          onExpansionChanged: (v) =>
              setState(() => _collapsedSections['likes'] = !v),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSelectorListTile<String>(
                label: l10n?.detailsVaccines ?? 'Vaccines',
                current: _detailsCount(draft, 'vaccines') > 0
                    ? (l10n?.editProfileCountSelected(_detailsCount(draft, 'vaccines')) ?? '${_detailsCount(draft, 'vaccines')} selected')
                    : null,
                placeholder: l10n?.editProfilePlaceholderVaccines ?? 'Select vaccines',
                onTap: () async {
                  final current = _readVaccines(draft);
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => VaccinesScreen(
                      current: current,
                      onChanged: (next) {
                        _updateDraftField((p) => _writeVaccines(p, next));
                      },
                    ),
                  ));
                },
              ),
              _buildSelectorListTile<String>(
                label: l10n?.detailsTripCount ?? 'Trips',
                current: _detailsCount(draft, 'trips') > 0
                    ? (l10n?.editProfileCountTrips(_detailsCount(draft, 'trips')) ?? '${_detailsCount(draft, 'trips')} trips')
                    : null,
                placeholder: l10n?.editProfilePlaceholderTrips ?? 'Add recent trips',
                onTap: () async {
                  final current = _readTrips(draft);
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => AddTripScreen(
                      current: current,
                      onChanged: (next) {
                        _updateDraftField((p) => _writeTrips(p, next));
                      },
                    ),
                  ));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Practices ──────────────────────────────────────────────────────
        _CollapsibleSection(
          title: (l10n?.editProfileSectionPractices ?? 'Practices')
              .toUpperCase(),
          collapsed: _collapsedSections['practices']!,
          onExpansionChanged: (v) =>
              setState(() => _collapsedSections['practices'] = !v),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSelectorListTile<String>(
                label: l10n?.detailsPractices ?? 'Practices',
                current: _detailsCount(draft, 'practices') > 0
                    ? (l10n?.editProfileCountSelected(_detailsCount(draft, 'practices')) ?? '${_detailsCount(draft, 'practices')} selected')
                    : null,
                placeholder: l10n?.editProfilePlaceholderPractices ?? 'Select practices',
                onTap: () async {
                  final current = _readPractices(draft);
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => PracticesScreen(
                      current: current,
                      onChanged: (next) {
                        _updateDraftField((p) => _writePractices(p, next));
                      },
                    ),
                  ));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Health ────────────────────────────────────────────────────────
        _CollapsibleSection(
          title: (l10n?.editProfileSectionHealth ?? 'Health').toUpperCase(),
          collapsed: _collapsedSections['health']!,
          onExpansionChanged: (_) {},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HIV Status dropdown (kept inline; the existing test relies
              // on finding the literal "HIV Status" label and the dropdown
              // widget).
              _buildLabel(l10n?.editProfileFieldHivStatus ?? 'HIV Status'),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: _hivStatus,
                dropdownColor: VibraTheme.kSurface,
                style: const TextStyle(color: VibraTheme.kTextPrimary),
                decoration: _inputDecoration(l10n?.editProfilePlaceholderSelectStatus ?? 'Select status'),
                items: kHivStatusOptions
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (val) => setState(() => _hivStatus = val),
              ),
              const SizedBox(height: 16),

              // Last tested on date picker (kept inline — test searches
              // 'Not set').
              _buildLabel(l10n?.editProfileFieldLastTestedOn ?? 'Last Tested On'),
              const SizedBox(height: 4),
              InkWell(
                onTap: _pickLastTestedDate,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 16),
                  decoration: BoxDecoration(
                    color: VibraTheme.kSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: VibraTheme.kDivider),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _lastTestedOn == null
                              ? (l10n?.editProfileNotSet ?? 'Not set')
                              : '${_lastTestedOn!.year.toString().padLeft(4, '0')}-${_lastTestedOn!.month.toString().padLeft(2, '0')}-${_lastTestedOn!.day.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: _lastTestedOn == null
                                ? VibraTheme.kTextSecondary
                                : VibraTheme.kTextPrimary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const Icon(Icons.calendar_today,
                          color: VibraTheme.kTextSecondary, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // PrEP switch (kept inline; test uses find.byType(Switch)).
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: VibraTheme.kSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: VibraTheme.kDivider),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n?.editProfileFieldOnPrep ?? 'On PrEP',
                        style: const TextStyle(
                            color: VibraTheme.kTextPrimary, fontSize: 14),
                      ),
                    ),
                    Switch(
                      value: _prep ?? false,
                      onChanged: (val) => setState(() => _prep = val),
                    ),
                  ],
                ),
              ),
              if (_isSavingHealth)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Privacy ───────────────────────────────────────────────────────
        // Privacy switches live in the dedicated Settings screen (T6). They
        // are read-only here; we surface the current values as a list.
        _CollapsibleSection(
          title:
              (l10n?.editProfileSectionPrivacy ?? 'Privacy').toUpperCase(),
          collapsed: _collapsedSections['privacy']!,
          onExpansionChanged: (v) =>
              setState(() => _collapsedSections['privacy'] = !v),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPrivacyRow(l10n?.editProfileShowAge ?? 'Show age', draft.showAge),
              _buildPrivacyRow(l10n?.editProfileShowRole ?? 'Show role', draft.showRole),
              _buildPrivacyRow(l10n?.editProfileShowTribes ?? 'Show tribes', draft.showTribes),
              _buildPrivacyRow(l10n?.editProfileShowPosition ?? 'Show position', draft.showPosition),
              _buildPrivacyRow(l10n?.editProfileShowEthnicity ?? 'Show ethnicity', draft.showEthnicity),
              _buildPrivacyRow(l10n?.editProfileShowRelationshipStatus ?? 'Show relationship status',
                  draft.showRelationshipStatus),
            ],
          ),
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildPhotoSection() {
    final l10n = AppLocalizations.of(context);

    // Show loading spinner when gallery is loading and empty.
    if (_isLoadingGallery && _galleryPhotos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = VibraTheme.kPadPage * 2;
    final spacing = 8.0;
    final tileSize = (screenWidth - horizontalPadding - spacing * 2) / 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label
        Text(
          'FOTOS',
          style: const TextStyle(
            color: VibraTheme.kTextSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),

        // Photo grid using Wrap
        Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            // Existing photo tiles
            ..._galleryPhotos.map((photo) {
              return _buildGalleryTile(photo, tileSize, l10n);
            }),

            // Add tile — shown when below 6 photos, or max-reached hint
            if (_galleryPhotos.length < 6)
              _buildAddTile(tileSize, l10n)
            else
              Container(
                width: tileSize,
                height: tileSize,
                decoration: BoxDecoration(
                  color: VibraTheme.kSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: VibraTheme.kDivider),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      l10n?.galleryMaxReached ?? 'Límite de 6 fotos alcanzado',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: VibraTheme.kTextSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildGalleryTile(
    GalleryPhoto photo,
    double size,
    AppLocalizations? l10n,
  ) {
    return GestureDetector(
      onLongPress: () => _showPhotoMenu(photo, l10n),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: size,
              height: size,
              child: Image.network(
                photo.url,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, stack) => Container(
                  color: VibraTheme.kSurface,
                  child: const Icon(Icons.broken_image,
                      color: VibraTheme.kTextSecondary),
                ),
              ),
            ),
          ),
          // Primary badge
          if (photo.isPrimary)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  color: VibraTheme.kSuccess,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  l10n?.galleryPrimaryBadge ?? 'Principal',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          // Actions button (⋮)
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: () => _showPhotoMenu(photo, l10n),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(2),
                child: const Icon(
                  Icons.more_vert,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddTile(double size, AppLocalizations? l10n) {
    return GestureDetector(
      onTap: _isUploadingGallery ? null : _addGalleryPhoto,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: VibraTheme.kSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: VibraTheme.kDivider,
            style: BorderStyle.solid,
            width: 1.5,
          ),
        ),
        child: _isUploadingGallery
            ? const Center(
                child: CircularProgressIndicator(
                  color: VibraTheme.kBrandPrimary,
                  strokeWidth: 2,
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add,
                      color: VibraTheme.kTextSecondary, size: 28),
                  const SizedBox(height: 4),
                  Text(
                    l10n?.galleryAddPhoto ?? 'Añadir foto',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: VibraTheme.kTextSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _showPhotoMenu(GalleryPhoto photo, AppLocalizations? l10n) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: VibraTheme.kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!photo.isPrimary)
                ListTile(
                  leading: const Icon(Icons.star_border,
                      color: VibraTheme.kBrandPrimary),
                  title: Text(
                    l10n?.gallerySetPrimary ?? 'Hacer principal',
                    style: const TextStyle(color: VibraTheme.kTextPrimary),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _setPhotoPrimary(photo.id);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: VibraTheme.kBadgeRed),
                title: Text(
                  l10n?.galleryDelete ?? 'Eliminar',
                  style: const TextStyle(color: VibraTheme.kBadgeRed),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deletePhoto(photo.id);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: VibraTheme.kTextSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
          color: VibraTheme.kTextSecondary, fontSize: 14),
      filled: true,
      fillColor: VibraTheme.kSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: VibraTheme.kDivider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: VibraTheme.kDivider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: VibraTheme.kBrandPrimary, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Widget _buildPrivacyRow(String label, bool value) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: VibraTheme.kTextPrimary)),
          ),
          Text(
            value ? (l10n?.editProfileOn ?? 'On') : (l10n?.editProfileOff ?? 'Off'),
            style: TextStyle(
              color: value ? VibraTheme.kBrandPrimary : VibraTheme.kTextSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorListTile<T>({
    required String label,
    required String? current,
    required String placeholder,
    required VoidCallback onTap,
  }) {
    final trailing = current == null
        ? const Icon(Icons.chevron_right,
            color: VibraTheme.kTextSecondary)
        : const Icon(Icons.check, color: VibraTheme.kBrandPrimary);
    return ListTile(
      title: Text(label,
          style: const TextStyle(color: VibraTheme.kTextPrimary)),
      subtitle: Text(
        current ?? placeholder,
        style: TextStyle(
          color: current == null
              ? VibraTheme.kTextSecondary
              : VibraTheme.kTextPrimary,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
    );
  }

  // ── copyWith helpers ─────────────────────────────────────────────────────

  UserProfile _copyWith(
    UserProfile p, {
    String? displayName,
    String? bio,
    String? ethnicity,
    String? pronouns,
    String? bodyType,
    String? position,
    String? relationshipStatus,
    int? heightCm,
    int? weightKg,
    List<String>? tribes,
    List<String>? lookingFor,
    List<String>? meetAt,
    List<String>? tags,
    Map<String, dynamic>? details,
    bool? showAge,
    bool? showRole,
    bool? showTribes,
    bool? showPosition,
    bool? showEthnicity,
    bool? showRelationshipStatus,
    bool? showSocialLinks,
  }) {
    return UserProfile(
      id: p.id,
      email: p.email,
      emailVerified: p.emailVerified,
      status: p.status,
      role: p.role,
      createdAt: p.createdAt,
      profilePhotoId: p.profilePhotoId,
      profilePhotoKey: p.profilePhotoKey,
      profilePhotoUrl: p.profilePhotoUrl,
      isVerified: p.isVerified,
      displayName: displayName ?? p.displayName,
      bio: bio ?? p.bio,
      birthdate: p.birthdate,
      heightCm: heightCm ?? p.heightCm,
      weightKg: weightKg ?? p.weightKg,
      bodyType: bodyType ?? p.bodyType,
      relationshipStatus: relationshipStatus ?? p.relationshipStatus,
      position: position ?? p.position,
      ethnicity: ethnicity ?? p.ethnicity,
      pronouns: pronouns ?? p.pronouns,
      tribes: tribes ?? p.tribes,
      lookingFor: lookingFor ?? p.lookingFor,
      meetAt: meetAt ?? p.meetAt,
      tags: tags ?? p.tags,
      details: details ?? p.details,
      showAge: showAge ?? p.showAge,
      showRole: showRole ?? p.showRole,
      showTribes: showTribes ?? p.showTribes,
      showPosition: showPosition ?? p.showPosition,
      showEthnicity: showEthnicity ?? p.showEthnicity,
      showRelationshipStatus:
          showRelationshipStatus ?? p.showRelationshipStatus,
      showSocialLinks: showSocialLinks ?? p.showSocialLinks,
    );
  }

  UserProfile _copyWithHeight(UserProfile p, int cm) =>
      _copyWith(p, heightCm: cm);
  UserProfile _copyWithWeight(UserProfile p, int kg) =>
      _copyWith(p, weightKg: kg);

  // ── details[] helpers (T4.8 sub-screens) ─────────────────────────────────

  int _detailsCount(UserProfile p, String key) {
    final raw = p.details[key];
    if (raw is List) return raw.length;
    return 0;
  }

  Set<String> _readVaccines(UserProfile p) {
    final raw = p.details['vaccines'];
    if (raw is List) return raw.map((e) => e.toString()).toSet();
    return <String>{};
  }

  UserProfile _writeVaccines(UserProfile p, Set<String> next) {
    final m = Map<String, dynamic>.from(p.details);
    m['vaccines'] = next.toList();
    return _copyWith(p, details: m);
  }

  Set<String> _readPractices(UserProfile p) {
    final raw = p.details['practices'];
    if (raw is List) return raw.map((e) => e.toString()).toSet();
    return <String>{};
  }

  UserProfile _writePractices(UserProfile p, Set<String> next) {
    final m = Map<String, dynamic>.from(p.details);
    m['practices'] = next.toList();
    return _copyWith(p, details: m);
  }

  List<TripEntry> _readTrips(UserProfile p) {
    final raw = p.details['trips'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((m) => TripEntry(
                date: (m['date'] ?? '').toString(),
                location: (m['location'] ?? '').toString(),
                notes: m['notes']?.toString(),
              ))
          .toList();
    }
    return <TripEntry>[];
  }

  UserProfile _writeTrips(UserProfile p, List<TripEntry> next) {
    final m = Map<String, dynamic>.from(p.details);
    m['trips'] = next.map((e) => e.toJson()).toList();
    return _copyWith(p, details: m);
  }
}

/// Wraps a section in an ExpansionTile. Defaults to collapsed state from
/// the parent's [_EditProfileScreenState._collapsedSections] map; user taps
/// the header to toggle.
///
/// The trailing icon is the standard ExpansionTile chevron — keeps the
/// look consistent with Material defaults rather than introducing a
/// custom thumb.
class _CollapsibleSection extends StatelessWidget {
  final String title;
  final bool collapsed;
  final ValueChanged<bool> onExpansionChanged;
  final Widget child;

  const _CollapsibleSection({
    required this.title,
    required this.collapsed,
    required this.onExpansionChanged,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      // Strip the default ExpansionTile divider/border so the section
      // header looks like the existing _buildSectionHeader (kTextSecondary,
      // 12 sp, CAPS, letterSpacing 1.0).
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(
          title,
          style: const TextStyle(
            color: VibraTheme.kTextSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        initiallyExpanded: !collapsed,
        onExpansionChanged: onExpansionChanged,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 12),
        children: [child],
      ),
    );
  }
}