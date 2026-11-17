import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/data/joining.dart';
import 'package:gym_membership/src/data/online_payments.dart';
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

/// What the search finds for [query], for someone working at [gyms]; each
/// gym has a package and a request to join that match 'pema'.
Future<List<SearchHit>> _search(List<MyVenue> gyms, _Repo repo, String query,
    {String approval = JoinApproval.desk}) async {
  final container = ProviderContainer(overrides: [
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
    expect(hits.every((h) => h.route.startsWith('/gyms/$gymId/manage/')), isTrue, reason: 'every one opens a page of theirs');
    expect(hits.first.subtitle, contains('Druk Fitness Club'), reason: 'with two gyms, it says which');
  });

  test('the owner finds the packages too, opening Memberships & packages', () async {
    final hits = await _search([owner], _Repo(), 'pema');
    expect(titles(hits, 'Members'), ['Pema Dorji']);
    expect(titles(hits, 'Join requests'), ['Pema Lhamo']);
    expect(titles(hits, 'Packages'), ['Pema special']);
    expect(hits.firstWhere((h) => h.group == 'Packages').route, GymRoutes.plansFor(gymId));
    expect(hits.first.subtitle, isNot(contains('Druk Fitness Club')), reason: 'one gym: no need to say');
  });

  test("where requests are left to managers, the front desk doesn't find them", () async {
    final hits = await _search([frontDesk], _Repo(), 'pema', approval: JoinApproval.managers);
    expect(titles(hits, 'Members'), ['Pema Dorji']);
    expect(titles(hits, 'Join requests'), isEmpty);
  });

  test('someone working at no gym finds nothing in gym management', () async {
    final repo = _Repo();
    final hits = await _search(const [], repo, 'pema');
    expect(hits, isEmpty);
    expect(repo.asked, isEmpty);
  });
}
