import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

/// A stand-in service: its pages under `/<key>`, a heading over the second;
/// [setUp] false for one they only could start.
class _Service extends HealthProModule {
  @override
  final String key;
  @override
  final String name;
  final bool setUp;

  const _Service(this.key, this.name, {this.setUp = true});

  @override
  String get description => 'The $name service';
  @override
  IconData get icon => Icons.storefront_rounded;
  @override
  List<String> get basePaths => ['/$key'];

  @override
  ServiceNav? navigation(WidgetRef ref, String location) => ServiceNav(
        key: key,
        name: name,
        icon: icon,
        color: BrandColors.green,
        tagline: 'Owner',
        homeRoute: '/$key',
        isSetUp: setUp,
        sections: [
          NavSection(items: [NavDestination(label: '$name home', icon: Icons.home_rounded, route: '/$key', exact: true)]),
          NavSection(title: 'Work', items: [NavDestination(label: '$name orders', icon: Icons.list_rounded, route: '/$key/orders')]),
        ],
        actions: [ServiceAction(label: 'New $name order', icon: Icons.add_rounded, route: '/$key/orders')],
        // Its reports page keeps the shortcuts out of the bar.
        actionsInBar: location != '/$key/reports',
      );

  /// One customer, Pema Dorji, for the search in the bar.
  @override
  Future<List<SearchHit>> search(Ref ref, String query) async => [
        if (searchWords(query).every('pema dorji'.contains))
          SearchHit(
              title: 'Pema Dorji', subtitle: '$name customer', icon: Icons.person, route: '/$key/pema', group: 'Customers'),
      ];
}

/// The platform's frame with [services], a stand-in page at every path.
Future<GoRouter> showShell(WidgetTester tester, List<HealthProModule> services,
    {String at = '/home', Size size = const Size(1440, 1000), bool team = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: at,
    routes: [
      ShellRoute(
        builder: (_, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/:a', builder: (_, s) => AppPage(title: 'Page ${s.uri.path}', body: const SizedBox())),
          GoRoute(path: '/:a/:b', builder: (_, s) => AppPage(title: 'Page ${s.uri.path}', body: const SizedBox())),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('u1'),
      enabledModulesProvider.overrideWith((ref) async => services),
      myProfileProvider.overrideWith((ref) async => Profile.fromJson({'id': 'u1', 'full_name': 'Pema Dorji'})),
      myAccessProvider.overrideWith((ref) async => PlatformAccess(isSuperAdmin: team, isActive: true, permissions: const {})),
      pendingVenuesProvider.overrideWith((ref) async => const []),
      myVenuesProvider.overrideWith((ref) async => const []),
      unreadCountProvider.overrideWithValue(3),
    ],
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

Finder inMenu(String text) => find.descendant(of: find.byType(PlatformSidebar), matching: find.text(text));

bool selected(WidgetTester tester, String label) =>
    tester.widget<SideNavTile>(find.ancestor(of: inMenu(label), matching: find.byType(SideNavTile))).selected;

void main() {
  const shop = _Service('shop', 'Shop');
  const cafe = _Service('cafe', 'Cafe');

  testWidgets('the super admin: the platform, then each service, then Administration', (tester) async {
    await showShell(tester, const [shop, _Service('cafe', 'Cafe', setUp: false)], team: true);
    for (final label in ['Overview', 'Modules', 'My dashboard', 'SERVICES', 'Shop', 'Cafe', 'ADMINISTRATION']) {
      expect(inMenu(label), findsOneWidget, reason: label);
    }
    expect(selected(tester, 'Overview'), isTrue);
    expect(find.descendant(of: find.byType(PlatformSidebar), matching: find.text('Developed by Innovates', findRichText: true)),
        findsOneWidget, reason: 'the company, at the foot');
    expect(inMenu('Pema Dorji'), findsNothing, reason: 'who is signed in is at the top right');
  });

  testWidgets("anyone else: only what they've been given", (tester) async {
    await showShell(tester, const [shop, _Service('cafe', 'Cafe', setUp: false)], at: '/shop');
    for (final label in ['Overview', 'Modules']) {
      expect(inMenu(label), findsNothing, reason: "$label: the super admin's");
    }
    expect(inMenu('My dashboard'), findsOneWidget, reason: "everyone's own");
    expect(inMenu('Notifications'), findsNothing, reason: 'the bell at the top');
    expect(inMenu('Shop'), findsOneWidget, reason: 'a service they work in');
    expect(inMenu('Cafe'), findsNothing, reason: 'one they could only start');
    expect(inMenu('ADMINISTRATION'), findsNothing, reason: 'not on the team');
  });

  testWidgets('visitors get the page alone', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [currentUserIdProvider.overrideWithValue(null)],
      child: const MaterialApp(home: AppShell(location: '/home', child: Text('the page'))),
    ));
    expect(find.byType(PlatformSidebar), findsNothing);
    expect(find.text('the page'), findsOneWidget);
  });

  testWidgets('a service shows its New button only on the pages it chooses', (tester) async {
    await showShell(tester, const [shop, cafe], at: '/cafe/orders');
    expect(find.text('New'), findsOneWidget);
    await showShell(tester, const [shop, cafe], at: '/cafe/reports');
    expect(find.text('New'), findsNothing);
  });

  testWidgets("every service starts closed; opened, the page's is marked, and it follows the page", (tester) async {
    await showShell(tester, const [shop, cafe], at: '/cafe/orders');
    expect(inMenu('Cafe orders'), findsNothing, reason: 'closed until opened');
    await tester.tap(inMenu('Cafe'));
    // Its lines come in one after another.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(selected(tester, 'Cafe orders'), isTrue);
    expect(selected(tester, 'Cafe home'), isFalse, reason: 'exact: the home is only its own page');
    expect(inMenu('Shop orders'), findsNothing, reason: 'folded away, not just hidden');
    // The page knows its service: its name over the title, its shortcuts.
    expect(find.text('Cafe'), findsWidgets);
    expect(find.text('New'), findsOneWidget);

    // Once opened, going to another of its pages keeps it open.
    await tester.tap(inMenu('Cafe home'));
    await tester.pumpAndSettle();
    expect(selected(tester, 'Cafe home'), isTrue);
  });

  testWidgets('a service opens from its line, and the one open closes', (tester) async {
    await showShell(tester, const [shop, cafe], at: '/cafe');
    await tester.tap(inMenu('Shop'));
    await tester.pumpAndSettle();
    // Its groups start closed too.
    expect(inMenu('Shop orders'), findsNothing);
    await tester.tap(inMenu('Work'));
    await tester.pumpAndSettle();
    expect(inMenu('Shop orders'), findsOneWidget);
    expect(inMenu('Cafe orders'), findsNothing);
    await tester.tap(inMenu('Shop orders'));
    await tester.pumpAndSettle();
    expect(selected(tester, 'Shop orders'), isTrue);
  });

  testWidgets('twenty services stay one short list, with a box to find one', (tester) async {
    final many = [for (var i = 1; i <= 20; i++) _Service('s$i', 'Service $i')];
    await showShell(tester, many, at: '/s7/orders');
    expect(find.text('20'), findsOneWidget, reason: 'how many, by the heading');
    await tester.tap(inMenu('Service 7'));
    await tester.pumpAndSettle();
    expect(inMenu('Service 7 orders'), findsOneWidget);
    expect(find.descendant(of: find.byType(PlatformSidebar), matching: find.textContaining('orders')), findsOneWidget,
        reason: "only the open service's pages");
    await tester.enterText(find.widgetWithText(TextField, 'Find a service'), 'service 1');
    await tester.pumpAndSettle();
    expect(inMenu('Service 12'), findsOneWidget);
    expect(inMenu('Service 7'), findsNothing);
  });

  testWidgets('folded, the menu is icons; a service opens its pages beside it', (tester) async {
    await showShell(tester, const [shop, cafe], at: '/shop', team: true);
    await tester.tap(find.byTooltip('Collapse menu'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(PlatformSidebar)).width, sideMenuFoldedWidth);
    expect(inMenu('Overview'), findsNothing);
    await tester.tap(find.byTooltip('Cafe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cafe orders').last);
    await tester.pumpAndSettle();
    expect(find.text('Page /cafe/orders'), findsOneWidget);
    await tester.tap(find.byTooltip('Expand menu'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(PlatformSidebar)).width, sideMenuWidth);
  });

  testWidgets("the Health Pro team get Administration, as a section like a service's", (tester) async {
    await showShell(tester, const [shop], at: '/admin', team: true);
    expect(inMenu('ADMINISTRATION'), findsOneWidget);
    await tester.tap(inMenu('Health Pro admin'));
    await tester.pumpAndSettle();
    expect(selected(tester, 'Admin home'), isTrue);
    expect(inMenu('Users'), findsOneWidget);
  });

  testWidgets('every page in the frame ends its bar with light or dark, the bell and the account menu', (tester) async {
    for (final team in [false, true]) {
      await showShell(tester, const [shop], at: '/shop', team: team);
      final bar = find.byType(AppBar);
      final theme = find.descendant(of: bar, matching: find.byType(ThemeModeButton));
      final bell = find.descendant(of: bar, matching: find.byTooltip('Notifications, 3 unread'));
      expect(bell, findsOneWidget, reason: 'team: $team');
      expect(theme, findsOneWidget, reason: 'team: $team');
      expect(tester.getCenter(theme).dx, lessThan(tester.getCenter(bell).dx), reason: 'light or dark comes before the bell');
      await tester.tap(find.descendant(of: bar, matching: find.byTooltip('Account and settings')));
      await tester.pumpAndSettle();
      for (final item in ['Pema Dorji', 'Account', 'Sign out']) {
        expect(find.text(item), findsWidgets, reason: item);
      }
      for (final gone in ['Light', 'Dark', 'Match device']) {
        expect(find.text(gone), findsNothing, reason: '$gone: the bar has the switch');
      }
      await tester.tapAt(const Offset(700, 600));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: bar, matching: find.byTooltip('Notifications, 3 unread')));
      await tester.pumpAndSettle();
      expect(find.text('Page /notifications'), findsOneWidget, reason: 'the bell opens Notifications');
    }
  });

  testWidgets('on a phone the menu is a drawer, opened from the page bar', (tester) async {
    await showShell(tester, const [shop], at: '/shop', size: const Size(390, 844));
    expect(find.byType(PlatformSidebar), findsNothing);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(inMenu('Shop'));
    await tester.pumpAndSettle();
    await tester.tap(inMenu('Work'));
    await tester.pumpAndSettle();
    expect(inMenu('Shop orders'), findsOneWidget);
    await tester.tap(inMenu('Shop orders'));
    await tester.pumpAndSettle();
    expect(find.text('Page /shop/orders'), findsOneWidget);
    expect(find.byType(PlatformSidebar), findsNothing, reason: 'the drawer closed');
  });

  testWidgets('a page in the frame on a phone opens the menu from its bar', (tester) async {
    var opened = 0;
    await tester.pumpWidget(ProviderScope(
      // The bar's bell and account menu.
      overrides: [
        unreadCountProvider.overrideWithValue(0),
        myProfileProvider.overrideWith((ref) async => Profile.fromJson({'id': 'u1', 'full_name': 'Pema Dorji'})),
      ],
      child: MaterialApp(
        home: AppShellScope(openMenu: () => opened++, child: const AppPage(title: 'Page', body: SizedBox())),
      ),
    ));
    await tester.tap(find.byTooltip('Menu'));
    expect(opened, 1);
  });

  testWidgets('a page with somewhere to go back to keeps its back button', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AppShellScope(
        openMenu: () {},
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AppPage(title: 'Deeper', body: SizedBox())),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byTooltip('Menu'), findsNothing);
  });

  group('the search in the bar', () {
    Finder results() => find.byType(GlobalSearchDialog);
    Finder inResults(String text) => find.descendant(of: results(), matching: find.text(text, findRichText: true));

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.descendant(of: results(), matching: find.byType(TextField)), text);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    testWidgets("finds the menu's pages and shortcuts, and opens one", (tester) async {
      // Wide enough for New, Ask AI and the icons beside a centred search (the
      // test font draws every letter full width).
      await showShell(tester, const [shop, cafe], at: '/shop', size: const Size(1800, 1000));
      final box = tester.getCenter(find.byType(GlobalSearchBox)).dx;
      expect(box, closeTo(tester.getCenter(find.byType(AppBar)).dx, 1), reason: 'in the middle of the bar');
      expect(box, greaterThan(tester.getCenter(find.text('Page /shop')).dx), reason: 'after the title');
      expect(box, lessThan(tester.getCenter(find.text('New')).dx), reason: 'before New and the icons');
      await tester.tap(find.text('Search anything…'));
      await tester.pumpAndSettle();
      expect(results(), findsOneWidget);
      expect(inResults('New Shop order'), findsOneWidget, reason: 'with nothing typed, the shortcuts');
      await type(tester, 'orders');
      expect(inResults('Shop orders'), findsOneWidget);
      expect(inResults('Cafe orders'), findsOneWidget);
      expect(inResults('Users'), findsNothing);
      await tester.tap(inResults('Cafe orders'));
      await tester.pumpAndSettle();
      expect(results(), findsNothing);
      expect(find.text('Page /cafe/orders'), findsOneWidget);
    });

    testWidgets('finds what the services hold; the arrows choose and Enter opens', (tester) async {
      await showShell(tester, const [shop], at: '/shop');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(results(), findsOneWidget, reason: 'Ctrl K opens it');
      await type(tester, 'dorji');
      expect(inResults('CUSTOMERS'), findsOneWidget);
      expect(inResults('Pema Dorji'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Page /shop/pema'), findsOneWidget);

      await tester.tap(find.text('Search anything…'));
      await tester.pumpAndSettle();
      await type(tester, 'shop');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Page /shop/orders'), findsOneWidget, reason: 'the second: Shop home, then Shop orders');
    });

    testWidgets("the team find Administration's pages; nothing found says so", (tester) async {
      await showShell(tester, const [shop], at: '/shop', team: true);
      await tester.tap(find.text('Search anything…'));
      await tester.pumpAndSettle();
      await type(tester, 'roles');
      expect(inResults('Roles & permissions'), findsOneWidget);
      await type(tester, 'zzzz');
      expect(inResults('Nothing found for "zzzz"'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(results(), findsNothing, reason: 'Esc closes it');
    });

    testWidgets("anyone else doesn't find Administration's pages", (tester) async {
      await showShell(tester, const [shop], at: '/shop');
      await tester.tap(find.text('Search anything…'));
      await tester.pumpAndSettle();
      await type(tester, 'roles');
      expect(inResults('Roles & permissions'), findsNothing);
      expect(inResults('Nothing found for "roles"'), findsOneWidget);
    });

    testWidgets('on a phone it is an icon in the bar', (tester) async {
      await showShell(tester, const [shop], at: '/shop', size: const Size(390, 844));
      expect(find.text('Search anything…'), findsNothing);
      final icon = tester.getCenter(find.byTooltip('Search')).dx;
      expect(icon, greaterThan(tester.getCenter(find.byTooltip('Menu')).dx), reason: 'after the menu button');
      expect(icon, lessThan(tester.getCenter(find.text('Page /shop')).dx), reason: 'at the left, before the title');
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(results(), findsOneWidget);
    });

    test('ranks the title starting with the words first; every word has to match', () {
      SearchHit hit(String title, {String? subtitle}) =>
          SearchHit(title: title, subtitle: subtitle, icon: Icons.circle, route: '/', group: 'Pages');
      final hits = [hit('Payments & income'), hit('Payments to confirm'), hit('Income', subtitle: 'Gym'), hit('Members')];
      expect(rankHits(hits, 'income').map((h) => h.title), ['Income', 'Payments & income']);
      expect(rankHits(hits, 'income gym').map((h) => h.title), ['Income']);
      expect(rankHits(hits, 'PAY').map((h) => h.title), ['Payments & income', 'Payments to confirm']);
      expect(rankHits(hits, '   '), isEmpty);
    });

    test('pages and shortcuts keep the 3D icons the menu gives them', () {
      const nav = ServiceNav(
        key: 'gym',
        name: 'Gym',
        icon: Icons.fitness_center,
        color: BrandColors.green,
        homeRoute: '/gym',
        sections: [
          NavSection(items: [NavDestination(label: 'Members', icon: Icons.groups, art: Art3D.person, route: '/gym/members')]),
        ],
        actions: [ServiceAction(label: 'Check in', icon: Icons.qr_code, art: Art3D.checkMark, route: '/gym/check-in')],
      );
      final hits = {for (final h in searchablePages(platformPages: true, services: [nav])) h.title: h.art};
      expect(hits['Members'], Art3D.person);
      expect(hits['Check in'], Art3D.checkMark);
      expect(hits['Overview'], Art3D.house);
      expect(hits['Notifications'], Art3D.bell);
    });
  });

  test('a page is open at its route, under it, but not under what it excludes', () {
    const members = NavDestination(label: 'Members', icon: Icons.groups, route: '/g/members', notUnder: ['/g/members/new']);
    expect(members.isOpenAt('/g/members'), isTrue);
    expect(members.isOpenAt('/g/members/abc'), isTrue);
    expect(members.isOpenAt('/g/members/new'), isFalse);
    expect(members.isOpenAt('/g/membership'), isFalse);
    const staff = NavDestination(label: 'Staff', icon: Icons.badge, route: '/manage/g/staff', alsoUnder: ['/g/staff']);
    expect(staff.isOpenAt('/g/staff/x'), isTrue);
  });
}
