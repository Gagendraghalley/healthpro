import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The suppliers connected to Health Pro (20261118000009_gym_inventory.sql),
/// whose items, stock and prices the gym's owner and managers see
/// ('gym.inventory', called Suppliers). Shown only: buying happens in the
/// supplier's own system.

/// How much a supplier has of an item.
enum StockLevel { ok, low, out }

/// A system connected to Health Pro whose items are shown here.
class Supplier {
  final String key;
  final String name;
  final String? description;
  final Uri website;

  const Supplier({required this.key, required this.name, this.description, required this.website});

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
        key: json['key'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        website: Uri.parse(json['website_url'] as String),
      );
}

/// An item in a supplier's system, with its stock there now.
class SupplierItem {
  final String id;
  final String name;
  final String? description;
  final String? category;
  final String? brand;
  final num? price;
  final String? currency;

  /// How many the supplier has; null when they don't say.
  final int? stock;

  /// The supplier's own words for it ('Low Stock'), when they give them.
  final String? availability;
  final String? image;

  /// The item in the supplier's system, where it's bought.
  final Uri url;

  const SupplierItem({
    required this.id,
    required this.name,
    this.description,
    this.category,
    this.brand,
    this.price,
    this.currency,
    this.stock,
    this.availability,
    this.image,
    required this.url,
  });

  StockLevel? get level {
    if (stock == 0 || (availability?.toLowerCase().contains('out of stock') ?? false)) return StockLevel.out;
    if (availability?.toLowerCase().contains('low') ?? false) return StockLevel.low;
    if (stock != null && stock! <= 5) return StockLevel.low;
    return stock == null && availability == null ? null : StockLevel.ok;
  }

  /// 'Nu. 1,200', 'USD 19.99'; null when they show no price.
  String? get priceText {
    final p = price;
    if (p == null) return null;
    if (currency == null || currency == 'BTN' || currency == 'Nu') return formatNu(p);
    return '$currency ${p == p.roundToDouble() ? p.toInt() : p.toStringAsFixed(2)}';
  }

  factory SupplierItem.fromJson(Map<String, dynamic> json) => SupplierItem(
        id: '${json['id']}',
        name: json['name'] as String,
        description: json['description'] as String?,
        category: json['category'] as String?,
        brand: json['brand'] as String?,
        price: json['price'] as num?,
        currency: json['currency'] as String?,
        stock: (json['stock'] as num?)?.toInt(),
        availability: json['availability'] as String?,
        image: json['image'] as String?,
        url: Uri.parse(json['url'] as String),
      );
}

/// What the supplier-catalog Edge Function answers: the connected suppliers,
/// the one shown, its items (or why they couldn't be read).
class SupplierCatalog {
  final List<Supplier> suppliers;
  final Supplier? supplier;
  final List<SupplierItem> items;
  final int total;
  final String? error;

  const SupplierCatalog({this.suppliers = const [], this.supplier, this.items = const [], this.total = 0, this.error});

  factory SupplierCatalog.fromJson(Map<String, dynamic> json) {
    final suppliers = [
      for (final s in (json['suppliers'] as List? ?? const [])) Supplier.fromJson((s as Map).cast<String, dynamic>()),
    ];
    final key = json['supplier'] as String?;
    return SupplierCatalog(
      suppliers: suppliers,
      supplier: suppliers.where((s) => s.key == key).firstOrNull ?? suppliers.firstOrNull,
      items: [for (final i in (json['items'] as List? ?? const [])) SupplierItem.fromJson((i as Map).cast<String, dynamic>())],
      total: (json['total'] as num?)?.toInt() ?? 0,
      error: json['error'] as String?,
    );
  }
}

final supplierRepositoryProvider = Provider<SupplierRepository>((ref) => SupplierRepository(ref.watch(supabaseProvider)));

/// The suppliers connected to Health Pro.
final connectedSuppliersProvider = FutureProvider.autoDispose<List<Supplier>>(
  (ref) => ref.watch(supplierRepositoryProvider).suppliers(),
);

final supplierCatalogProvider =
    FutureProvider.autoDispose.family<SupplierCatalog, ({String venueId, String? supplier, String query})>(
  (ref, q) => ref.watch(supplierRepositoryProvider).catalog(q.venueId, supplier: q.supplier, query: q.query),
);

class SupplierRepository {
  final SupabaseClient _client;

  SupplierRepository(this._client);


  Future<List<Supplier>> suppliers() async {
    final rows = await _client
        .from('inventory_suppliers')
        .select('key, name, description, website_url')
        .eq('is_active', true)
        .order('sort_order')
        .order('name');
    return [for (final r in rows) Supplier.fromJson(r)];
  }

  /// The connected suppliers and [supplier]'s items (the first one's when
  /// null) matching [query], live from their system. When it isn't answering,
  /// the suppliers still come back, with the [SupplierCatalog.error].
  Future<SupplierCatalog> catalog(String venueId, {String? supplier, String query = ''}) async {
    try {
      final response = await _client.functions.invoke('supplier-catalog', body: {
        'venue_id': venueId,
        if (supplier != null) 'supplier': supplier,
        if (query.trim().isNotEmpty) 'query': query.trim(),
      });
      return SupplierCatalog.fromJson((response.data as Map).cast<String, dynamic>());
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map && details['suppliers'] is List) return SupplierCatalog.fromJson(details.cast<String, dynamic>());
      final message = details is Map ? details['error'] as String? : null;
      if (message != null) throw StateError(message);
      rethrow;
    }
  }
}
