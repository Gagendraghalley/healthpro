// The whole app (core shell, router and the gym module) with fake data
// instead of Supabase.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:health_pro_app/main.dart' show modules;
import 'package:health_pro_core/health_pro_core.dart';

class FakeAuth extends Fake implements AuthRepository {
  FakeAuth([this.userId]);

  @override
  final String? userId;

  @override
  bool get isLoggedIn => userId != null;

  @override
  bool get mustChooseCode => false;

  @override
  bool get mustAddPhone => false;

  @override
  String? takeNextAfterGoogle() => null;

  @override
  Stream<String> get unfinishedSignIns => const Stream.empty();

  @override
  Stream<void> get changes => const Stream.empty();
}

class FakeModules extends Fake implements ModuleRepository {
  FakeModules({required this.gymOn});
  final bool gymOn;

  @override
  Future<List<AppModuleRow>> list() async => [
        AppModuleRow(key: 'gym_membership', name: 'Gym membership', isEnabled: gymOn, sortOrder: 20),
      ];
}

class FakeProfiles extends Fake implements ProfileRepository {
  @override
  Future<Profile?> get(String userId) async =>
      Profile(id: userId, fullName: 'Pema Wangmo', role: PlatformRole.user, memberCode: '4K7P9Q');
}

class FakeVenues extends Fake implements VenueRepository {
  @override
  Future<List<MyVenue>> myVenues() async => const [];

  static final peak = Venue.fromJson({
    'id': 'g1',
    'type': 'gym',
    'module_key': 'gym_membership',
    'name': 'Peak Fitness',
    'dzongkhag': 'Thimphu',
    'verification_status': 'verified',
    'created_at': '2026-11-07T10:00:00Z',
  });

  @override
  Future<List<Venue>> listPublic({required String type, String? dzongkhag}) async => [peak];

  @override
  Future<List<Venue>> listForModule(String moduleKey) async => [peak];

  @override
  Future<List<VenueType>> types() async => const [
        VenueType(key: 'gym', moduleKey: 'gym_membership', name: 'Gym', sortOrder: 10),
        VenueType(key: 'swimming', moduleKey: 'gym_membership', name: 'Swimming Pool', icon: 'pool', sortOrder: 30),
      ];
}

class FakeGym extends Fake implements GymRepository {}

class FakeNotifications extends Fake implements NotificationRepository {
  @override
  Stream<List<AppNotification>> watch(String userId) => Stream.value(const []);
}

/// A signed-in member (no Health Pro team roles), or the super admin.
class FakeAccess extends Fake implements AccessRepository {
  FakeAccess({this.superAdmin = false});
  final bool superAdmin;

  @override
  Future<PlatformAccess> myAccess() async => PlatformAccess(isSuperAdmin: superAdmin, isActive: true, permissions: const {});
}

Future<ProviderContainer> pumpApp(WidgetTester tester, {String? userId, bool gymOn = true, bool superAdmin = false}) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    registeredModulesProvider.overrideWithValue(modules),
    authRepositoryProvider.overrideWithValue(FakeAuth(userId)),
    moduleRepositoryProvider.overrideWithValue(FakeModules(gymOn: gymOn)),
    profileRepositoryProvider.overrideWithValue(FakeProfiles()),
    venueRepositoryProvider.overrideWithValue(FakeVenues()),
    gymRepositoryProvider.overrideWithValue(FakeGym()),
    notificationRepositoryProvider.overrideWithValue(FakeNotifications()),
    accessRepositoryProvider.overrideWithValue(FakeAccess(superAdmin: superAdmin)),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const HealthProApp()));
  await tester.pumpAndSettle();
  return container;
}

/// The sign-in pages' photo drifts for as long as it shows, so pumpAndSettle
/// never settles on them: pump through the page change instead.
Future<void> pumpOnSignIn(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('visitors land on the public Welcome page', (tester) async {
    final container = await pumpApp(tester);
    expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, CoreRoutes.welcome);
    expect(find.text('Services'), findsWidgets);
  });

  testWidgets('visitors choose a kind of service, then browse its public pages', (tester) async {
    final container = await pumpApp(tester);
    container.read(appRouterProvider).go(GymRoutes.gyms);
    await tester.pumpAndSettle();
    expect(find.text('What are you looking for?'), findsOneWidget);
    expect(find.text('Swimming Pool'), findsOneWidget);
    await tester.tap(find.text('Gym'));
    await tester.pumpAndSettle();
    expect(find.text('Peak Fitness'), findsOneWidget);
  });

  testWidgets("a gym's staff pages need signing in", (tester) async {
    final container = await pumpApp(tester);
    final router = container.read(appRouterProvider);
    router.go(GymRoutes.membersFor('g1'));
    await pumpOnSignIn(tester);
    expect(router.routerDelegate.currentConfiguration.uri.path, CoreRoutes.signIn, reason: 'the sign-in page');
  });

  testWidgets('signing in and signing up have a way back to the Welcome page', (tester) async {
    final container = await pumpApp(tester);
    final router = container.read(appRouterProvider);
    for (final page in [CoreRoutes.signIn, CoreRoutes.signUp]) {
      router.go(page);
      await pumpOnSignIn(tester);
      await tester.tap(find.byTooltip('Back to home'));
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, CoreRoutes.welcome, reason: page);
    }
  });

  testWidgets('visitors ask AI from the top of the gym list and the sign-in pages, nothing floating', (tester) async {
    final container = await pumpApp(tester);
    final router = container.read(appRouterProvider);
    for (final page in [GymRoutes.gyms, CoreRoutes.signIn, CoreRoutes.signUp]) {
      router.go(page);
      await pumpOnSignIn(tester);
      expect(find.byType(FloatingActionButton), findsNothing, reason: page);
      if (page == GymRoutes.gyms) {
        expect(find.descendant(of: find.byType(GlassAppBar), matching: find.text('Ask AI')), findsOneWidget);
      }
      await tester.tap(find.byTooltip('Ask AI'));
      await pumpOnSignIn(tester);
      expect(find.text('Health Pro assistant'), findsOneWidget, reason: page);
      await tester.tap(find.byTooltip('Close'));
      await pumpOnSignIn(tester);
      expect(find.text('Health Pro assistant'), findsNothing, reason: page);
    }
  });

  testWidgets('the super admin, running no gym yet: Overview shows how to start', (tester) async {
    final container = await pumpApp(tester, userId: 'u1', superAdmin: true);
    expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, CoreRoutes.home);
    expect(find.text('Overview'), findsWidgets);
    expect(find.text('Gym management'), findsWidgets, reason: 'the service, in the menu and on Overview');
    expect(find.text('Set up your gym'), findsWidgets);
    expect(find.textContaining('Work at a gym?'), findsOneWidget);
  });

  testWidgets("anyone else given nothing (a member) starts at their QR code, without the platform's pages", (tester) async {
    final container = await pumpApp(tester, userId: 'u1');
    final router = container.read(appRouterProvider);
    expect(router.routerDelegate.currentConfiguration.uri.path, CoreRoutes.myQr);
    expect(find.text('Overview'), findsNothing);
    expect(find.text('Set up your gym'), findsNothing);
    router.go(CoreRoutes.services);
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, CoreRoutes.myQr, reason: "My services is the super admin's");
  });

  testWidgets('pages of a module that is off send users to their start', (tester) async {
    final container = await pumpApp(tester, userId: 'u1', gymOn: false);
    container.read(appRouterProvider).go(GymRoutes.gyms);
    await tester.pumpAndSettle();
    expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, CoreRoutes.myQr,
        reason: 'home, which for someone given nothing is their QR code');
  });

  test('main.dart registers the gym service', () {
    expect(modules.map((m) => m.key), ['gym_membership']);
  });
}
