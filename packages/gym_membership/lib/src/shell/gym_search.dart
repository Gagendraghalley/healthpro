import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/gym_repository.dart';
import '../data/online_payments.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import 'gym_navigation.dart';

/// What the search in the bar finds in gym management for [query], at the
/// gyms they work at, each as their role there allows, the same as the
/// menu: members (by name, phone, card code or email) with Members,
/// requests to join waiting with Join requests, trainers with Trainers,
/// packages with Memberships & packages. Every result opens one of those
/// pages; with several gyms, each says which gym. [color] is the service's.
Future<List<SearchHit>> searchGyms(Ref ref, String query, {required Color color}) async {
  final words = searchWords(query);
  bool has(Iterable<String?> texts) {
    final all = texts.whereType<String>().join(' ').toLowerCase();
    return words.every(all.contains);
  }

  final mine = [for (final v in await ref.watch(myVenuesProvider.future)) if (v.venue.type == gymVenueType) v];
  if (mine.isEmpty) return const [];
  final byId = {for (final g in mine) g.venue.id: g};
  String line(String venueId, Iterable<String?> parts) => [
        ...parts,
        if (mine.length > 1) byId[venueId]?.venue.name,
      ].whereType<String>().where((p) => p.trim().isNotEmpty).join(' · ');

  // One part failing (a list that won't load) leaves the others.
  Future<List<SearchHit>> part(Future<List<SearchHit>> Function() find) async {
    try {
      return await find();
    } catch (_) {
      return const [];
    }
  }

  final memberGyms = [for (final g in mine) if (g.access.can(GymPermission.members)) g.venue.id];
  Future<List<SearchHit>> members() async => [
        for (final m in await ref.watch(gymRepositoryProvider).searchMembers(memberGyms, query))
          // Only the gyms asked for, whatever comes back.
          if (memberGyms.contains(m.venueId))
            SearchHit(
              title: m.fullName,
              subtitle: line(m.venueId, [m.code, m.phone]),
              icon: Icons.person_rounded,
              art: Art3D.person,
              route: GymRoutes.memberFor(m.venueId, m.id),
              group: 'Members',
              color: color,
            ),
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
          SearchHit(
            title: r.name,
            subtitle: line(id, ['Wants to join', r.planName]),
            icon: Icons.how_to_reg_outlined,
            art: Art3D.handshake,
            route: GymRoutes.requestsFor(id),
            group: 'Join requests',
            color: color,
          ),
    ];
  }

  Future<List<SearchHit>> trainers(MyVenue gym) async {
    final id = gym.venue.id;
    if (!gym.access.can(GymPermission.trainers)) return const [];
    return [
      for (final t in await ref.watch(gymTrainersProvider(id).future))
        if (has([t.profile.name, t.profile.headline, t.email, t.phone, ...t.profile.specialties]))
          SearchHit(
            title: t.profile.name,
            subtitle: line(id, [t.status.label, t.profile.headline]),
            icon: Icons.sports_outlined,
            art: Art3D.biceps,
            route: GymRoutes.gymTrainersFor(id),
            group: 'Trainers',
            color: color,
          ),
    ];
  }

  Future<List<SearchHit>> packages(MyVenue gym) async {
    final id = gym.venue.id;
    if (!gym.access.can(GymPermission.plans)) return const [];
    return [
      for (final p in await ref.watch(gymPlansProvider((venueId: id, all: true)).future))
        if (has([p.name, p.description]))
          SearchHit(
            title: p.name,
            subtitle: line(id, ['${formatNu(p.price)} / ${formatDuration(p.durationDays)}', if (!p.isActive) 'Not on sale']),
            icon: Icons.sell_outlined,
            art: Art3D.tickets,
            route: GymRoutes.plansFor(id),
            group: 'Packages',
            color: color,
          ),
    ];
  }

  final found = await Future.wait([
    if (memberGyms.isNotEmpty) part(members),
    for (final g in mine) ...[part(() => requests(g)), part(() => trainers(g)), part(() => packages(g))],
  ]);
  final all = [for (final hits in found) ...hits];
  const order = ['Members', 'Join requests', 'Trainers', 'Packages'];
  return [
    for (final group in order) ...all.where((h) => h.group == group),
  ];
}
