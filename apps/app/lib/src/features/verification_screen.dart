import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/gen/app_localizations.dart';
import '../auth/auth_provider.dart';
import '../media/media_service.dart';
import '../theme/app_theme.dart';
import '../verification/verification_service.dart';

/// Full-screen profile verification flow (blue-check, Grindr-style).
///
/// Shows one of three states depending on [verificationStatusProvider]:
///   1. **verified** — success panel with green check.
///   2. **pending**  — "under review" info panel.
///   3. **not submitted** — explanation + selfie CTA.
class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen({super.key});

  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends ConsumerState<VerificationScreen> {
  bool _uploading = false;

  Future<void> _takeSelfieAndSubmit() async {
    final l10n = AppLocalizations.of(context)!;

    // Pick image from camera (prefer camera; fall back gracefully if denied).
    XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );
    } catch (_) {
      // Camera not available — try gallery.
      try {
        file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.verifySubmitError)),
        );
        return;
      }
    }

    if (file == null) return; // User cancelled.

    if (!mounted) return;
    setState(() => _uploading = true);

    try {
      final Uint8List bytes = await file.readAsBytes();
      final dio = ref.read(dioProvider);
      final mediaService = MediaService(dio);

      // Get presigned upload URL (kind = 'verification').
      final uploadUrl = await mediaService.getUploadUrl(kind: 'verification');

      // Upload directly to R2 (no NSFW check required for verification selfies).
      await mediaService.uploadToR2(uploadUrl.putUrl, bytes);

      // Submit the R2 key to the backend verification endpoint.
      await ref.read(verificationServiceProvider).submit(uploadUrl.key);

      if (!mounted) return;
      // Refresh status so the screen transitions to the pending panel.
      ref.invalidate(verificationStatusProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.verifySubmitError)),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final statusAsync = ref.watch(verificationStatusProvider);

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        backgroundColor: VibraTheme.kBg,
        elevation: 0,
        title: Text(
          l10n.verifyProfileTitle,
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: statusAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: VibraTheme.kBrandPrimary),
        ),
        error: (err, _) => _ErrorPanel(
          onRetry: () => ref.invalidate(verificationStatusProvider),
        ),
        data: (status) {
          if (status.verified) return const _VerifiedPanel();
          if (status.pending) return const _PendingPanel();
          return _NotSubmittedPanel(
            uploading: _uploading,
            onTakeSelfie: _takeSelfieAndSubmit,
          );
        },
      ),
    );
  }
}

// ── Verified panel ────────────────────────────────────────────────────────────

class _VerifiedPanel extends StatelessWidget {
  const _VerifiedPanel();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified, size: 80, color: VibraTheme.kSuccess),
            const SizedBox(height: 24),
            Text(
              l10n.verifyVerified,
              style: const TextStyle(
                color: VibraTheme.kText,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pending panel ─────────────────────────────────────────────────────────────

class _PendingPanel extends StatelessWidget {
  const _PendingPanel();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_top, size: 80,
                color: VibraTheme.kBrandPrimary),
            const SizedBox(height: 24),
            Text(
              l10n.verifyPending,
              style: const TextStyle(
                color: VibraTheme.kTextSecondary,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Not-submitted panel ───────────────────────────────────────────────────────

class _NotSubmittedPanel extends StatelessWidget {
  final bool uploading;
  final VoidCallback onTakeSelfie;

  const _NotSubmittedPanel({
    required this.uploading,
    required this.onTakeSelfie,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.verified_user, size: 72,
              color: VibraTheme.kBrandPrimary),
          const SizedBox(height: 24),
          Text(
            l10n.verifyProfileTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.verifyProfileIntro,
            style: const TextStyle(
              color: VibraTheme.kTextSecondary,
              fontSize: 15,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: uploading ? null : onTakeSelfie,
              icon: uploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.camera_alt, color: Colors.black),
              label: Text(
                l10n.verifyTakeSelfie,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: VibraTheme.kBrandPrimary,
                disabledBackgroundColor:
                    VibraTheme.kBrandPrimary.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error panel ───────────────────────────────────────────────────────────────

class _ErrorPanel extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorPanel({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: VibraTheme.kError),
            const SizedBox(height: 16),
            const Text(
              'Error loading verification status',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
