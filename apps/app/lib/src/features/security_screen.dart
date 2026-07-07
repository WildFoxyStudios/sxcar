import 'package:flutter/material.dart';
import '../../l10n/gen/app_localizations.dart';
import '../theme/app_theme.dart';

/// Security & Privacy tips screen.
class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        title: Text(l10n.centroSeguridad),
        backgroundColor: VibraTheme.kBg,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tipCard(
            icon: Icons.block,
            title: l10n.securityBlockReportTitle,
            body: l10n.securityBlockReportBody,
          ),
          _tipCard(
            icon: Icons.visibility_off,
            title: l10n.securityIncognitoTitle,
            body: l10n.securityIncognitoBody,
          ),
          _tipCard(
            icon: Icons.lock,
            title: l10n.securityPinLockTitle,
            body: l10n.securityPinLockBody,
          ),
          _tipCard(
            icon: Icons.dark_mode,
            title: l10n.securityDiscreetIconTitle,
            body: l10n.securityDiscreetIconBody,
          ),
          _tipCard(
            icon: Icons.camera_alt,
            title: l10n.securityScreenshotAlertsTitle,
            body: l10n.securityScreenshotAlertsBody,
          ),
          _tipCard(
            icon: Icons.shield,
            title: l10n.securityNsfwBlurTitle,
            body: l10n.securityNsfwBlurBody,
          ),
        ],
      ),
    );
  }

  Widget _tipCard({required IconData icon, required String title, required String body}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VibraTheme.kSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: VibraTheme.kYellow, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 6),
                Text(body, style: const TextStyle(color: VibraTheme.kTextSecondary, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
