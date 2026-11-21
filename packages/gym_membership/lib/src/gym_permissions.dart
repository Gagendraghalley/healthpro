/// The gym module's venue permissions (20261108000003_gym_permissions.sql):
/// the database checks them; the app uses them to decide what to show.
/// Income is the core's VenuePermission.income.
abstract final class GymPermission {
  /// Register members at the front desk, change their details and photo,
  /// reissue their cards (20261108000004_gym_registration.sql).
  static const register = 'gym.register';

  /// See members, their memberships and check-ins.
  static const members = 'gym.members';

  /// Confirm payments to start memberships, and cancel requests.
  static const payments = 'gym.payments';

  /// Check members in.
  static const checkIn = 'gym.check_in';

  /// Plans and prices.
  static const plans = 'gym.plans';

  /// The Classes page: adding and changing classes on the timetable, who's
  /// booked into each, booking members in and taking anyone out, and who has
  /// registered to date (20261118000018_gym_classes_permission.sql,
  /// 20261121000002_gym_classes_right_keeps_timetable.sql).
  static const classes = 'gym.classes';

  /// Verify trainers who ask to train here; their timings and attendance
  /// (20261115000004_trainers.sql).
  static const trainers = 'gym.trainers';

  /// The gym's stock, and items from connected suppliers
  /// (20261118000009_gym_inventory.sql).
  static const inventory = 'gym.inventory';

  /// The activity log: who registered, sold, took payments, paused or
  /// cancelled what (20261118000006_gym_audit_log.sql). Enquiries are
  /// [register]'s.
  static const activity = 'gym.activity';
}
