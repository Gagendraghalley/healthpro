import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A gym's inventory (20261118000009_gym_inventory.sql): what it keeps and
/// how many, for its owner and managers ('gym.inventory'); and the suppliers
/// connected to Health Pro, whose items and stock are only shown here. Buying
/// happens in the supplier's own system.

/// Why a count changed (gym_inventory_moves.reason).
enum StockReason {
  opening('opening', 'Opening count'),
  stockIn('stock_in', 'Stock in'),
  used('used', 'Used'),
  sold('sold', 'Sold'),
  damaged('damaged', 'Damaged or lost'),
  recount('recount', 'Recount');

  const StockReason(this.value, this.label);
  final String value;
  final String label;

  /// What staff choose when stock goes out.
  static const out = [used, sold, damaged];

  bool get takesAway => out.contains(this);

  static StockReason from(String value) =>
      StockReason.values.firstWhere((r) => r.value == value, orElse: () => StockReason.recount);
}

enum StockLevel { ok, low, out }

class InventoryItem {
  final String id;
  final String venueId;
  final String name;
  final String? category;
  final String unit;
  final int quantity;

  /// Low stock at or below this; 0 for only when it runs out.
  final int reorderLevel;

  /// What one cost the gym, in Ngultrum; null when not given.
  final int? unitCost;
  final String? notes;
  final DateTime updatedAt;

  const InventoryItem({
    required this.id,
    required this.venueId,
    required this.name,
    this.category,
    this.unit = 'pcs',
    required this.quantity,
    this.reorderLevel = 0,
    this.unitCost,
    this.notes,
    required this.updatedAt,
  });

  StockLevel get level => quantity == 0
      ? StockLevel.out
      : quantity <= reorderLevel
          ? StockLevel.low
          : StockLevel.ok;

  /// What the count is worth, when the cost is known.
  int? get value => unitCost == null ? null : unitCost! * quantity;

  /// '12 pcs'.
  String get countText => '$quantity $unit';

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
        id: json['id'] as String,
        venueId: json['venue_id'] as String,
        name: json['name'] as String,
        category: json['category'] as String?,
        unit: (json['unit'] as String?) ?? 'pcs',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        reorderLevel: (json['reorder_level'] as num?)?.toInt() ?? 0,
        unitCost: (json['unit_cost'] as num?)?.toInt(),
        notes: json['notes'] as String?,
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}

/// What the item form saves (gym_save_inventory_item's details).
class InventoryDetails {
  final String name;
  final String? category;
  final String unit;
  final int reorderLevel;
  final int? unitCost;
  final String? notes;

  /// A new item's opening count; ignored when editing.
  final int quantity;

  const InventoryDetails({
    required this.name,
    this.category,
    this.unit = 'pcs',
    this.reorderLevel = 0,
    this.unitCost,
    this.notes,
    this.quantity = 0,
  });

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'category': _clean(category),
        'unit': _clean(unit) ?? 'pcs',
        'reorder_level': reorderLevel,
        'unit_cost': unitCost,
        'notes': _clean(notes),
        'quantity': quantity,
      };
}

/// One change to an item's count.
class StockMove {
  final String id;
  final StockReason reason;
  final int change;
  final int quantityAfter;
  final String? note;
  final String? madeBy;
  final DateTime madeAt;

  const StockMove({
    required this.id,
    required this.reason,
    required this.change,
    required this.quantityAfter,
    this.note,
    this.madeBy,
    required this.madeAt,
  });

  /// '+5', '-2'.
  String get changeText => change > 0 ? '+$change' : '$change';

  factory StockMove.fromJson(Map<String, dynamic> json) => StockMove(
        id: json['id'] as String,
        reason: StockReason.from(json['reason'] as String),
        change: (json['change'] as num).toInt(),
        quantityAfter: (json['quantity_after'] as num).toInt(),
        note: json['note'] as String?,
        madeBy: (json['by'] as Map?)?['full_name'] as String?,
        madeAt: DateTime.parse(json['made_at'] as String),
      );
}

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

/// Items at a glance: how many, how many low or out, what they're worth.
({int items, int low, int out, int? value}) inventorySummary(List<InventoryItem> items) {
  var low = 0, out = 0, value = 0;
  var priced = false;
  for (final i in items) {
    if (i.level == StockLevel.low) low++;
    if (i.level == StockLevel.out) out++;
    if (i.value != null) {
      priced = true;
      value += i.value!;
    }
  }
  return (items: items.length, low: low, out: out, value: priced ? value : null);
}

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) => InventoryRepository(ref.watch(supabaseProvider)));

final gymInventoryProvider = FutureProvider.family<List<InventoryItem>, String>(
  (ref, venueId) => ref.watch(inventoryRepositoryProvider).items(venueId),
);

final inventoryMovesProvider = FutureProvider.autoDispose.family<List<StockMove>, String>(
  (ref, itemId) => ref.watch(inventoryRepositoryProvider).moves(itemId),
);

/// The suppliers connected to Health Pro.
final connectedSuppliersProvider = FutureProvider.autoDispose<List<Supplier>>(
  (ref) => ref.watch(inventoryRepositoryProvider).suppliers(),
);

final supplierCatalogProvider =
    FutureProvider.autoDispose.family<SupplierCatalog, ({String venueId, String? supplier, String query})>(
  (ref, q) => ref.watch(inventoryRepositoryProvider).catalog(q.venueId, supplier: q.supplier, query: q.query),
);

class InventoryRepository {
  final SupabaseClient _client;

  InventoryRepository(this._client);

  Future<List<InventoryItem>> items(String venueId) async {
    final rows = await _client.from('gym_inventory_items').select().eq('venue_id', venueId).order('name');
    return [for (final r in rows) InventoryItem.fromJson(r)];
  }

  /// The latest 50 changes to [itemId]'s count, newest first.
  Future<List<StockMove>> moves(String itemId) async {
    final rows = await _client
        .from('gym_inventory_moves')
        .select('*, by:profiles!gym_inventory_moves_made_by_fkey(full_name)')
        .eq('item_id', itemId)
        .order('made_at', ascending: false)
        .limit(50);
    return [for (final r in rows) StockMove.fromJson(r)];
  }

  /// Adds an item ([itemId] null) or changes one's details. Returns its id.
  Future<String> saveItem(String venueId, String? itemId, InventoryDetails details) async =>
      await _client.rpc('gym_save_inventory_item', params: {
        'venue_id': venueId,
        'item_id': itemId,
        'details': details.toJson(),
      }) as String;

  /// Stock in, out ([StockReason.out]) or a recount to [amount]. Returns the
  /// new count.
  Future<int> moveStock(String itemId, StockReason reason, int amount, {String? note}) async =>
      ((await _client.rpc('gym_move_stock', params: {
        'item_id': itemId,
        'reason': reason.value,
        'amount': amount,
        'note': _clean(note),
      })) as num)
          .toInt();

  Future<void> deleteItem(String itemId) => _client.rpc('gym_delete_inventory_item', params: {'item_id': itemId});

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

String? _clean(String? value) => (value == null || value.trim().isEmpty) ? null : value.trim();
