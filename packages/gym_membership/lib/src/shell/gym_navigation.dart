import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/follow_ups.dart';
import '../data/gym_repository.dart';
import '../data/online_payments.dart';
import '../data/trainers.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import 'current_gym.dart';

/// The gym being worked at, from a page's [path]: a gym page
/// (`/gyms/<id>/manage/...`) or one of the core's pages for it
/// (`/manage/<id>/staff`, `/manage/<id>/edit`).
String? gymIdInPath(String path) =>
    GymRoutes.gymIdIn(path) ?? RegExp(r'^/manage/([0-9a-fA-F-]{36})(/|$)').firstMatch(path)?.group(1);

/// Whether [a] answers the gym's requests to join: whoever registers
/// members, unless the gym ([settings]) leaves them to its owner and managers.
bool answersJoinRequests(VenueAccess a, GymSettings? settings) =>
    a.can(GymPermission.register) &&
    (settings == null || !settings.managersAnswerJoins || VenueRole.hasEverything(a.role) || a.role == VenueRole.manager);

/// The menu groups' own colours, beside the brand's.
const _violet = Color(0xFF7C5CDB);
const _teal = Color(0xFF0E9384);

/// Gym management's section of the side menu: the gym (with a switcher for
/// someone at several), then its pages as their role there allows, in groups
/// (Front desk, Requests, Training, Sales & money, Stock, Team & settings);
/// and its shortcuts. For someone with no gym yet, the way to set one up.
ServiceNav gymNavigation(WidgetRef ref, String location,
    {required String name, required IconData icon, required Color color}) {
  final gyms = ref.watch(myGymsProvider).valueOrNull ?? const <MyVenue>[];
  final gym = currentGym(gyms, pathGymId: gymIdInPath(location), remembered: ref.watch(rememberedGymProvider));
  // What they run first (a gym, a pool...), then its form.
  const setUp = CoreRoutes.registerVenue;
  if (gym == null) {
    return ServiceNav(
      key: gymModuleKey,
      name: name,
      icon: icon,
      color: color,
      tagline: 'Not set up yet',
      isSetUp: false,
      homeRoute: setUp,
      sections: [
        NavSection(items: [NavDestination(label: 'Set up your gym', icon: Icons.rocket_launch_outlined, art: Art3D.rocket, route: setUp)]),
      ],
      actions: [
        ServiceAction(
            label: 'Set up your gym',
            icon: Icons.add_business_rounded,
            art: Art3D.rocket,
            route: setUp,
            hint: 'Then packages, staff and members'),
      ],
    );
  }

  final id = gym.venue.id;
  final a = gym.access;
  final register = GymRoutes.registerMemberFor(id);
  // Requests to join: whoever registers members, unless the gym leaves them
  // to its owner and managers.
  final answersJoins = answersJoinRequests(a, ref.watch(gymSettingsProvider(id)).valueOrNull);
  final waiting = answersJoins ? ref.watch(gymWaitingRequestsProvider(id)).valueOrNull ?? 0 : 0;
  final toConfirm = a.can(GymPermission.payments) ? ref.watch(gymWaitingPaymentsProvider(id)).valueOrNull ?? 0 : 0;
  final trainersWaiting = a.can(GymPermission.trainers)
      ? (ref.watch(gymTrainersProvider(id)).valueOrNull ?? const []).where((t) => t.status == TrainerStatus.pending).length
      : 0;
  // Enquiries to follow up today (or missed), and trials that have ended.
  final today = BhutanTime.today();
  final followUps = a.can(GymPermission.register)
      ? (ref.watch(gymEnquiriesProvider(id)).valueOrNull ?? const <GymEnquiry>[]).where((e) => e.needsActionOn(today)).length
      : 0;
  // Small groups, each opening and closing under its heading: the day's
  // work first, then what's waiting, training, money, stock and the team.
  final sections = [
    NavSection(items: [
      NavDestination(
          label: 'Dashboard',
          icon: Icons.space_dashboard_outlined,
          art: Art3D.chartIncreasing,
          route: GymRoutes.dashboardFor(id),
          exact: true),
      if (a.can(GymPermission.members))
        NavDestination(label: 'Reports & analytics', icon: Icons.insights_rounded, art: Art3D.barChart, route: GymRoutes.reportsFor(id)),
    ]),
    NavSection(title: 'Front desk', icon: Icons.room_service_rounded, art: Art3D.bellhopBell, color: BrandColors.orange, items: [
      if (a.can(GymPermission.checkIn))
        NavDestination(label: 'Check-in', icon: Icons.qr_code_scanner_rounded, art: Art3D.checkMark, route: GymRoutes.checkInFor(id)),
      if (a.can(GymPermission.members))
        NavDestination(label: 'Members', icon: Icons.groups_outlined, art: Art3D.person, route: GymRoutes.membersFor(id), notUnder: [register]),
      if (a.can(GymPermission.register))
        NavDestination(label: 'Register member', icon: Icons.person_add_alt_1_outlined, art: Art3D.memo, route: register),
      if (a.can(GymPermission.register))
        NavDestination(label: 'Gym QR code', icon: Icons.qr_code_2_rounded, art: Art3D.phoneScan, route: GymRoutes.gymQrFor(id)),
    ]),
    NavSection(title: 'Requests', icon: Icons.inbox_rounded, art: Art3D.inbox, color: BrandColors.amber, items: [
      if (answersJoins)
        NavDestination(
            label: 'Join requests',
            icon: Icons.how_to_reg_outlined,
            art: Art3D.handshake,
            route: GymRoutes.requestsFor(id),
            badge: waiting),
      if (a.can(GymPermission.payments))
        NavDestination(
            label: 'Payments to confirm',
            icon: Icons.fact_check_outlined,
            art: Art3D.creditCard,
            route: GymRoutes.paymentsFor(id),
            badge: toConfirm),
      if (a.can(GymPermission.register))
        NavDestination(
            label: 'Enquiries & trials',
            icon: Icons.contact_phone_outlined,
            art: Art3D.speechBalloon,
            route: GymRoutes.enquiriesFor(id),
            badge: followUps),
    ]),
    NavSection(title: 'Training', icon: Icons.directions_run_rounded, art: Art3D.runner, color: _violet, items: [
      if (a.can(GymPermission.classes))
        NavDestination(label: 'Classes', icon: Icons.event_note_outlined, art: Art3D.calendar, route: GymRoutes.classesFor(id)),
      if (a.can(GymPermission.trainers))
        NavDestination(
            label: 'Trainers',
            icon: Icons.sports_outlined,
            art: Art3D.biceps,
            route: GymRoutes.gymTrainersFor(id),
            badge: trainersWaiting),
    ]),
    NavSection(title: 'Sales & money', icon: Icons.account_balance_wallet_rounded, art: Art3D.moneyBag, color: BrandColors.green, items: [
      if (a.can(GymPermission.plans))
        NavDestination(label: 'Memberships & packages', icon: Icons.sell_outlined, art: Art3D.tickets, route: GymRoutes.plansFor(id)),
      if (a.can(GymPermission.plans))
        NavDestination(label: 'Offers & discounts', icon: Icons.local_offer_outlined, art: Art3D.priceTag, route: GymRoutes.offersFor(id)),
      if (a.can(VenuePermission.income))
        NavDestination(label: 'Payments & income', icon: Icons.payments_outlined, art: Art3D.coin, route: GymRoutes.incomeFor(id)),
      if (a.can(VenuePermission.income))
        NavDestination(label: 'Expenses & profit', icon: Icons.receipt_long_outlined, art: Art3D.receipt, route: GymRoutes.expensesFor(id)),
    ]),
    NavSection(title: 'Stock', icon: Icons.inventory_2_rounded, art: Art3D.package, color: _teal, items: [
      if (a.can(GymPermission.inventory))
        NavDestination(label: 'Suppliers', icon: Icons.storefront_outlined, art: Art3D.truck, route: GymRoutes.suppliersFor(id)),
    ]),
    NavSection(title: 'Team & settings', icon: Icons.settings_rounded, art: Art3D.gear, color: BrandColors.blue, items: [
      if (a.can(VenuePermission.staff))
        NavDestination(label: 'Staff', icon: Icons.badge_outlined, art: Art3D.officeWorker, route: CoreRoutes.venueStaffFor(id)),
      if (a.can(VenuePermission.roles))
        NavDestination(label: 'Roles & permissions', icon: Icons.verified_user_outlined, art: Art3D.key, route: CoreRoutes.venueRolesFor(id)),
      if (a.can(VenuePermission.edit))
        NavDestination(label: 'Gym settings', icon: Icons.tune_rounded, art: Art3D.tools, route: CoreRoutes.editVenueFor(id)),
      if (a.can(VenuePermission.edit))
        NavDestination(label: 'Membership settings', icon: Icons.card_membership_rounded, art: Art3D.knobs, route: GymRoutes.settingsFor(id)),
      if (a.can(GymPermission.activity))
        NavDestination(label: 'Activity log', icon: Icons.manage_history_rounded, art: Art3D.notepad, route: GymRoutes.activityFor(id)),
    ]),
  ];
  return ServiceNav(
    key: gymModuleKey,
    name: name,
    icon: icon,
    color: color,
    tagline: gym.roleName,
    homeRoute: GymRoutes.dashboardFor(id),
    scope: ServiceScope(
      currentId: id,
      label: gym.venue.name,
      detail: gym.venue.place,
      options: [for (final g in gyms) ServiceScopeOption(id: g.venue.id, label: g.venue.name, detail: g.venue.place)],
      onSelect: (gymId) {
        ref.read(rememberedGymProvider.notifier).state = gymId;
        return GymRoutes.dashboardFor(gymId);
      },
      addLabel: 'Register another gym',
      addRoute: setUp,
    ),
    sections: [for (final s in sections) if (s.items.isNotEmpty) s],
    // Never in the top bar: Members and Check-in show the New menu under it
    // (ServiceActionsButton.onPage); Overview and search keep the shortcuts.
    actionsInBar: false,
    actions: [
      if (a.can(GymPermission.checkIn))
        ServiceAction(
            label: 'Check in a member',
            icon: Icons.qr_code_scanner_rounded,
            art: Art3D.checkMark,
            route: GymRoutes.checkInFor(id),
            hint: 'Scan their QR card'),
      if (a.can(GymPermission.register))
        ServiceAction(
            label: 'Register a member',
            icon: Icons.person_add_alt_1_rounded,
            art: Art3D.memo,
            route: register,
            hint: 'Details, photo and package'),
      if (a.can(GymPermission.plans))
        ServiceAction(
            label: 'New package', icon: Icons.add_card_rounded, art: Art3D.tickets, route: GymRoutes.newPlanFor(id), hint: 'What the desk sells'),
      if (a.can(VenuePermission.staff))
        ServiceAction(
            label: 'Add staff',
            icon: Icons.group_add_outlined,
            art: Art3D.officeWorker,
            route: CoreRoutes.venueStaffFor(id),
            hint: 'And choose their role'),
    ],
  );
}

/// Gym management's card on Overview and My services: the gym, its numbers
/// today, and the way in; for someone with no gym, how to start.
class GymOverviewCard extends ConsumerWidget {
  final String name;
  final IconData icon;
  final Color color;

  const GymOverviewCard({super.key, required this.name, required this.icon, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gyms = ref.watch(myGymsProvider).valueOrNull ?? const <MyVenue>[];
    final gym = currentGym(gyms, remembered: ref.watch(rememberedGymProvider));
    if (gym == null) return _start(context);
    final id = gym.venue.id;
    final a = gym.access;
    final dash = ref.watch(gymDashboardProvider(id)).valueOrNull;
    final more = gyms.length - 1;
    return ServiceCard(
      icon: icon,
      color: color,
      name: name,
      subtitle: '${gym.venue.name} · ${gym.roleName}${more > 0 ? ' · +$more more' : ''}',
      status: gym.venue.isVerified
          ? null
          : StatusChip(label: 'Being verified', color: context.brand.warning, icon: Icons.hourglass_top_rounded),
      onOpen: () => context.go(GymRoutes.dashboardFor(id)),
      actions: [
        FilledButton.icon(
          onPressed: () => context.go(GymRoutes.dashboardFor(id)),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          icon: const Icon(Icons.space_dashboard_outlined, size: 18),
          label: const Text('Open dashboard'),
        ),
        if (a.can(GymPermission.checkIn))
          OutlinedButton.icon(
            onPressed: () => context.go(GymRoutes.checkInFor(id)),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
            label: const Text('Check in'),
          ),
        if (a.can(GymPermission.register))
          OutlinedButton.icon(
            onPressed: () => context.go(GymRoutes.registerMemberFor(id)),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: const Text('Register member'),
          ),
      ],
      child: dash == null
          ? const Shimmer(
              child: Row(children: [
                Expanded(child: SkeletonBox(height: 64, radius: 14)),
                SizedBox(width: 10),
                Expanded(child: SkeletonBox(height: 64, radius: 14)),
              ]),
            )
          : ServiceStats(stats: [
              ServiceStat(label: 'Active members', value: dash.active, color: BrandColors.blue),
              ServiceStat(label: 'Check-ins today', value: dash.checkInsToday, color: BrandColors.green),
              ServiceStat(label: 'Ending this week', value: dash.expiringSoon, color: BrandColors.amber),
              if (dash.incomeThisMonth != null)
                ServiceStat(
                  label: 'Income this month',
                  value: dash.incomeThisMonth!,
                  format: (v) => formatNu(v.round()),
                  color: BrandColors.orange,
                ),
            ]),
    );
  }

  /// No gym yet: the three steps, and the way in.
  Widget _start(BuildContext context) {
    final muted = context.brand.muted;
    Widget step(int n, String title, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Text('$n', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12.5)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '$title  ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: text, style: TextStyle(color: muted)),
                ])),
              ),
            ],
          ),
        );
    return ServiceCard(
      icon: icon,
      color: color,
      name: name,
      subtitle: 'Run your gym on Health Pro',
      status: StatusChip(label: 'Not set up', color: context.colors.tertiary),
      onOpen: () => context.go(CoreRoutes.registerVenue),
      actions: [
        FilledButton.icon(
          onPressed: () => context.go(CoreRoutes.registerVenue),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          icon: const Icon(Icons.rocket_launch_outlined, size: 18),
          label: const Text('Set up your gym'),
        ),
        Text(
          'Work at a gym? Its owner adds you on its Staff page; it shows here as soon as they do.',
          style: TextStyle(color: muted, fontSize: 12.5),
        ),
      ],
      child: Column(
        children: [
          step(1, 'Register your gym.', 'Its name, place and how members pay.'),
          step(2, 'Add your packages.', 'What the front desk sells, and the prices.'),
          step(3, 'Register members.', 'Photo, package and a QR card they show at the counter.'),
        ],
      ),
    );
  }
}
