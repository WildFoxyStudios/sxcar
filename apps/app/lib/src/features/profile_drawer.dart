import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/gen/app_localizations.dart';
import '../auth/auth_provider.dart';
import '../billing/billing_providers.dart';
import '../billing/models.dart';
import '../boost/boost_service.dart';
import '../premium/premium_gate.dart';
import '../premium/premium_service.dart';
import '../presence/presence_mode_provider.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'profile_screen.dart' show UserProfile;

// ── Own-profile provider (T2: used in drawer; T10 can promote to shared) ─────

/// Fetches the authenticated user's own profile. Returns null if the user is
/// not authenticated or the request fails. Cached by Riverpod for the session.
final ownProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (authState.status != AuthStatus.authenticated) return null;
  try {
    final dio = ref.watch(dioProvider);
    final response = await dio.get<Map<String, dynamic>>('/profile');
    final userJson = response.data!['user'] as Map<String, dynamic>;
    return UserProfile.fromJson(userJson);
  } on DioException {
    return null;
  } catch (_) {
    return null;
  }
});

// ── ProfileDrawer ─────────────────────────────────────────────────────────────

/// Left-side profile drawer — opened by the avatar in Navegar's header (T3)
/// or the temporary menu icon in CascadeScreen's AppBar (T2).
///
/// Layout (matches visual references 1000144700.jpg / 1000144701.jpg):
///   • Profile photo 180×180 rounded-corner
///   • Name pill + pencil → /edit-profile
///   • Online / Incógnito segmented (persists + disables heartbeat)
///   • COMPLEMENTOS: Boost row, Right Now row
///   • ELEGIR UN PLAN: yellow CTA card, dark "see plans" card
///   • Menu items: edit profile, albums, health, privacy, settings
class ProfileDrawer extends ConsumerWidget {
  const ProfileDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final profileAsync = ref.watch(ownProfileProvider);
    final isIncognito = ref.watch(presenceModeProvider);
    final mySubAsync = ref.watch(mySubscriptionProvider);
    final Subscription? activeSub =
        mySubAsync is AsyncData<Subscription?> ? mySubAsync.value : null;

    return Drawer(
      backgroundColor: VibraTheme.kBg,
      width: MediaQuery.of(context).size.width * 0.82,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ── Header: photo + name + segmented ──────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Profile photo
                  profileAsync.when(
                    loading: () => _PhotoPlaceholder(initials: '?'),
                    error: (_, _) => _PhotoPlaceholder(initials: '?'),
                    data: (profile) => _ProfilePhoto(profile: profile),
                  ),

                  const SizedBox(height: 16),

                  // Name pill + pencil
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push('/edit-profile');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: VibraTheme.kChip,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          profileAsync.when(
                            loading: () => const Text(
                              '...',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16),
                            ),
                            error: (_, _) => const Text(
                              '...',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16),
                            ),
                            data: (profile) {
                              final name = profile?.displayName ??
                                  profile?.email.split('@').first ??
                                  '...';
                              return Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.edit,
                              color: VibraTheme.kTextSecondary, size: 16),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Online / Incógnito segmented (Incógnito gated behind tier check)
                  SizedBox(
                    width: double.infinity,
                    child: VibraSegmented(
                      options: [l10n.online, l10n.incognito],
                      selectedIndex: isIncognito ? 1 : 0,
                      onChanged: (idx) {
                        if (idx == 1) {
                          // Check if user has incognito access
                          final premiumAsync =
                              ref.read(premiumStatusProvider);
                          final data = premiumAsync is AsyncData
                              ? premiumAsync.value
                              : null;
                          if (data == null || !data.features.incognitoMode) {
                            showPremiumComparisonSheet(context);
                            return;
                          }
                        }
                        ref
                            .read(presenceModeProvider.notifier)
                            .setIncognito(idx == 1);
                      },
                    ),
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),

            // ── COMPLEMENTOS ──────────────────────────────────────────────
            const SizedBox(height: 8),
            SectionBand(
              icon: Icons.extension_outlined,
              title: l10n.complementos,
            ),

            // Boost row
            _BoostRow(),

            const Divider(height: 1, color: VibraTheme.kDivider,
                indent: 16, endIndent: 16),

            // Right Now row
            _DrawerListTile(
              icon: Icons.water_drop,
              iconColor: VibraTheme.kAccentGlow,
              label: l10n.rightNow,
              onTap: () {
                Navigator.of(context).pop();
                context.go('/right-now');
              },
            ),

            // Active sub banner (only when user has a current subscription).
            // Per brief: placed ABOVE the ELEGIR UN PLAN SectionBand.
            if (activeSub != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push('/tienda');
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: VibraTheme.kBrandPrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: VibraTheme.kBrandPrimary, width: 1),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              color: VibraTheme.kBrandPrimary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${activeSub.planName} — ${l10n.planActivo}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              color: VibraTheme.kTextSecondary, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],

            // ── ELEGIR UN PLAN ────────────────────────────────────────────
            const SizedBox(height: 8),
            SectionBand(
              icon: Icons.star_outline,
              title: l10n.elegirUnPlan,
            ),
            const SizedBox(height: 12),

            // Yellow CTA plan card → /tienda (UpsellCard).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push('/tienda');
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: UpsellCard(
                    highlighted: true,
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.obtenerPremium,
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.chatearMasLugarenos,
                          style: const TextStyle(
                              color: Colors.black87, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Dark "See plans" card → /tienda (UpsellCard).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push('/tienda');
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: UpsellCard(
                    content: Text(
                      l10n.verPlanes,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Divider(height: 1, color: VibraTheme.kDivider),
            const SizedBox(height: 8),

            // ── Menu items ────────────────────────────────────────────────
            _DrawerListTile(
              icon: Icons.edit_outlined,
              label: l10n.editarPerfil,
              onTap: () {
                Navigator.of(context).pop();
                context.push('/edit-profile');
              },
            ),

            _DrawerListTile(
              icon: Icons.photo_library_outlined,
              label: l10n.misAlbumes,
              onTap: () {
                Navigator.of(context).pop();
                context.push('/albums');
              },
            ),

            _DrawerListTile(
              icon: Icons.event_outlined,
              label: l10n.events_title,
              onTap: () {
                Navigator.of(context).pop();
                context.push('/events');
              },
            ),

            _DrawerListTile(
              icon: Icons.storefront_outlined,
              label: l10n.shopMenuItem,
              onTap: () {
                Navigator.of(context).pop();
                context.push('/shop');
              },
            ),

            _DrawerListTile(
              icon: Icons.favorite_border,
              label: l10n.saludSexual,
              onTap: () {
                Navigator.of(context).pop();
                context.push('/edit-profile');
              },
            ),

            _DrawerListTile(
              icon: Icons.verified_outlined,
              label: l10n.verifyProfileMenuItem,
              onTap: () {
                Navigator.of(context).pop();
                context.push('/verify-profile');
              },
            ),

            _DrawerListTile(
              icon: Icons.verified_user_outlined,
              label: l10n.seguridadPrivacidad,
              onTap: () {
                Navigator.of(context).pop();
                context.push('/settings?tab=privacy');
              },
            ),

            _DrawerListTile(
              icon: Icons.settings_outlined,
              label: l10n.ajustes,
              onTap: () {
                Navigator.of(context).pop();
                context.push('/settings');
              },
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Profile photo widget ──────────────────────────────────────────────────────

class _ProfilePhoto extends StatelessWidget {
  final UserProfile? profile;

  const _ProfilePhoto({required this.profile});

  @override
  Widget build(BuildContext context) {
    if (profile?.profilePhotoUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          profile!.profilePhotoUrl!,
          width: 180,
          height: 180,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              _PhotoPlaceholder(initials: _initials(profile)),
        ),
      );
    }
    return _PhotoPlaceholder(initials: _initials(profile));
  }

  String _initials(UserProfile? p) {
    if (p == null) return '?';
    final name = p.displayName ?? p.email;
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  final String initials;

  const _PhotoPlaceholder({required this.initials});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        color: VibraTheme.kSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 60,
            color: VibraTheme.kBrandPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ── Boost row ─────────────────────────────────────────────────────────────────

class _BoostRow extends ConsumerStatefulWidget {
  @override
  ConsumerState<_BoostRow> createState() => _BoostRowState();
}

class _BoostRowState extends ConsumerState<_BoostRow> {
  bool _activating = false;

  Future<void> _handleBoost() async {
    final activeAsync = ref.read(activeBoostProvider);
    // If already boosted, just show status.
    Boost? existingBoost;
    if (activeAsync is AsyncData<Boost?>) {
      existingBoost = activeAsync.value;
    }
    if (existingBoost != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Boost activo · ${existingBoost.minutesRemaining}m restantes',
          ),
        ),
      );
      return;
    }

    setState(() => _activating = true);
    try {
      await ref.read(boostServiceProvider).activate();
      ref.invalidate(activeBoostProvider);
      if (mounted) {
        Navigator.of(context).pop(); // close drawer
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Boost activado por 30 min!'),
            backgroundColor: VibraTheme.kAccentPulse,
          ),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Error: ${e.response?.statusCode ?? e.message}'),
            backgroundColor: VibraTheme.kError,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: VibraTheme.kError,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeAsync = ref.watch(activeBoostProvider);
    // Narrow the type safely without a cast that the linter would flag.
    Boost? activeBoost;
    if (activeAsync is AsyncData<Boost?>) {
      activeBoost = activeAsync.value;
    }
    // Build label using Dart flow analysis (avoids null-assertion lint).
    final String boostLabel;
    if (activeBoost != null) {
      boostLabel = 'Boost · ${activeBoost.minutesRemaining}m';
    } else {
      boostLabel = 'Boost';
    }

    return _DrawerListTile(
      icon: Icons.bolt,
      iconColor: VibraTheme.kAccentPulse,
      label: boostLabel,
      trailing: _activating
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: VibraTheme.kAccentPulse),
            )
          : null,
      onTap: _handleBoost,
    );
  }
}

// ── Shared list-tile ──────────────────────────────────────────────────────────

class _DrawerListTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final Widget? trailing;
  final VoidCallback onTap;

  const _DrawerListTile({
    required this.icon,
    this.iconColor,
    required this.label,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? VibraTheme.kTextSecondary),
      title: Text(
        label,
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
      ),
      trailing: trailing,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    );
  }
}
