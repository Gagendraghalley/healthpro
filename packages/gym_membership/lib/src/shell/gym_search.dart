import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/classes.dart';
import '../data/coaching.dart';
import '../data/follow_ups.dart';
import '../data/gym_repository.dart';
import '../data/inventory.dart';
import '../data/money.dart';
import '../data/online_payments.dart';
import '../data/trainers.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import 'gym_navigation.dart';

/// The most of one kind the search shows, best first.
const searchGroupLimit = 6;

/// The order the gym's results come in.
const gymSearchGroups = [
  'Members',
  'Join requests',
  'Enquiries & trials',
  'Payments',
  'Classes',
  'Trainers',
  'Packages',
  'Offers',
  'Expenses',
  'Stock',
  'Suppliers',
  'Members you train',
  'My gyms',
  'My classes',
  'Gyms',
];

/// What the search in the bar finds in gyms for [query]. Staff find, at the
/// gyms they work at and as their role there allows (the same as the menu):
/// members (by name, phone, card code or email), requests to join, enquiries
/// and trials, online payments (by name, card code or JRN), classes,
/// trainers, packages, offers, expenses, stock and suppliers. A trainer finds
/// the members they train; anyone signed in, their own gyms and classes; and
/// everyone, the gyms on Health Pro. Every result opens the page that shows
/// it; with several gyms, each says which gym. [color] is the service's.
Future<List<SearchHit>> searchGyms(Ref ref, String query, {required Color color}) async {
  final words = searchWords(query);
  bool has(Iterable<String?> texts) {
    final all = texts.whereType<String>().join(' ').toLowerCase();
    return words.every(all.contains);
  }

  // One part failing (a list that won't load) leaves the others.
  Future<List<SearchHit>> part(Future<List<SearchHit>> Function() find) async {
    try {
      return await find();
    } catch (_) {
      return const [];
    }
  }

  List<MyVenue> mine = const [];
  try {
    mine = [for (final v in await ref.watch(myVenuesProvider.future)) if (v.venue.type == gymVenueType) v];
  } catch (_) {}
  final byId = {for (final g in mine) g.venue.id: g};
  String line(String venueId, Iterable<String?> parts) => [
        ...parts,
        if (mine.length > 1) byId[venueId]?.venue.name,
      ].whereType<String>().where((p) => p.trim().isNotEmpty).join(' · ');
  SearchHit hit(String title, Iterable<String?> subtitle, String venueId,
          {required IconData icon, required Art3D art, required String route, required String group}) =>
      SearchHit(title: title, subtitle: line(venueId, subtitle), icon: icon, art: art, route: route, group: group, color: color);

  // ---- Gym management: the gyms they work at.

  final memberGyms = [for (final g in mine) if (g.access.can(GymPermission.members)) g.venue.id];
  Future<List<SearchHit>> members() async => [
        for (final m in await ref.watch(gymRepositoryProvider).searchMembers(memberGyms, query))
          // Only the gyms asked for, whatever comes back.
          if (memberGyms.contains(m.venueId))
            hit(m.fullName, [m.code, m.phone], m.venueId,
                icon: Icons.person_rounded, art: Art3D.person, route: GymRoutes.memberFor(m.venueId, m.id), group: 'Members'),
      ];

  Future<List<SearchHit>> requests(MyVenue gym) async {
    final id = gym.venue.id;
    // Settings that won't load: as the menu, whoever registers members.
    GymSettings? settings;
    try {
      settings = await ref.watch(gymSettingsProvider(id).future);
    } catch (_) {}
    if (!answersJoinRequests(gym.access, settings)) return const [];
    return [
      for (final r in await ref.watch(gymJoinRequestsProvider(id).future))
        if (r.isPending && has([r.name, r.phone, r.email]))
          hit(r.name, ['Wants to join', r.planName], id,
              icon: Icons.how_to_reg_outlined, art: Art3D.handshake, route: GymRoutes.requestsFor(id, open: r.id), group: 'Join requests'),
    ];
  }

  Future<List<SearchHit>> enquiries(MyVenue gym) async {
    final id = gym.venue.id;
    if (!gym.access.can(GymPermission.register)) return const [];
    return [
      for (final e in await ref.watch(gymEnquiriesProvider(id).future))
        if (has([e.fullName, e.phone, e.interest, e.notes]))
          hit(e.fullName, [e.status.label, e.phone, e.interest], id,
              icon: Icons.contact_phone_outlined,
              art: Art3D.speechBalloon,
              route: GymRoutes.enquiriesFor(id, open: e.id),
              group: 'Enquiries & trials'),
    ];
  }

  Future<List<SearchHit>> payments(MyVenue gym) async {
    final id = gym.venue.id;
    if (!gym.access.can(GymPermission.payments)) return const [];
    return [
      for (final c in await ref.watch(gymPaymentClaimsProvider(id).future))
        if (has([c.memberName, c.memberCode, c.jrn, c.planName]))
          hit(c.memberName, ['JRN ${c.jrn}', formatNu(c.amount), c.status.label], id,
              icon: Icons.account_balance_wallet_outlined,
              art: Art3D.creditCard,
              route: GymRoutes.paymentsFor(id, open: c.id),
              group: 'Payments'),
    ];
  }

  Future<List<SearchHit>> classes(MyVenue gym) async {
    final id = gym.venue.id;
    if (!gym.access.can(GymPermission.classes)) return const [];
    return [
      for (final c in await ref.watch(gymClassesProvider(id).future))
        if (has([c.name, c.description, c.trainerName]))
          hit(c.name, ['${weekdayNames[c.weekday - 1]} ${c.time}', c.trainerName, if (!c.isActive) 'Off the timetable'], id,
              icon: Icons.event_note_outlined, art: Art3D.calendar, route: GymRoutes.classesFor(id, open: c.id), group: 'Classes'),
    ];
  }

  Future<List<SearchHit>> trainers(MyVenue gym) async {
    final id = gym.venue.id;
    if (!gym.access.can(GymPermission.trainers)) return const [];
    return [
      for (final t in await ref.watch(gymTrainersProvider(id).future))
        if (has([t.profile.name, t.profile.headline, t.email, t.phone, ...t.profile.specialties]))
          hit(t.profile.name, [t.status.label, t.profile.headline], id,
              icon: Icons.sports_outlined, art: Art3D.biceps, route: GymRoutes.gymTrainersFor(id, open: t.profile.userId), group: 'Trainers'),
    ];
  }

  Future<List<SearchHit>> packages(MyVenue gym) async {
    final id = gym.venue.id;
    if (!gym.access.can(GymPermission.plans)) return const [];
    return [
      for (final p in await ref.watch(gymPlansProvider((venueId: id, all: true)).future))
        if (has([p.name, p.description]))
          hit(p.name, ['${formatNu(p.price)} / ${formatDuration(p.durationDays)}', if (!p.isActive) 'Not on sale'], id,
              icon: Icons.sell_outlined, art: Art3D.tickets, route: GymRoutes.plansFor(id, open: p.id), group: 'Packages'),
    ];
  }

  Future<List<SearchHit>> offers(MyVenue gym) async {
    final id = gym.venue.id;
    if (!gym.access.can(GymPermission.plans)) return const [];
    return [
      for (final o in await ref.watch(gymOffersProvider(id).future))
        if (has([o.name]))
          hit(o.name, [o.label, if (!o.isActive) 'Not offered'], id,
              icon: Icons.local_offer_outlined, art: Art3D.priceTag, route: GymRoutes.offersFor(id, open: o.id), group: 'Offers'),
    ];
  }

  Future<List<SearchHit>> expenses(MyVenue gym) async {
    final id = gym.venue.id;
    if (!gym.access.can(VenuePermission.income)) return const [];
    return [
      for (final e in await ref.watch(gymExpensesProvider(id).future))
        if (has([e.paidTo, e.note, e.category.label]))
          hit(e.paidTo?.trim().isNotEmpty == true ? e.paidTo!.trim() : e.category.label,
              [formatNu(e.amount), formatDate(e.spentOn), e.category.label, e.note], id,
              icon: Icons.receipt_long_outlined, art: Art3D.receipt, route: GymRoutes.expensesFor(id, open: e.id), group: 'Expenses'),
    ];
  }

  Future<List<SearchHit>> stock(MyVenue gym) async {
    final id = gym.venue.id;
    if (!gym.access.can(GymPermission.inventory)) return const [];
    return [
      for (final i in await ref.watch(gymInventoryProvider(id).future))
        if (has([i.name, i.category, i.notes]))
          hit(i.name, [
            '${i.quantity} ${i.unit}',
            switch (i.level) { StockLevel.out => 'Out of stock', StockLevel.low => 'Running low', StockLevel.ok => null },
            i.category,
          ], id, icon: Icons.inventory_2_outlined, art: Art3D.clipboard, route: GymRoutes.inventoryFor(id, open: i.id), group: 'Stock'),
    ];
  }

  // The suppliers are the same for every gym: one result each, opening the
  // first gym's Suppliers whose role shows them.
  final stockGyms = [for (final g in mine) if (g.access.can(GymPermission.inventory)) g.venue.id];
  Future<List<SearchHit>> suppliers() async => [
        for (final s in await ref.watch(connectedSuppliersProvider.future))
          if (has([s.name, s.description]))
            SearchHit(
              title: s.name,
              subtitle: s.description,
              icon: Icons.storefront_outlined,
              art: Art3D.truck,
              route: GymRoutes.suppliersFor(stockGyms.first, open: s.key),
              group: 'Suppliers',
              color: color,
            ),
      ];

  // ---- Their own: as a trainer, as a member, and every gym.

  Future<List<SearchHit>> trained() async {
    final training = await ref.watch(myTrainingProvider.future);
    if (!training.gyms.any((g) => g.status == TrainerStatus.verified)) return const [];
    return [
      for (final m in await ref.watch(trainerMembersProvider.future))
        if (has([m.fullName, m.code, m.phone, m.venueName]))
          SearchHit(
            title: m.fullName,
            subtitle: [m.code, m.venueName].join(' · '),
            icon: Icons.groups_rounded,
            art: Art3D.person,
            route: GymRoutes.trainerMemberFor(m.gymMemberId),
            group: 'Members you train',
            color: color,
          ),
    ];
  }

  final memberOf = <String>{};
  Future<List<SearchHit>> myGyms() async {
    final gyms = (await ref.watch(myMembershipsProvider.future)).gyms;
    memberOf.addAll(gyms.map((g) => g.venueId));
    return [
      for (final g in gyms)
        if (has([g.venueName, g.place, g.memberCode, g.planName]))
          SearchHit(
            title: g.venueName,
            subtitle: [g.planName, if (g.endDate != null) 'Until ${formatDate(g.endDate!)}', g.place].whereType<String>().join(' · '),
            icon: Icons.fitness_center_rounded,
            art: Art3D.liftingWeights,
            route: GymRoutes.myGymFor(g.venueId),
            group: 'My gyms',
            color: color,
          ),
    ];
  }

  Future<List<SearchHit>> myClasses() async => [
        for (final b in await ref.watch(myClassBookingsProvider.future))
          if (has([b.name, b.trainerName, b.venueName]))
            SearchHit(
              title: b.name,
              subtitle: ['${formatShortDate(b.date)} ${b.time}', b.trainerName, b.venueName].whereType<String>().join(' · '),
              icon: Icons.event_available_outlined,
              art: Art3D.calendar,
              route: GymRoutes.myGymFor(b.venueId),
              group: 'My classes',
              color: color,
            ),
      ];

  Future<List<SearchHit>> gyms() async => [
        for (final v in await ref.watch(publicVenuesProvider((type: gymVenueType, dzongkhag: null)).future))
          if (has([v.name, v.place, v.address, v.description]))
            SearchHit(
              title: v.name,
              subtitle: v.place,
              icon: Icons.fitness_center_outlined,
              art: Art3D.officeBuilding,
              route: GymRoutes.gymFor(v.id),
              group: 'Gyms',
              color: color,
            ),
      ];

  final signedIn = ref.watch(currentUserIdProvider) != null;
  final found = await Future.wait([
    if (memberGyms.isNotEmpty) part(members),
    for (final g in mine) ...[
      part(() => requests(g)),
      part(() => enquiries(g)),
      part(() => payments(g)),
      part(() => classes(g)),
      part(() => trainers(g)),
      part(() => packages(g)),
      part(() => offers(g)),
      part(() => expenses(g)),
      part(() => stock(g)),
    ],
    if (stockGyms.isNotEmpty) part(suppliers),
    if (signedIn) ...[part(trained), part(myGyms), part(myClasses)],
    part(gyms),
  ]);
  final all = [for (final hits in found) ...hits];

  // A gym they work at or belong to is already found as theirs.
  final theirs = {for (final id in {...byId.keys, ...memberOf}) GymRoutes.gymFor(id)};
  return [
    for (final group in gymSearchGroups)
      ...bestFirst([
        for (final h in all)
          if (h.group == group && !(group == 'Gyms' && theirs.contains(h.route))) h,
      ], query)
          .take(searchGroupLimit),
  ];
}

/// [hits] with the best title matches first; equal ones keep their order.
/// Unlike [rankHits], it keeps those found by what isn't shown (an email,
/// a note), last.
List<SearchHit> bestFirst(List<SearchHit> hits, String query) {
  final scored = [for (var i = 0; i < hits.length; i++) (hit: hits[i], score: searchScore(hits[i], query), at: i)]
    ..sort((a, b) => a.score != b.score ? b.score.compareTo(a.score) : a.at.compareTo(b.at));
  return [for (final s in scored) s.hit];
}
