import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:health_pro_core/src/shell/account_menu.dart';

void main() {
  MyVenue gym(String name, String role, {String? roleName}) => MyVenue(
      Venue(id: name, type: 'gym', name: name, dzongkhag: 'Thimphu', verificationStatus: 'verified', createdAt: DateTime(2026)),
      role,
      roleName: roleName);

  const member = PlatformAccess(isSuperAdmin: false, isActive: true, permissions: {});

  test('someone who runs nothing is a member', () {
    expect(accountRoleLabels(member, const []), ['Member']);
  });

  test('their role at each gym they run, with its name', () {
    expect(accountRoleLabels(member, [gym('Iron Gym', 'owner'), gym('Core Fit', 'staff'), gym('Peak', 'x', roleName: 'Cleaner')]),
        ['Owner · Iron Gym', 'Front desk · Core Fit', 'Cleaner · Peak']);
  });

  test('super admin and the Health Pro team come first', () {
    const admin = PlatformAccess(isSuperAdmin: true, isActive: true, permissions: {});
    const team = PlatformAccess(isSuperAdmin: false, isActive: true, permissions: {'users.manage'});
    expect(accountRoleLabels(admin, const []), ['Super admin']);
    expect(accountRoleLabels(team, [gym('Iron Gym', 'trainer')]), ['Health Pro team', 'Trainer · Iron Gym']);
  });
}
