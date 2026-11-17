import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/data/online_payments.dart';
import 'package:gym_membership/src/screens/member_registered_screen.dart';
import 'package:gym_membership/src/widgets/package_fields.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:health_pro_core/health_pro_core.dart';

/// Gives the bank-issued QR image's address.
class _QrRepo extends Fake implements GymRepository {
  @override
  String? paymentQrUrl(String? path) => path == null || path.isEmpty ? null : 'https://example.test/gym-payment-qr/$path';
}

final venue = Venue.fromJson({
  'id': 'g1',
  'type': gymVenueType,
  'name': 'Peak Fitness',
  'dzongkhag': 'Thimphu',
  'verification_status': 'verified',
  'created_at': '2026-11-01T00:00:00Z',
});

const plans = [
  GymPlan(id: 'p1', venueId: 'g1', name: 'Standard Membership', durationDays: 30, price: 1500, isActive: true),
  GymPlan(id: 'p2', venueId: 'g1', name: 'Gym + Aerobics', durationDays: 30, price: 2200, isActive: true),
];

final karma = GymMember.fromJson({
  'id': 'gm1',
  'venue_id': 'g1',
  'code': '4K7P9Q',
  'qr_token': '0123456789abcdef0123456789abcdef',
  'full_name': 'Karma Wangmo',
  'phone': '+97517123456',
  'blood_group': 'B+',
  'village': {'name': 'Changangkha'},
  'gewog': {'name': 'Thim Throm'},
  'dzongkhag': {'name': 'Thimphu'},
  'emergency_contact_name': 'Pema',
  'emergency_contact_phone': '+97577123456',
  'medical_notes': 'Asthma: keeps an inhaler',
  'joined_on': isoDate(BhutanTime.today()),
  'created_at': '2026-11-08T04:00:00Z',
});

/// Karma's package, as gym_register_member records it.
GymSubscription soldToday({int months = 3}) {
  final today = BhutanTime.today();
  return GymSubscription(
    id: 's1',
    venueId: 'g1',
    memberId: 'gm1',
    gymMemberId: 'gm1',
    planId: 'p1',
    planName: 'Standard Membership',
    durationDays: BhutanTime.daysBetween(today, packageEnd(today, months)) + 1,
    price: 4500,
    status: SubscriptionStatus.active,
    startDate: today,
    endDate: packageEnd(today, months),
    requestedAt: DateTime.now().toUtc(),
  );
}

Future<void> showRegistered(WidgetTester tester, {Size size = const Size(1440, 1000), bool dark = false,
    List<GymSubscription>? subs}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      venueAccessProvider.overrideWith((ref, id) async => VenueAccess(venue, VenueRole.owner)),
      myVenuesProvider.overrideWith((ref) async => [MyVenue(venue, VenueRole.owner)]),
      myProfileProvider.overrideWith((ref) async => Profile.fromJson({'id': 'u1', 'full_name': 'Kinley Dorji'})),
      unreadCountProvider.overrideWithValue(0),
      gymMemberProvider.overrideWith((ref, id) async => karma),
      gymSubscriptionsProvider.overrideWith((ref, id) async => subs ?? [soldToday()]),
      gymMemberPhotoProvider.overrideWith((ref, path) async => null),
    ],
    child: MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: const MemberRegisteredScreen(venueId: 'g1', memberId: 'gm1'),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the expiry date is worked out: 8 Nov 2026 for 3 months expires on 8 Feb 2027', (tester) async {
    PackageSale? sale;
    await tester.pumpWidget(ProviderScope(
      overrides: [gymPlansProvider.overrideWith((ref, q) async => plans)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Form(
            child: PackageFields(venueId: 'g1', start: DateTime(2026, 11, 8), onChanged: (s) => sale = s),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Expiry date'), findsOneWidget);

    await tester.tap(find.byType(SearchableDropdown<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Standard Membership').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SearchableDropdown<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 months').last);
    await tester.pumpAndSettle();

    expect(find.text(formatDate(DateTime(2027, 2, 8))), findsOneWidget);
    expect(sale?.plan.id, 'p1');
    expect(sale?.months, 3);
    // The amount follows the package until the desk types its own.
    expect(sale?.amount, 4500);
  });

  /// The package form at the desk, a package chosen and paid by bank
  /// transfer; the gym's bank-issued QR uploaded at [qrPath], or none.
  Future<void> payByTransfer(WidgetTester tester, {String? qrPath}) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        gymPlansProvider.overrideWith((ref, q) async => plans),
        gymRepositoryProvider.overrideWithValue(_QrRepo()),
        gymSettingsProvider.overrideWith((ref, id) async => GymSettings(
            venueId: 'g1',
            account: const PaymentAccount(bankName: 'Bank of Bhutan', accountNumber: '200123456789', accountName: 'Peak Fitness'),
            paymentQrPath: qrPath)),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Form(
            child: PackageFields(venueId: 'g1', start: DateTime(2026, 11, 8), onChanged: (_) {}),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SearchableDropdown<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Standard Membership').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank transfer'));
    await tester.pumpAndSettle();
  }

  testWidgets("the desk can show the gym's bank QR with the amount while adding or renewing a package", (tester) async {
    await payByTransfer(tester, qrPath: 'g1/qr.png');
    expect(
        find.byWidgetPredicate((w) => w is Image && w.semanticLabel == 'Bank-issued payment QR code for Peak Fitness'),
        findsOneWidget);
    expect(find.text('Nu. 1,500'), findsOneWidget);
    expect(find.text('2001 2345 6789'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no bank QR uploaded yet: the desk is told where to add it', (tester) async {
    await payByTransfer(tester);
    expect(find.textContaining('upload its bank-issued QR in Membership settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (name, size) in [('computer', const Size(1440, 1000)), ('phone', const Size(390, 844))]) {
    for (final dark in [false, true]) {
      testWidgets("registered: the news, the package and the QR card fit a $name, ${dark ? 'dark' : 'light'}", (tester) async {
        await showRegistered(tester, size: size, dark: dark);
        expect(tester.takeException(), isNull);
        expect(find.text('Karma Wangmo is registered'), findsOneWidget);
        expect(find.byType(QrImageView), findsOneWidget);
      });
    }
  }

  testWidgets('registered: the expiry date, what they paid, their card and what to do next', (tester) async {
    await showRegistered(tester);
    final expiry = formatDate(packageEnd(BhutanTime.today(), 3));
    expect(find.text('Expiry date'), findsOneWidget);
    expect(find.text(expiry), findsOneWidget);
    expect(find.text('Nu. 4,500'), findsOneWidget);
    // The card: their code and how long it's good for; no personal details.
    expect(find.text('4K7P9Q'), findsOneWidget);
    expect(find.text('Valid until $expiry'), findsOneWidget);
    expect(find.textContaining('Asthma'), findsOneWidget);
    for (final action in ['Copy QR code', 'WhatsApp message', 'Register another', 'Open their page']) {
      expect(find.text(action), findsOneWidget, reason: action);
    }
    // Just made: no "New card" here.
    expect(find.text('New card'), findsNothing);
  });

  testWidgets('registered without a package: says they cannot check in yet', (tester) async {
    await showRegistered(tester, subs: const []);
    expect(find.textContaining("can't check in until they have a package"), findsOneWidget);
    expect(find.text('Sell a package'), findsOneWidget);
    expect(find.text('No package yet'), findsOneWidget); // on the card
  });
}
