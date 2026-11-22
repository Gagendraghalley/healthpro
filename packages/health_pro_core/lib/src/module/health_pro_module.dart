import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router/core_routes.dart';
import '../search/global_search.dart';
import '../shell/service_nav.dart';
import '../theme/brand.dart';
import '../utils/launch.dart';
import '../venues/venue.dart';
import '../widgets/art3d.dart';

/// What every Health Pro service (gym management, later
/// coaching, events...) gives the platform. A service is a module: a package
/// that depends only on health_pro_core, never on another module; the app
/// lists them in main.dart.
///
/// The platform draws every service the same way: its own section of the
/// side menu ([navigation]), its card on Overview and My services
/// ([buildOverviewCard]), its shortcuts. Adding one = a package implementing
/// this + one line in main.dart + one migration (its tables, and its row in
/// app_modules). Nothing else in the app changes.
abstract class HealthProModule {
  const HealthProModule();

  /// Matches app_modules.key, where admins turn the module on and off.
  String get key;
  String get name;
  String get description;
  IconData get icon;

  /// Its colour: its icon's tile in the menu, its cards, its accents.
  Color get color => BrandColors.blue;

  /// The paths the module's pages live under, e.g. ['/gyms', '/my-gym'].
  /// While the module is turned off, the router sends these home.
  List<String> get basePaths => const [];

  /// The module's pages, inside the platform's frame (the side menu) for
  /// signed-in users.
  List<RouteBase> get routes => const [];

  /// Pages with no frame: full screen, outside the side menu's.
  List<RouteBase> get fullScreenRoutes => const [];

  /// Route patterns visitors can open without signing in, e.g.
  /// ['/gyms', '/gyms/:id'].
  List<String> get publicPaths => const [];

  /// The kinds of venue it serves, offered on 'Register your venue'.
  List<VenueKind> get venueKinds => const [];

  /// For players and members: what the module offers them.
  List<ModuleMenuItem> playerMenuItems([WidgetRef? ref]) => const [];

  /// What the signed-in person is at each of this service's venues besides
  /// its staff (venue_staff gives those): e.g. a trainer a gym verified, a
  /// gym's member. The account menu and My dashboard show them by venue
  /// (myRoleGroupsProvider). Null while still loading; read providers with
  /// `ref.watch`.
  List<AccountRole>? accountRoles(Ref ref) => const [];

  /// The service's part of a person's own dashboard (My dashboard, beside
  /// their QR code): what it keeps for them, e.g. their gyms, packages and
  /// visits. It sits in a scrolling page, so it sizes to its content; null
  /// for nothing.
  Widget? buildMemberDashboard(BuildContext context) => null;

  /// For someone running [venue] (one of this module's [venueKinds]): the
  /// pages that run it that their role allows ([VenueAccess.can]).
  List<ModuleMenuItem> managerMenuItems(Venue venue, VenueAccess access) => const [];

  /// The service's section of the side menu for whoever is signed in: what
  /// it's working on (a gym of several), its pages that their roles allow,
  /// grouped, and its shortcuts. [location] is the open page's path. Null
  /// keeps it out of the menu; with nothing set up yet, a way to start.
  ///
  /// Read providers with `ref.watch`, so the menu follows them.
  ServiceNav? navigation(WidgetRef ref, String location) => null;

  /// What the search in the bar finds in this service for whoever is signed
  /// in (members, packages...): only what their roles let them open. Its
  /// pages are found from [navigation] already. [query] is two letters or
  /// more; read providers with `ref.watch`.
  Future<List<SearchHit>> search(Ref ref, String query) async => const [];

  /// The service's card on Overview and My services: how things stand for
  /// this person, and the way in. Null for a plain one from [name],
  /// [description] and [navigation] (or [playerMenuItems]).
  Widget? buildOverviewCard(BuildContext context) => null;

  /// The whole Welcome page for visitors, when this module is the first
  /// enabled one that has one (the app's lead service); null for none. With
  /// none, Welcome is the plain one: the logo, sign-up and sign-in.
  Widget? buildWelcome(BuildContext context) => null;

  /// Where someone running [venue] lands from Your venues: the module's own
  /// console (e.g. a gym's dashboard); null for the venue's Manage page.
  String? managerHomeRoute(Venue venue) => null;

  /// Shown above [managerMenuItems] on a venue's Manage page (e.g. today's
  /// numbers); null for nothing.
  Widget? buildManagerSection(BuildContext context, Venue venue, VenueAccess access) => null;

  /// What the Ask AI button (in the top bar) opens on [location] when this
  /// module has its own assistant there (a gym's Ask AI on that gym's staff
  /// pages), as an [AssistantPanel]; null for Health Pro's assistant, which
  /// answers questions about the platform.
  Widget? buildAssistant(BuildContext context, String location) => null;

  /// Pages without the Ask AI button: its chat is open full size there.
  bool hidesAssistantButton(String location) => false;

  /// Pages Health Pro's assistant may point people to, by the keys its guide
  /// uses (supabase/functions/ask-health-pro/reply.ts), e.g. 'gyms'.
  Map<String, ModuleMenuItem> get assistantLinks => const {};

  /// A venue's public page, for Health Pro's assistant's lists of venues;
  /// null when it has none in the app.
  String? publicVenueRoute(Venue venue) => null;

  /// Where someone who signs up as a trainer goes first: the module's page
  /// for setting up their trainer profile (gyms verify them from it). Null
  /// when the module has no trainers. With one, the sign-up page offers
  /// 'Join as Trainer'; everyone else joins as a member.
  String? get trainerSignUpRoute => null;

  /// Whether [path] is one of this module's pages.
  bool ownsPath(String path) => basePaths.any((base) => path == base || path.startsWith('$base/'));

  /// Whether this module runs venues of [venueType].
  bool servesVenueType(String venueType) => venueKinds.any((k) => k.key == venueType);
}

/// Where someone running [venue] lands: the console of the module that runs
/// it ([HealthProModule.managerHomeRoute]), or else the venue's Manage page.
String venueHomeRoute(Iterable<HealthProModule> modules, Venue venue) {
  for (final m in modules) {
    if (m.servesVenueType(venue.type)) return m.managerHomeRoute(venue) ?? CoreRoutes.venueManageFor(venue.id);
  }
  return CoreRoutes.venueManageFor(venue.id);
}

/// A kind of venue a module serves (venue_types.key), e.g. 'gym'.
class VenueKind {
  final String key;
  final String label;
  final String description;
  final IconData icon;

  /// What venues of this kind often have, offered as ticks on the form
  /// (a gym: shower, massage...); they add any others.
  final List<String> facilities;

  const VenueKind({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
    this.facilities = const [],
  });
}

/// Someone's [role] at one venue, e.g. Trainer at Iron Gym, and the page
/// they work in as that ([route]; null for none).
class AccountRole {
  final String venueId;
  final String venueName;
  final String role;
  final String? route;

  const AccountRole({required this.venueId, required this.venueName, required this.role, this.route});
}

/// A menu entry: a page in the app ([route]) or a website ([externalUrl]).
class ModuleMenuItem {
  final String title;
  final String? subtitle;
  final IconData icon;
  final String? route;
  final Uri? externalUrl;

  /// Its 3D icon in the side menu; [icon] elsewhere.
  final Art3D? art;

  const ModuleMenuItem(
      {required this.title, required this.icon, this.subtitle, this.route, this.externalUrl, this.art})
      : assert((route == null) != (externalUrl == null), 'Give a route or an externalUrl');

  bool get isExternal => externalUrl != null;

  Future<void> open(BuildContext context) async {
    if (route != null) {
      context.push(route!);
    } else {
      await openExternal(context, externalUrl!);
    }
  }
}
