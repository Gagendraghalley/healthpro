import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:health_pro_core/src/auth/auth_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends Fake implements AuthRepository {
  final googleNext = <String?>[];
  var codes = 0;

  @override
  Future<void> sendSignUpCode({required String email, required String fullName, String? phone}) async => codes++;

  @override
  Future<void> signInWithGoogle({String? next}) async => googleNext.add(next);

  @override
  Stream<String> get unfinishedSignIns => const Stream.empty();
}

void main() {
  const trainerStart = '/gyms/trainer/profile';

  Future<(_Auth, ProviderContainer)> show(WidgetTester tester, {String? trainerRoute = trainerStart, String? next}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = _Auth();
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      trainerSignUpRouteProvider.overrideWithValue(trainerRoute),
      googleSignInProvider.overrideWith((ref) async => true),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        // The photo's drift and the rainbow stand still, so the page settles.
        data: const MediaQueryData(size: Size(1280, 1600), disableAnimations: true),
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, __) => SignUpScreen(next: next)),
            GoRoute(path: CoreRoutes.verify, builder: (_, __) => const Text('Enter the code')),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return (auth, container);
  }

  Future<void> fillIn(WidgetTester tester) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Full name *'), 'Pema Dorji');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email address *'), 'pema@sportshub.bt');
  }

  testWidgets('a member signs up and goes where they were going', (tester) async {
    final (auth, container) = await show(tester, next: '/gyms/7');
    expect(find.text('Join as'), findsOneWidget);
    await fillIn(tester);
    await tester.tap(find.text('Register account'));
    await tester.pumpAndSettle();
    expect(auth.codes, 1);
    expect(container.read(pendingCodeProvider)?.next, '/gyms/7');
  });

  testWidgets('a trainer signs up, by form or Google, and sets up their trainer profile first', (tester) async {
    final (auth, container) = await show(tester, next: '/gyms/7');
    await tester.tap(find.text('Trainer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('set up your trainer profile'), findsOneWidget);

    await tester.tap(find.text('Sign up with Google'));
    await tester.pumpAndSettle();
    expect(auth.googleNext, [trainerStart]);

    await fillIn(tester);
    await tester.tap(find.text('Register account'));
    await tester.pumpAndSettle();
    expect(container.read(pendingCodeProvider)?.next, trainerStart);
  });

  testWidgets('Google sign-up joins as a member by default', (tester) async {
    final (auth, _) = await show(tester);
    await tester.tap(find.text('Sign up with Google'));
    await tester.pumpAndSettle();
    expect(auth.googleNext, [null]);
  });

  testWidgets('no choice where no service has trainers', (tester) async {
    await show(tester, trainerRoute: null);
    expect(find.text('Join as'), findsNothing);
    expect(find.text('Trainer'), findsNothing);
  });
}
