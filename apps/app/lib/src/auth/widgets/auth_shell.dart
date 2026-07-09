import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// The "Vibra" wordmark — teal→magenta gradient over the Halo identity.
class VibraWordmark extends StatelessWidget {
  const VibraWordmark({super.key, this.fontSize = 40});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [VibraTheme.kBrandPrimary, VibraTheme.kBrandSecondary],
      ).createShader(bounds),
      child: Text(
        'Vibra',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: -1,
          color: Colors.white, // masked by the gradient
        ),
      ),
    );
  }
}

/// Shared branded full-screen shell for the auth flow (login / register /
/// recover). Centers the Vibra wordmark + an optional subtitle above a
/// scrollable form column, on the Halo background. No AppBar — this is the
/// app's first impression, so it's fully branded.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.children,
    this.subtitle,
    this.onBack,
  });

  /// Form widgets rendered below the wordmark, stretched to full width.
  final List<Widget> children;

  /// Optional one-line subtitle under the wordmark.
  final String? subtitle;

  /// When set, shows a back chevron in the top-left.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      body: SafeArea(
        child: Stack(
          children: [
            if (onBack != null)
              Positioned(
                top: 4,
                left: 4,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  color: VibraTheme.kTextSecondary,
                  onPressed: onBack,
                ),
              ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Center(child: VibraWordmark()),
                      if (subtitle != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          subtitle!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: VibraTheme.kTextSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                      const SizedBox(height: 36),
                      ...children,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Halo-styled input decoration: filled surface, teal focus ring, rounded.
InputDecoration authInput({
  required String label,
  String? hint,
  IconData? icon,
  Widget? suffix,
}) {
  const radius = BorderRadius.all(Radius.circular(14));
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: icon == null ? null : Icon(icon, size: 20),
    suffixIcon: suffix,
    filled: true,
    fillColor: VibraTheme.kSurface,
    labelStyle: const TextStyle(color: VibraTheme.kTextSecondary),
    floatingLabelStyle: const TextStyle(color: VibraTheme.kBrandPrimary),
    enabledBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: VibraTheme.kDivider),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: VibraTheme.kBrandPrimary, width: 2),
    ),
    errorBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: VibraTheme.kError),
    ),
    focusedErrorBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: VibraTheme.kError, width: 2),
    ),
  );
}

/// Full-width primary action button in the brand teal, with a loading state.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: VibraTheme.kBrandPrimary,
          foregroundColor: Colors.black,
          disabledBackgroundColor: VibraTheme.kBrandPrimary.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.black),
              )
            : Text(label),
      ),
    );
  }
}

/// Inline error banner used across the auth screens.
class AuthErrorText extends StatelessWidget {
  const AuthErrorText(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: VibraTheme.kError, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: VibraTheme.kError, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
