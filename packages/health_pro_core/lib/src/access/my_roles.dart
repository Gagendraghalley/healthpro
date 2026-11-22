import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../module/health_pro_module.dart';
import '../module/module_providers.dart';
import '../venues/venue.dart';
import '../venues/venue_repository.dart';
import 'access.dart';
import 'access_repository.dart';

// What the signed-in person is, by place: Health Pro's own role, then each
// venue with every role they have there. One account can be an owner at one
// gym, a trainer at another and a member at both; each gym keeps its own.

/// A role, and the page they work in as that ([route]; null for none).
typedef PlaceRole = ({String name, String? route});

/// A place and every role they have there; [venue] null for Health Pro's
/// own (super admin, team, or a plain member).
typedef RoleGroup = ({String? venue, List<PlaceRole> roles});

/// Their roles by place: Health Pro's first (super admin or team), then each
/// venue with all their roles there, as staff ([venues]: Owner, Front
/// desk..., to its console, [staffRoute]) and as the services know them
/// ([moduleRoles]: Trainer, Member), each once, staff first. 'Member' alone
/// when they have none.
List<RoleGroup> accountRoleGroups(PlatformAccess access, List<MyVenue> venues,
    [List<AccountRole> moduleRoles = const [], String? Function(MyVenue)? staffRoute]) {
  final byVenue = <String, ({String name, List<PlaceRole> roles})>{};
  void add(String venueId, String venueName, String role, String? route) {
    final roles = byVenue.putIfAbsent(venueId, () => (name: venueName, roles: <PlaceRole>[])).roles;
    if (!roles.any((r) => r.name == role)) roles.add((name: role, route: route));
  }

  for (final v in venues) {
    add(v.venue.id, v.venue.name, v.roleName, staffRoute?.call(v));
  }
  for (final r in moduleRoles) {
    add(r.venueId, r.venueName, r.role, r.route);
  }
  final groups = <RoleGroup>[
    if (access.isSuperAdmin) (venue: null, roles: const [(name: 'Super admin', route: null)])
    else if (access.isTeam) (venue: null, roles: const [(name: 'Health Pro team', route: null)]),
    for (final g in byVenue.values) (venue: g.name, roles: g.roles),
  ];
  return groups.isEmpty ? const [(venue: null, roles: [(name: 'Member', route: null)])] : groups;
}

/// Each role they have, once, for one line ('Owner · Trainer · Member'); a
/// plain member is a 'Health Pro member'.
String roleSummary(List<RoleGroup> groups) {
  final names = {for (final g in groups) for (final r in g.roles) r.name};
  return names.isEmpty || (names.length == 1 && names.first == 'Member') ? 'Health Pro member' : names.join(' · ');
}

/// Whether they're more than a member anywhere (staff, trainer, team).
bool hasRolesBeyondMember(List<RoleGroup> groups) => groups.any((g) => g.roles.any((r) => r.name != 'Member'));

/// The signed-in person's roles by place ([accountRoleGroups]); null until
/// all of it has loaded, so a trainer never flashes as 'Member'.
final myRoleGroupsProvider = Provider<List<RoleGroup>?>((ref) {
  final access = ref.watch(myAccessProvider).valueOrNull;
  final venues = ref.watch(myVenuesProvider).valueOrNull;
  final modules = ref.watch(enabledModulesProvider).valueOrNull;
  if (access == null || venues == null || modules == null) return null;
  final moduleRoles = [for (final m in modules) m.accountRoles(ref)];
  if (moduleRoles.contains(null)) return null;
  return accountRoleGroups(
      access, venues, [for (final r in moduleRoles) ...?r], (v) => venueHomeRoute(modules, v.venue));
});
