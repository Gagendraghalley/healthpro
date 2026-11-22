import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:health_pro_core/src/access/my_roles.dart';

void main() {
  MyVenue gym(String name, String role, {String? roleName}) => MyVenue(
      Venue(id: name, type: 'gym', name: name, dzongkhag: 'Thimphu', verificationStatus: 'verified', createdAt: DateTime(2026)),
      role,
      roleName: roleName);
  AccountRole at(String gym, String role, [String? route]) => AccountRole(venueId: gym, venueName: gym, role: role, route: route);

  /// Their roles by place, as text: 'Iron Gym: Owner, Member'.
  List<String> lines(List<RoleGroup> groups) => [
        for (final g in groups) '${g.venue ?? 'Health Pro'}: ${g.roles.map((r) => r.name).join(', ')}',
      ];

  const member = PlatformAccess(isSuperAdmin: false, isActive: true, permissions: {});

  test('someone with no role anywhere is a member', () {
    final groups = accountRoleGroups(member, const []);
    expect(lines(groups), ['Health Pro: Member']);
    expect(roleSummary(groups), 'Health Pro member');
    expect(hasRolesBeyondMember(groups), isFalse);
  });

  test('their role at each gym they run, by gym', () {
    expect(lines(accountRoleGroups(member, [gym('Iron Gym', 'owner'), gym('Core Fit', 'staff'), gym('Peak', 'x', roleName: 'Cleaner')])),
        ['Iron Gym: Owner', 'Core Fit: Front desk', 'Peak: Cleaner']);
  });

  test('every role at the same gym on its line, staff first, each once', () {
    final groups = accountRoleGroups(member, [gym('Iron Gym', 'owner'), gym('Peak', 'trainer')],
        [at('Peak', 'Trainer'), at('Gym Test', 'Trainer'), at('Iron Gym', 'Member'), at('Gym Test', 'Member'), at('Core Fit', 'Member')]);
    expect(lines(groups), ['Iron Gym: Owner, Member', 'Peak: Trainer', 'Gym Test: Trainer, Member', 'Core Fit: Member']);
    expect(roleSummary(groups), 'Owner · Member · Trainer');
    expect(hasRolesBeyondMember(groups), isTrue);
  });

  test('a member of several gyms is still just a member', () {
    final groups = accountRoleGroups(member, const [], [at('Iron Gym', 'Member'), at('Gym Test', 'Member')]);
    expect(lines(groups), ['Iron Gym: Member', 'Gym Test: Member']);
    expect(roleSummary(groups), 'Health Pro member');
    expect(hasRolesBeyondMember(groups), isFalse);
  });

  test('each role keeps the page it opens: staff to the console, the rest their own', () {
    final groups = accountRoleGroups(member, [gym('Iron Gym', 'owner')], [at('Iron Gym', 'Member', '/my-gym'), at('Peak', 'Trainer', '/trainer')],
        (v) => '/gyms/${v.venue.id}');
    expect([for (final g in groups) for (final r in g.roles) '${r.name} ${r.route}'],
        ['Owner /gyms/Iron Gym', 'Member /my-gym', 'Trainer /trainer']);
  });

  test('super admin and the Health Pro team come first', () {
    const admin = PlatformAccess(isSuperAdmin: true, isActive: true, permissions: {});
    const team = PlatformAccess(isSuperAdmin: false, isActive: true, permissions: {'users.manage'});
    expect(lines(accountRoleGroups(admin, const [])), ['Health Pro: Super admin']);
    expect(lines(accountRoleGroups(team, [gym('Iron Gym', 'trainer')], [at('Iron Gym', 'Member')])),
        ['Health Pro: Health Pro team', 'Iron Gym: Trainer, Member']);
  });
}
