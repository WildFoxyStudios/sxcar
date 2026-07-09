import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/gen/app_localizations.dart';
import '../auth/auth_provider.dart';
import '../settings/settings_providers.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// Redesigned settings screen. Single ListView with 7 SectionBands.
class SettingsScreen extends ConsumerStatefulWidget {
  /// Optional deep-link tab key (notifications/privacy/blocks). If present, the
  /// scroll controller jumps to that section on first build. The key is
  /// kept for backward compatibility with the old tabbed UI.
  final String? initialTab;

  const SettingsScreen({super.key, this.initialTab});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _scrollController = ScrollController();
  final _sectionKeys = <String, GlobalKey>{};

  // Notification pref state (synced via /notifications/preferences).
  bool _newMessages = false;
  bool _newTaps = false;
  bool _promotions = false;
  bool _notifLoading = true;
  String? _notifError;

  // Privacy toggle state (synced via ProfileEditProvider PUT /profile).
  bool _showAlbumUpdates = true;
  bool _showCarousel = true;
  bool _markChatted = true;
  bool _chatSync = true;
  bool _keepUnlocked = false;

  @override
  void initState() {
    super.initState();
    for (final key in const [
      'cuenta', 'multimedia', 'pantalla', 'privacidad',
      'unidades', 'visitante', 'notificaciones',
    ]) {
      _sectionKeys[key] = GlobalKey();
    }
    _loadNotificationPreferences();
    if (widget.initialTab != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollTo(widget.initialTab!);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollTo(String key) {
    final key2 = _sectionKeys[key];
    if (key2 == null) return;
    final ctx = key2.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  }

  Future<void> _loadNotificationPreferences() async {
    setState(() {
      _notifLoading = true;
      _notifError = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get<Map<String, dynamic>>('/notifications/preferences');
      final data = response.data!;
      if (!mounted) return;
      setState(() {
        _newMessages = (data['new_messages'] as bool?) ?? false;
        _newTaps = (data['new_taps'] as bool?) ?? false;
        _promotions = (data['promotions'] as bool?) ?? false;
        _notifLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notifLoading = false;
        _notifError = 'Error cargando notificaciones';
      });
    }
  }

  Future<void> _updateNotificationPref(String key, bool value) async {
    try {
      await ref.read(dioProvider).put<Map<String, dynamic>>(
        '/notifications/preferences',
        data: {key: value},
      );
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorGuardandoPreferencia)),
        );
        _loadNotificationPreferences();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final units = ref.watch(unitsProvider);
    final discreetIcon = ref.watch(discreetIconProvider);
    final pinEnabled = ref.watch(pinEnabledProvider);
    final visitorStatus = ref.watch(visitorStatusProvider);

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        title: Text(l10n.ajustes),
        backgroundColor: VibraTheme.kBg,
        elevation: 0,
      ),
      body: ListView(
        controller: _scrollController,
        padding: EdgeInsets.zero,
        children: [
          // ── CUENTA ─────────────────────────────────────────────────────
          _sectionHeader(l10n.cuenta, 'cuenta'),
          SettingRow(
            icon: Icons.edit_outlined,
            title: l10n.editarPerfil,
            onTap: () => context.push('/edit-profile'),
          ),
          const Divider(height: 1, color: VibraTheme.kDivider, indent: 16, endIndent: 16),
          SettingRow(
            icon: Icons.photo_library_outlined,
            title: l10n.misAlbumes,
            onTap: () => context.push('/albums'),
          ),
          const Divider(height: 1, color: VibraTheme.kDivider, indent: 16, endIndent: 16),
          SettingRow(
            icon: Icons.delete_forever,
            iconColor: VibraTheme.kError,
            title: l10n.eliminarCuenta,
            onTap: _confirmDeleteAccount,
          ),

          // ── MULTIMEDIA ─────────────────────────────────────────────────
          _sectionHeader(l10n.multimedia, 'multimedia'),
          // TODO(persist): no backend endpoint for these multimedia/display
          // privacy toggles yet — they are local UI state only. Wire each
          // onChanged to PUT /profile (or shared_preferences) once the
          // backend supports these fields.
          SettingRow(
            icon: Icons.photo_album_outlined,
            title: l10n.mostrarActualizacionesAlbumes,
            trailing: Switch(
              value: _showAlbumUpdates,
              activeThumbColor: VibraTheme.kBrandPrimary,
              onChanged: (v) => setState(() => _showAlbumUpdates = v),
            ),
          ),
          const Divider(height: 1, color: VibraTheme.kDivider, indent: 16, endIndent: 16),
          SettingRow(
            icon: Icons.view_carousel_outlined,
            title: l10n.mostrarCarruselBandeja,
            trailing: Switch(
              value: _showCarousel,
              activeThumbColor: VibraTheme.kBrandPrimary,
              onChanged: (v) => setState(() => _showCarousel = v),
            ),
          ),

          // ── PREFERENCIAS DE PANTALLA ───────────────────────────────────
          _sectionHeader(l10n.preferenciasPantalla, 'pantalla'),
          SettingRow(
            icon: Icons.screen_lock_portrait_outlined,
            title: l10n.mantenerPantallaDesbloqueada,
            trailing: Switch(
              value: _keepUnlocked,
              activeThumbColor: VibraTheme.kBrandPrimary,
              onChanged: (v) => setState(() => _keepUnlocked = v),
            ),
          ),

          // ── PRIVACIDAD / SEGURIDAD ─────────────────────────────────────
          _sectionHeader(l10n.centroSeguridad, 'privacidad'),
          SettingRow(
            icon: Icons.apps_outlined,
            iconColor: VibraTheme.kTierTop,
            title: l10n.iconoAplicacionDiscreto,
            subtitle: discreetIcon ? l10n.activado : l10n.desactivada,
            onTap: () => context.push('/settings/discreet-icon'),
          ),
          const Divider(height: 1, color: VibraTheme.kDivider, indent: 16, endIndent: 16),
          SettingRow(
            icon: Icons.pin_outlined,
            iconColor: VibraTheme.kGold,
            title: l10n.pin,
            subtitle: pinEnabled ? l10n.activado : l10n.desactivada,
            onTap: () => context.push('/settings/pin'),
          ),
          const Divider(height: 1, color: VibraTheme.kDivider, indent: 16, endIndent: 16),
          SettingRow(
            icon: Icons.block,
            title: l10n.desbloquearUsuarios,
            onTap: () => context.push('/settings/blocks'),
          ),
          const Divider(height: 1, color: VibraTheme.kDivider, indent: 16, endIndent: 16),
          // TODO(persist): _markChatted and _chatSync are local UI state only.
          // Wire to PUT /profile once the backend exposes these fields.
          SettingRow(
            icon: Icons.chat_bubble_outline,
            title: l10n.marcarConQuienChateeado,
            trailing: Switch(
              value: _markChatted,
              activeThumbColor: VibraTheme.kBrandPrimary,
              onChanged: (v) => setState(() => _markChatted = v),
            ),
          ),
          const Divider(height: 1, color: VibraTheme.kDivider, indent: 16, endIndent: 16),
          SettingRow(
            icon: Icons.sync,
            title: l10n.sincronizacionMensajes,
            trailing: Switch(
              value: _chatSync,
              activeThumbColor: VibraTheme.kBrandPrimary,
              onChanged: (v) => setState(() => _chatSync = v),
            ),
          ),
          const Divider(height: 1, color: VibraTheme.kDivider, indent: 16, endIndent: 16),
          SettingRow(
            icon: Icons.security_outlined,
            title: l10n.centroSeguridad,
            onTap: () => context.push('/security'),
          ),
          const Divider(height: 1, color: VibraTheme.kDivider, indent: 16, endIndent: 16),
          SettingRow(
            icon: Icons.policy_outlined,
            title: l10n.preferenciasConsentimiento,
            onTap: _showConsentDialog,
          ),
          const Divider(height: 1, color: VibraTheme.kDivider, indent: 16, endIndent: 16),
          SettingRow(
            icon: Icons.download_outlined,
            title: l10n.descargarDatos,
            onTap: () => _downloadData(context, ref),
          ),

          // ── UNIDADES ───────────────────────────────────────────────────
          _sectionHeader(l10n.sistemaUnidades, 'unidades'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: VibraSegmented(
              options: [l10n.metrico, l10n.imperial],
              selectedIndex: units,
              onChanged: (i) =>
                  ref.read(unitsProvider.notifier).setUnits(i),
            ),
          ),

          // ── VISITANTE ─────────────────────────────────────────────────
          _sectionHeader(l10n.estadoVisitante, 'visitante'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Segmented3(
              options: [l10n.desactivada, l10n.activado, l10n.automatico],
              selectedIndex: visitorStatus,
              onChanged: (i) =>
                  ref.read(visitorStatusProvider.notifier).setVisitorStatus(i),
            ),
          ),

          // ── NOTIFICACIONES / SESIONES ─────────────────────────────────
          _sectionHeader(l10n.notificacionesYSesiones, 'notificaciones'),
          if (_notifLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_notifError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(_notifError!,
                      style: const TextStyle(color: VibraTheme.kError)),
                  TextButton(
                    onPressed: _loadNotificationPreferences,
                    child: Text(l10n.reintentar),
                  ),
                ],
              ),
            )
          else ...[
            SettingRow(
              icon: Icons.message_outlined,
              title: l10n.mensajesNuevos,
              trailing: Switch(
                value: _newMessages,
                activeThumbColor: VibraTheme.kBrandPrimary,
                onChanged: (v) {
                  setState(() => _newMessages = v);
                  _updateNotificationPref('new_messages', v);
                },
              ),
            ),
            const Divider(height: 1, color: VibraTheme.kDivider, indent: 16, endIndent: 16),
            SettingRow(
              icon: Icons.touch_app_outlined,
              title: l10n.tapsNuevos,
              trailing: Switch(
                value: _newTaps,
                activeThumbColor: VibraTheme.kBrandPrimary,
                onChanged: (v) {
                  setState(() => _newTaps = v);
                  _updateNotificationPref('new_taps', v);
                },
              ),
            ),
            const Divider(height: 1, color: VibraTheme.kDivider, indent: 16, endIndent: 16),
            SettingRow(
              icon: Icons.local_offer_outlined,
              title: l10n.promociones,
              trailing: Switch(
                value: _promotions,
                activeThumbColor: VibraTheme.kBrandPrimary,
                onChanged: (v) {
                  setState(() => _promotions = v);
                  _updateNotificationPref('promotions', v);
                },
              ),
            ),
            const Divider(height: 1, color: VibraTheme.kDivider, indent: 16, endIndent: 16),
            SettingRow(
              icon: Icons.chat_bubble_outline,
              title: l10n.frasesGuardadas,
              onTap: () => context.push('/settings/phrases'),
            ),
            const Divider(height: 1, color: VibraTheme.kDivider, indent: 16, endIndent: 16),
            SettingRow(
              icon: Icons.devices,
              title: l10n.sesionesActivas,
              onTap: () => context.push('/settings/sessions'),
            ),
          ],

          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton(
              onPressed: _logout,
              child: Text(l10n.cerrarSesion, style: const TextStyle(color: VibraTheme.kError)),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, String key) {
    return Padding(
      key: _sectionKeys[key],
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: VibraTheme.kTextSecondary,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  void _showConsentDialog() {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VibraTheme.kSurface,
        title: Text(l10n.preferenciasConsentimiento),
        content: const Text(
          'You accepted the Terms of Service and Privacy Policy during '
          'registration. Your data is processed in accordance with GDPR. '
          'You can request a full data export or account deletion at any time.',
          style: TextStyle(color: VibraTheme.kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadData(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(dioProvider).post('/me/export-data');
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Data export complete. Check your email.'),
        backgroundColor: VibraTheme.kSuccess,
      ));
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Export failed: $e'),
        backgroundColor: VibraTheme.kBadgeRed,
      ));
    }
  }

  Future<void> _logout() async {
    await ref.read(authStateProvider.notifier).logout();
  }

  Future<void> _confirmDeleteAccount() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VibraTheme.kSurface,
        title: Text(l10n.confirmarEliminar),
        content: Text(l10n.accionNoSePuedeDeshacer),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancelar),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.eliminar, style: const TextStyle(color: VibraTheme.kError)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    try {
      await ref.read(dioProvider).delete('/profile');
      if (!mounted) return;
      await ref.read(authStateProvider.notifier).logout();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }
}