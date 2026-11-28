import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import 'dashboard/gym_dashboard_page.dart';
import 'data/gym_repository.dart';
import 'data/trainers.dart';
import 'gym_permissions.dart';
import 'gym_routes.dart';
import 'screens/activity_screen.dart';
import 'screens/add_trainer_screen.dart';
import 'screens/ask_screen.dart';
import 'screens/enquiries_screen.dart';
import 'screens/expenses_screen.dart';
import 'screens/offers_screen.dart';
import 'screens/check_in_screen.dart';
import 'screens/gym_trainer_screens.dart';
import 'screens/supplier_screens.dart';
import 'screens/join_screens.dart';
import 'screens/member_registered_screen.dart';
import 'screens/members_screens.dart';
import 'screens/my_gyms_screen.dart';
import 'screens/payment_screens.dart';
import 'screens/public_screens.dart';
import 'screens/reports_screen.dart';
import 'screens/staff_screens.dart';
import 'screens/trainer_members_screen.dart';
import 'screens/trainer_screens.dart';
import 'screens/classes_screen.dart';
import 'shell/gym_navigation.dart';
import 'shell/gym_search.dart';
import 'welcome/gym_welcome_page.dart';

/// Gym management, the platform's first service. A gym's front desk
/// registers members (details, webcam photo, package for a number of
/// months), gives them a QR card (sent on WhatsApp) and checks them in with
/// it; owners set packages and prices, see income and reports, and choose
/// their staff's roles. Visitors see the public Welcome page and the gyms'
/// public pages.
class GymModule extends HealthProModule {
  const GymModule();

  @override
  String get key => gymModuleKey;

  @override
  String get name => 'Gym management';

  @override
  String get description => 'Manage memberships, check-ins, trainers and member payments.';

  @override
  IconData get icon => Icons.fitness_center_rounded;

  /// 'Join as Trainer' on sign-up leads to Become a trainer.
  @override
  String? get trainerSignUpRoute => GymRoutes.trainerProfile;

  @override
  Color get color => BrandColors.orange;

  @override
  List<String> get basePaths => const [GymRoutes.gyms, GymRoutes.trainers];

  @override
  List<String> get publicPaths => const [GymRoutes.gyms, GymRoutes.gym, GymRoutes.trainer];

  @override
  List<VenueKind> get venueKinds => const [
        VenueKind(
          key: gymVenueType,
          label: 'Gym',
          description: 'A gym or fitness centre with membership packages',
          icon: Icons.fitness_center_rounded,
          facilities: gymFacilities,
        ),
      ];

  /// Every page in the platform's frame. The register's 'new' comes before
  /// ':memberId', so it isn't taken for a member.
  @override
  List<RouteBase> get routes => [
        GoRoute(
            path: GymRoutes.gyms,
            builder: (_, s) => GymListScreen(nearMe: s.uri.queryParameters['near'] == '1', type: s.uri.queryParameters['type'])),
        GoRoute(path: GymRoutes.my, builder: (_, s) => MyGymScreen(gymId: s.uri.queryParameters['gym'])),
        GoRoute(path: GymRoutes.trainerHome, builder: (_, __) => const TrainerHomeScreen()),
        GoRoute(
          path: GymRoutes.trainerProfile,
          builder: (_, s) => TrainerProfileScreen(thenAskGymId: s.uri.queryParameters['gym']),
        ),
        GoRoute(path: GymRoutes.trainerMembers, builder: (_, __) => const TrainerMembersScreen()),
        GoRoute(path: GymRoutes.trainerMember, builder: (_, s) => TrainerMemberScreen(gymMemberId: s.pathParameters['memberId']!)),
        GoRoute(path: GymRoutes.chooseTrainer, builder: (_, s) => ChooseTrainerScreen(venueId: s.pathParameters['id']!)),
        GoRoute(
          path: GymRoutes.trainer,
          builder: (_, s) => TrainerPublicScreen(trainerId: s.pathParameters['id']!, venueId: s.uri.queryParameters['gym']),
        ),
        GoRoute(path: GymRoutes.pay, builder: (_, s) => PayOnlineScreen(venueId: s.pathParameters['id']!)),
        GoRoute(
          path: GymRoutes.gym,
          builder: (_, s) => GymDetailsScreen(venueId: s.pathParameters['id']!, join: s.uri.queryParameters['join'] == '1'),
        ),
        GoRoute(path: GymRoutes.dashboard, builder: (_, s) => GymDashboardPage(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.checkIn, builder: (_, s) => CheckInScreen(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.members, builder: (_, s) => MembersScreen(venueId: s.pathParameters['id']!)),
        GoRoute(
          path: GymRoutes.registerMember,
          builder: (_, s) => RegisterMemberScreen(
            venueId: s.pathParameters['id']!,
            personQr: s.uri.queryParameters['person'],
            requestId: s.uri.queryParameters['request'],
            prefillName: s.uri.queryParameters['name'],
            prefillPhone: s.uri.queryParameters['phone'],
          ),
        ),
        GoRoute(
          path: GymRoutes.editMember,
          builder: (_, s) => RegisterMemberScreen(venueId: s.pathParameters['id']!, memberId: s.pathParameters['memberId']),
        ),
        GoRoute(
          path: GymRoutes.memberRegistered,
          builder: (_, s) => MemberRegisteredScreen(venueId: s.pathParameters['id']!, memberId: s.pathParameters['memberId']!),
        ),
        GoRoute(
          path: GymRoutes.member,
          builder: (_, s) => GymMemberScreen(venueId: s.pathParameters['id']!, memberId: s.pathParameters['memberId']!),
        ),
        GoRoute(
          path: GymRoutes.plans,
          builder: (_, s) => PlansScreen(
              venueId: s.pathParameters['id']!,
              openNew: s.uri.queryParameters['new'] == '1',
              openId: s.uri.queryParameters[openParam]),
        ),
        GoRoute(path: GymRoutes.income, builder: (_, s) => IncomeScreen(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.reports, builder: (_, s) => ReportsScreen(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.ask, builder: (_, s) => AskScreen(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.requests, builder: (_, s) => JoinRequestsScreen(venueId: s.pathParameters['id']!, openId: s.uri.queryParameters[openParam])),
        GoRoute(path: GymRoutes.gymQr, builder: (_, s) => GymQrScreen(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.payments, builder: (_, s) => PaymentsToConfirmScreen(venueId: s.pathParameters['id']!, openId: s.uri.queryParameters[openParam])),
        GoRoute(path: GymRoutes.addTrainer, builder: (_, s) => AddTrainerScreen(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.gymTrainers, builder: (_, s) => GymTrainersScreen(venueId: s.pathParameters['id']!, openId: s.uri.queryParameters[openParam])),
        GoRoute(path: GymRoutes.settings, builder: (_, s) => MembershipSettingsScreen(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.suppliers, builder: (_, s) => SuppliersScreen(venueId: s.pathParameters['id']!, openId: s.uri.queryParameters[openParam])),
        GoRoute(path: GymRoutes.enquiries, builder: (_, s) => EnquiriesScreen(venueId: s.pathParameters['id']!, openId: s.uri.queryParameters[openParam])),
        GoRoute(path: GymRoutes.activity, builder: (_, s) => ActivityLogScreen(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.offers, builder: (_, s) => OffersScreen(venueId: s.pathParameters['id']!, openId: s.uri.queryParameters[openParam])),
        GoRoute(path: GymRoutes.expenses, builder: (_, s) => ExpensesScreen(venueId: s.pathParameters['id']!, openId: s.uri.queryParameters[openParam])),
        GoRoute(path: GymRoutes.classes, builder: (_, s) => ClassesScreen(venueId: s.pathParameters['id']!, openId: s.uri.queryParameters[openParam])),
      ];

  /// On a person's own dashboard, beside their QR code: their gyms,
  /// packages, requests and visits.
  @override
  Widget? buildMemberDashboard(BuildContext context) => const MyGymsDashboard();

  /// A person's own pages, in the side menu under their dashboard: Find
  /// services (every organisation on Health Pro, to join with their one
  /// account), My gym (the places they've joined, in full), and a trainer's
  /// page.
  @override
  List<ModuleMenuItem> playerMenuItems([WidgetRef? ref]) {
    final training = ref?.watch(myTrainingProvider).valueOrNull;
    return [
      const ModuleMenuItem(
        title: 'Services',
        subtitle: 'Gyms, pools, cycling, wellness and more near you: join any with your one account',
        icon: Icons.travel_explore_rounded,
        art: Art3D.magnifier,
        route: GymRoutes.gyms,
      ),
      const ModuleMenuItem(
        title: 'My services',
        subtitle: "Every service you've joined: your package and days left, photos, where it is and its trainers",
        icon: Icons.fitness_center_rounded,
        art: Art3D.liftingWeights,
        route: GymRoutes.my,
      ),
      if (training?.profile != null)
        ModuleMenuItem(
          title: training!.joinedPublicly ? 'Trainer profile' : 'My training',
          subtitle: training.joinedPublicly
              ? 'Your public profile, gyms, schedule and attendance'
              : 'Your gyms, schedule and attendance',
          icon: Icons.sports_rounded,
          art: Art3D.biceps,
          route: GymRoutes.trainerHome,
        ),
      // A trainer verified at a gym: the members they train.
      if (training?.gyms.any((g) => g.status == TrainerStatus.verified) ?? false)
        const ModuleMenuItem(
          title: 'My members',
          subtitle: 'The members you train: their progress, and their workout and diet plans',
          icon: Icons.groups_rounded,
          art: Art3D.person,
          route: GymRoutes.trainerMembers,
        ),
    ];
  }

  /// Per gym: Trainer where it verified them (not while they wait), to their
  /// trainer page; Member where they're registered, to My gym.
  @override
  List<AccountRole>? accountRoles(Ref ref) {
    final training = ref.watch(myTrainingProvider);
    final memberships = ref.watch(myMembershipsProvider);
    if ([training, memberships].any((v) => v.isLoading && !v.hasValue)) return null;
    return [
      for (final g in training.valueOrNull?.gyms ?? const [])
        if (g.status == TrainerStatus.verified)
          AccountRole(venueId: g.venueId, venueName: g.venueName, role: 'Trainer', route: GymRoutes.trainerHome),
      for (final g in memberships.valueOrNull?.gyms ?? const [])
        AccountRole(venueId: g.venueId, venueName: g.venueName, role: 'Member', route: GymRoutes.my),
    ];
  }

  @override
  ServiceNav? navigation(WidgetRef ref, String location) =>
      gymNavigation(ref, location, name: name, icon: icon, color: color);

  @override
  Future<List<SearchHit>> search(Ref ref, String query) => searchGyms(ref, query, color: color);

  @override
  Widget? buildOverviewCard(BuildContext context) => GymOverviewCard(name: name, icon: icon, color: color);

  /// For the core's pages that list a venue's pages.
  @override
  List<ModuleMenuItem> managerMenuItems(Venue venue, VenueAccess access) => [
        ModuleMenuItem(
          title: 'Dashboard',
          subtitle: 'Today, revenue, members and what just happened',
          icon: Icons.space_dashboard_rounded,
          route: GymRoutes.dashboardFor(venue.id),
        ),
        if (access.can(GymPermission.checkIn))
          ModuleMenuItem(
            title: 'Check-in',
            subtitle: 'Scan their QR card or type their member code',
            icon: Icons.qr_code_scanner_rounded,
            route: GymRoutes.checkInFor(venue.id),
          ),
        if (access.can(GymPermission.members))
          ModuleMenuItem(
            title: 'Members',
            subtitle: 'The register: packages, cards and visits',
            icon: Icons.groups_rounded,
            route: GymRoutes.membersFor(venue.id),
          ),
        if (access.can(GymPermission.register))
          ModuleMenuItem(
            title: 'Register member',
            subtitle: 'Details, photo and package',
            icon: Icons.person_add_alt_1_rounded,
            route: GymRoutes.registerMemberFor(venue.id),
          ),
        if (access.can(GymPermission.classes))
          ModuleMenuItem(
            title: 'Classes',
            subtitle: 'The weekly timetable of yoga, zumba and the rest, and who\'s booked into each',
            icon: Icons.event_note_rounded,
            route: GymRoutes.classesFor(venue.id),
          ),
        if (access.can(GymPermission.register))
          ModuleMenuItem(
            title: 'Enquiries & trials',
            subtitle: 'Walk-ins and free trials to follow up and sign up',
            icon: Icons.contact_phone_rounded,
            route: GymRoutes.enquiriesFor(venue.id),
          ),
        if (access.can(GymPermission.activity))
          ModuleMenuItem(
            title: 'Activity log',
            subtitle: 'Who registered, sold, took payments, paused or cancelled what',
            icon: Icons.manage_history_rounded,
            route: GymRoutes.activityFor(venue.id),
          ),
        if (access.can(GymPermission.payments))
          ModuleMenuItem(
            title: 'Payments to confirm',
            subtitle: 'Members who paid online: check the journal number, then confirm',
            icon: Icons.fact_check_outlined,
            route: GymRoutes.paymentsFor(venue.id),
          ),
        if (access.can(VenuePermission.edit))
          ModuleMenuItem(
            title: 'Membership settings',
            subtitle: 'Bank account for online payments, reminders, who answers requests to join',
            icon: Icons.tune_rounded,
            route: GymRoutes.settingsFor(venue.id),
          ),
        if (access.can(GymPermission.trainers))
          ModuleMenuItem(
            title: 'Trainers',
            subtitle: 'Add or verify trainers, their times and attendance',
            icon: Icons.sports_rounded,
            route: GymRoutes.gymTrainersFor(venue.id),
          ),
        if (access.can(GymPermission.inventory))
          ModuleMenuItem(
            title: 'Suppliers',
            subtitle: 'Items, stock and prices from connected suppliers',
            icon: Icons.storefront_outlined,
            route: GymRoutes.suppliersFor(venue.id),
          ),
        if (access.can(GymPermission.register))
          ModuleMenuItem(
            title: 'Join requests',
            subtitle: 'People who scanned the gym QR code and asked to join',
            icon: Icons.how_to_reg_rounded,
            route: GymRoutes.requestsFor(venue.id),
          ),
        if (access.can(GymPermission.plans))
          ModuleMenuItem(
            title: 'Memberships & packages',
            subtitle: 'What the front desk sells, and the prices',
            icon: Icons.sell_outlined,
            route: GymRoutes.plansFor(venue.id),
          ),
        if (access.can(GymPermission.plans))
          ModuleMenuItem(
            title: 'Offers & discounts',
            subtitle: 'Student, couple and other deals; every discount given, and why',
            icon: Icons.local_offer_outlined,
            route: GymRoutes.offersFor(venue.id),
          ),
        if (access.can(VenuePermission.income))
          ModuleMenuItem(
            title: 'Payments & income',
            subtitle: 'Payments month by month',
            icon: Icons.payments_outlined,
            route: GymRoutes.incomeFor(venue.id),
          ),
        if (access.can(VenuePermission.income))
          ModuleMenuItem(
            title: 'Expenses & profit',
            subtitle: 'What the gym spends, and what\'s left each month',
            icon: Icons.receipt_long_outlined,
            route: GymRoutes.expensesFor(venue.id),
          ),
        if (access.can(GymPermission.members))
          ModuleMenuItem(
            title: 'Reports & analytics',
            subtitle: 'Members, visits, packages and revenue over time',
            icon: Icons.insights_rounded,
            route: GymRoutes.reportsFor(venue.id),
          ),
      ];

  /// On a gym's staff pages, the Ask AI button opens that gym's own:
  /// questions about its members, visits and money.
  @override
  Widget? buildAssistant(BuildContext context, String location) {
    final id = gymIdInPath(location);
    return id == null ? null : GymAssistantPanel(venueId: id);
  }

  /// Not on Ask AI's own page.
  @override
  bool hidesAssistantButton(String location) => RegExp(r'^/gyms/[^/]+/manage/ask$').hasMatch(location);

  @override
  Map<String, ModuleMenuItem> get assistantLinks => const {
        'gyms': ModuleMenuItem(title: 'Gyms on Health Pro', icon: Icons.fitness_center_rounded, route: GymRoutes.gyms),
      };

  @override
  String? publicVenueRoute(Venue venue) => gymModuleRuns(venue) ? GymRoutes.gymFor(venue.id) : null;

  @override
  Widget? buildWelcome(BuildContext context) => const GymWelcomePage();

  @override
  String? managerHomeRoute(Venue venue) => GymRoutes.dashboardFor(venue.id);
}
