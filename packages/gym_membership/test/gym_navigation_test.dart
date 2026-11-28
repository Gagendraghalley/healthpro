import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:health_pro_core/health_pro_core.dart';

const gymId = '0f8e3a1c-2b4d-4e5f-8a9b-0c1d2e3f4a5b';
const otherId = '1f8e3a1c-2b4d-4e5f-8a9b-0c1d2e3f4a5c';

Venue venue(String id, String name) => Venue.fromJson({
      'id': id,
      'type': 'gym',
      'name': name,
      'dzongkhag': 'Thimphu',
      'verification_status': 'verified',
      'created_at': '2026-11-01T00:00:00Z',
    });

/// Who is signed in: the gyms they run (role and its permissions) and
/// whether they're on the Health Pro team.
List<Override> person({List<MyVenue> gyms = const [], bool team = false}) => [
      currentUserIdProvider.overrideWithValue('u1'),
      myProfileProvider.overrideWith((ref) async => Profile.fromJson({'id': 'u1', 'full_name': 'Gagendra Ghalley'})),
      myAccessProvider.overrideWith((ref) async => PlatformAccess(isSuperAdmin: team, isActive: true, permissions: const {})),
      myVenuesProvider.overrideWith((ref) async => gyms),
      enabledModulesProvider.overrideWith((ref) async => const [GymModule()]),
      pendingVenuesProvider.overrideWith((ref) async => const []),
      unreadCountProvider.overrideWithValue(2),
    ];

final owner = [MyVenue(venue(gymId, 'Druk Fitness Club'), VenueRole.owner), MyVenue(venue(otherId, 'Paro Power Gym'), VenueRole.owner)];
final frontDesk = [
  MyVenue(venue(gymId, 'Druk Fitness Club'), VenueRole.staff,
      roleName: 'Front desk',
      permissions: const {
        GymPermission.register,
        GymPermission.members,
        GymPermission.payments,
        GymPermission.checkIn,
        GymPermission.classes,
      }),
];

/// The platform's frame (the gym is one service in it) with a stand-in for
/// each page.
Future<GoRouter> showApp(WidgetTester tester, Size size, List<Override> who,
    {bool dark = false, String at = '/gyms/$gymId/manage', bool withNewMenu = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // [withNewMenu]: each page offers the gym's New menu under the bar, as
  // Members and Check-in do.
  Widget page(String name) => AppPage(
        title: name,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Page: $name'),
            if (withNewMenu) Builder(builder: (context) => ServiceActionsButton.onPage(context) ?? const SizedBox()),
          ]),
        ),
      );
  final router = GoRouter(
    initialLocation: at,
    routes: [
      ShellRoute(
        builder: (_, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          for (final (path, name) in [
            (CoreRoutes.home, 'Overview'),
            (CoreRoutes.services, 'Modules'),
            (CoreRoutes.account, 'Account'),
            (CoreRoutes.notifications, 'Notifications'),
            (CoreRoutes.admin, 'Admin'),
            (CoreRoutes.registerVenue, 'Register a venue'),
            (CoreRoutes.registerVenueForm, 'Register a gym'),
            (CoreRoutes.venueStaff, 'Staff'),
            (CoreRoutes.venueRoles, 'Roles'),
            (CoreRoutes.editVenue, 'Gym settings'),
            (GymRoutes.dashboard, 'Dashboard'),
            (GymRoutes.checkIn, 'Check-in'),
            (GymRoutes.members, 'Members'),
            (GymRoutes.registerMember, 'Register member'),
            (GymRoutes.plans, 'Packages'),
            (GymRoutes.income, 'Income'),
            (GymRoutes.reports, 'Reports'),
            (GymRoutes.suppliers, 'Suppliers'),
          ])
            GoRoute(path: path, builder: (_, __) => page(name)),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: who,
    child: MaterialApp.router(theme: dark ? AppTheme.dark : AppTheme.light, routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

Finder inMenu(String label) => find.descendant(of: find.byType(PlatformSidebar), matching: find.text(label));

/// The gym's section starts closed: open it from its line.
Future<void> openGym(WidgetTester tester) async {
  await tester.tap(inMenu('Gym management'));
  await tester.pumpAndSettle();
}

/// A group of the gym's pages ('Requests') starts closed: open it from its
/// heading.
Future<void> openGroup(WidgetTester tester, String heading) async {
  await tester.ensureVisible(inMenu(heading));
  await tester.pumpAndSettle();
  await tester.tap(inMenu(heading));
  await tester.pumpAndSettle();
}

/// The count on a group's heading while it's closed.
Finder groupBadge(String heading, int count) => find.descendant(
    of: find.ancestor(of: inMenu(heading), matching: find.byType(InkWell)).first, matching: find.text('$count'));

bool selected(WidgetTester tester, String label) =>
    tester.widget<SideNavTile>(find.ancestor(of: inMenu(label), matching: find.byType(SideNavTile))).selected;

void main() {
  const computer = Size(1440, 1000);
  const phone = Size(390, 844);

  testWidgets("an owner's menu: Gym management with their gym and its pages, grouped", (tester) async {
    final router = await showApp(tester, computer, person(gyms: owner));
    await openGym(tester);
    for (final label in ['Gym management', 'Druk Fitness Club']) {
      expect(inMenu(label), findsOneWidget, reason: label);
    }
    for (final label in ['Overview', 'Modules']) {
      expect(inMenu(label), findsNothing, reason: "$label: the super admin's");
    }
    expect(inMenu('My dashboard'), findsOneWidget, reason: "everyone's own: their QR code and their gyms");
    expect(inMenu('My services'), findsOneWidget, reason: "every service they've joined, in full");
    for (final label in ['My QR code', 'My gyms', 'Notifications']) {
      expect(inMenu(label), findsNothing, reason: '$label: on the dashboard, or the bell at the top');
    }
    // On the dashboard every group is closed under its heading until opened.
    for (final label in ['Dashboard', 'Reports & analytics']) {
      expect(inMenu(label), findsOneWidget, reason: label);
    }
    final groups = {
      'Front desk': ['Check-in', 'Members', 'Register member', 'Gym QR code'],
      'Requests': ['Join requests', 'Payments to confirm'],
      'Training': ['Classes', 'Trainers'],
      'Sales & money': ['Memberships & packages', 'Payments & income'],
      'Stock': ['Suppliers'],
      'Team & settings': ['Staff', 'Roles & permissions', 'Gym settings'],
    };
    // One open at a time, as with the services: opening one closes the last.
    var (previous, previousPage) = ('', '');
    for (final MapEntry(key: heading, value: pages) in groups.entries) {
      expect(inMenu(pages.first), findsNothing, reason: '$heading: closed');
      await openGroup(tester, heading);
      for (final label in pages) {
        expect(inMenu(label), findsOneWidget, reason: '$heading: $label');
      }
      if (previous.isNotEmpty) expect(inMenu(previousPage), findsNothing, reason: 'opening $heading closes $previous');
      (previous, previousPage) = (heading, pages.first);
    }
    // Closed by hand, none is open.
    await tester.tap(inMenu(previous));
    await tester.pumpAndSettle();
    expect(inMenu(previousPage), findsNothing, reason: '$previous: closed again');
    expect(inMenu('Check-in'), findsNothing);
    await openGroup(tester, 'Front desk');
    expect(inMenu('ADMINISTRATION'), findsNothing);
    expect(selected(tester, 'Dashboard'), isTrue);

    await tester.tap(inMenu('Members'));
    await tester.pumpAndSettle();
    expect(find.text('Page: Members'), findsOneWidget);
    expect(selected(tester, 'Members'), isTrue);
    expect(selected(tester, 'Dashboard'), isFalse);
    expect(router.routerDelegate.currentConfiguration.uri.path, GymRoutes.membersFor(gymId));
    // The page says whose it is: the gym's name, over its title.
    expect(find.text('Gym management · Druk Fitness Club'), findsNothing);
    expect(find.text('DRUK FITNESS CLUB'), findsOneWidget);
    expect(find.byTooltip('Menu'), findsNothing);

    // Still open on a page without the Ask AI button (the register form).
    await tester.tap(inMenu('Register member'));
    await tester.pumpAndSettle();
    expect(selected(tester, 'Register member'), isTrue);
    await tester.tap(inMenu('Check-in'));
    await tester.pumpAndSettle();
    expect(selected(tester, 'Check-in'), isTrue);
  });

  testWidgets("the core's pages for the gym (Staff, Gym settings) are the gym's in the menu", (tester) async {
    await showApp(tester, computer, person(gyms: owner), at: CoreRoutes.venueStaffFor(otherId));
    await openGym(tester);
    expect(selected(tester, 'Staff'), isTrue);
    expect(inMenu('Paro Power Gym'), findsOneWidget, reason: 'the gym in the address');
  });

  testWidgets('Suppliers is in the menu; Inventory is gone', (tester) async {
    await showApp(tester, computer, person(gyms: owner), at: GymRoutes.suppliersFor(gymId));
    await openGym(tester);
    expect(selected(tester, 'Suppliers'), isTrue);
    expect(inMenu('Inventory'), findsNothing);
  });

  testWidgets("its organisation's roles are the gym's page too", (tester) async {
    await showApp(tester, computer, person(gyms: owner), at: CoreRoutes.venueRolesFor(otherId));
    await openGym(tester);
    expect(selected(tester, 'Roles & permissions'), isTrue);
    expect(inMenu('Paro Power Gym'), findsOneWidget, reason: 'the gym in the address');
  });

  testWidgets('the front desk sees only what its role allows', (tester) async {
    await showApp(tester, computer, person(gyms: frontDesk));
    await openGym(tester);
    // Their role says 'Front desk' too, over the gym; the group's heading is below.
    await tester.tap(inMenu('Front desk').last);
    await tester.pumpAndSettle();
    for (final label in ['Check-in', 'Members', 'Register member', 'Reports & analytics']) {
      expect(inMenu(label), findsOneWidget, reason: label);
    }
    for (final hidden in [
      'Memberships & packages', 'Payments & income', 'Suppliers', 'Staff', 'Roles & permissions', 'Gym settings',
      'Manage',
    ]) {
      expect(inMenu(hidden), findsNothing, reason: hidden);
    }
    expect(inMenu('Front desk'), findsWidgets, reason: 'their role, and the heading');
  });

  testWidgets('no gym yet: the service offers setting one up; the team get Administration', (tester) async {
    await showApp(tester, computer, person(team: true), at: CoreRoutes.home);
    expect(inMenu('Set up your gym'), findsNothing, reason: 'closed until opened');
    await openGym(tester);
    expect(inMenu('Set up your gym'), findsOneWidget);
    expect(inMenu('Not set up yet'), findsOneWidget);
    expect(inMenu('Dashboard'), findsNothing);
    expect(inMenu('ADMINISTRATION'), findsOneWidget);
  });

  testWidgets("no gym, and not the super admin: nothing they haven't been given", (tester) async {
    await showApp(tester, computer, person(), at: CoreRoutes.account);
    for (final label in ['Overview', 'Modules', 'Gym management', 'Set up your gym', 'ADMINISTRATION']) {
      expect(inMenu(label), findsNothing, reason: label);
    }
    expect(inMenu('My dashboard'), findsOneWidget, reason: "a member's own");
    expect(inMenu('My services'), findsOneWidget, reason: "a member's own");
    for (final label in ['My QR code', 'My gyms', 'Notifications']) {
      expect(inMenu(label), findsNothing, reason: '$label: on the dashboard, or the bell at the top');
    }
  });

  testWidgets('switching gyms, and registering another, from the gym at the top of its section', (tester) async {
    final router = await showApp(tester, computer, person(gyms: owner));
    await openGym(tester);
    await tester.tap(inMenu('Druk Fitness Club'));
    await tester.pumpAndSettle();
    expect(find.text('Register another gym'), findsOneWidget);
    await tester.tap(find.text('Paro Power Gym').last);
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, GymRoutes.dashboardFor(otherId));
    expect(inMenu('Paro Power Gym'), findsOneWidget);
  });

  testWidgets('the New menu, on a page under the bar, has the gym shortcuts the role allows', (tester) async {
    await showApp(tester, computer, person(gyms: frontDesk), at: GymRoutes.membersFor(gymId), withNewMenu: true);
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    expect(find.text('Check in a member'), findsOneWidget);
    expect(find.text('Register a member'), findsOneWidget);
    expect(find.text('New package'), findsNothing);
  });

  testWidgets('the top bar never has New: not on Members or Check-in either', (tester) async {
    for (final at in [
      GymRoutes.membersFor(gymId), GymRoutes.registerMemberFor(gymId), GymRoutes.checkInFor(gymId),
      GymRoutes.dashboardFor(gymId), GymRoutes.plansFor(gymId), GymRoutes.suppliersFor(gymId),
    ]) {
      await showApp(tester, computer, person(gyms: owner), at: at, withNewMenu: true);
      expect(find.descendant(of: find.byType(GlassAppBar), matching: find.text('New')), findsNothing, reason: at);
      expect(find.text('New'), findsOneWidget, reason: '$at: the page can still offer it');
    }
  });

  testWidgets('the menu folds to its icons and opens out again', (tester) async {
    await showApp(tester, computer, person(gyms: owner));
    expect(tester.getSize(find.byType(PlatformSidebar)).width, sideMenuWidth);
    await tester.tap(find.byTooltip('Collapse menu'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 25));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(PlatformSidebar)).width, sideMenuFoldedWidth);
    await tester.tap(find.byTooltip('Expand menu'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(PlatformSidebar)).width, sideMenuWidth);
  });

  testWidgets("on a phone the menu is a drawer, opened from the page's bar", (tester) async {
    await showApp(tester, phone, person(gyms: owner));
    expect(find.byType(PlatformSidebar), findsNothing);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Collapse menu'), findsNothing);
    await openGym(tester);
    await openGroup(tester, 'Front desk');
    await tester.tap(inMenu('Check-in'));
    await tester.pumpAndSettle();
    expect(find.text('Page: Check-in'), findsOneWidget);
    expect(find.byType(PlatformSidebar), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets('the frame fits a laptop, open and folded, ${dark ? 'dark' : 'light'}', (tester) async {
      await showApp(tester, const Size(1280, 800), person(gyms: owner, team: true), dark: dark);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Collapse menu'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
