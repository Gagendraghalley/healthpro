import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/data/classes.dart';
import 'package:gym_membership/src/data/follow_ups.dart';
import 'package:gym_membership/src/data/inventory.dart';
import 'package:gym_membership/src/data/joining.dart';
import 'package:gym_membership/src/data/money.dart';
import 'package:gym_membership/src/data/online_payments.dart';
import 'package:gym_membership/src/data/trainers.dart';
import 'package:health_pro_core/health_pro_core.dart';

const gymId = '0f8e3a1c-2b4d-4e5f-8a9b-0c1d2e3f4a5b';
const otherId = '1f8e3a1c-2b4d-4e5f-8a9b-0c1d2e3f4a5c';
const pemaGymId = '2f8e3a1c-2b4d-4e5f-8a9b-0c1d2e3f4a5d';

Venue venue(String id, String name) => Venue.fromJson({
      'id': id,
      'type': 'gym',
      'name': name,
      'dzongkhag': 'Thimphu',
      'verification_status': 'verified',
      'created_at': '2026-11-01T00:00:00Z',
    });

/// Finds Pema Dorji at every gym it's asked about, and keeps which it was.
class _Repo extends Fake implements GymRepository {
  final asked = <List<String>>[];

  @override
  Future<List<GymMember>> searchMembers(List<String> venueIds, String search, {int limit = 8}) async {
    asked.add(venueIds);
    return [
      for (final id in venueIds)
        GymMember.fromJson({
          'id': 'm-$id',
          'venue_id': id,
          'code': 'HP-0042',
          'qr_token': 'card',
          'full_name': 'Pema Dorji',
          'phone': '17123456',
          'joined_on': '2026-11-01',
          'created_at': '2026-11-01T00:00:00Z',
        }),
    ];
  }
}

/// What the search finds for [query], for someone working at [gyms] and a
/// member of [memberOf]; each gym has a package, a request to join, an
/// enquiry, a payment, a class, an offer, an expense and stock that match
/// 'pema'. Health Pro lists Druk Fitness Club and Pema Gym.
Future<List<SearchHit>> _search(List<MyVenue> gyms, _Repo repo, String query,
    {String approval = JoinApproval.desk, List<MyGym> memberOf = const []}) async {
  final container = ProviderContainer(overrides: [
    myMembershipsProvider.overrideWith((ref) async => MyMemberships(gyms: memberOf)),
    myClassBookingsProvider.overrideWith((ref) async => const []),
    myTrainingProvider.overrideWith((ref) async => const MyTraining()),
    publicVenuesProvider.overrideWith((ref, q) async => [venue(gymId, 'Druk Fitness Club'), venue(pemaGymId, 'Pema Gym')]),
    gymEnquiriesProvider.overrideWith((ref, id) async => [
          GymEnquiry(id: 'e-$id', venueId: id, fullName: 'Pema Choden', phone: '17000001', createdAt: DateTime(2026, 11, 1)),
        ]),
    gymPaymentClaimsProvider.overrideWith((ref, id) async => [
          PaymentClaim(
              id: 'c-$id',
              venueId: id,
              gymMemberId: 'm-$id',
              memberName: 'Pema Dorji',
              planName: 'Monthly',
              months: 1,
              amount: 1500,
              jrn: '884421',
              status: ClaimStatus.pending,
              createdAt: DateTime(2026, 11, 1)),
        ]),
    gymClassesProvider.overrideWith((ref, id) async => [
          GymClass(id: 'k-$id', venueId: id, name: 'Morning yoga', trainerName: 'Pema', weekday: 1, hour: 7, minute: 0, capacity: 12),
        ]),
    gymOffersProvider.overrideWith((ref, id) async => [
          GymOffer(id: 'o-$id', venueId: id, name: 'Pema festival', kind: OfferKind.percent, value: 10),
        ]),
    gymExpensesProvider.overrideWith((ref, id) async => const []),
    gymInventoryProvider.overrideWith((ref, id) async => [
          InventoryItem(id: 'i-$id', venueId: id, name: 'Pema towels', quantity: 2, reorderLevel: 5, updatedAt: DateTime(2026, 11, 1)),
        ]),
    connectedSuppliersProvider.overrideWith((ref) async => const []),
    venueStaffProvider.overrideWith((ref, id) async => const []),
    currentUserIdProvider.overrideWithValue('u1'),
    myAccessProvider.overrideWith((ref) async => const PlatformAccess(isSuperAdmin: false, isActive: true, permissions: {})),
    myVenuesProvider.overrideWith((ref) async => gyms),
    enabledModulesProvider.overrideWith((ref) async => const [GymModule()]),
    gymRepositoryProvider.overrideWithValue(repo),
    gymSettingsProvider.overrideWith((ref, id) async => GymSettings(venueId: id, joinApproval: approval)),
    gymJoinRequestsProvider.overrideWith((ref, id) async => [
          JoinRequest(
              id: 'r-$id', venueId: id, status: JoinRequestStatus.pending, name: 'Pema Lhamo', createdAt: DateTime(2026, 11, 1)),
        ]),
    gymTrainersProvider.overrideWith((ref, id) async => const []),
    gymPlansProvider.overrideWith((ref, q) async => [
          GymPlan.fromJson(
              {'id': 'p-${q.venueId}', 'venue_id': q.venueId, 'name': 'Pema special', 'duration_days': 30, 'price': 1500}),
        ]),
  ]);
  addTearDown(container.dispose);
  final sub = container.listen(globalSearchProvider(query).future, (_, __) {});
  return sub.read();
}

List<String> titles(List<SearchHit> hits, String group) => [for (final h in hits) if (h.group == group) h.title];

void main() {
  final frontDesk = MyVenue(venue(gymId, 'Druk Fitness Club'), VenueRole.staff,
      roleName: 'Front desk',
      permissions: const {GymPermission.register, GymPermission.members, GymPermission.payments, GymPermission.checkIn});
  final doorOnly = MyVenue(venue(otherId, 'Paro Power Gym'), VenueRole.staff,
      roleName: 'Door', permissions: const {GymPermission.checkIn});
  final owner = MyVenue(venue(gymId, 'Druk Fitness Club'), VenueRole.owner);

  test('the front desk finds members and requests to join, not packages', () async {
    final repo = _Repo();
    final hits = await _search([frontDesk, doorOnly], repo, 'pema');
    expect(repo.asked, [
      [gymId]
    ], reason: 'members only where their role shows them');
    expect(titles(hits, 'Members'), ['Pema Dorji']);
    expect(titles(hits, 'Join requests'), ['Pema Lhamo'], reason: 'only where they register members');
    expect(titles(hits, 'Packages'), isEmpty);
    expect(hits.where((h) => h.group != 'Gyms').every((h) => h.route.startsWith('/gyms/$gymId/manage/')), isTrue,
        reason: 'every one opens a page of theirs');
    expect(hits.first.subtitle, contains('Druk Fitness Club'), reason: 'with two gyms, it says which');
  });

  test('the owner finds the packages too, opening Memberships & packages', () async {
    final hits = await _search([owner], _Repo(), 'pema');
    expect(titles(hits, 'Members'), ['Pema Dorji']);
    expect(titles(hits, 'Join requests'), ['Pema Lhamo']);
    expect(titles(hits, 'Packages'), ['Pema special']);
    expect(hits.firstWhere((h) => h.group == 'Packages').route, '/gyms/$gymId/manage/plans?open=p-$gymId', reason: 'opens that package');
    expect(hits.first.subtitle, isNot(contains('Druk Fitness Club')), reason: 'one gym: no need to say');
  });

  test("where requests are left to managers, the front desk doesn't find them", () async {
    final hits = await _search([frontDesk], _Repo(), 'pema', approval: JoinApproval.managers);
    expect(titles(hits, 'Members'), ['Pema Dorji']);
    expect(titles(hits, 'Join requests'), isEmpty);
  });

  test('someone working at no gym finds nothing in gym management, only gyms on Health Pro', () async {
    final repo = _Repo();
    final hits = await _search(const [], repo, 'pema');
    expect(hits.map((h) => h.group).toSet(), {'Gyms'});
    expect(titles(hits, 'Gyms'), ['Pema Gym']);
    expect(hits.single.route, GymRoutes.gymFor(pemaGymId));
    expect(repo.asked, isEmpty);
  });

  test('the owner finds everything at their gym, each opening its page', () async {
    final hits = await _search([owner], _Repo(), 'pema');
    expect(titles(hits, 'Enquiries & trials'), ['Pema Choden']);
    expect(titles(hits, 'Payments'), ['Pema Dorji']);
    expect(titles(hits, 'Classes'), ['Morning yoga'], reason: 'found by its trainer');
    expect(titles(hits, 'Offers'), ['Pema festival']);
    expect(titles(hits, 'Stock'), ['Pema towels']);
    expect(hits.firstWhere((h) => h.group == 'Stock').subtitle, contains('Running low'));
    // Each opens that record on its page.
    expect(hits.firstWhere((h) => h.group == 'Classes').route, GymRoutes.classesFor(gymId, open: 'k-$gymId'));
    expect(hits.firstWhere((h) => h.group == 'Offers').route, GymRoutes.offersFor(gymId, open: 'o-$gymId'));
    expect(hits.firstWhere((h) => h.group == 'Stock').route, GymRoutes.inventoryFor(gymId, open: 'i-$gymId'));
    expect(hits.firstWhere((h) => h.group == 'Enquiries & trials').route, GymRoutes.enquiriesFor(gymId, open: 'e-$gymId'));
    expect(hits.firstWhere((h) => h.group == 'Join requests').route, GymRoutes.requestsFor(gymId, open: 'r-$gymId'));
    expect(titles(hits, 'Gyms'), ['Pema Gym'], reason: 'their own gym is not found again');
  });

  test('a payment is found by its JRN', () async {
    final hits = await _search([owner], _Repo(), '884421');
    expect(titles(hits, 'Payments'), ['Pema Dorji']);
    expect(hits.firstWhere((h) => h.group == 'Payments').route, GymRoutes.paymentsFor(gymId, open: 'c-$gymId'));
  });

  test("the front desk doesn't find what their role doesn't show", () async {
    final hits = await _search([frontDesk], _Repo(), 'pema');
    expect(titles(hits, 'Enquiries & trials'), ['Pema Choden']);
    expect(titles(hits, 'Payments'), ['Pema Dorji']);
    expect(titles(hits, 'Classes'), isEmpty);
    expect(titles(hits, 'Offers'), isEmpty);
    expect(titles(hits, 'Stock'), isEmpty);
  });

  test('a member finds their own gym, opening My gym', () async {
    final hits = await _search(const [], _Repo(), 'pema',
        memberOf: const [MyGym(venueId: pemaGymId, venueName: 'Pema Gym', place: 'Thimphu', memberCode: 'HP-0042')]);
    expect(titles(hits, 'My gyms'), ['Pema Gym']);
    expect(hits.firstWhere((h) => h.group == 'My gyms').route, GymRoutes.myGymFor(pemaGymId));
    expect(titles(hits, 'Gyms'), isEmpty, reason: 'already found as theirs');
  });
}
