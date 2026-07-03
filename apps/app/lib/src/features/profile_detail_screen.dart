import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/gen/app_localizations.dart';
import '../auth/auth_provider.dart';
import '../chat/chat_service.dart';
import '../presence/presence_service.dart';
import '../reports/report_service.dart';
import '../theme/app_theme.dart';
import 'cascade_screen.dart' show NearbyUser;
import 'profile_screen.dart' show UserProfile;

/// Full-screen profile of another user — Grindr-style redesign (T4).
///
/// Accessed by tapping a user card in Cascade, Interest, or Navegar.
class ProfileDetailScreen extends ConsumerStatefulWidget {
  final String userId;

  const ProfileDetailScreen({super.key, required this.userId});

  @override
  ConsumerState<ProfileDetailScreen> createState() =>
      _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends ConsumerState<ProfileDetailScreen> {
  UserProfile? _profile;
  bool _isLoading = true;
  String? _error;
  bool _isFavorited = false;
  bool _isBlocked = false;
  Map<String, dynamic>? _healthData;
  List<NearbyUser> _suggestions = [];
  final TextEditingController _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final response =
          await dio.get<Map<String, dynamic>>('/profile/${widget.userId}');
      final userJson = response.data!['user'] as Map<String, dynamic>;
      final profile = UserProfile.fromJson(userJson);
      final health = response.data!['health'] as Map<String, dynamic>?;

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _healthData = health;
        _isLoading = false;
      });

      // Fetch suggestions in background (silently ignore failures)
      _loadSuggestions();
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

  Future<void> _loadSuggestions() async {
    try {
      final dio = ref.read(dioProvider);
      final response =
          await dio.get<Map<String, dynamic>>('/grid/nearby');
      final usersJson =
          response.data!['users'] as List<dynamic>? ?? [];
      final list = usersJson
          .map((e) => NearbyUser.fromJson(e as Map<String, dynamic>))
          .where((u) => u.id != widget.userId)
          .take(4)
          .toList();
      if (mounted) {
        setState(() => _suggestions = list);
      }
    } catch (_) {
      // Silently skip — section is hidden when empty.
    }
  }

  Future<void> _sendTap() async {
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/taps', data: {
        'to_user_id': widget.userId,
        'tap_type': 'wave',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tap sent!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send tap: $e')),
        );
      }
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      final dio = ref.read(dioProvider);
      if (_isFavorited) {
        await dio.delete('/favorites/${widget.userId}');
      } else {
        await dio.post('/favorites', data: {'user_id': widget.userId});
      }
      if (mounted) setState(() => _isFavorited = !_isFavorited);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  // Keep _toggleBlock for future use — no block button in the new UI.
  // ignore: unused_element
  Future<void> _toggleBlock() async {
    try {
      final dio = ref.read(dioProvider);
      if (_isBlocked) {
        await dio.delete('/blocks/${widget.userId}');
      } else {
        await dio.post('/blocks',
            data: {'user_id': widget.userId, 'reason': null});
      }
      if (mounted) setState(() => _isBlocked = !_isBlocked);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isBlocked ? 'User blocked' : 'User unblocked'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _showReportSheet() async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: VibraTheme.kSurface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Report this user',
                style: TextStyle(
                  color: VibraTheme.kTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final r in kReportReasons)
              ListTile(
                title: Text(r,
                    style:
                        const TextStyle(color: VibraTheme.kTextPrimary)),
                onTap: () => Navigator.of(ctx).pop(r),
              ),
          ],
        ),
      ),
    );
    if (reason == null) return;
    try {
      await ref.read(reportServiceProvider).report(
            targetUserId: widget.userId,
            targetKind: 'profile',
            reason: reason,
          );
      messenger.showSnackBar(
        const SnackBar(content: Text('Report submitted. Thank you.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to submit report')),
      );
    }
  }

  Future<void> _startChat() async {
    try {
      final chatService = ref.read(chatServiceProvider);
      final conversationId =
          await chatService.createConversation(widget.userId);
      if (!mounted) return;
      context.push('/inbox/$conversationId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start chat: $e')),
      );
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    try {
      final chatService = ref.read(chatServiceProvider);
      final convId = await chatService.createConversation(widget.userId);
      await chatService.sendMessage(convId, text.trim());
      if (!mounted) return;
      context.go('/inbox/$convId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: VibraTheme.kBg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: VibraTheme.kBg,
        appBar: AppBar(backgroundColor: VibraTheme.kBg),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: VibraTheme.kSurface,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.error_outline,
                      size: 36, color: VibraTheme.kError),
                ),
                const SizedBox(height: 20),
                Text(_error!,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: VibraTheme.kTextPrimary),
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loadProfile,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final p = _profile!;
    final l10n = AppLocalizations.of(context)!;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      body: Column(
        children: [
          // ── Scrollable content ─────────────────────────────────────────────
          Expanded(
            child: CustomScrollView(
              slivers: [
                // ── Hero photo SliverAppBar ──────────────────────────────────
                SliverAppBar(
                  expandedHeight: screenHeight * 0.65,
                  pinned: true,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  surfaceTintColor: Colors.transparent,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(
                        Icons.person_off_outlined,
                        color: Colors.white,
                      ),
                      onPressed: _showReportSheet,
                    ),
                    IconButton(
                      icon: Icon(
                        _isFavorited ? Icons.star : Icons.star_border,
                        color:
                            _isFavorited ? VibraTheme.kYellow : Colors.white,
                      ),
                      onPressed: _toggleFavorite,
                    ),
                  ],
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: VibraTheme.kOnline,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        p.displayName ?? p.email,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    collapseMode: CollapseMode.pin,
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Photo or letter placeholder
                        if (p.profilePhotoUrl != null)
                          Image.network(
                            p.profilePhotoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                _buildPhotoPlaceholder(p),
                          )
                        else
                          _buildPhotoPlaceholder(p),
                        // Bottom gradient → fades into kBg
                        const Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 160,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  VibraTheme.kBg,
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Verified badge (top-right of photo)
                        if (p.isVerified)
                          Positioned(
                            top: 60,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: VibraTheme.kYellow,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.verified,
                                      color: Colors.black, size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'Verified',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // ── Profile body ─────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Display name (34 w800)
                        Text(
                          p.displayName ?? p.email,
                          style: const TextStyle(
                            color: VibraTheme.kTextPrimary,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Presence badge
                        _PresenceBadge(userId: p.id),
                        const SizedBox(height: 8),

                        // Quick stats row (position | height | weight | bodyType)
                        _QuickStatsRow(profile: p),

                        // ── ACERCA DE MÍ ────────────────────────────────────
                        if (p.bio != null && p.bio!.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          _sectionHeader(l10n.acercaDeMi.toUpperCase()),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: VibraTheme.kSurface,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              p.bio!,
                              style: const TextStyle(
                                color: VibraTheme.kTextPrimary,
                                fontSize: 17,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],

                        // ── ESTADÍSTICAS ────────────────────────────────────
                        const SizedBox(height: 20),
                        _sectionHeader(l10n.estadisticas.toUpperCase()),
                        const SizedBox(height: 12),
                        _buildStatsSection(p),

                        // ── EXPECTATIVAS ────────────────────────────────────
                        if (p.lookingFor.isNotEmpty || p.meetAt.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          _sectionHeader(l10n.expectativas.toUpperCase()),
                          const SizedBox(height: 12),
                          _buildExpectativasSection(p, l10n),
                        ],

                        // ── SALUD ───────────────────────────────────────────
                        if (_hasHealthData()) ...[
                          const SizedBox(height: 20),
                          _sectionHeader(l10n.salud.toUpperCase()),
                          const SizedBox(height: 12),
                          _buildSaludSection(),
                        ],

                        // ── TE PODRÍA INTERESAR ─────────────────────────────
                        if (_suggestions.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Text(
                                l10n.tePodriaInteresar.toUpperCase(),
                                style: const TextStyle(
                                  color: VibraTheme.kTextSecondary,
                                  fontSize: 13,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: VibraTheme.kYellow,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  l10n.nuevo.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildSuggestionsGrid(),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Sticky bottom bar ─────────────────────────────────────────────
          Container(
            color: VibraTheme.kBg,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SafeArea(
              top: false,
              left: false,
              right: false,
              child: Row(
                children: [
                  // Di algo... pill text field
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: VibraTheme.kChip,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _messageController,
                        style: const TextStyle(
                          color: VibraTheme.kTextPrimary,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: l10n.diAlgo,
                          hintStyle: const TextStyle(
                            color: VibraTheme.kTextSecondary,
                            fontSize: 15,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        onSubmitted: (text) {
                          _messageController.clear();
                          _sendMessage(text);
                        },
                      ),
                    ),
                  ),
                  // Flame (Tap)
                  IconButton(
                    icon: const Icon(
                      Icons.local_fire_department,
                      color: VibraTheme.kYellow,
                      size: 28,
                    ),
                    onPressed: _sendTap,
                  ),
                  // Chat bubble
                  IconButton(
                    icon: const Icon(
                      Icons.chat_bubble_outline,
                      color: VibraTheme.kYellow,
                      size: 28,
                    ),
                    onPressed: _startChat,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: VibraTheme.kTextSecondary,
        fontSize: 13,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildStatsSection(UserProfile p) {
    final rows = <Widget>[];

    // Height | Weight | BodyType in one row (only non-null parts)
    final hwbParts = <String>[];
    if (p.heightCm != null) hwbParts.add('${p.heightCm} cm');
    if (p.weightKg != null) hwbParts.add('${p.weightKg} kg');
    if (p.bodyType != null && p.bodyType!.isNotEmpty) {
      hwbParts.add(p.bodyType!);
    }
    if (hwbParts.isNotEmpty) {
      rows.add(_statRow(Icons.straighten, hwbParts.join(' | ')));
    }

    // Pronouns with (i) tooltip
    if (p.pronouns != null && p.pronouns!.isNotEmpty) {
      rows.add(_statRowWithTooltip(
          Icons.person_outline, p.pronouns!, 'Pronombres / Pronouns'));
    }

    // Position (role)
    if (p.position != null && p.position!.isNotEmpty) {
      rows.add(_statRow(Icons.swap_vert, p.position!));
    }

    // Ethnicity
    if (p.ethnicity != null && p.ethnicity!.isNotEmpty) {
      rows.add(_statRow(Icons.circle_outlined, p.ethnicity!));
    }

    // Relationship status
    if (p.relationshipStatus != null && p.relationshipStatus!.isNotEmpty) {
      rows.add(_statRow(Icons.people_outline, p.relationshipStatus!));
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(children: rows);
  }

  Widget _statRow(IconData icon, String value) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 22, color: VibraTheme.kTextSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: VibraTheme.kTextPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRowWithTooltip(IconData icon, String value, String tooltip) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 22, color: VibraTheme.kTextSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: VibraTheme.kTextPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Tooltip(
            message: tooltip,
            child: const Icon(
              Icons.info_outline,
              size: 18,
              color: VibraTheme.kTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpectativasSection(UserProfile p, AppLocalizations l10n) {
    final rows = <Widget>[];
    if (p.lookingFor.isNotEmpty) {
      rows.add(
        _expectativaRow(
          Icons.people_outline,
          l10n.enBuscaDe,
          p.lookingFor.join(', '),
        ),
      );
    }
    if (p.meetAt.isNotEmpty) {
      rows.add(
        _expectativaRow(
          Icons.home_outlined,
          l10n.quedarEn,
          p.meetAt.join(', '),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _expectativaRow(IconData icon, String label, String value) {
    return SizedBox(
      height: 44,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: VibraTheme.kTextSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$label ',
                    style: const TextStyle(
                      color: VibraTheme.kTextSecondary,
                      fontSize: 15,
                    ),
                  ),
                  TextSpan(
                    text: value,
                    style: const TextStyle(
                      color: VibraTheme.kTextPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasHealthData() {
    final h = _healthData;
    if (h == null) return false;
    final practices = h['safer_practices_list'] as List?;
    return h['hiv_status'] != null ||
        h['last_tested_at'] != null ||
        (practices?.isNotEmpty ?? false);
  }

  Widget _buildSaludSection() {
    final h = _healthData!;
    final rows = <Widget>[];

    if (h['hiv_status'] != null) {
      rows.add(_statRowWithTooltip(
        Icons.health_and_safety_outlined,
        h['hiv_status'] as String,
        'Estado de VIH',
      ));
    }
    if (h['last_tested_at'] != null) {
      rows.add(_statRow(
        Icons.calendar_today_outlined,
        h['last_tested_at'] as String,
      ));
    }
    final practices = h['safer_practices_list'] as List?;
    if (practices != null && practices.isNotEmpty) {
      rows.add(_statRow(
        Icons.favorite_border,
        practices.map((e) => e as String).join(', '),
      ));
    }
    return Column(children: rows);
  }

  Widget _buildSuggestionsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.85,
      children: _suggestions.map((user) {
        return GestureDetector(
          onTap: () => context.pushReplacement('/profile/${user.id}'),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Photo or letter placeholder
                if (user.profilePhotoUrl != null)
                  Image.network(
                    user.profilePhotoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _buildNearbyPlaceholder(user),
                  )
                else
                  _buildNearbyPlaceholder(user),
                // Gradient overlay
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 60,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                ),
                // Name overlay (bottom-left)
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Text(
                    user.displayName ?? user.email,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(blurRadius: 4, color: Colors.black),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPhotoPlaceholder(UserProfile p) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [VibraTheme.kSurface, VibraTheme.kSurfaceElevated],
        ),
      ),
      child: Center(
        child: Text(
          (p.displayName ?? p.email)[0].toUpperCase(),
          style: const TextStyle(
            fontSize: 80,
            color: VibraTheme.kTextMuted,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildNearbyPlaceholder(NearbyUser user) {
    return Container(
      color: VibraTheme.kSurface,
      child: Center(
        child: Text(
          (user.displayName ?? user.email)[0].toUpperCase(),
          style: const TextStyle(
            fontSize: 32,
            color: VibraTheme.kTextMuted,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

/// Quick stats row: position icon | height | weight | bodyType, kTextTertiary.
class _QuickStatsRow extends StatelessWidget {
  final UserProfile profile;

  const _QuickStatsRow({required this.profile});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final parts = <Widget>[];

    if (p.position != null && p.position!.isNotEmpty) {
      parts.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_downward,
              size: 14, color: VibraTheme.kTextTertiary),
          const SizedBox(width: 2),
          Text(
            p.position!,
            style: const TextStyle(
              color: VibraTheme.kTextTertiary,
              fontSize: 15,
            ),
          ),
        ],
      ));
    }

    final hwbParts = <String>[];
    if (p.heightCm != null) hwbParts.add('${p.heightCm} cm');
    if (p.weightKg != null) hwbParts.add('${p.weightKg} kg');
    if (p.bodyType != null && p.bodyType!.isNotEmpty) {
      hwbParts.add(p.bodyType!);
    }
    if (hwbParts.isNotEmpty) {
      if (parts.isNotEmpty) {
        parts.add(const Text(
          ' | ',
          style: TextStyle(color: VibraTheme.kTextTertiary, fontSize: 15),
        ));
      }
      parts.add(Text(
        hwbParts.join(' | '),
        style: const TextStyle(
          color: VibraTheme.kTextTertiary,
          fontSize: 15,
        ),
      ));
    }

    if (parts.isEmpty) return const SizedBox.shrink();

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: parts,
    );
  }
}

/// Online / last-seen badge using the presence module.
class _PresenceBadge extends ConsumerWidget {
  final String userId;

  const _PresenceBadge({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final statusAsync = ref.watch(userStatusProvider(userId));

    return statusAsync.when(
      loading: () => const SizedBox(height: 20),
      error: (_, _) => const SizedBox(height: 20),
      data: (status) {
        final label = status.isOnline
            ? (l10n?.conectado ?? 'Conectado')
            : formatLastSeen(status);
        if (label.isEmpty) return const SizedBox(height: 20);
        final color =
            status.isOnline ? VibraTheme.kOnline : VibraTheme.kTextMuted;
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color, fontSize: 13)),
            ],
          ),
        );
      },
    );
  }
}
