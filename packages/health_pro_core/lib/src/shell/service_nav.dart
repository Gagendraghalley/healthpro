import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../module/module_providers.dart';
import '../module/health_pro_module.dart';
import '../widgets/art3d.dart';

// The side menu is made of services, not features. Each service (a module:
// gym management, later coaching...) describes its own
// pages for whoever is signed in; the platform draws every service the same
// way, one collapsible section each. A new service adds its section without
// anyone touching the menu.

/// A page in a service's menu, or a website ([externalUrl]).
class NavDestination {
  final String label;
  final IconData icon;
  final String? route;
  final Uri? externalUrl;

  /// Open only at [route] itself, not the pages under it (a dashboard whose
  /// path is the start of all the service's others).
  final bool exact;

  /// Also open under these paths (a gym's Staff page lives at the core's
  /// `/manage/<id>/staff`).
  final List<String> alsoUnder;

  /// Not open under these, though they're under [route] (Register member,
  /// its own entry, under Members).
  final List<String> notUnder;

  /// A count beside it: requests waiting, unread.
  final int badge;

  /// Its 3D icon in the side menu and the search; [icon] where there's none.
  final Art3D? art;

  const NavDestination({
    required this.label,
    required this.icon,
    this.art,
    this.route,
    this.externalUrl,
    this.exact = false,
    this.alsoUnder = const [],
    this.notUnder = const [],
    this.badge = 0,
  }) : assert((route == null) != (externalUrl == null), 'Give a route or an externalUrl');

  bool get isExternal => externalUrl != null;

  /// Whether [location] (a page's path) is this page, or under it.
  bool isOpenAt(String location) {
    if (route == null) return false;
    bool under(String base) => location == base || location.startsWith('$base/');
    if (exact) return location == route;
    if (notUnder.any(under)) return false;
    return under(route!) || alsoUnder.any(under);
  }
}

/// Some of a service's pages under a heading ('Front desk', 'Business') that
/// opens and closes them; a [title] of null for the first, unheaded ones,
/// always shown.
class NavSection {
  final String? title;
  final List<NavDestination> items;

  /// The heading's icon, on a small tile of [color] (the service's when null).
  final IconData? icon;
  final Color? color;

  /// The heading's 3D icon, in place of [icon]'s tile.
  final Art3D? art;

  const NavSection({this.title, required this.items, this.icon, this.color, this.art});

  /// Its key among every service's groups, for remembering it open or closed.
  String keyIn(ServiceNav nav) => '${nav.key}/$title';

  /// Whether [location] is one of its pages.
  bool isOpenAt(String location) => items.any((d) => d.isOpenAt(location));

  /// Its pages' counts together, shown on the heading while it's closed.
  int get badge => items.fold(0, (sum, d) => sum + d.badge);
}

/// One of the things a service can be working on: a gym of several.
class ServiceScopeOption {
  final String id;
  final String label;
  final String? detail;

  const ServiceScopeOption({required this.id, required this.label, this.detail});
}

/// What a service is working on, shown at the top of its section with a menu
/// to switch: the gym, for someone at several. [onSelect] remembers the
/// choice and answers the page to open.
class ServiceScope {
  final String currentId;
  final String label;
  final String? detail;
  final List<ServiceScopeOption> options;
  final String Function(String id) onSelect;

  /// 'Register another gym', and where it is.
  final String? addLabel;
  final String? addRoute;

  const ServiceScope({
    required this.currentId,
    required this.label,
    required this.options,
    required this.onSelect,
    this.detail,
    this.addLabel,
    this.addRoute,
  });
}

/// A shortcut a service offers: on Overview, the service's dashboard and the
/// bar's New menu (Register member, Check in, New package).
class ServiceAction {
  final String label;
  final IconData icon;
  final String route;

  /// A line under it on Overview.
  final String? hint;

  /// Its 3D icon in the search; [icon] where there's none.
  final Art3D? art;

  const ServiceAction({required this.label, required this.icon, required this.route, this.hint, this.art});
}

/// A service's place in the app for the person signed in: its name, icon and
/// colour, what it's working on, its pages (as their roles allow) and its
/// shortcuts. [HealthProModule.navigation] makes it.
class ServiceNav {
  /// The module's key.
  final String key;
  final String name;
  final IconData icon;
  final Color color;

  /// Under its name: their role ('Owner', 'Front desk'), or 'Set it up'.
  final String? tagline;

  /// Where its name leads: its dashboard.
  final String? homeRoute;
  final ServiceScope? scope;
  final List<NavSection> sections;
  final List<ServiceAction> actions;

  /// Whether the open page's top bar offers [actions] (its New button). They
  /// stay on Overview and in search either way.
  final bool actionsInBar;

  /// Whether they have something running in it (a gym), rather than only the
  /// way to start.
  final bool isSetUp;

  const ServiceNav({
    required this.key,
    required this.name,
    required this.icon,
    required this.color,
    required this.sections,
    this.tagline,
    this.homeRoute,
    this.scope,
    this.actions = const [],
    this.actionsInBar = true,
    this.isSetUp = true,
  });

  Iterable<NavDestination> get destinations => sections.expand((s) => s.items);

  /// The page of this service open at [location], if one is.
  NavDestination? openAt(String location) => destinations.where((d) => d.isOpenAt(location)).firstOrNull;

  bool isOpenAt(String location) => openAt(location) != null;
}

/// Every enabled service's menu for the person signed in, in app_modules'
/// order; [location] is the page open (it decides, say, which gym).
List<({HealthProModule module, ServiceNav nav})> serviceNavs(WidgetRef ref, String location) {
  final modules = ref.watch(enabledModulesProvider).valueOrNull ?? const <HealthProModule>[];
  return [
    for (final m in modules)
      if (m.navigation(ref, location) case final nav?) (module: m, nav: nav),
  ];
}
