import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/media/media_service.dart';
import 'package:app/src/nsfw/nsfw_service.dart';
import '../models.dart';
import '../onboarding_card.dart';
import '../onboarding_provider.dart';

/// Card: profile_photo. Reuses the existing image picker + R2 upload
/// flow from edit_profile_screen.dart. The wizard re-uses the same
/// sanitization + presigned-PUT flow — DO NOT duplicate.
class ProfilePhotoCard extends ConsumerStatefulWidget {
  const ProfilePhotoCard({
    super.key,
    required this.card,
    required this.provider,
    required this.onComplete,
  });

  final OnboardingCard card;
  final OnboardingProvider provider;
  final ValueChanged<bool> onComplete;

  @override
  ConsumerState<ProfilePhotoCard> createState() => _ProfilePhotoCardState();
}

class _ProfilePhotoCardState extends ConsumerState<ProfilePhotoCard> {
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Reuse the existing photo upload flow from edit_profile_screen.dart:
      // ImagePicker -> NSFW check -> presigned PUT -> return R2 key.
      final r2Key = await _uploadProfilePhoto();
      await widget.provider
          .completeCard('profile_photo', {'r2_key': r2Key, 'is_nsfw': false});
      widget.onComplete(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Pick a photo from the gallery, run on-device NSFW check,
  /// upload to R2 via presigned PUT, and return the R2 key.
  Future<String> _uploadProfilePhoto() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) {
      throw Exception('No photo selected');
    }

    final bytes = await picked.readAsBytes();

    // On-device NSFW check before upload (same as edit_profile_screen).
    final nsfwResult = await ref.read(nsfwServiceProvider).check(bytes);
    if (!mounted) throw Exception('Cancelled');
    if (nsfwResult.isNsfw) {
      throw Exception('This image appears to violate content guidelines.');
    }

    final dio = ref.read(dioProvider);
    final mediaService = MediaService(dio);
    final uploadUrl = await mediaService.getUploadUrl(kind: 'profile');
    await mediaService.uploadToR2(uploadUrl.putUrl, bytes);

    return uploadUrl.key;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return OnboardingCardScaffold(
      card: widget.card,
      primaryLabel: l10n.onboarding_next,
      primaryEnabled: !_busy,
      onPrimary: _pick,
      child: Center(
        child: _busy
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_photo_alternate_outlined, size: 64),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                ],
              ),
      ),
    );
  }
}
