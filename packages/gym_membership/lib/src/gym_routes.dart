import 'package:health_pro_core/health_pro_core.dart' show withOpen;

/// The gym module's pages. Everything lives under /gyms, so the router can
/// close them all while the module is turned off.
abstract final class GymRoutes {
  static const gyms = '/gyms';

  /// The gyms, nearest first (asks for the location).
  static const gymsNearMe = '/gyms?near=1';

  /// My gym: the gyms a member belongs to, each in full (photos, facilities,
  /// where it is, its trainers) with their membership there.
  /// Before ':id', so it isn't taken for a gym.
  static const my = '/gyms/my';

  /// My gym, opened on one of their gyms.
  static String myGymFor(String venueId) => '$my?gym=$venueId';

  // Public information, for visitors: the gyms on Health Pro and each gym's
  // page (its packages, prices and how to reach it).
  static const gym = '/gyms/:id';

  // Running a gym: its staff, by their role's permissions.
  static const dashboard = '/gyms/:id/manage';
  static const checkIn = '/gyms/:id/manage/check-in';
  static const members = '/gyms/:id/manage/members';
  static const registerMember = '/gyms/:id/manage/members/new';
  static const member = '/gyms/:id/manage/members/:memberId';
  static const editMember = '/gyms/:id/manage/members/:memberId/edit';

  /// Straight after registering them: done, and their QR card to send.
  static const memberRegistered = '/gyms/:id/manage/members/:memberId/registered';
  static const plans = '/gyms/:id/manage/plans';
  static const income = '/gyms/:id/manage/income';
  static const reports = '/gyms/:id/manage/reports';

  /// Ask AI: questions in their own words, answered with the gym's reports.
  static const ask = '/gyms/:id/manage/ask';

  /// Requests to join, from the gym's QR code; the desk adds or declines.
  static const requests = '/gyms/:id/manage/requests';

  /// The gym's QR code, to put up at the desk or entrance: scanned, it opens
  /// the gym's page, where people with Health Pro ask to join.
  static const gymQr = '/gyms/:id/manage/qr';

  /// Online payments (a journal number) for the desk to check and confirm.
  static const payments = '/gyms/:id/manage/payments';

  /// The bank account for online payments, reminders, and who answers
  /// requests to join.
  static const settings = '/gyms/:id/manage/settings';

  /// A member pays their gym online: package, payment QR, journal number.
  static const pay = '/gyms/my/:id/pay';

  /// A member chooses their trainer at one of their gyms.
  static const chooseTrainer = '/gyms/my/:id/trainer';

  /// A trainer's own: profile, certificates, gyms, times, attendance,
  /// members and reviews. Before ':id', so it isn't taken for a gym.
  static const trainerHome = '/gyms/trainer';
  static const trainerProfile = '/gyms/trainer/profile';

  /// A trainer's members, and one of them: progress and plans.
  static const trainerMembers = '/gyms/trainer/members';
  static const trainerMember = '/gyms/trainer/members/:memberId';
  static String trainerMemberFor(String gymMemberId) => '/gyms/trainer/members/$gymMemberId';

  /// A gym's trainers, for its staff: verify them, their times, attendance.
  static const gymTrainers = '/gyms/:id/manage/trainers';

  /// The gym adds a trainer itself, with all their details.
  static const addTrainer = '/gyms/:id/manage/trainers/new';

  /// What connected suppliers have (owner and managers): shown only, bought
  /// in the supplier's own system. Its address is from when it sat under
  /// the gym's inventory, since taken out.
  static const suppliers = '/gyms/:id/manage/inventory/suppliers';
  static String suppliersFor(String id, {String? open}) => withOpen('/gyms/$id/manage/inventory/suppliers', open);

  /// People who asked about the gym, on a free trial or to follow up.
  static const enquiries = '/gyms/:id/manage/enquiries';
  static String enquiriesFor(String id, {String? open}) => withOpen('/gyms/$id/manage/enquiries', open);

  /// Who did what at the gym (owner and managers).
  static const activity = '/gyms/:id/manage/activity';
  static String activityFor(String id) => '/gyms/$id/manage/activity';

  /// The gym's offers, and the discounts given (who sets prices).
  static const offers = '/gyms/:id/manage/offers';
  static String offersFor(String id, {String? open}) => withOpen('/gyms/$id/manage/offers', open);

  /// What the gym spends, and its profit (who sees income).
  static const expenses = '/gyms/:id/manage/expenses';
  static String expensesFor(String id, {String? open}) => withOpen('/gyms/$id/manage/expenses', open);

  /// The gym's weekly timetable, and who's booked into each class.
  static const classes = '/gyms/:id/manage/classes';
  static String classesFor(String id, {String? open}) => withOpen('/gyms/$id/manage/classes', open);

  /// Register member, filled in from an enquiry: their name and phone.
  static String registerEnquiryFor(String id, {required String name, required String phone}) =>
      Uri(path: '/gyms/$id/manage/members/new', queryParameters: {'name': name, 'phone': phone}).toString();

  /// A trainer's public profile (certificates, gyms, times, reviews); seen
  /// from a gym with `?gym=<its id>`.
  static const trainers = '/trainers';
  static const trainer = '/trainers/:id';

  static String gymFor(String id) => '/gyms/$id';
  static String dashboardFor(String id) => '/gyms/$id/manage';
  static String checkInFor(String id) => '/gyms/$id/manage/check-in';
  static String membersFor(String id) => '/gyms/$id/manage/members';
  static String registerMemberFor(String id) => '/gyms/$id/manage/members/new';

  /// Register member, for someone already on Health Pro: by the QR code they
  /// showed, or their request to join (which saving approves).
  static String addPersonFor(String id, {String? qrToken, String? requestId}) => Uri(
        path: '/gyms/$id/manage/members/new',
        queryParameters: {if (qrToken != null) 'person': qrToken, if (requestId != null) 'request': requestId},
      ).toString();
  static String requestsFor(String id, {String? open}) => withOpen('/gyms/$id/manage/requests', open);
  static String gymQrFor(String id) => '/gyms/$id/manage/qr';
  static String paymentsFor(String id, {String? open}) => withOpen('/gyms/$id/manage/payments', open);
  static String settingsFor(String id) => '/gyms/$id/manage/settings';
  static String payFor(String id) => '/gyms/my/$id/pay';
  static String chooseTrainerFor(String id) => '/gyms/my/$id/trainer';
  static String gymTrainersFor(String id, {String? open}) => withOpen('/gyms/$id/manage/trainers', open);
  static String addTrainerFor(String id) => '/gyms/$id/manage/trainers/new';

  /// Making a trainer profile on the way to asking gym [id] to train there.
  static String trainerProfileFor(String id) => '/gyms/trainer/profile?gym=$id';
  static String trainerFor(String id, {String? venueId}) => venueId == null ? '/trainers/$id' : '/trainers/$id?gym=$venueId';

  /// A gym's public page; [join] from its QR code (asks to join, up top).
  static String gymJoinFor(String id) => '/gyms/$id?join=1';
  static String memberFor(String id, String memberId) => '/gyms/$id/manage/members/$memberId';
  static String editMemberFor(String id, String memberId) => '/gyms/$id/manage/members/$memberId/edit';
  static String memberRegisteredFor(String id, String memberId) => '/gyms/$id/manage/members/$memberId/registered';
  static String plansFor(String id, {String? open}) => withOpen('/gyms/$id/manage/plans', open);

  /// Packages, with the form for a new one open.
  static String newPlanFor(String id) => '/gyms/$id/manage/plans?new=1';
  static String incomeFor(String id) => '/gyms/$id/manage/income';
  static String reportsFor(String id) => '/gyms/$id/manage/reports';
  static String askFor(String id) => '/gyms/$id/manage/ask';

  /// The gym whose staff page [path] is, if it's one.
  static String? gymIdIn(String path) =>
      RegExp(r'^/gyms/([0-9a-fA-F-]{36})/manage(/|$)').firstMatch(path)?.group(1);
}
