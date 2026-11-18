import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/src/data/gym_repository.dart' show gymVenueType;
import 'package:gym_membership/src/data/inventory.dart';
import 'package:gym_membership/src/screens/inventory_screens.dart';
import 'package:health_pro_core/health_pro_core.dart';

final gym = Venue.fromJson({
  'id': 'g1',
  'type': gymVenueType,
  'name': 'Peak Fitness',
  'dzongkhag': 'Thimphu',
  'verification_status': 'verified',
  'created_at': '2026-11-01T00:00:00Z',
});

final testStore = Supplier(key: 'test-store', name: 'Test supplier', website: Uri.parse('https://dummyjson.com'));

final stock = [
  InventoryItem(
      id: 'mat', venueId: 'g1', name: 'Yoga mat', category: 'Equipment', quantity: 12, reorderLevel: 4, unitCost: 800,
      updatedAt: DateTime(2026, 11, 18)),
  InventoryItem(
      id: 'whey', venueId: 'g1', name: 'Whey protein', category: 'Supplements', unit: 'tubs', quantity: 2, reorderLevel: 3,
      updatedAt: DateTime(2026, 11, 18)),
  InventoryItem(id: 'towel', venueId: 'g1', name: 'Towel', quantity: 0, updatedAt: DateTime(2026, 11, 18)),
];

List<Override> staff({String role = VenueRole.owner, Set<String> permissions = const {}}) => [
      venueAccessProvider.overrideWith((ref, id) async => VenueAccess(gym, role, permissions: permissions)),
      gymInventoryProvider.overrideWith((ref, id) async => stock),
      connectedSuppliersProvider.overrideWith((ref) async => [testStore]),
      supplierCatalogProvider.overrideWith((ref, q) async => SupplierCatalog(
            suppliers: [testStore],
            supplier: testStore,
            total: 2,
            items: [
              SupplierItem(
                  id: '137', name: 'American Football', price: 19.99, currency: 'USD', stock: 53,
                  url: Uri.parse('https://dummyjson.com/products/137')),
              SupplierItem(
                  id: '140', name: 'Basketball Rim', price: 39.99, currency: 'USD', stock: 2,
                  url: Uri.parse('https://dummyjson.com/products/140')),
            ],
          )),
      unreadCountProvider.overrideWithValue(0),
    ];

Future<void> show(WidgetTester tester, Widget page, List<Override> overrides, {Size size = const Size(1440, 1000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(theme: AppTheme.light, home: page),
  ));
  await tester.pumpAndSettle();
}

InventoryItem item(int quantity, {int reorder = 0, int? cost, String? category}) => InventoryItem(
      id: 'i$quantity',
      venueId: 'g',
      name: 'Item $quantity',
      category: category,
      quantity: quantity,
      reorderLevel: reorder,
      unitCost: cost,
      updatedAt: DateTime(2026, 11, 18),
    );

void main() {
  test('an item is low at or below its reorder level, out at none', () {
    expect(item(10, reorder: 3).level, StockLevel.ok);
    expect(item(3, reorder: 3).level, StockLevel.low);
    expect(item(0, reorder: 3).level, StockLevel.out);
    expect(item(1).level, StockLevel.ok, reason: 'no reorder level: only out counts');
  });

  test('items read from the database, and what the form saves', () {
    final i = InventoryItem.fromJson({
      'id': 'a',
      'venue_id': 'g',
      'name': 'Yoga mat',
      'category': 'Equipment',
      'unit': 'pcs',
      'quantity': 12,
      'reorder_level': 4,
      'unit_cost': 800,
      'notes': null,
      'updated_at': '2026-11-18T03:00:00Z',
    });
    expect(i.countText, '12 pcs');
    expect(i.value, 9600);
    expect(
      const InventoryDetails(name: ' Towel ', category: ' ', unit: '', notes: '', quantity: 5).toJson(),
      {'name': 'Towel', 'category': null, 'unit': 'pcs', 'reorder_level': 0, 'unit_cost': null, 'notes': null, 'quantity': 5},
    );
  });

  test('the summary counts low and out, and values only priced items', () {
    final s = inventorySummary([item(10, reorder: 3, cost: 100), item(2, reorder: 3), item(0, cost: 50)]);
    expect((s.items, s.low, s.out, s.value), (3, 1, 1, 1000));
    expect(inventorySummary([item(1)]).value, isNull);
  });

  test('a history line shows who and how it changed', () {
    final m = StockMove.fromJson({
      'id': 'm',
      'reason': 'damaged',
      'change': -2,
      'quantity_after': 8,
      'note': 'Torn',
      'by': {'full_name': 'Mani Manager'},
      'made_at': '2026-11-18T03:00:00Z',
    });
    expect((m.reason, m.changeText, m.madeBy), (StockReason.damaged, '-2', 'Mani Manager'));
    expect(StockReason.from('stock_in').takesAway, isFalse);
    expect(StockReason.out.every((r) => r.takesAway), isTrue);
  });

  test("a supplier's catalogue, its stock and prices", () {
    final c = SupplierCatalog.fromJson({
      'suppliers': [
        {'key': 'test-store', 'name': 'Test supplier', 'description': null, 'website_url': 'https://dummyjson.com'},
      ],
      'supplier': 'test-store',
      'items': [
        {'id': '137', 'name': 'Football', 'price': 19.99, 'currency': 'USD', 'stock': 53, 'url': 'https://dummyjson.com/products/137'},
        {'id': '2', 'name': 'Gloves', 'price': 1200, 'currency': 'BTN', 'stock': 3, 'url': 'https://s.bt/2'},
        {'id': '3', 'name': 'Rope', 'stock': 0, 'availability': 'Out of Stock', 'url': 'https://s.bt/3'},
        {'id': '4', 'name': 'Band', 'price': 20, 'currency': 'USD', 'url': 'https://s.bt/4'},
      ],
      'total': 4,
    });
    expect(c.supplier?.name, 'Test supplier');
    expect(c.items.map((i) => i.level), [StockLevel.ok, StockLevel.low, StockLevel.out, null]);
    expect(c.items.map((i) => i.priceText), ['USD 19.99', 'Nu. 1,200', null, 'USD 20']);
    expect(c.items.first.url.toString(), 'https://dummyjson.com/products/137');
  });

  test("when the supplier isn't answering, the reason comes back with the suppliers", () {
    final c = SupplierCatalog.fromJson({
      'suppliers': [
        {'key': 's', 'name': 'S', 'website_url': 'https://s.bt'},
      ],
      'supplier': 's',
      'error': "S isn't answering just now.",
    });
    expect(c.items, isEmpty);
    expect((c.error, c.supplier?.website.host), ("S isn't answering just now.", 's.bt'));
  });

  testWidgets('stock chips say how much is left', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: Column(children: [
          StockChip(level: StockLevel.ok, count: 53),
          StockChip(level: StockLevel.low, count: 3),
          StockChip(level: StockLevel.out),
          StockChip(level: StockLevel.ok),
        ]),
      ),
    ));
    for (final label in ['53 in stock', 'Low stock · 3', 'Out of stock', 'In stock']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets("the gym's inventory: counts, what's low, a way to suppliers", (tester) async {
    await show(tester, const GymInventoryScreen(venueId: 'g1'), staff());
    for (final text in ['Yoga mat', 'Whey protein', 'Towel', 'Nu. 9,600', 'Low or out (2)', 'Browse suppliers']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.text('Out of stock'), findsWidgets);
    expect(find.text('Open'), findsNWidgets(3), reason: 'a table: each item opens from its Action column');
    // Moving stock is in the menu beside Open.
    await tester.tap(find.byTooltip('More').last);
    await tester.pumpAndSettle();
    final takeOut = find.ancestor(of: find.text('Take out'), matching: find.byWidgetPredicate((w) => w is PopupMenuItem));
    expect(tester.widget<PopupMenuItem>(takeOut).enabled, isFalse, reason: 'nothing to take out of an empty item');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Low or out (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Yoga mat'), findsNothing);
    expect(find.text('Whey protein'), findsOneWidget);

    await tester.tap(find.byTooltip('More').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stock in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'How many *'), '5');
    await tester.pumpAndSettle();
    expect(find.text('2 → 7 tubs'), findsOneWidget, reason: 'what the count will be');
  });

  testWidgets('the inventory fits a phone', (tester) async {
    await show(tester, const GymInventoryScreen(venueId: 'g1'), staff(), size: const Size(390, 844));
    expect(tester.takeException(), isNull);
    expect(find.text('Suppliers'), findsOneWidget);
    expect(find.text('Add item'), findsOneWidget);
  });

  testWidgets("the page's buttons are under the top bar, not in it", (tester) async {
    final bar = find.byType(GlassAppBar);
    await show(tester, const GymInventoryScreen(venueId: 'g1'), staff());
    for (final button in ['Add item', 'Suppliers']) {
      expect(find.descendant(of: bar, matching: find.text(button)), findsNothing, reason: button);
      expect(find.text(button), findsOneWidget, reason: '$button: on the page');
    }
    await show(tester, const SuppliersScreen(venueId: 'g1'), staff());
    expect(find.descendant(of: bar, matching: find.byTooltip('Latest stock')), findsNothing);
    expect(find.byTooltip('Latest stock'), findsOneWidget, reason: 'beside the search');
  });

  testWidgets('suppliers: their items and stock, bought in their own system', (tester) async {
    await show(tester, const SuppliersScreen(venueId: 'g1'), staff());
    for (final text in ['American Football', 'USD 19.99', '53 in stock', 'Low stock · 2', 'Visit their website']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.text('View in Test supplier'), findsNWidgets(2));
    expect(find.textContaining('ordering and payment happen in their system'), findsOneWidget);
  });

  testWidgets('desk staff without Inventory are kept out', (tester) async {
    await show(tester, const GymInventoryScreen(venueId: 'g1'),
        staff(role: VenueRole.staff, permissions: const {'gym.check_in'}));
    expect(find.text('Yoga mat'), findsNothing);
  });
}
