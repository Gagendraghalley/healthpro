import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../access/access.dart';
import '../access/access_repository.dart';
import '../admin/admin_repository.dart';
import '../module/module_providers.dart';
import '../module/health_pro_module.dart';
import '../push/push_notifications.dart';
import '../router/core_routes.dart';
import '../search/global_search.dart';
import '../theme/brand.dart';
import '../utils/launch.dart';
import '../widgets/art3d.dart';
import '../widgets/logo.dart';
import '../widgets/motion.dart';
import 'app_shell.dart';
import 'service_nav.dart';
import 'start_page.dart';

/// Widths at which the menu shows beside the page; under it, a drawer.
const sideMenuFrom = 1100.0;

/// The side menu's widths: open, and folded to its icons.
const sideMenuWidth = 276.0;
const sideMenuFoldedWidth = 84.0;

/// The platform's frame around every signed-in page: one menu down the side
/// (a drawer on a phone, foldable to icons on a computer), the page beside
/// it.
///
/// The menu is made of services, not features: the platform's own pages
/// (Overview, My services, Notifications), then a section per service, each
/// with its icon, what it's working on (a gym of several) and its pages,
/// then Administration for the Health Pro team, then the company. Every
/// section starts closed, each one line, so twenty services stay one short
/// list; once the person has opened one, the section of the page being used
/// opens with it.
class PlatformShell extends ConsumerStatefulWidget {
  /// The page's path, for the menu to mark it.
  final String location;
  final Widget child;

  const PlatformShell({super.key, required this.location, required this.child});

  @override
  ConsumerState<PlatformShell> createState() => _PlatformShellState();
}

class _PlatformShellState extends ConsumerState<PlatformShell> {
  final _scaffold = GlobalKey<ScaffoldState>();

  /// A section opened (or closed, with null) by hand since the last page.
  /// They all start closed.
  String? _opened;
  bool _openedByHand = true;

  /// Whether the person has opened or closed a section yet: until then, going
  /// from page to page leaves them all closed.
  bool _touched = false;

  /// What the search finds without asking the services: the menu's pages
  /// and shortcuts, as of the last build.
  List<SearchHit> _pages = const [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    // After signing in, not on first opening: notifications on this device?
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && PushNotifications.configured) PushNotifications.maybeAsk(context, ref);
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Ctrl K (⌘ K) opens the search, unless something is open over the page.
  bool _onKey(KeyEvent event) {
    if (!isSearchShortcut(event) || !mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    _openSearch();
    return true;
  }

  void _openSearch() {
    if (_searching) return;
    _searching = true;
    showGlobalSearch(context, pages: _pages).whenComplete(() => _searching = false);
  }

  @override
  void didUpdateWidget(PlatformShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location && _touched) _openedByHand = false;
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.location;
    final access = ref.watch(myAccessProvider).valueOrNull ?? PlatformAccess.none;
    final platformPages = hasPlatformPages(access);
    // The super admin sees every service; anyone else only those they work
    // in, not the way to start one.
    final services = [
      for (final s in serviceNavs(ref, location))
        if (platformPages || s.nav.isSetUp) s,
    ];
    final admin = adminNav(access, pending: ref.watch(_pendingCountProvider));
    final memberItems = [
      for (final m in ref.watch(enabledModulesProvider).valueOrNull ?? const <HealthProModule>[])
        for (final item in m.playerMenuItems(ref))
          if (item.route != null) item,
    ];
    final active = [
      for (final s in services)
        if (s.nav.isOpenAt(location) || s.module.ownsPath(location)) s.nav,
      if (admin != null && admin.isOpenAt(location)) admin,
    ].firstOrNull;
    // Closed by default: only the service holding the page opens with it.
    final open = _openedByHand ? _opened : active?.key;
    _pages = searchablePages(
      platformPages: platformPages,
      services: [for (final s in services) s.nav],
      admin: admin,
      memberItems: memberItems,
    );

    final beside = MediaQuery.sizeOf(context).width >= sideMenuFrom;
    final folded = beside && ref.watch(sideMenuCollapsedProvider);
    Widget menu({required bool inDrawer}) => PlatformSidebar(
          location: location,
          services: [for (final s in services) s.nav],
          admin: admin,
          memberItems: memberItems,
          platformPages: platformPages,
          openSection: open,
          inDrawer: inDrawer,
          onToggleSection: (key) => setState(() {
            _touched = true;
            _openedByHand = true;
            _opened = open == key ? null : key;
          }),
          onFold: inDrawer ? null : () => ref.read(sideMenuCollapsedProvider.notifier).toggle(),
        );

    return Scaffold(
      key: _scaffold,
      backgroundColor: context.brand.background,
      drawer: beside ? null : Drawer(width: 300, child: menu(inDrawer: true)),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (beside)
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              width: folded ? sideMenuFoldedWidth : sideMenuWidth,
              child: menu(inDrawer: false),
            ),
          Expanded(
            child: AppShellScope(
              openMenu: beside ? null : () => _scaffold.currentState?.openDrawer(),
              openSearch: _openSearch,
              service: active,
              // Each page fades up into place: quick enough not to wait for.
              child: FadeSlideIn(key: ValueKey(location), offset: 14, duration: Motion.page, child: widget.child),
            ),
          ),
        ],
      ),
    );
  }
}

/// Venues waiting for the team to verify them, for those who verify.
final _pendingCountProvider = Provider<int>((ref) {
  final access = ref.watch(myAccessProvider).valueOrNull ?? PlatformAccess.none;
  if (!access.can(PlatformPermission.venuesVerify)) return 0;
  return ref.watch(pendingVenuesProvider).valueOrNull?.length ?? 0;
});

/// The Health Pro team's pages, as a section like a service's: what [access]
/// allows. Null for those not on the team.
ServiceNav? adminNav(PlatformAccess access, {int pending = 0}) {
  if (!access.isTeam) return null;
  return ServiceNav(
    key: 'platform_admin',
    name: 'Health Pro admin',
    icon: Icons.admin_panel_settings_rounded,
    color: BrandColors.blue,
    tagline: access.isSuperAdmin ? 'Super admin' : 'Health Pro team',
    homeRoute: CoreRoutes.admin,
    sections: [
      NavSection(items: [
        const NavDestination(
            label: 'Admin home', icon: Icons.home_work_outlined, art: Art3D.officeBuilding, route: CoreRoutes.admin, exact: true),
        if (access.can(PlatformPermission.users))
          const NavDestination(label: 'Users', icon: Icons.people_alt_outlined, art: Art3D.person, route: CoreRoutes.adminUsers),
        if (access.can(PlatformPermission.roles))
          const NavDestination(
              label: 'Roles & permissions', icon: Icons.verified_user_outlined, art: Art3D.key, route: CoreRoutes.adminRoles),
        if (access.can(PlatformPermission.organisations))
          const NavDestination(
              label: 'Organisations',
              icon: Icons.apartment_rounded,
              art: Art3D.classicalBuilding,
              route: CoreRoutes.adminOrganisations),
        if (access.can(PlatformPermission.venuesVerify))
          NavDestination(
              label: 'Venues to verify',
              icon: Icons.fact_check_outlined,
              art: Art3D.magnifier,
              route: CoreRoutes.adminVenues,
              badge: pending),
        if (access.can(PlatformPermission.masters))
          const NavDestination(
              label: 'Master data', icon: Icons.account_tree_outlined, art: Art3D.cardFileBox, route: CoreRoutes.adminMasters),
        if (access.can(PlatformPermission.modules))
          const NavDestination(
              label: 'Services on/off', icon: Icons.toggle_on_outlined, art: Art3D.plug, route: CoreRoutes.adminModules),
        if (access.can(PlatformPermission.errors))
          const NavDestination(
              label: 'App errors', icon: Icons.bug_report_outlined, art: Art3D.ladybird, route: CoreRoutes.adminErrors),
      ]),
    ],
  );
}

/// The side menu's colours: white with a hairline edge in the light theme,
/// deep navy in the dark; mixed while the theme switches, so the menu
/// glides with the page.
class SideInk {
  /// 0 light, 1 dark ([Brand.darkness]).
  final double t;

  const SideInk(this.t);

  factory SideInk.of(BuildContext context) => SideInk(context.brand.darkness);

  bool get dark => t >= 0.5;

  Color _pick(Color light, Color dark) => Color.lerp(light, dark, t)!;
  Color _white(Color light, double alpha) => _pick(light, Colors.white.withValues(alpha: alpha));

  /// The menu behind everything, top to bottom; its edge against the page.
  List<Color> get background =>
      [_pick(LightColors.card, BrandColors.slateNavy), _pick(LightColors.card, BrandColors.navy)];
  Color? get edge => t >= 1 ? null : _pick(LightColors.border, BrandColors.navy);

  /// A service's name, the page that's open, what's being worked on.
  Color get strong => _pick(LightColors.ink, Colors.white);

  /// A page's name, and under the mouse.
  Color get label => _white(const Color(0xFF475569), 0.72);
  Color get labelHover => _white(LightColors.ink, 0.92);

  /// Taglines, details, the company line.
  Color get quiet => _white(LightColors.muted, 0.5);

  /// Group headings ('SERVICES') and a service's own headings.
  Color get heading => _white(const Color(0xFF7D8A9E), 0.42);

  /// Small icons at a line's end (a chevron, opens elsewhere).
  Color get faint => _white(const Color(0xFF94A3B8), 0.6);

  /// Behind a line under the mouse, and the open page's (in its [accent]).
  Color get hover => _white(const Color(0xFFF3F6FA), 0.05);
  Color selected(Color accent) => _white(accent.withValues(alpha: 0.09), 0.1);

  /// Behind a service's header when it's open, and under the mouse.
  Color get sectionOpen => _white(LightColors.background, 0.06);
  Color get sectionHover => _white(const Color(0xFFF8FAFC), 0.04);

  /// The switcher's well, the find box and the fold button.
  Color get well => _white(LightColors.card, 0.05);
  Color get wellEdge => _white(LightColors.border, 0.08);
  Color get field => _white(LightColors.background, 0.06);
  Color get button => _white(LightColors.background, 0.08);
  Color get buttonIcon => _white(LightColors.muted, 0.85);

  /// Rules between groups.
  Color get rule => _white(LightColors.border, 0.08);  Color get foldedRule => _white(LightColors.border, 0.12);
}

/// The menu itself: the logo, the platform's pages, each service's section,
/// Administration, and the company (Innovates). Navy in the dark theme,
/// white in the light ([SideInk]).
class PlatformSidebar extends ConsumerStatefulWidget {
  final String location;
  final List<ServiceNav> services;
  final ServiceNav? admin;

  /// Everyone's own pages from the services (a member's gyms), under Me with
  /// their QR code.
  final List<ModuleMenuItem> memberItems;

  /// Overview, My services and Notifications: the super admin's.
  final bool platformPages;

  /// The key of the section that's open.
  final String? openSection;
  final ValueChanged<String> onToggleSection;

  /// In the phone's drawer, which closes before a page opens.
  final bool inDrawer;

  /// Folds the menu to its icons and back; null for no button (a drawer).
  final VoidCallback? onFold;

  const PlatformSidebar({
    super.key,
    required this.location,
    required this.services,
    required this.openSection,
    required this.onToggleSection,
    this.admin,
    this.memberItems = const [],
    this.platformPages = true,
    this.inDrawer = false,
    this.onFold,
  });

  /// Whether the menu around [context] shows only icons.
  static bool isFolded(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_Folded>()?.folded ?? false;

  @override
  ConsumerState<PlatformSidebar> createState() => _PlatformSidebarState();
}

class _PlatformSidebarState extends ConsumerState<PlatformSidebar> {
  /// With many services, a box to find one.
  static const _findFrom = 7;
  String _find = '';

  void _open(String route) {
    if (widget.inDrawer) Navigator.of(context).pop();
    context.go(route);
  }

  void _external(Uri url) {
    if (widget.inDrawer) Navigator.of(context).pop();
    openExternal(context, url);
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.location;
    final services = _find.isEmpty
        ? widget.services
        : widget.services.where((s) => s.name.toLowerCase().contains(_find.toLowerCase())).toList();

    Widget section(ServiceNav nav) => ServiceSection(
          nav: nav,
          location: location,
          open: widget.openSection == nav.key,
          onToggle: () => widget.onToggleSection(nav.key),
          onOpen: _open,
          onExternal: _external,
        );

    final ink = SideInk.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: ink.background,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: ink.edge == null || widget.inDrawer ? null : Border(right: BorderSide(color: ink.edge!)),
      ),
      child: SafeArea(
        right: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Folded, or folding: icons only, their names as tooltips.
            final folded = constraints.maxWidth < 200;
            final fold = widget.onFold == null ? null : _FoldButton(folded: folded, onPressed: widget.onFold!);
            final logo = HealthProLogo(height: folded ? 40 : 54, markOnly: folded, onDark: ink.dark);
            return _Folded(
              folded: folded,
              child: Padding(
                padding: EdgeInsets.fromLTRB(folded ? 12 : 14, 18, folded ? 12 : 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (folded) ...[
                      Center(child: logo),
                      if (fold != null) ...[const SizedBox(height: 12), Center(child: fold)],
                    ] else
                      Row(
                        children: [
                          Flexible(child: Align(alignment: Alignment.centerLeft, child: logo)),
                          if (fold != null) ...[const SizedBox(width: 8), fold],
                        ],
                      ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          if (widget.platformPages) ...[
                            SideNavTile(
                              icon: Icons.space_dashboard_rounded,
                              art: Art3D.house,
                              label: 'Overview',
                              selected: location == CoreRoutes.home,
                              onTap: () => _open(CoreRoutes.home),
                            ),
                            SideNavTile(
                              icon: Icons.apps_rounded,
                              art: Art3D.puzzle,
                              label: 'My services',
                              selected: location == CoreRoutes.services,
                              onTap: () => _open(CoreRoutes.services),
                            ),
                          ],
                          // Everyone's own: their dashboard (their QR code for
                          // the front desk, and what the services keep for
                          // them). Their alerts are the bell at the top.
                          if (widget.platformPages ||
                              widget.services.isNotEmpty ||
                              widget.memberItems.isNotEmpty ||
                              widget.admin != null)
                            const SideNavHeading('My Health Pro'),
                          SideNavTile(
                            icon: Icons.dashboard_rounded,
                            art: Art3D.idCard,
                            label: 'My dashboard',
                            selected: location == CoreRoutes.myQr,
                            onTap: () => _open(CoreRoutes.myQr),
                          ),
                          for (final item in widget.memberItems)
                            SideNavTile(
                              icon: item.icon,
                              art: item.art,
                              label: item.title,
                              selected: location == item.route,
                              onTap: () => _open(item.route!),
                            ),
                          if (widget.services.isNotEmpty) ...[
                            SideNavHeading('Services', count: widget.services.length),
                            if (widget.services.length >= _findFrom && !folded) _FindService(onChanged: (v) => setState(() => _find = v)),
                            for (final nav in services) section(nav),
                            if (services.isEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                                child: Text('No service called "$_find"', style: TextStyle(color: ink.quiet, fontSize: 12.5)),
                              ),
                          ],
                          if (widget.admin != null) ...[
                            const SideNavHeading('Administration'),
                            section(widget.admin!),
                          ],
                        ],
                      ),
                    ),
                    const _Company(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Folded extends InheritedWidget {
  final bool folded;

  const _Folded({required this.folded, required super.child});

  @override
  bool updateShouldNotify(_Folded oldWidget) => oldWidget.folded != folded;
}

/// The round button that folds the menu, or opens it out.
class _FoldButton extends StatelessWidget {
  final bool folded;
  final VoidCallback onPressed;

  const _FoldButton({required this.folded, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final ink = SideInk.of(context);
    return IconButton(
      tooltip: folded ? 'Expand menu' : 'Collapse menu',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: ink.button,
        foregroundColor: ink.buttonIcon,
        minimumSize: const Size(36, 36),
        fixedSize: const Size(36, 36),
        padding: EdgeInsets.zero,
      ),
      icon: AnimatedRotation(
        turns: folded ? 0.5 : 0,
        duration: const Duration(milliseconds: 240),
        child: const Icon(Icons.keyboard_double_arrow_left_rounded, size: 20),
      ),
    );
  }
}

/// A small heading between the menu's groups ('SERVICES 3'); a rule when
/// it's folded.
class SideNavHeading extends StatelessWidget {
  final String text;
  final int? count;

  const SideNavHeading(this.text, {super.key, this.count});

  @override
  Widget build(BuildContext context) {
    final ink = SideInk.of(context);
    if (PlatformSidebar.isFolded(context)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Divider(height: 1, color: ink.foldedRule),
      );
    }
    final style = TextStyle(color: ink.heading, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
      child: Row(
        children: [
          Expanded(child: Text(text.toUpperCase(), style: style)),
          if (count != null) Text('$count', style: style),
        ],
      ),
    );
  }
}

/// Finding a service by name, when there are many.
class _FindService extends StatelessWidget {
  final ValueChanged<String> onChanged;

  const _FindService({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final ink = SideInk.of(context);
    final dark = ink.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        onChanged: onChanged,
        style: TextStyle(color: ink.strong, fontSize: 13.5),
        cursorColor: dark ? Colors.white : context.brand.accent,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Find a service',
          hintStyle: TextStyle(color: dark ? Colors.white.withValues(alpha: 0.45) : ink.faint),
          prefixIcon: Icon(Icons.search_rounded, size: 18, color: dark ? Colors.white.withValues(alpha: 0.55) : ink.faint),
          filled: true,
          fillColor: ink.field,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: dark ? BorderSide.none : BorderSide(color: ink.wellEdge)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: dark ? Colors.white.withValues(alpha: 0.3) : context.brand.accent)),
        ),
      ),
    );
  }
}

/// The menu's one grid, top to bottom: every line's icon (a page's, a
/// service's tile, the gym's initials, a group's tile) centred on the same
/// column, every name starting at [label], every page's line the same height.
abstract final class _MenuGrid {
  /// A page's icon (its 3D icon, or a flat one centred in the same square):
  /// its left edge, and its size.
  static const inset = 8.0;
  static const icon = 28.0;

  /// The column every icon and tile is centred on.
  static const column = inset + icon / 2;

  /// Where every name starts.
  static const label = 46.0;

  /// Above and below a page's icon.
  static const rowPad = 7.0;
  static const text = 14.0;

  /// A group's pages, set in from its heading: they start under the
  /// heading's icon ([column]), with a smaller icon and text.
  static const childIcon = 24.0;
  static const childInset = 6.0;
  static const childText = 13.5;
}

/// One line of the menu: an icon and a label, marked when it's the page
/// open (a soft light and a bar in [accent]). Folded, the icon alone.
class SideNavTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final int badge;

  /// The bar's and icon's colour when it's open: the service's.
  final Color accent;

  final bool external;

  /// Its 3D icon, in place of [icon].
  final Art3D? art;

  /// One of a group's pages: set in under the group's heading, a size smaller.
  final bool nested;

  const SideNavTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.art,
    this.nested = false,
    this.selected = false,
    this.badge = 0,
    this.accent = BrandColors.orange,
    this.external = false,
  });

  @override
  State<SideNavTile> createState() => _SideNavTileState();
}

class _SideNavTileState extends State<SideNavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final ink = SideInk.of(context);
    final folded = PlatformSidebar.isFolded(context);
    final selected = widget.selected;
    final text = selected ? ink.strong : (_hover ? ink.labelHover : ink.label);
    // The brand's orange (a service's colour) shows as the colour they picked.
    final accent = context.brand.themed(widget.accent);
    final iconColor = selected ? accent : text;
    final badgeColor = context.brand.accent;
    final badge = widget.badge;
    final nested = widget.nested && !folded;
    final iconSize = nested ? _MenuGrid.childIcon : _MenuGrid.icon;
    final inset = nested ? _MenuGrid.childInset : _MenuGrid.inset;
    final Widget glyph = widget.art != null
        ? Art3DIcon(widget.art!, size: iconSize, fallback: widget.icon, fallbackColor: iconColor)
        : SizedBox.square(
            dimension: iconSize, child: Center(child: Icon(widget.icon, size: nested ? 18 : 20, color: iconColor)));
    final Widget content;
    if (folded) {
      content = Center(
        child: Badge(isLabelVisible: badge > 0, backgroundColor: badgeColor, smallSize: 8, child: glyph),
      );
    } else {
      content = Row(
        children: [
          // The icon leans in a touch under the mouse.
          AnimatedScale(
            scale: _hover && !selected && !reduceMotion(context) ? 1.1 : 1,
            duration: Motion.hover,
            curve: Motion.ease,
            child: glyph,
          ),
          const SizedBox(width: _MenuGrid.label - _MenuGrid.inset - _MenuGrid.icon),
          Expanded(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: text,
                // A group's pages a step lighter than its heading (w800).
                fontWeight: selected ? FontWeight.w700 : (nested ? FontWeight.w500 : FontWeight.w600),
                fontSize: nested ? _MenuGrid.childText : _MenuGrid.text,
              ),
            ),
          ),
          if (widget.external)
            Icon(Icons.open_in_new_rounded, size: 14, color: ink.dark ? Colors.white.withValues(alpha: 0.45) : ink.faint),
          if (badge > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(20)),
              child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
        ],
      );
    }
    final tile = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? ink.selected(accent) : (_hover ? ink.hover : ink.hover.withValues(alpha: 0)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Padding(
                  padding: folded
                      ? const EdgeInsets.symmetric(vertical: _MenuGrid.rowPad)
                      : EdgeInsets.fromLTRB(inset, _MenuGrid.rowPad, 10, _MenuGrid.rowPad),
                  child: content,
                ),
                // The bar down the left of the open page.
                Positioned(
                  left: 0,
                  top: 8,
                  bottom: 8,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: selected ? 3 : 0,
                    decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Padding(
      // A group's page is set in to its heading's icon column.
      padding: EdgeInsets.only(bottom: 2, left: nested ? _MenuGrid.column - 1.5 : 0),
      child: Semantics(
        button: true,
        selected: selected,
        label: folded ? (badge > 0 ? '${widget.label}, $badge' : widget.label) : null,
        child: folded ? Tooltip(message: widget.label, preferBelow: false, child: tile) : tile,
      ),
    );
  }
}

/// A service in the menu: its icon, name and the person's role in it; open,
/// what it's working on (with a switcher) and its pages in groups that open
/// and close under their headings ([navGroupsProvider]). Folded, its icon,
/// which opens its pages in a menu beside it.
class ServiceSection extends ConsumerWidget {
  final ServiceNav nav;
  final String location;
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<String> onOpen;
  final ValueChanged<Uri> onExternal;

  const ServiceSection({
    super.key,
    required this.nav,
    required this.location,
    required this.open,
    required this.onToggle,
    required this.onOpen,
    required this.onExternal,
  });

  void _go(NavDestination d) => d.isExternal ? onExternal(d.externalUrl!) : onOpen(d.route!);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = nav.isOpenAt(location);
    if (PlatformSidebar.isFolded(context)) return _foldedTile(context, active);
    final scope = nav.scope;
    // One group open at a time: the page's, or the one opened by hand.
    ref.watch(navGroupsProvider);
    final groups = ref.read(navGroupsProvider.notifier);
    final openGroup = groups.openIn(nav, location);
    Widget page(NavDestination d, {bool nested = false}) => SideNavTile(
          icon: d.icon,
          label: d.label,
          art: d.art,
          nested: nested,
          external: d.isExternal,
          badge: d.badge,
          accent: nav.color,
          selected: d.isOpenAt(location),
          onTap: () => _go(d),
        );
    // Each line's place as the section opens: they come in one after another.
    var line = 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ServiceHeader(nav: nav, open: open, active: active, onTap: onToggle),
          Collapsible(
            open: open,
            child: Padding(
              // Its lines on the menu's grid, under its header: not set in.
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (scope != null)
                    CollapsibleItem(index: line++, child: _ScopeSwitcher(scope: scope, color: nav.color, onOpen: onOpen)),
                  for (final s in nav.sections)
                    if (s.title == null)
                      for (final d in s.items) CollapsibleItem(index: line++, child: page(d))
                    else ...[
                      if (openGroup == s.keyIn(nav) case final groupOpen) ...[
                        CollapsibleItem(
                          index: line++,
                          child: _GroupHeading(
                            section: s,
                            color: s.color ?? nav.color,
                            open: groupOpen,
                            here: s.isOpenAt(location),
                            onTap: () => groups.choose(nav.key, groupOpen ? null : s.keyIn(nav), at: location),
                          ),
                        ),
                        CollapsibleItem(
                          index: line++,
                          child: Collapsible(
                            open: groupOpen,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final (j, d) in s.items.indexed)
                                  CollapsibleItem(index: j, child: page(d, nested: true)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Folded: the service's icon; its pages in a menu beside it.
  Widget _foldedTile(BuildContext context, bool active) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Tooltip(
        message: nav.name,
        preferBelow: false,
        child: Builder(
          builder: (context) => InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _flyout(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Center(
                  child: ServiceIconTile(icon: nav.icon, color: context.brand.themed(nav.color), filled: true, size: 38)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _flyout(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset(box.size.width + 8, 0), ancestor: overlay);
    final chosen = await showMenu<NavDestination>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, overlay.size.width - at.dx, 0),
      items: [
        PopupMenuItem<NavDestination>(
          enabled: false,
          child: Text(
            nav.scope == null ? nav.name : '${nav.name} · ${nav.scope!.label}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const PopupMenuDivider(),
        for (final s in nav.sections) ...[
          if (s.title != null)
            PopupMenuItem<NavDestination>(
              enabled: false,
              height: 34,
              child: Row(children: [
                Icon(s.icon ?? Icons.folder_outlined, size: 16, color: context.brand.themed(s.color ?? nav.color)),
                const SizedBox(width: 8),
                Text(s.title!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
              ]),
            ),
          for (final d in s.items)
            CheckedPopupMenuItem<NavDestination>(value: d, checked: d.isOpenAt(location), child: Text(d.label)),
        ],
      ],
    );
    if (chosen != null) _go(chosen);
  }
}

/// A group's heading in a service's section: its icon on a tile of its
/// colour (solid while one of its pages is open), its name in bold and a
/// chevron; closed, its pages' counts together.
class _GroupHeading extends StatefulWidget {
  final NavSection section;
  final Color color;
  final bool open;
  final bool here;
  final VoidCallback onTap;

  const _GroupHeading(
      {required this.section, required this.color, required this.open, required this.here, required this.onTap});

  @override
  State<_GroupHeading> createState() => _GroupHeadingState();
}

class _GroupHeadingState extends State<_GroupHeading> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final ink = SideInk.of(context);
    final s = widget.section;
    final color = context.brand.themed(widget.color);
    final here = widget.here;
    final badge = widget.open ? 0 : s.badge;
    const tile = 30.0;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Semantics(
        button: true,
        expanded: widget.open,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            onHover: (h) => setState(() => _hover = h),
            borderRadius: BorderRadius.circular(10),
            hoverColor: ink.hover,
            child: Padding(
              // Its tile on the menu's icon column, its name where every name starts.
              padding: const EdgeInsets.fromLTRB(_MenuGrid.column - tile / 2, 7, 10, 7),
              child: Row(
                children: [
                  if (s.art != null)
                    Art3DIcon(s.art!, size: tile, fallback: s.icon, fallbackColor: color)
                  else
                    AnimatedContainer(
                      duration: Motion.of(context, Motion.hover),
                      curve: Motion.ease,
                      width: tile,
                      height: tile,
                      decoration: BoxDecoration(
                        color: here ? color : color.withValues(alpha: ink.dark ? 0.2 : 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(s.icon ?? Icons.folder_outlined, size: 15, color: here ? Colors.white : color),
                    ),
                  const SizedBox(width: _MenuGrid.label - _MenuGrid.column - tile / 2),
                  Expanded(
                    child: Text(
                      s.title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: ink.strong, fontWeight: FontWeight.w800, fontSize: _MenuGrid.text),
                    ),
                  ),
                  // Closed over the page that's open: a dot says it's in here.
                  if (here && !widget.open)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                  if (badge > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(color: context.brand.accent, borderRadius: BorderRadius.circular(20)),
                      child: Text('$badge',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  AnimatedRotation(
                    turns: widget.open ? 0.5 : 0,
                    duration: Motion.of(context, Motion.dropdown),
                    curve: Motion.ease,
                    child: Icon(Icons.expand_more_rounded, size: 18, color: _hover || widget.open ? ink.label : ink.faint),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A service's icon on a tile of its colour: solid when it's the one in
/// use, and then glossy, like a 3D icon: lit from the top left, a shine
/// across its top and the icon raised off it.
class ServiceIconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool filled;
  final double size;

  const ServiceIconTile({super.key, required this.icon, required this.color, this.filled = false, this.size = 34});

  /// A glossy tile of [color]: lighter at the top left, deeper at the
  /// bottom right.
  static Gradient gloss(Color color) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.lerp(color, Colors.white, 0.26)!, color, Color.lerp(color, Colors.black, 0.16)!],
        stops: const [0, 0.5, 1],
      );

  /// The shine across a glossy tile's top half, laid over it.
  static BoxDecoration shine(BorderRadius radius) => BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [Colors.white.withValues(alpha: 0.36), Colors.white.withValues(alpha: 0)],
        ),
      );

  /// White on a glossy tile, raised off it by a soft shadow of its colour.
  static List<Shadow> raised(Color color, double size) =>
      [Shadow(color: Color.lerp(color, Colors.black, 0.5)!.withValues(alpha: 0.45), blurRadius: size * 0.08, offset: Offset(0, size * 0.04))];

  @override
  Widget build(BuildContext context) {
    // Softer in the light: a paler tint, and a shorter glow under it.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(size * 0.3);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? null : color.withValues(alpha: dark ? 0.18 : 0.12),
        gradient: filled ? gloss(color) : null,
        borderRadius: radius,
        boxShadow: filled
            ? [
                dark
                    ? BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))
                    : BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 8, offset: const Offset(0, 3)),
              ]
            : null,
      ),
      foregroundDecoration: filled ? shine(radius) : null,
      child: Icon(icon, size: size * 0.55, color: filled ? Colors.white : color, shadows: filled ? raised(color, size) : null),
    );
  }
}

class _ServiceHeader extends StatefulWidget {
  final ServiceNav nav;
  final bool open;
  final bool active;
  final VoidCallback onTap;

  const _ServiceHeader({required this.nav, required this.open, required this.active, required this.onTap});

  @override
  State<_ServiceHeader> createState() => _ServiceHeaderState();
}

class _ServiceHeaderState extends State<_ServiceHeader> {
  static const _tile = 32.0;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final nav = widget.nav;
    final ink = SideInk.of(context);
    return Semantics(
      button: true,
      expanded: widget.open,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: widget.active || widget.open
                ? ink.sectionOpen
                : (_hover ? ink.sectionHover : ink.sectionHover.withValues(alpha: 0)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                // On the menu's grid: its tile on the icon column, its name where every name starts.
                padding: const EdgeInsets.fromLTRB(_MenuGrid.column - _tile / 2, 8, 10, 8),
                child: Row(
                  children: [
                    // Always glossy, the service's own 3D tile.
                    ServiceIconTile(icon: nav.icon, color: context.brand.themed(nav.color), filled: true, size: _tile),
                    const SizedBox(width: _MenuGrid.label - _MenuGrid.column - _tile / 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nav.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: ink.strong, fontWeight: FontWeight.w700, fontSize: 14.5),
                          ),
                          if (nav.tagline != null)
                            Text(
                              nav.tagline!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: ink.quiet, fontSize: 11.5),
                            ),
                        ],
                      ),
                    ),
                    // The chevron, on a small white chip while it's open.
                    AnimatedContainer(
                      duration: Motion.of(context, Motion.hover),
                      curve: Motion.ease,
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: widget.open ? ink.well : ink.well.withValues(alpha: 0),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: widget.open ? ink.wellEdge : ink.wellEdge.withValues(alpha: 0)),
                      ),
                      child: AnimatedRotation(
                        turns: widget.open ? 0.5 : 0,
                        duration: Motion.of(context, Motion.dropdown),
                        curve: Motion.ease,
                        child: Icon(Icons.expand_more_rounded, color: widget.open || _hover ? ink.label : ink.faint, size: 19),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the service is working on (the gym); a menu to switch, and to add
/// another.
class _ScopeSwitcher extends StatelessWidget {
  final ServiceScope scope;
  final Color color;
  final ValueChanged<String> onOpen;

  const _ScopeSwitcher({required this.scope, required this.color, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final ink = SideInk.of(context);
    final several = scope.options.length > 1 || scope.addRoute != null;
    final initials = scope.label.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase();
    // On the menu's grid: the initials on the icon column (inside the card's
    // edge), the name where every name starts.
    const avatar = 28.0;
    final card = Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(_MenuGrid.column - avatar / 2 - 1, 8, 8, 8),
      decoration: BoxDecoration(
        color: ink.well,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ink.wellEdge),
      ),
      child: Row(
        children: [
          // The gym's initials on a glossy 3D tile, like the service's.
          Container(
            width: avatar,
            height: avatar,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: ServiceIconTile.gloss(context.brand.themed(color)),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(color: context.brand.themed(color).withValues(alpha: 0.28), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            foregroundDecoration: ServiceIconTile.shine(BorderRadius.circular(8)),
            child: Text(initials,
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                    shadows: ServiceIconTile.raised(context.brand.themed(color), avatar))),
          ),
          const SizedBox(width: _MenuGrid.label - _MenuGrid.column - avatar / 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(scope.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ink.strong, fontWeight: FontWeight.w700, fontSize: 13)),
                if (scope.detail != null)
                  Text(scope.detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: ink.dark ? Colors.white.withValues(alpha: 0.55) : ink.quiet, fontSize: 11.5)),
              ],
            ),
          ),
          if (several) Icon(Icons.unfold_more_rounded, color: ink.faint, size: 18),
        ],
      ),
    );
    if (!several) return card;
    return PopupMenuButton<String>(
      tooltip: scope.options.length > 1 ? 'Switch' : scope.label,
      position: PopupMenuPosition.under,
      onSelected: (value) => onOpen(value == '+' ? scope.addRoute! : scope.onSelect(value)),
      itemBuilder: (_) => [
        for (final o in scope.options)
          CheckedPopupMenuItem(
            value: o.id,
            checked: o.id == scope.currentId,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(o.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: o.detail == null ? null : Text(o.detail!, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        if (scope.addRoute != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: '+',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_business_outlined),
              title: Text(scope.addLabel ?? 'Add another'),
            ),
          ),
        ],
      ],
      child: card,
    );
  }
}

/// A section's pages: they slide open and fold away. Opening, its lines
/// ([CollapsibleItem]) come in one after another; closing, they fade
/// together. Folded, they're gone from the tree (not just hidden), once the
/// fold has finished.
class Collapsible extends StatefulWidget {
  final bool open;
  final Widget child;

  const Collapsible({super.key, required this.open, required this.child});

  @override
  State<Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<Collapsible> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: Motion.card, reverseDuration: Motion.dropdown, value: widget.open ? 1 : 0);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Motion.ease, reverseCurve: Motion.easeIn);

  @override
  void didUpdateWidget(Collapsible oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open == widget.open) return;
    if (reduceMotion(context)) {
      _c.value = widget.open ? 1 : 0;
    } else if (widget.open) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Unfolding(
      progress: _c,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => _c.isDismissed
            ? const SizedBox.shrink()
            : ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: _t.value,
                  // Opening, each line fades in itself.
                  child: Opacity(opacity: _c.status == AnimationStatus.forward ? 1 : _t.value, child: child),
                ),
              ),
        child: widget.child,
      ),
    );
  }
}

class _Unfolding extends InheritedWidget {
  final Animation<double> progress;

  const _Unfolding({required this.progress, required super.child});

  @override
  bool updateShouldNotify(_Unfolding oldWidget) => progress != oldWidget.progress;
}

/// A line of a [Collapsible]: as it opens, each comes in a moment after the
/// one above, easing in from the left. Still when the section is already
/// open, or when motion is reduced.
class CollapsibleItem extends StatelessWidget {
  final int index;
  final Widget child;

  const CollapsibleItem({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final progress = context.dependOnInheritedWidgetOfExactType<_Unfolding>()?.progress;
    if (progress == null) return child;
    final start = (index * 0.05).clamp(0.0, 0.4);
    final curve = Interval(start, start + 0.6, curve: Motion.ease);
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        final t = progress.status == AnimationStatus.forward ? curve.transform(progress.value) : 1.0;
        return Opacity(opacity: t, child: Transform.translate(offset: Offset(-14 * (1 - t), 0), child: child));
      },
      child: child,
    );
  }
}

/// The company behind Health Pro, at the foot of the menu: 'Developed by'
/// quiet, 'Innovates' in the brand's orange. Folded, just the name (the
/// whole line as its tooltip). Who is signed in is at the top right of the
/// page (AccountButton).
class _Company extends StatelessWidget {
  const _Company();

  static const _company = 'Innovates';

  @override
  Widget build(BuildContext context) {
    final ink = SideInk.of(context);
    // The orange that reads as text on the white menu; the brand's on navy.
    final name = TextStyle(
        color: ink.dark ? context.brand.highlight : context.brand.accentText,
        fontWeight: FontWeight.w800,
        fontSize: 13,
        letterSpacing: 0.2);
    final quiet = TextStyle(color: ink.quiet, fontWeight: FontWeight.w500, fontSize: 12);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: ink.rule))),
      child: PlatformSidebar.isFolded(context)
          ? Tooltip(
              message: 'Developed by $_company',
              child: FittedBox(fit: BoxFit.scaleDown, child: Text(_company, maxLines: 1, style: name)),
            )
          : Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Developed by ', style: quiet),
                TextSpan(text: _company, style: name),
              ]),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
    );
  }
}
