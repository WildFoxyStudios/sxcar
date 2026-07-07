import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// A purchasable product from the in-app merchandise store.
class ShopProduct {
  final String id;
  final String name;
  final String? description;
  final double priceUsd;
  final String productType;
  final String revenuecatId;

  const ShopProduct({
    required this.id,
    required this.name,
    this.description,
    required this.priceUsd,
    required this.productType,
    required this.revenuecatId,
  });

  factory ShopProduct.fromJson(Map<String, dynamic> json) {
    return ShopProduct(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      priceUsd: (json['price_usd'] as num).toDouble(),
      productType: json['type'] as String,
      revenuecatId: json['revenuecat_id'] as String,
    );
  }
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// HTTP client for the /shop/* endpoints.
class ShopService {
  final Dio _dio;
  ShopService(this._dio);

  /// GET /shop/products — returns the static product catalog.
  Future<List<ShopProduct>> listProducts() async {
    final response = await _dio.get<Map<String, dynamic>>('/shop/products');
    final data = response.data!;
    final products = (data['products'] as List<dynamic>?) ?? const [];
    return products
        .map((e) => ShopProduct.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final shopServiceProvider = Provider<ShopService>((ref) {
  final dio = ref.watch(dioProvider);
  return ShopService(dio);
});

final shopProductsProvider = FutureProvider<List<ShopProduct>>((ref) async {
  final service = ref.watch(shopServiceProvider);
  return service.listProducts();
});
