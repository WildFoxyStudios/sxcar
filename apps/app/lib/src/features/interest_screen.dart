import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/gen/app_localizations.dart';
import '../auth/auth_provider.dart';
import '../boost/boost_service.dart';
import '../billing/billing_providers.dart';
import '../billing/models.dart';
import '../profile_views/viewed_me_provider.dart';
import '../taps/taps_count_provider.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// Model for a tap received from another user.
class ReceivedTap {
  final String id;
  final String senderId;
  final String? senderDisplayName;
  final String? senderPhotoUrl;
  final String tapType;
  final String createdAt;

  const ReceivedTap({
    required this.id,
    required this.senderId,
    this.senderDisplayName,
    this.senderPhotoUrl,
    required this.tapType,
    required this.createdAt,
  });

  factory ReceivedTap.fromJson(Map<String, dynamic> json) {
    return ReceivedTap(
      id: json['id'] as String,
      senderId: json['sender_id'] as String,
      senderDisplayName: json['sender_display_name'] as String?,
      senderPhotoUrl: json['sender_photo_url'] as String?,
      tapType: json['tap_type'] as String? ?? 'wave',
      createdAt: json['created_at'] as String,
    );
  }
}

/// Interest screen — combines Tabs (Views N / Taps N) with a sticky
/// upsell CTA + Boost FAB. Matches the Grindr Interest IA.
///
/// Tabs are driven by count providers (T3.5) so the tab labels themselves
/// function as a "you have N unseen views / taps" indicator.
class InterestScreen extends ConsumerStatefulWidget {
  const InterestScreen({super.key});

  @override
  ConsumerState<InterestScreen> createState() => _InterestScreenState();
}

class _InterestScreenState extends ConsumerState<InterestScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Future<List<ReceivedTap>> _tapsFuture;
  // false = taps received, true = taps sent (Grindr-style Received/Sent toggle).
  bool _tapsSent = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tapsFuture = _fetchTaps();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Wait until `authState` actually has a token before firing any
  /// authenticated request. The Dio client's Authorization interceptor reads
  /// from the secure-storage cache, but the cache is only populated after
  /// the boot path reads the token (asynchronous). If the user lands on
  /// InterestScreen before that finishes, the request goes out without a
  /// Bearer header and the server returns 401 — a race that the catch-all
  /// refresh-on-401 in api_client cannot recover from (no refresh token yet
  /// either). Poll the provider until the token is present.
  Future<void> _waitForAuth() async {
    while (mounted) {
      final token = ref.read(authStateProvider).accessToken;
      if (token != null && token.isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<List<ReceivedTap>> _fetchTaps() async {
    await _waitForAuth();
    final dio = ref.read(dioProvider);
    final response = await dio.get<Map<String, dynamic>>(
        _tapsSent ? '/taps/sent' : '/taps/received');
    final data = response.data!;
    final tapsJson = data['taps'] as List<dynamic>;
    return tapsJson
        .map((t) => ReceivedTap.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  /// True when the current user has an active subscription. Used to gate
  /// the NUEVO upsell (counts > 6 without entitlement).
  bool _hasEntitlement() {
    final sub = ref.read(mySubscriptionProvider);
    if (sub is! AsyncData<Subscription?>) return false;
    return sub.value != null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final viewsCountAsync = ref.watch(profileViewsCountProvider);
    final tapsCountAsync = ref.watch(tapsCountProvider);
    final viewsCount = viewsCountAsync is AsyncData<int> ? viewsCountAsync.value : 0;
    final tapsTotal = tapsCountAsync is AsyncData<TapsCount>
        ? tapsCountAsync.value.total
        : 0;

    final maxCount = viewsCount > tapsTotal ? viewsCount : tapsTotal;
    final showNUEVO = maxCount > 6 && !_hasEntitlement();

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        backgroundColor: VibraTheme.kBg,
        elevation: 0,
        title: Text(
          l10n.interest,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 32,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 2,
          labelColor: Colors.white,
          unselectedLabelColor: VibraTheme.kTextSecondary,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          tabs: [
            Tab(text: '${l10n.views} $viewsCount'),
            Tab(text: '${l10n.taps} $tapsTotal'),
          ],
        ),
      ),
      body: Column(
        children: [
          // NUEVO badge row — visible only when count > 6 without entitlement.
          if (showNUEVO)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: VibraTheme.kBrandPrimary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flash_on, color: Colors.black, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.desbloquearGratis,
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          l10n.desbloquearTodoSinLimites,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.black),
                ],
              ),
            ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                const _ViewsListTab(),
                Column(
                  children: [
                    // Received / Sent toggle (Grindr parity).
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: Text(l10n.tapsReceived),
                            selected: !_tapsSent,
                            onSelected: (_) {
                              if (_tapsSent) {
                                setState(() {
                                  _tapsSent = false;
                                  _tapsFuture = _fetchTaps();
                                });
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text(l10n.tapsSent),
                            selected: _tapsSent,
                            onSelected: (_) {
                              if (!_tapsSent) {
                                setState(() {
                                  _tapsSent = true;
                                  _tapsFuture = _fetchTaps();
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _TapsListTab(
                        tapsFuture: _tapsFuture,
                        onRetry: () {
                          setState(() {
                            _tapsFuture = _fetchTaps();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Sticky CTA when there's an upsell
          if (showNUEVO)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: YellowPillButton(
                  label: l10n.desbloquearSinLimites,
                  onPressed: () => context.push('/tienda'),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.black,
        foregroundColor: VibraTheme.kBrandPrimary,
        onPressed: () {
          ref.read(boostServiceProvider).activate();
        },
        icon: const Icon(Icons.bolt),
        label: Text(
          l10n.boostTuInterest,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// "Views" tab — shows the list of users who recently viewed the current
/// user's profile. The list endpoint is `GET /profile/views`; the count
/// is exposed separately via `profileViewsCountProvider` and rendered in
/// the TabBar label.
class _ViewsListTab extends ConsumerWidget {
  const _ViewsListTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final viewersAsync = ref.watch(viewedMeProvider);
    return viewersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.errorCargandoVistas,
              style: const TextStyle(color: VibraTheme.kError),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => ref.invalidate(viewedMeProvider),
              child: Text(l10n.reintentar),
            ),
          ],
        ),
      ),
      data: (viewers) {
        if (viewers.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                l10n.nadieHaVistoPerfil,
                style: const TextStyle(color: VibraTheme.kTextSecondary),
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: viewers.length,
          separatorBuilder: (_, _) => const Divider(
            height: 1,
            color: VibraTheme.kDivider,
            indent: 16,
            endIndent: 16,
          ),
          itemBuilder: (_, i) {
            final v = viewers[i];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: VibraTheme.kSurface,
                backgroundImage: v.profilePhotoUrl != null
                    ? NetworkImage(v.profilePhotoUrl!)
                    : null,
                child: v.profilePhotoUrl == null
                    ? Text(
                        (v.displayName ?? '?').isNotEmpty
                            ? (v.displayName ?? '?')[0].toUpperCase()
                            : '?',
                        style: const TextStyle(color: Colors.white),
                      )
                    : null,
              ),
              title: Text(
                v.displayName ?? 'Usuario',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                l10n.vistoEl(v.viewedAt.substring(0, 10)),
                style: const TextStyle(
                  color: VibraTheme.kTextSecondary,
                  fontSize: 12,
                ),
              ),
              onTap: () => context.push('/profile/${v.viewerId}'),
            );
          },
        );
      },
    );
  }
}

/// "Taps" tab — shows the list of recent taps from other users.
///
/// The taps are fetched once in `_InterestScreenState.initState` (so the
/// race-fix `_waitForAuth()` logic runs before the first request), and the
/// resulting [Future] is passed in via [tapsFuture]. A retry callback
/// regenerates the future.
class _TapsListTab extends StatelessWidget {
  final Future<List<ReceivedTap>> tapsFuture;
  final VoidCallback onRetry;

  const _TapsListTab({required this.tapsFuture, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<List<ReceivedTap>>(
      future: tapsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.errorCargandoTaps,
                  style: const TextStyle(color: VibraTheme.kError),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onRetry,
                  child: Text(l10n.reintentar),
                ),
              ],
            ),
          );
        }
        final taps = snapshot.data ?? const [];
        if (taps.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                l10n.sinTaps,
                style: const TextStyle(color: VibraTheme.kTextSecondary),
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: taps.length,
          separatorBuilder: (_, _) => const Divider(
            height: 1,
            color: VibraTheme.kDivider,
            indent: 16,
            endIndent: 16,
          ),
          itemBuilder: (_, i) {
            final t = taps[i];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: VibraTheme.kSurface,
                backgroundImage: t.senderPhotoUrl != null
                    ? NetworkImage(t.senderPhotoUrl!)
                    : null,
                child: t.senderPhotoUrl == null
                    ? Text(
                        (t.senderDisplayName ?? '?').isNotEmpty
                            ? t.senderDisplayName![0].toUpperCase()
                            : '?',
                        style: const TextStyle(color: Colors.white),
                      )
                    : null,
              ),
              title: Text(
                t.senderDisplayName ?? 'Usuario',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                l10n.tipoTap(t.tapType),
                style: const TextStyle(
                  color: VibraTheme.kTextMuted,
                  fontSize: 12,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: VibraTheme.kTextMuted,
                size: 18,
              ),
              onTap: () => context.push('/profile/${t.senderId}'),
            );
          },
        );
      },
    );
  }
}
