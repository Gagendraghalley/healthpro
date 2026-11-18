import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../access/access.dart';
import '../access/access_repository.dart';
import '../admin/admin_repository.dart';
import '../module/health_pro_module.dart';
import '../module/module_providers.dart';
import '../router/core_routes.dart';
import '../shell/service_nav.dart';
import '../theme/brand.dart';
import '../venues/venue_repository.dart';
import '../widgets/art3d.dart';
import '../widgets/motion.dart';

// The search in every page's bar (and Ctrl K / ⌘ K): one box for the whole
// app. It finds the pages and shortcuts the menu gives the person signed in,
// and what the services hold (members, packages, people...) as far as their
// roles let them see it. Nothing they couldn't open from the menu shows up.

/// One thing the search finds: a page, a shortcut, or a record in a service
/// (a member, a package), and the page that shows it.
class SearchHit {
  final String title;
  final String? subtitle;
  final IconData icon;
  final String route;

  /// Its 3D icon, as in the side menu; [icon] where there's none.
  final Art3D? art;

  /// Its heading in the results: 'Pages', 'Members'...
  final String group;

  /// Its service's colour; the accent for none.
  final Color? color;

  /// Other words it's found by, not shown: a page's service and section.
  final String keywords;

  const SearchHit({
    required this.title,
    required this.icon,
    required this.route,
    required this.group,
    this.art,
    this.subtitle,
    this.color,
    this.keywords = '',
  });
}

/// The words of [query], in lower case.
List<String> searchWords(String query) =>
    query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// How well [hit] matches [query]: 0 for not at all. Every word has to be in
/// its title, subtitle or keywords; it ranks higher for its title being the
/// query (4), starting with it (3), a word in it starting with it (2).
int searchScore(SearchHit hit, String query) {
  final words = searchWords(query);
  if (words.isEmpty) return 0;
  final title = hit.title.toLowerCase();
  final all = '$title ${hit.subtitle?.toLowerCase() ?? ''} ${hit.keywords.toLowerCase()}';
  if (!words.every(all.contains)) return 0;
  final whole = words.join(' ');
  if (title == whole) return 4;
  if (title.startsWith(whole)) return 3;
  if (' $title'.contains(' $whole')) return 2;
  return 1;
}

/// [hits] that match [query], best first; equal ones keep their order.
List<SearchHit> rankHits(List<SearchHit> hits, String query) {
  final scored = [
    for (var i = 0; i < hits.length; i++)
      if (searchScore(hits[i], query) case final score when score > 0) (hit: hits[i], score: score, at: i),
  ]..sort((a, b) => a.score != b.score ? b.score.compareTo(a.score) : a.at.compareTo(b.at));
  return [for (final s in scored) s.hit];
}

/// The pages and shortcuts the side menu gives the person signed in, to
/// search: the services' (their roles already decided which), then
/// Administration, then their own.
List<SearchHit> searchablePages({
  required bool platformPages,
  required List<ServiceNav> services,
  ServiceNav? admin,
  List<ModuleMenuItem> memberItems = const [],
}) {
  final pages = <SearchHit>[];
  final shortcuts = <SearchHit>[];
  void page(String title, IconData icon, String route,
      {Art3D? art, String? subtitle, Color? color, String keywords = ''}) {
    if (pages.any((p) => p.route == route && p.title == title)) return;
    pages.add(SearchHit(
        title: title, subtitle: subtitle, icon: icon, art: art, route: route, group: 'Pages', color: color, keywords: keywords));
  }

  if (platformPages) {
    page('Overview', Icons.space_dashboard_rounded, CoreRoutes.home, art: Art3D.house, keywords: 'home platform');
    page('My services', Icons.apps_rounded, CoreRoutes.services, art: Art3D.puzzle, keywords: 'services modules');
  }
  for (final nav in [...services, if (admin != null) admin]) {
    final where = nav.scope == null ? nav.name : '${nav.name} · ${nav.scope!.label}';
    for (final section in nav.sections) {
      for (final d in section.items) {
        if (d.route == null) continue;
        page(d.label, d.icon, d.route!, art: d.art, subtitle: where, color: nav.color, keywords: '${nav.name} ${section.title ?? ''}');
      }
    }
    for (final a in nav.actions) {
      shortcuts.add(SearchHit(
        title: a.label,
        subtitle: a.hint == null ? where : '${a.hint} · $where',
        icon: a.icon,
        art: a.art,
        route: a.route,
        group: 'Shortcuts',
        color: nav.color,
        keywords: 'new add ${nav.name}',
      ));
    }
  }
  page('My dashboard', Icons.dashboard_rounded, CoreRoutes.myQr,
      art: Art3D.idCard, subtitle: 'Your QR code and memberships', keywords: 'qr card me');
  for (final item in memberItems) {
    if (item.route != null) page(item.title, item.icon, item.route!, art: item.art, subtitle: item.subtitle, keywords: 'my me');
  }
  page('Notifications', Icons.notifications_none_rounded, CoreRoutes.notifications, art: Art3D.bell, keywords: 'alerts updates bell');
  page('Account', Icons.person_outline_rounded, CoreRoutes.account, art: Art3D.person, keywords: 'profile settings sign-in code me');
  return [...pages, ...shortcuts];
}

/// What the platform and its services hold that matches [query] (two
/// letters or more): venues, people, members, packages... each source only
/// as far as the signed-in person's roles let them see it. A source that
/// fails leaves the others' results.
final globalSearchProvider = FutureProvider.autoDispose.family<List<SearchHit>, String>((ref, query) async {
  final q = query.trim();
  if (q.length < 2) return const [];
  final access = await ref.watch(myAccessProvider.future);
  final modules = await ref.watch(enabledModulesProvider.future);
  Future<List<SearchHit>> safely(Future<List<SearchHit>> Function() find) async {
    try {
      return await find();
    } catch (_) {
      return const [];
    }
  }

  final found = await Future.wait([
    safely(() => _platformSearch(ref, q, access, modules)),
    for (final m in modules) safely(() => m.search(ref, q)),
  ]);
  return [for (final hits in found) ...hits];
});

/// The platform's own records: the venues they run, and for the Health Pro
/// team what their permissions show (people, organisations, venues to verify).
Future<List<SearchHit>> _platformSearch(Ref ref, String q, PlatformAccess access, List<HealthProModule> modules) async {
  final words = searchWords(q);
  bool has(Iterable<String?> texts) {
    final all = texts.whereType<String>().join(' ').toLowerCase();
    return words.every(all.contains);
  }

  Future<List<SearchHit>> venues() async => [
        for (final v in await ref.watch(myVenuesProvider.future))
          if (has([v.venue.name, v.venue.place, v.organisationName]))
            SearchHit(
              title: v.venue.name,
              subtitle: '${v.venue.place} · ${v.roleName}',
              icon: Icons.storefront_rounded,
              art: Art3D.officeBuilding,
              route: venueHomeRoute(modules, v.venue),
              group: 'Your venues',
            ),
      ];
  Future<List<SearchHit>> people() async => [
        for (final u in await ref.watch(accessRepositoryProvider).users(search: q, limit: 6))
          SearchHit(
            title: u.fullName.isEmpty ? (u.email ?? 'No name') : u.fullName,
            subtitle: [u.email, u.phone, if (!u.isActive) 'Turned off'].whereType<String>().join(' · '),
            icon: Icons.person_rounded,
            art: Art3D.person,
            route: CoreRoutes.adminUserFor(u.id),
            group: 'People',
            color: BrandColors.blue,
          ),
      ];
  Future<List<SearchHit>> organisations() async => [
        for (final o in await ref.watch(organisationsProvider.future))
          if (has([o.name, o.description]))
            SearchHit(
              title: o.name,
              subtitle: o.venueCount == 1 ? '1 venue' : '${o.venueCount} venues',
              icon: Icons.apartment_rounded,
              art: Art3D.classicalBuilding,
              route: CoreRoutes.adminOrganisationFor(o.id),
              group: 'Organisations',
              color: BrandColors.blue,
            ),
      ];
  Future<List<SearchHit>> toVerify() async => [
        for (final v in await ref.watch(pendingVenuesProvider.future))
          if (has([v.name, v.place]))
            SearchHit(
              title: v.name,
              subtitle: '${v.place} · Waiting to be verified',
              icon: Icons.fact_check_outlined,
              art: Art3D.magnifier,
              route: CoreRoutes.adminVenues,
              group: 'Venues to verify',
              color: BrandColors.blue,
            ),
      ];

  final found = await Future.wait([
    venues(),
    if (access.can(PlatformPermission.users)) people(),
    if (access.can(PlatformPermission.organisations)) organisations(),
    if (access.can(PlatformPermission.venuesVerify)) toVerify(),
  ]);
  return [for (final hits in found) ...hits];
}

/// Opens the search over the page. [pages] are what the side menu offers
/// ([searchablePages]); the services' records are looked up as they type.
/// The page chosen opens.
Future<void> showGlobalSearch(BuildContext context, {required List<SearchHit> pages}) async {
  final router = GoRouter.of(context);
  final route = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close search',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: Motion.of(context, Motion.modal),
    pageBuilder: (context, _, __) => GlobalSearchDialog(pages: pages),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Motion.ease, reverseCurve: Motion.easeIn);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -0.02), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
  if (route != null) router.go(route);
}

/// The search window: a box, and what it finds under headings, best first.
/// Up and down choose, Enter opens, Esc closes.
class GlobalSearchDialog extends ConsumerStatefulWidget {
  final List<SearchHit> pages;

  const GlobalSearchDialog({super.key, required this.pages});

  @override
  ConsumerState<GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends ConsumerState<GlobalSearchDialog> {
  late final _focus = FocusNode(onKeyEvent: _onKey);
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  Timer? _wait;

  /// What they've typed: the pages match it at once.
  String _query = '';

  /// What the services are asked: what was typed, once typing pauses.
  String _asked = '';

  /// The services' last answer, shown while the next one comes.
  List<SearchHit> _lastFound = const [];
  int _selected = 0;
  List<SearchHit> _shown = const [];

  @override
  void dispose() {
    _wait?.cancel();
    _focus.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed(String value) {
    setState(() {
      _query = value;
      _selected = 0;
    });
    _wait?.cancel();
    _wait = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _asked = value.trim());
    });
  }

  void _clear() {
    _text.clear();
    _changed('');
    _focus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      _move(key == LogicalKeyboardKey.arrowDown ? 1 : -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _move(int by) {
    if (_shown.isEmpty) return;
    setState(() => _selected = (_selected + by) % _shown.length);
    final target = _keys[_selected]?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: Motion.of(context, Motion.hover),
      curve: Motion.ease,
      alignmentPolicy:
          by > 0 ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  }

  void _open(SearchHit hit) => Navigator.of(context).pop(hit.route);

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final size = MediaQuery.sizeOf(context);
    final q = _query.trim();

    // Pages and shortcuts at once; with nothing typed, where to start.
    final List<SearchHit> pages;
    if (q.isEmpty) {
      pages = [
        ...widget.pages.where((p) => p.group == 'Shortcuts').take(4),
        ...widget.pages.where((p) => p.group == 'Pages').take(8),
      ];
    } else {
      // The group of the best match first.
      final ranked = rankHits(widget.pages, q);
      final matching = ranked.where((p) => p.group == 'Pages').take(8);
      final quick = ranked.where((p) => p.group == 'Shortcuts').take(4);
      pages = ranked.isNotEmpty && ranked.first.group == 'Shortcuts' ? [...quick, ...matching] : [...matching, ...quick];
    }

    // The services' records, a moment after typing stops.
    final asked = _asked.length >= 2 ? _asked : null;
    final answer = asked == null ? null : ref.watch(globalSearchProvider(asked));
    if (answer != null && answer.hasValue && !answer.isLoading) _lastFound = answer.value!;
    final found = q.length < 2 ? const <SearchHit>[] : _lastFound;
    final looking = q.length >= 2 && (asked != q || (answer?.isLoading ?? false));

    _shown = [...pages, ...found];
    if (_selected >= _shown.length) _selected = 0;

    // Under headings, in the order the hits come.
    final rows = <Widget>[];
    String? group;
    for (var i = 0; i < _shown.length; i++) {
      final hit = _shown[i];
      if (hit.group != group) {
        group = hit.group;
        rows.add(_Heading(q.isEmpty && group == 'Pages' ? 'Go to' : group));
      }
      rows.add(_ResultTile(
        key: _keys.putIfAbsent(i, GlobalKey.new),
        hit: hit,
        query: q,
        selected: i == _selected,
        onHover: () {
          if (_selected != i) setState(() => _selected = i);
        },
        onTap: () => _open(hit),
      ));
    }

    final wide = size.width >= 700;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, wide ? size.height * 0.1 : 12, 16, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 640, maxHeight: wide ? 560 : size.height * 0.8),
            child: Material(
              color: brand.card,
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: brand.glassBorder),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(boxShadow: brand.cardShadow),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _box(context),
                    Divider(height: 1, color: brand.glassBorder),
                    SizedBox(
                      height: 2,
                      child: looking ? LinearProgressIndicator(minHeight: 2, color: brand.accent, backgroundColor: Colors.transparent) : null,
                    ),
                    Flexible(
                      child: _shown.isEmpty && !looking && q.isNotEmpty
                          ? _NothingFound(query: q, short: q.length < 2)
                          : ListView(
                              controller: _scroll,
                              shrinkWrap: true,
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                              children: rows,
                            ),
                    ),
                    if (wide) _Footer(count: _shown.length),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _box(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 10, 6),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: brand.accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _text,
              focusNode: _focus,
              autofocus: true,
              onChanged: _changed,
              onSubmitted: (_) {
                if (_shown.isNotEmpty) _open(_shown[_selected]);
              },
              textInputAction: TextInputAction.search,
              style: TextStyle(fontSize: 16.5, color: brand.ink, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Search pages, people, members…',
                hintStyle: TextStyle(color: brand.muted, fontWeight: FontWeight.w400),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            IconButton(tooltip: 'Clear', icon: Icon(Icons.close_rounded, color: brand.muted, size: 20), onPressed: _clear)
          else
            IconButton(
              tooltip: 'Close',
              icon: Icon(Icons.close_rounded, color: brand.muted, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }
}

/// A heading over a group of results.
class _Heading extends StatelessWidget {
  final String text;

  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: context.brand.muted),
      ),
    );
  }
}

/// One result: its 3D icon as in the side menu (or a flat one on a tile of its service's colour), what it is, and
/// where; marked when chosen (by the arrows or the mouse).
class _ResultTile extends StatelessWidget {
  final SearchHit hit;
  final String query;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  const _ResultTile({
    super.key,
    required this.hit,
    required this.query,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final color = hit.color ?? brand.accent;
    final titleStyle = TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: brand.ink);
    return MouseRegion(
      onEnter: (_) => onHover(),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.hover),
          curve: Motion.ease,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? brand.accent.withValues(alpha: 0.09) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                // A 3D icon stands on its own, as in the side menu; a flat one on its tile.
                decoration: hit.art != null
                    ? null
                    : BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: hit.art == null
                    ? Icon(hit.icon, size: 19, color: color)
                    : Art3DIcon(hit.art!, size: 28, fallback: hit.icon, fallbackColor: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Marked(text: hit.title, query: query, style: titleStyle, mark: brand.accent),
                    if (hit.subtitle != null && hit.subtitle!.isNotEmpty)
                      Text(
                        hit.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: brand.muted),
                      ),
                  ],
                ),
              ),
              AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: Motion.of(context, Motion.hover),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.keyboard_return_rounded, size: 17, color: brand.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [text] with the part that matches [query] in [mark].
class _Marked extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle style;
  final Color mark;

  const _Marked({required this.text, required this.query, required this.style, required this.mark});

  @override
  Widget build(BuildContext context) {
    final lower = text.toLowerCase();
    final words = searchWords(query);
    final term = [words.join(' '), ...words].firstWhere((w) => w.isNotEmpty && lower.contains(w), orElse: () => '');
    final at = term.isEmpty || lower.length != text.length ? -1 : lower.indexOf(term);
    if (at < 0) return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: text.substring(0, at)),
        TextSpan(text: text.substring(at, at + term.length), style: TextStyle(color: mark, fontWeight: FontWeight.w800)),
        TextSpan(text: text.substring(at + term.length)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// Nothing matches: say so, and what to try.
class _NothingFound extends StatelessWidget {
  final String query;

  /// One letter: too short to look in the services.
  final bool short;

  const _NothingFound({required this.query, required this.short});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 36, color: brand.muted),
          const SizedBox(height: 10),
          Text('Nothing found for "$query"',
              textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            short ? 'Type another letter or two.' : 'Check the spelling, or try a name, phone number or code.',
            textAlign: TextAlign.center,
            style: TextStyle(color: brand.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// The keys, along the foot on a computer.
class _Footer extends StatelessWidget {
  final int count;

  const _Footer({required this.count});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final style = TextStyle(fontSize: 12, color: brand.muted);
    Widget hint(String key, String text) =>
        Row(mainAxisSize: MainAxisSize.min, children: [Keycap(key), const SizedBox(width: 6), Text(text, style: style)]);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: brand.surfaceAlt.withValues(alpha: 0.6),
        border: Border(top: BorderSide(color: brand.glassBorder)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [hint('↑↓', 'to choose'), hint('Enter', 'to open'), hint('Esc', 'to close')],
              ),
            ),
            const SizedBox(width: 12),
            Text(count == 1 ? '1 result' : '$count results', style: style),
          ],
        ),
      ),
    );
  }
}

/// A key on the keyboard, drawn small: 'Esc', '⌘', 'K'.
class Keycap extends StatelessWidget {
  final String label;

  /// The key's face; the theme's soft grey when null.
  final Color? fill;

  const Keycap(this.label, {super.key, this.fill});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: fill ?? brand.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: brand.fieldBorder.withValues(alpha: 0.8)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: brand.muted, height: 1.1),
      ),
    );
  }
}

/// Whether the keyboard's shortcut key is ⌘ (Apple) rather than Ctrl.
bool get _apple => defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;

/// The shortcut that opens the search, as its key cap shows it.
String get searchShortcutLabel => _apple ? '⌘K' : 'Ctrl K';

/// The shortcut's keys, one key cap each.
List<String> get searchShortcutKeys => _apple ? const ['⌘', 'K'] : const ['Ctrl', 'K'];

/// Whether [event] is the shortcut that opens the search: Ctrl K, or ⌘ K.
bool isSearchShortcut(KeyEvent event) =>
    event is KeyDownEvent &&
    event.logicalKey == LogicalKeyboardKey.keyK &&
    (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed);

/// The search on a phone or a small window: an icon in the bar.
class GlobalSearchButton extends StatelessWidget {
  final VoidCallback onPressed;

  const GlobalSearchButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) =>
      IconButton(tooltip: 'Search', icon: const Icon(Icons.search_rounded), onPressed: onPressed);
}

/// The search on a computer: a field in the middle of the bar, as tall as the
/// bar's buttons, with its shortcut's keys. In the light theme a soft grey
/// well with the search icon on an orange tile; under the mouse it turns
/// white with a warm edge and lifts. Keyboard focus rings it in the accent.
/// The dark theme keeps its look.
class GlobalSearchBox extends StatefulWidget {
  final VoidCallback onPressed;

  const GlobalSearchBox({super.key, required this.onPressed});

  /// Window widths from which the bar has the field rather than the icon.
  static const from = 1180.0;

  /// Whether the bar around [context] has the field.
  static bool shows(BuildContext context) => MediaQuery.sizeOf(context).width >= from;

  /// As tall as the bar's New button.
  static const height = 40.0;

  @override
  State<GlobalSearchBox> createState() => _GlobalSearchBoxState();
}

class _GlobalSearchBoxState extends State<GlobalSearchBox> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final duration = Motion.of(context, Motion.hover);
    final radius = BorderRadius.circular(12);
    final lit = _hover || _focus;
    final fill = brand.pick(lit ? LightColors.card : const Color(0xFFF1F4F9), brand.card);
    final edge = _focus
        ? brand.accent
        : _hover
            ? brand.pick(brand.accent.withValues(alpha: 0.45), brand.muted.withValues(alpha: 0.55))
            : brand.pick(LightColors.border, brand.fieldBorder);
    return Semantics(
      button: true,
      label: 'Search, $searchShortcutLabel',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onPressed,
          onHover: (v) => setState(() => _hover = v),
          onFocusChange: (v) => setState(() => _focus = v),
          borderRadius: radius,
          splashFactory: NoSplash.splashFactory,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          highlightColor: Colors.transparent,
          mouseCursor: SystemMouseCursors.text,
          child: AnimatedContainer(
            duration: duration,
            curve: Motion.ease,
            height: GlobalSearchBox.height,
            padding: const EdgeInsets.only(left: 6, right: 8),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: radius,
              border: Border.all(color: edge),
              boxShadow: [
                // In the light theme it lifts under the mouse; flat in the dark.
                BoxShadow(
                    color: brand.pick(lit ? const Color(0x140F172A) : const Color(0x000F172A), Colors.transparent),
                    blurRadius: 10,
                    offset: const Offset(0, 2)),
                // Keyboard focus: a ring.
                BoxShadow(color: brand.accent.withValues(alpha: _focus ? 0.16 : 0), spreadRadius: _focus ? 3 : 0),
              ],
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: duration,
                  curve: Motion.ease,
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: brand.pick(brand.accent.withValues(alpha: lit ? 0.16 : 0.1), Colors.transparent),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.search_rounded,
                      size: 18, color: brand.pick(brand.accentText, lit ? brand.body : brand.muted)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Search anything…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0, height: 1.2, color: brand.muted),
                  ),
                ),
                const SizedBox(width: 10),
                for (final (i, key) in searchShortcutKeys.indexed) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Keycap(key, fill: brand.pick(LightColors.card, brand.surfaceAlt)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// On a phone or a small window: the search's icon at the left of the bar
/// (close after the menu button where there is one), then [heading] (the
/// page's title). On a computer the field sits in the middle of the bar
/// instead ([GlassAppBar.search]).
class TitleWithSearch extends StatelessWidget {
  final Widget? heading;
  final VoidCallback onSearch;

  const TitleWithSearch({super.key, required this.heading, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GlobalSearchButton(onPressed: onSearch),
        if (heading != null) ...[const SizedBox(width: 4), Flexible(child: heading!)],
      ],
    );
  }
}
