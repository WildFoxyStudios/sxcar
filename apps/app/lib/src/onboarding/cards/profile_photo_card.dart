import 'package:flutter/material.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import '../models.dart';
import '../onboarding_card.dart';
import '../onboarding_provider.dart';

/// Card: profile_photo. Reuses the existing image picker + R2 upload
/// flow from edit_profile_screen.dart. The wizard re-uses the same
/// sanitization + presigned-PUT flow — DO NOT duplicate.
class ProfilePhotoCard extends StatefulWidget {
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
  State<ProfilePhotoCard> createState() => _ProfilePhotoCardState();
}

class _ProfilePhotoCardState extends State<ProfilePhotoCard> {
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Reuse the existing photo upload flow.
      // For a real implementation, delegate to the same ImagePicker + R2
      // presigned PUT code that edit_profile_screen.dart uses.
      final r2Key = await _uploadProfilePhoto();
      await widget.provider
          .completeCard('profile_photo', {'r2_key': r2Key, 'is_nsfw': false});
      widget.onComplete(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
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

/// Stand-in for the real photo upload. The implementer MUST replace
/// this with the actual R2 presigned PUT flow used by
/// edit_profile_screen.dart. Do not commit a stub.
Future<String> _uploadProfilePhoto() async {
  throw UnimplementedError('Wire to existing photo upload flow');
}
