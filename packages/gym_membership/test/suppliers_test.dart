import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/src/data/gym_repository.dart' show gymVenueType;
import 'package:gym_membership/src/data/suppliers.dart';
import 'package:gym_membership/src/screens/supplier_screens.dart';
import 'package:health_pro_core/health_pro_core.dart';

// Suppliers: items from systems connected to Health Pro, shown only (the
// gym's own inventory was taken out).

final gym = Venue.fromJson({
  'id': 'g1',
  'type': gymVenueType,
  'name': 'Peak Fitness',
  'dzongkhag': 'Thimphu',
  'verification_status': 'verified',
  'created_at': '2026-11-01T00:00:00Z',
});

final testStore = Supplier(key: 'test-store', name: 'Test supplier', website: Uri.parse('https://dummyjson.com'));

List<Override> staff({String role = VenueRole.owner, Set<String> permissions = const {}}) => [
      venueAccessProvider.overrideWith((ref, id) async => VenueAccess(gym, role, permissions: permissions)),
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

void main() {
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

  testWidgets('suppliers: their items and stock, bought in their own system', (tester) async {
    await show(tester, const SuppliersScreen(venueId: 'g1'), staff());
    for (final text in ['American Football', 'USD 19.99', '53 in stock', 'Low stock · 2', 'Visit their website']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.text('View in Test supplier'), findsNWidgets(2));
    expect(find.textContaining('ordering and payment happen in their system'), findsOneWidget);
  });

  testWidgets("the page's buttons are under the top bar, not in it", (tester) async {
    final bar = find.byType(GlassAppBar);
    await show(tester, const SuppliersScreen(venueId: 'g1'), staff());
    expect(find.descendant(of: bar, matching: find.byTooltip('Latest stock')), findsNothing);
    expect(find.byTooltip('Latest stock'), findsOneWidget, reason: 'beside the search');
  });

  testWidgets('desk staff without Suppliers are kept out', (tester) async {
    await show(tester, const SuppliersScreen(venueId: 'g1'), staff(role: VenueRole.staff, permissions: const {'gym.check_in'}));
    expect(find.text('American Football'), findsNothing);
  });
}
