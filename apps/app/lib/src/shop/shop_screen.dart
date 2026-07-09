import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../l10n/gen/app_localizations.dart';
import '../billing/revenuecat_providers.dart';
import '../theme/app_theme.dart';
import 'shop_service.dart';

/// /shop — In-app merchandise store for boosts, highlights, and upgrades.
///
/// Shows a grid of purchasable product cards. Tapping a card initiates the
/// RevenueCat purchase flow for that product's revenuecat_id.
class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  bool _purchasing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final productsAsync = ref.watch(shopProductsProvider);

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        title: Text(l10n.shopTitle,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: VibraTheme.kBg,
        elevation: 0,
      ),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorRetry(
          message: l10n.shopLoadError,
          onRetry: () => ref.invalidate(shopProductsProvider),
        ),
        data: (products) => products.isEmpty
            ? _EmptyState(message: l10n.shopEmpty)
            : _buildGrid(context, l10n, products),
      ),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    AppLocalizations l10n,
    List<ShopProduct> products,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: products.length,
      itemBuilder: (_, index) => _ProductCard(
        product: products[index],
        onTap: _purchasing ? null : () => _purchase(context, products[index]),
      ),
    );
  }

  Future<void> _purchase(BuildContext context, ShopProduct product) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    // Show a confirmation dialog before proceeding.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VibraTheme.kSurface,
        title: Text(product.name,
            style: const TextStyle(color: Colors.white)),
        content: Text(
          l10n.shopConfirmPurchase(product.name, '\$${product.priceUsd.toStringAsFixed(2)}'),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancelar,
                style: const TextStyle(color: VibraTheme.kTextSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.continuar,
                style: const TextStyle(color: VibraTheme.kBrandPrimary)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _purchasing = true);
    try {
      // Use RevenueCat to purchase the product by its revenuecat_id.
      final rcSvc = ref.read(revenueCatServiceProvider);
      final offerings = await rcSvc.getOfferings();
      final current = offerings?.current;
      if (current == null) {
        throw Exception('No RevenueCat offerings available');
      }

      // Find a package whose identifier matches the product's revenuecat_id.
      // where(...).firstOrNull avoids both CastError and StateError.
      final matches = current.availablePackages
          .where((p) => p.identifier == product.revenuecatId);
      final pkg = matches.isEmpty ? null : matches.first;
      if (pkg == null) {
        throw Exception(
          'No RevenueCat package found for ${product.revenuecatId}',
        );
      }

      await rcSvc.purchasePackage(pkg);
      ref.invalidate(customerInfoProvider);

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.shopPurchaseSuccess(product.name)),
          backgroundColor: VibraTheme.kAccentPulse,
        ),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      // User cancellation is not an error worth shouting about.
      if (e.code != 'purchaseCancelledError') {
        messenger.showSnackBar(
          SnackBar(
            content: Text('${l10n.shopPurchaseError}: ${e.message ?? e.code}'),
            backgroundColor: VibraTheme.kError,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('${l10n.shopPurchaseError}: $e'),
          backgroundColor: VibraTheme.kError,
        ),
      );
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Product card
// ---------------------------------------------------------------------------

class _ProductCard extends StatelessWidget {
  final ShopProduct product;
  final VoidCallback? onTap;

  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: VibraTheme.kSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: VibraTheme.kDivider, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _badgeColor(product.productType),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _badgeLabel(product.productType),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                // Name
                Text(
                  product.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // Description (if present)
                if (product.description != null)
                  Text(
                    product.description!,
                    style: const TextStyle(
                      color: VibraTheme.kTextSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 8),
                // Price
                Text(
                  '\$${product.priceUsd.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: VibraTheme.kBrandPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _badgeColor(String type) {
    switch (type) {
      case 'boost':
        return VibraTheme.kAccentPulse;
      case 'highlight':
        return VibraTheme.kBrandPrimary;
      case 'tribe_slot':
        return VibraTheme.kOnline;
      default:
        return VibraTheme.kTextSecondary;
    }
  }

  String _badgeLabel(String type) {
    switch (type) {
      case 'boost':
        return 'BOOST';
      case 'highlight':
        return 'HIGHLIGHT';
      case 'tribe_slot':
        return 'TRIBE';
      default:
        return type.toUpperCase();
    }
  }
}

// ---------------------------------------------------------------------------
// Error / Empty states
// ---------------------------------------------------------------------------

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: VibraTheme.kBrandPrimary,
            ),
            child: const Text('Retry', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style:
            const TextStyle(color: VibraTheme.kTextSecondary, fontSize: 16),
      ),
    );
  }
}
