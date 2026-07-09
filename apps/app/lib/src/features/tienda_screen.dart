import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/gen/app_localizations.dart';
import '../billing/billing_providers.dart';
import '../billing/models.dart';
import '../billing/revenuecat_providers.dart';
import '../premium/premium_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// Map of feature key → (title, subtitle). Title is localized via
/// [AppLocalizations]; subtitle is a hardcoded Spanish string for now
/// (acceptable per task brief).
final Map<String, ({String Function(AppLocalizations) title, String Function(AppLocalizations) subtitle})>
    _featureCopy = {
  'unlimited_chats': (
    title: (l) => l.chatIlimitados,
    subtitle: (_) => 'Match sin espera',
  ),
  'no_ads': (
    title: (_) => 'Sin anuncios',
    subtitle: (_) => 'Interfaz limpia',
  ),
  'see_who_viewed': (
    title: (l) => l.quienMeHaVisto,
    subtitle: (_) => 'Lista completa',
  ),
  'incognito_mode': (
    title: (l) => l.navegarIncognito,
    subtitle: (_) => 'Navega sin aparecer',
  ),
  'boost_discount': (
    title: (_) => 'Boost descuento',
    subtitle: (_) => 'Más visibilidad por menos',
  ),
  'unlimited_profiles': (
    title: (l) => l.perfilesIlimitados,
    subtitle: (_) => 'Sin restricciones',
  ),
};

/// /tienda — user-facing shop screen.
///
/// Shows a segmented tier switcher (Pulse / Aura), hero block, horizontal
/// duration cards, feature list, summary line and a Continue CTA. If the user
/// already has an active subscription, a yellow banner is shown and the
/// Continue button is disabled.
class TiendaScreen extends ConsumerStatefulWidget {
  const TiendaScreen({super.key});

  @override
  ConsumerState<TiendaScreen> createState() => _TiendaScreenState();
}

class _TiendaScreenState extends ConsumerState<TiendaScreen> {
  /// Currently-selected plan code (segmented). Defaults to 'vibra_plus'.
  String _selectedPlanCode = 'vibra_plus';

  /// Currently-selected price id (within the selected plan's price list).
  String? _selectedPriceId;

  bool _purchasing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final plansAsync = ref.watch(plansProvider);
    final mySubAsync = ref.watch(mySubscriptionProvider);

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        title: Text(l10n.elijaLaActualizacion,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: VibraTheme.kBg,
        elevation: 0,
      ),
      body: plansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) =>
            _ErrorRetry(onRetry: () => ref.invalidate(plansProvider)),
        data: (plans) => _buildBody(context, l10n, plans, mySubAsync.value),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    List<Plan> plans,
    Subscription? activeSub,
  ) {
    // Determine which plans to show in the segmented control.
    final tiered = plans
        .where((p) => p.code == 'vibra_plus' || p.code == 'unlimited')
        .toList()
      ..sort((a, b) => a.tier.compareTo(b.tier));

    if (tiered.isEmpty) {
      return const Center(
        child: Text(
          'No hay planes disponibles',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    // Resolve the active plan code — fall back to first if stale.
    final activePlanCode = tiered.any((p) => p.code == _selectedPlanCode)
        ? _selectedPlanCode
        : tiered.first.code;
    final selectedPlan =
        tiered.firstWhere((p) => p.code == activePlanCode);

    // Resolve the active price id — fall back to monthly or first available.
    if (selectedPlan.prices.isEmpty) {
      // No prices — surface a graceful empty state instead of crashing.
      return _NoPricesState(onRetry: () => ref.invalidate(plansProvider));
    }

    // Compute effective priceId purely (no setState in build).
    final effectivePriceId = _selectedPriceId != null &&
            selectedPlan.prices.any((p) => p.id == _selectedPriceId)
        ? _selectedPriceId!
        : (selectedPlan.priceFor('monthly')?.id ??
            selectedPlan.prices.first.id);

    // If the resolved values differ from stored state, fix up after the frame.
    if (activePlanCode != _selectedPlanCode ||
        effectivePriceId != _selectedPriceId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedPlanCode = activePlanCode;
            _selectedPriceId = effectivePriceId;
          });
        }
      });
    }

    final selectedPrice =
        selectedPlan.prices.firstWhere((p) => p.id == effectivePriceId);

    // Find the index of the currently-selected plan for the segmented control.
    final selectedIndex =
        tiered.indexWhere((p) => p.code == activePlanCode);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Active subscription banner ─────────────────────────────
        if (activeSub != null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: VibraTheme.kBrandPrimary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: VibraTheme.kBrandPrimary, width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle,
                    color: VibraTheme.kBrandPrimary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${l10n.planActivo} — ${activeSub.planName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── Segmented plan switcher ───────────────────────────────
        VibraSegmented(
          options: tiered.map((p) => p.name).toList(),
          selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
          onChanged: (idx) => setState(() {
            _selectedPlanCode = tiered[idx].code;
            _selectedPriceId = null; // reset on plan change
          }),
        ),
        const SizedBox(height: 16),

        // ── Hero block ───────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: VibraTheme.kSurface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                selectedPlan.name,
                style: const TextStyle(
                  color: VibraTheme.kBrandPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                selectedPlan.description ?? l10n.encuentraMasMasRapido,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Duration cards (horizontal scroll) ──────────────────
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: selectedPlan.prices.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final price = selectedPlan.prices[i];
              final isSelected = price.id == effectivePriceId;
              final durationLabel = price.period == 'monthly'
                  ? l10n.mes
                  : price.period == 'yearly'
                      ? l10n.meses
                      : l10n.semana;
              // Calculate savings % if yearly vs monthly (assume 2nd = yearly
              // if present).
              String? savings;
              final monthlyPrice = selectedPlan.priceFor('monthly');
              if (price.period == 'yearly' &&
                  monthlyPrice != null &&
                  monthlyPrice.amountMinor > 0) {
                final monthlyAnnualized = monthlyPrice.amountMinor * 12;
                final savingsPct =
                    ((monthlyAnnualized - price.amountMinor) /
                            monthlyAnnualized *
                            100)
                        .round();
                if (savingsPct > 0) savings = savingsPct.toString();
              }
              return SizedBox(
                width: 140,
                child: PlanDurationCard(
                  duration: durationLabel,
                  price: price.formatted,
                  savingsPercent: savings,
                  popular: price.period == 'yearly',
                  selected: isSelected,
                  onTap: () => setState(() => _selectedPriceId = price.id),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),

        // ── Feature list ─────────────────────────────────────────
        ..._featureCopy.entries
            .where((e) => selectedPlan.features.contains(e.key))
            .map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: VibraTheme.kBrandPrimary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check,
                          size: 18, color: Colors.black),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.value.title(l10n),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            e.value.subtitle(l10n),
                            style: const TextStyle(
                              color: VibraTheme.kTextSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 24),

        // ── Summary + Continue CTA ───────────────────────────────
        Text(
          _summaryLine(l10n, selectedPrice),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 12),
        YellowPillButton(
          label: l10n.continuar,
          enabled: activeSub == null && !_purchasing,
          onPressed: _purchasing
              ? null
              : () => _purchase(context, _selectedPlanCode, selectedPrice),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.compraSimulada,
          textAlign: TextAlign.center,
          style: const TextStyle(color: VibraTheme.kTextTertiary, fontSize: 11),
        ),
      ],
    );
  }

  /// "{price}/día por {days}" — localized via `precioContinuar`.
  String _summaryLine(AppLocalizations l10n, PlanPrice price) {
    final days = price.period == 'monthly'
        ? 30
        : price.period == 'yearly'
            ? 365
            : 7;
    return l10n.precioContinuar(price.formatted, days);
  }

  Future<void> _purchase(
    BuildContext context,
    String planCode,
    PlanPrice price,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _purchasing = true);
    try {
      if (kDebugMode) {
        // ── Dev / testing path ────────────────────────────────────
        // Use the backend simulate-purchase endpoint to avoid real
        // Platform Channel calls during development.
        final svc = ref.read(billingServiceProvider);
        await svc.simulatePurchase(price.id);
      } else {
        // ── Production path ────────────────────────────────────────
        // Find the matching RC package and purchase via RevenueCat.
        // The backend webhook (G7a) will update the subscriptions table.
        final rcSvc = ref.read(revenueCatServiceProvider);
        final pkg = await rcSvc.packageFor(planCode, price.period);
        if (pkg == null) {
          throw Exception(
            'No RC package found for $planCode/${price.period}',
          );
        }
        await rcSvc.purchasePackage(pkg);
        // Invalidate RC customer info so tierFeaturesFromRCProvider
        // recalculates and the UI reflects the new entitlement.
        ref.invalidate(customerInfoProvider);
      }

      ref.invalidate(mySubscriptionProvider);
      // Refresh gating status so PremiumGate / PremiumStatusBadge unlock
      // immediately after a successful purchase (no app restart needed).
      ref.invalidate(premiumStatusProvider);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.planActivo)),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Error: ${e.response?.statusCode ?? e.type}')),
      );
    } on PlatformException catch (e) {
      // RC purchase failure (including user cancellation).
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'purchaseCancelledError'
                ? 'Compra cancelada'
                : 'Error: ${e.message ?? e.code}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }
}

class _ErrorRetry extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorRetry({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Error cargando planes',
              style: TextStyle(color: Colors.white)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

class _NoPricesState extends StatelessWidget {
  final VoidCallback onRetry;
  const _NoPricesState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Sin precios disponibles',
              style: TextStyle(color: Colors.white)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}