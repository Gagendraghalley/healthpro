import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/classes.dart';
import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../gym_routes.dart';
import '../widgets/class_widgets.dart';
import '../widgets/gym_public_widgets.dart';
import '../widgets/trainer_widgets.dart';
import '../data/trainers.dart';
import 'my_gyms_screen.dart';

/// How the list of gyms is ordered.
enum GymSort {
  suggested('Suggested'),
  nearest('Nearest first'),
  cheapest('Lowest price'),
  dearest('Highest price'),
  name('Name');

  final String label;

  const GymSort(this.label);
}

/// Budgets to filter by: gyms with a package at or under it.
const gymBudgets = [1000, 2000, 3000, 5000, 10000];

/// Every type of organisation at once, on Find services (its `?type=`).
const anyServiceType = 'all';

/// How far from the person Find services looks, once it knows where they
/// are; 0 for anywhere. It starts at [nearbyKm].
const nearbyDistances = [5, 10, 25, 50, 0];
const nearbyKm = 25;

/// 'Within 25 km', 'Anywhere'.
String withinText(int km) => km == 0 ? 'Anywhere' : 'Within $km km';

/// The area [venue] is in (its town), tidied; null without one.
String? venueArea(Venue venue) => (venue.town?.trim().isEmpty ?? true) ? null : venue.town!.trim();

/// Where a visitor looks for services: a dzongkhag, and one of its areas
/// (towns), or all of it when [town] is null.
typedef ServicesArea = ({String dzongkhag, String? town});

/// The area chosen on the welcome page (Where are you based?), this
/// session: Find services starts in it.
final servicesAreaProvider = StateProvider<ServicesArea?>((ref) => null);

/// The organisations [all] as the list shows them: of [type] (every type
/// when null or [anyServiceType]), in [dzongkhag] and [area] (all when
/// null), offering [service] (a facility, package or class), matching
/// [query] (name, place, type, facilities, packages and classes), with a
/// package within [budget] (any when null), in [sort] order; distances from
/// [here] when known, and then only those within [withinKm] of it (all when
/// null or 0; those with no place on the map are left out). [services] are
/// each one's packages and classes by name; [typeNames] each type's name.
List<({Venue gym, ({int low, int high})? price, double? km})> arrangeGyms(
  List<Venue> all, {
  required Map<String, ({int low, int high})> prices,
  String? dzongkhag,
  int? budget,
  GymSort sort = GymSort.suggested,
  LatLng? here,
  String? type,
  String? area,
  String? service,
  String query = '',
  Map<String, List<String>> services = const {},
  Map<String, String> typeNames = const {},
  int? withinKm,
}) {
  final words = searchWords(query);
  final near = here != null && withinKm != null && withinKm > 0;
  bool matches(Venue g) {
    if (words.isEmpty) return true;
    final text = [g.name, g.place, g.address, g.description, typeNames[g.type], ...g.facilities, ...?services[g.id]]
        .whereType<String>()
        .join(' ')
        .toLowerCase();
    return words.every(text.contains);
  }

  bool offers(Venue g) {
    if (service == null) return true;
    final wanted = service.toLowerCase();
    return [...g.facilities, ...?services[g.id]].any((s) => s.trim().toLowerCase() == wanted);
  }

  final rows = [
    for (final g in all)
      if ((type == null || type == anyServiceType || g.type == type) &&
          (dzongkhag == null || g.dzongkhag == dzongkhag) &&
          (area == null || venueArea(g) == area) &&
          offers(g) &&
          matches(g))
        (
          gym: g,
          price: prices[g.id],
          km: here == null || !g.hasLocation ? null : distanceKm(here.latitude, here.longitude, g.latitude!, g.longitude!),
        ),
  ]
      .where((r) => budget == null || (r.price != null && r.price!.low <= budget))
      .where((r) => !near || (r.km != null && r.km! <= withinKm))
      .toList();
  int byNull(num? a, num? b) => a == null ? (b == null ? 0 : 1) : (b == null ? -1 : a.compareTo(b));
  switch (sort) {
    case GymSort.nearest:
      rows.sort((a, b) => byNull(a.km, b.km));
    case GymSort.cheapest:
      rows.sort((a, b) => byNull(a.price?.low, b.price?.low));
    case GymSort.dearest:
      rows.sort((a, b) {
        final x = a.price?.high, y = b.price?.high;
        if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1;
        return y.compareTo(x);
      });
    case GymSort.name:
      rows.sort((a, b) => a.gym.name.toLowerCase().compareTo(b.gym.name.toLowerCase()));
    case GymSort.suggested:
      break;
  }
  return rows;
}

/// The services most of [venues] offer (their facilities, packages and
/// classes), most common first, at most [limit]: the Service filter's
/// choices.
List<String> commonServices(Iterable<Venue> venues, Map<String, List<String>> services, {int limit = 20}) {
  final counts = <String, int>{};
  final spelling = <String, String>{};
  for (final v in venues) {
    for (final s in {for (final s in [...v.facilities, ...?services[v.id]]) if (s.trim().isNotEmpty) s.trim().toLowerCase(): s.trim()}.entries) {
      counts[s.key] = (counts[s.key] ?? 0) + 1;
      spelling.putIfAbsent(s.key, () => s.value);
    }
  }
  final keys = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!) != 0 ? counts[b]!.compareTo(counts[a]!) : a.compareTo(b));
  return [for (final k in keys.take(limit)) spelling[k]!];
}

/// The organisation types Find services offers: the master's ones in use
/// that this module runs, in its order, and any other type a verified
/// organisation has (while the master loads, or if it can't).
List<VenueType> findableTypes(List<VenueType> master, List<Venue> venues) {
  final types = [for (final t in master) if (t.isActive && t.moduleKey == gymModuleKey) t];
  for (final key in {for (final v in venues) v.type}) {
    if (!types.any((t) => t.key == key)) {
      types.add(venueTypeOf(master, key) ??
          VenueType(key: key, moduleKey: gymModuleKey, name: venueTypeName(master, key), icon: key == gymVenueType ? 'fitness' : 'health'));
    }
  }
  return types;
}

/// Find services: public information about every verified organisation on
/// Health Pro. It starts with the kinds of service (Gym, Swimming Pool,
/// Cycling, Wellness Centre...: the Service types master), each with
/// how many there are; choosing one lists those organisations, each with its
/// photo, opening hours and price range. It starts from where the person is
/// (they're asked once), nearest first; anyone narrows it by dzongkhag, area,
/// a service (sauna, yoga, swimming lessons...), a search, a budget, and
/// sorts by price. What the Welcome page's Services opens; no account
/// needed, and members join any of them with their one account.
class GymListScreen extends ConsumerStatefulWidget {
  /// Ask for the location straight away (Gyms near me).
  final bool nearMe;

  /// The type to list straight away (a link's `?type=`), [anyServiceType]
  /// for all; null to choose first.
  final String? type;

  const GymListScreen({super.key, this.nearMe = false, this.type});

  @override
  ConsumerState<GymListScreen> createState() => _GymListScreenState();
}

class _GymListScreenState extends ConsumerState<GymListScreen> {
  late String? _type = widget.type;
  // Where the welcome page left them, if they chose.
  late String? _dzongkhag = ref.read(servicesAreaProvider)?.dzongkhag;
  late String? _area = ref.read(servicesAreaProvider)?.town;
  String? _service;
  int? _budget;
  GymSort? _sort;
  int _within = nearbyKm;
  bool _locating = false;
  final _searchField = TextEditingController();
  String _search = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ref.read(myLocationProvider) != null) return;
      if (widget.nearMe) {
        _nearMe();
      } else if (!ref.read(locationLookedUpProvider)) {
        _startFromHere();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchField.dispose();
    super.dispose();
  }

  /// The person's location as where the list starts from, without a fuss:
  /// once a session, and nothing said when it can't be had.
  Future<void> _startFromHere() async {
    ref.read(locationLookedUpProvider.notifier).state = true;
    final here = await locationIfAllowed();
    if (!mounted || here == null || ref.read(myLocationProvider) != null) return;
    ref.read(myLocationProvider.notifier).state = here;
  }

  Future<void> _nearMe() async {
    if (ref.read(myLocationProvider) != null) {
      // Off again: the list as it was.
      ref.read(myLocationProvider.notifier).state = null;
      if (_sort == GymSort.nearest) setState(() => _sort = null);
      return;
    }
    setState(() => _locating = true);
    final ok = await runAction(context, () async {
      final here = await currentLocation();
      ref.read(myLocationProvider.notifier).state = here;
    });
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (ok) _sort = GymSort.nearest;
    });
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _search = text.trim());
    });
  }

  /// A type chosen (null: back to choosing); the filters of the last go.
  void _choose(String? type) => setState(() {
        _type = type;
        _area = null;
        _service = null;
        if (type == null) {
          _searchField.clear();
          _search = '';
        }
      });

  /// [chips] in a row: wrapping onto more lines, or on a phone one line
  /// swiped along.
  Widget _chips(BuildContext context, List<Widget> chips) {
    if (MediaQuery.sizeOf(context).width >= 600) {
      return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: chips);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [for (final (i, chip) in chips.indexed) ...[if (i > 0) const SizedBox(width: 8), chip]]),
    );
  }

  Widget _searchBox({required String hint}) => TextField(
        controller: _searchField,
        onChanged: _onSearch,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchField.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _searchField.clear();
                    _onSearch('');
                  },
                ),
        ),
      );

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(left: 2, right: 4),
        child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.brand.muted)),
      );

  Widget _divider(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: context.brand.glassBorder));

  /// Near me (asks for the location, or forgets it), and once known how far
  /// to look.
  List<Widget> _whereChips(LatLng? here) => [
        FilterChip(
          avatar: _locating
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location_rounded, size: 18),
          label: const Text('Near me'),
          selected: here != null,
          onSelected: _locating ? null : (_) => _nearMe(),
        ),
        if (here != null)
          _MenuChip<int>(
            icon: Icons.radar_rounded,
            label: withinText(_within),
            options: [for (final km in nearbyDistances) (km, withinText(km))],
            onSelected: (km) => setState(() => _within = km),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final query = moduleVenuesProvider(gymModuleKey);
    final choosing = _type == null && _search.isEmpty;
    final master = ref.watch(venueTypesProvider).valueOrNull ?? const <VenueType>[];
    final chosen = _type == null || _type == anyServiceType ? null : venueTypeOf(master, _type!);
    return AppPage(
      title: chosen?.name ?? (_type == gymVenueType ? 'Gyms' : 'Services'),
      leading: IconButton(
        tooltip: choosing ? 'Back to Health Pro home' : 'Back to the kinds of service',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => choosing ? context.go(CoreRoutes.root) : _choose(null),
      ),
      body: AsyncValueView<List<Venue>>(
        value: ref.watch(query),
        onRetry: () => ref.invalidate(query),
        data: (all) {
          final types = findableTypes(master, all);
          return RefreshIndicator(
            onRefresh: () {
              ref.invalidate(gymPriceRangesProvider);
              ref.invalidate(gymVenueServicesProvider);
              ref.invalidate(venueTypesProvider);
              return ref.refresh(query.future);
            },
            child: choosing ? _chooser(context, all, types) : _list(context, all, types, master),
          );
        },
      ),
    );
  }

  /// First, the kinds of service: a card each, with how many there are.
  Widget _chooser(BuildContext context, List<Venue> all, List<VenueType> types) {
    final here = ref.watch(myLocationProvider);
    final near = here != null && _within > 0;
    // How many of each type (near them, once known), all told, and the nearest.
    final count = <String, int>{};
    final total = <String, int>{};
    final nearest = <String, double>{};
    for (final v in all) {
      total[v.type] = (total[v.type] ?? 0) + 1;
      final km = here != null && v.hasLocation ? distanceKm(here.latitude, here.longitude, v.latitude!, v.longitude!) : null;
      if (km != null && km < (nearest[v.type] ?? double.infinity)) nearest[v.type] = km;
      if (!near || (km != null && km <= _within)) count[v.type] = (count[v.type] ?? 0) + 1;
    }
    // Those with organisations first (near them first), in the master's order.
    int rank(VenueType t) => (count[t.key] ?? 0) > 0 ? 0 : ((total[t.key] ?? 0) > 0 ? 1 : 2);
    // A type with none yet shows (Coming soon) only when the team says so.
    final shown = [
      for (final r in [0, 1, 2])
        ...types.where((t) => rank(t) == r && (t.showWhenEmpty || (total[t.key] ?? 0) > 0)),
    ];
    return ListView(
      padding: pagePadding(context),
      children: [
        GymListHeader(
          gyms: all.length,
          places: {for (final v in all) v.dzongkhag}.length,
          openNow: switch (all.where((g) => g.openingHours?.at(BhutanTime.now())?.open ?? false).length) {
            0 => null,
            final open => open,
          },
          badge: 'VERIFIED PLACES',
          accent: 'service',
          blurb: 'Gyms, swimming pools, cycling, wellness and more across Bhutan. Choose what you are looking for, '
              'then join any of them with your one Health Pro account.',
          noun: ('place', 'places'),
          filters: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _searchBox(hint: 'Search every service: a name, a place, yoga, sauna...'),
              const SizedBox(height: 12),
              _chips(context, [
                ..._whereChips(here),
                if (here == null)
                  Text('Allow your location to see what is near you', style: TextStyle(fontSize: 12.5, color: context.brand.muted)),
              ]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 26, 4, 14),
          child: Text(
            'What are you looking for?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: context.brand.ink),
          ),
        ),
        if (shown.isEmpty)
          const EmptyState(icon: Icons.storefront_rounded, title: 'Services open soon')
        else
          ResponsiveGrid(
            minItemWidth: 250,
            maxColumns: 4,
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final (i, t) in shown.indexed)
                GymReveal(
                  key: ValueKey('type ${t.key}'),
                  delay: Motion.stagger * (i % 4),
                  child: ServiceTypeCard(
                    type: t,
                    count: count[t.key] ?? 0,
                    total: total[t.key] ?? 0,
                    withinKm: near ? _within : null,
                    nearestKm: nearest[t.key],
                    onTap: () => _choose(t.key),
                  ),
                ),
            ],
          ),
        if (all.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Center(
              child: TextButton.icon(
                onPressed: () => _choose(anyServiceType),
                icon: const Icon(Icons.apps_rounded),
                label: Text('See all ${all.length} ${all.length == 1 ? 'place' : 'places'}'),
              ),
            ),
          ),
      ],
    );
  }

  /// Then the organisations of the chosen type, and the filters.
  Widget _list(BuildContext context, List<Venue> all, List<VenueType> types, List<VenueType> master) {
    final here = ref.watch(myLocationProvider);
    final prices = ref.watch(gymPriceRangesProvider).valueOrNull ?? const {};
    final services = ref.watch(gymVenueServicesProvider).valueOrNull ?? const <String, List<String>>{};
    final sort = _sort ?? (here != null ? GymSort.nearest : GymSort.suggested);
    final type = _type ?? anyServiceType;
    final single = type != anyServiceType;
    final gymsOnly = type == gymVenueType;
    final typeName = single ? venueTypeName(master, type) : null;
    final ofType = [for (final v in all) if (!single || v.type == type) v];
    final places = {for (final g in ofType) g.dzongkhag}.toList()..sort();
    final areas = _dzongkhag == null
        ? const <String>[]
        : ({for (final g in ofType) if (g.dzongkhag == _dzongkhag) venueArea(g)}.whereType<String>().toList()..sort());
    final offered = commonServices(ofType, services);
    final shown = arrangeGyms(
      all,
      prices: prices,
      type: type,
      dzongkhag: _dzongkhag,
      area: _area,
      service: _service,
      query: _search,
      services: services,
      typeNames: {for (final t in types) t.key: t.name},
      budget: _budget,
      sort: sort,
      here: here,
      withinKm: _within,
    );
    final near = here != null && _within > 0;
    final noun = gymsOnly ? ('gym', 'gyms') : ('place', 'places');
    final countText = [
      '${shown.length} ${shown.length == 1 ? noun.$1 : noun.$2}',
      if (near) 'within $_within km',
      if (_service != null) 'with $_service',
      if (_budget != null) 'with a package up to ${formatNu(_budget!)}',
      if (sort != GymSort.suggested) sort.label.toLowerCase(),
    ].join(' · ');
    final filtered = _budget != null || _service != null || _search.isNotEmpty || _area != null;
    // None near them, though there are further away.
    final farOnly = near && !filtered && ofType.isNotEmpty;
    return ListView(
      padding: pagePadding(context),
      children: [
        GymListHeader(
          gyms: ofType.length,
          places: places.length,
          openNow: switch (ofType.where((g) => g.openingHours?.at(BhutanTime.now())?.open ?? false).length) {
            0 => null,
            final open => open,
          },
          badge: gymsOnly ? 'VERIFIED GYMS' : 'VERIFIED PLACES',
          accent: gymsOnly ? 'gym' : (typeName?.toLowerCase() ?? 'service'),
          noun: noun,
          filters: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _chips(context, [
                _label(context, 'Service'),
                ChoiceChip(
                  avatar: const Icon(Icons.apps_rounded, size: 18),
                  label: const Text('All'),
                  selected: !single,
                  onSelected: (_) => _choose(anyServiceType),
                ),
                for (final t in types)
                  if (t.key == type || all.any((v) => v.type == t.key))
                    ChoiceChip(
                      avatar: Icon(t.iconData, size: 18),
                      label: Text(t.name),
                      selected: t.key == type,
                      onSelected: (_) => _choose(t.key),
                    ),
              ]),
              _divider(context),
              _searchBox(hint: single ? 'Search ${typeName!.toLowerCase()}: a name, a place, a class...' : 'Search a name, a place, yoga, sauna...'),
              const SizedBox(height: 12),
              _chips(
                context,
                [
                  ..._whereChips(here),
                  _MenuChip<GymSort>(
                    icon: Icons.sort_rounded,
                    label: 'Sort: ${sort.label}',
                    options: [
                      for (final o in GymSort.values)
                        if (o != GymSort.nearest || here != null) (o, o.label),
                    ],
                    onSelected: (o) => setState(() => _sort = o),
                  ),
                  _MenuChip<int?>(
                    icon: Icons.account_balance_wallet_outlined,
                    label: _budget == null ? 'Any budget' : 'Up to ${formatNu(_budget!)}',
                    options: [(null, 'Any budget'), for (final b in gymBudgets) (b, 'Up to ${formatNu(b)}')],
                    onSelected: (b) => setState(() => _budget = b),
                  ),
                  if (offered.isNotEmpty || _service != null)
                    _MenuChip<String?>(
                      icon: Icons.room_service_outlined,
                      label: _service ?? 'Any service',
                      options: [(null, 'Any service'), for (final s in offered) (s, s)],
                      onSelected: (s) => setState(() => _service = s),
                    ),
                ],
              ),
              if (places.length > 1) ...[
                _divider(context),
                _chips(
                  context,
                  [
                    _label(context, 'Dzongkhag'),
                    for (final place in [null, ...places])
                      ChoiceChip(
                        label: Text(place ?? 'All'),
                        selected: _dzongkhag == place,
                        onSelected: (_) => setState(() {
                          _dzongkhag = place;
                          _area = null;
                        }),
                      ),
                  ],
                ),
              ],
              if (areas.length > 1) ...[
                const SizedBox(height: 10),
                _chips(
                  context,
                  [
                    _label(context, 'Area'),
                    for (final area in [null, ...areas])
                      ChoiceChip(
                        label: Text(area ?? 'All of $_dzongkhag'),
                        selected: _area == area,
                        onSelected: (_) => setState(() => _area = area),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 26, 4, 14),
          child: Align(
            alignment: Alignment.centerLeft,
            // A new count slides in over the last.
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.page),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              layoutBuilder: (current, previous) =>
                  Stack(alignment: Alignment.centerLeft, children: [...previous, if (current != null) current]),
              child: Text(
                countText,
                key: ValueKey(countText),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: context.brand.ink),
              ),
            ),
          ),
        ),
        if (shown.isEmpty)
          FadeSlideIn(
            key: ValueKey('empty $type $_budget $_service $_search $_area $_within'),
            child: switch ((farOnly, filtered)) {
              (true, _) => EmptyState(
                  icon: Icons.radar_rounded,
                  title: 'None within $_within km of you',
                  message: '${ofType.length} further away.',
                  actionLabel: 'Look anywhere',
                  onAction: () => setState(() => _within = 0),
                ),
              (_, true) => EmptyState(
                  icon: Icons.search_off_rounded,
                  title: _budget != null ? 'None within that budget' : 'Nothing matches',
                  message: _budget != null ? 'Try a higher budget.' : 'Try fewer words, another area or any service.',
                  actionLabel: 'Clear the filters',
                  onAction: () => setState(() {
                    _budget = null;
                    _service = null;
                    _area = null;
                    _searchField.clear();
                    _search = '';
                  }),
                ),
              _ => EmptyState(
                  icon: single ? venueTypeOf(types, type)?.iconData ?? Icons.storefront_rounded : Icons.storefront_rounded,
                  title: gymsOnly ? 'No gyms here yet' : 'None here yet',
                  message: gymsOnly ? 'Run a gym? Register it on Health Pro.' : 'Run one? Register it on Health Pro.',
                  actionLabel: gymsOnly ? 'Register your gym' : 'Register your organisation',
                  onAction: () => context.push(CoreRoutes.registerVenue),
                ),
            },
          )
        else
          ResponsiveGrid(
            minItemWidth: 300,
            maxColumns: 4,
            spacing: 18,
            runSpacing: 18,
            equalHeight: false,
            // Rising into place as they scroll into view, a row's
            // cards one after another.
            children: [
              for (final (i, row) in shown.indexed)
                GymReveal(
                  key: ValueKey(row.gym.id),
                  delay: Motion.stagger * (i % 4),
                  child: GymListCard(
                    gym: row.gym,
                    price: row.price,
                    km: row.km,
                    typeLabel: single ? null : venueTypeName(types, row.gym.type),
                    typeIcon: single ? null : venueTypeOf(types, row.gym.type)?.iconData,
                    onTap: () => context.push(GymRoutes.gymFor(row.gym.id)),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// How many places of a kind there are: near them ([withinKm], when known) or
/// in [inArea] (the area they chose), then all told; Coming soon when none yet.
String serviceCountText({required int count, required int total, int? withinKm, String? inArea, double? nearestKm}) {
  final where = withinKm != null ? ' within $withinKm km' : (inArea == null ? '' : ' in $inArea');
  return switch ((count, total)) {
    (_, 0) => 'Coming soon',
    (0, final total) => 'None$where · $total ${withinKm != null ? 'further away' : 'elsewhere'}',
    _ => [
        '$count ${count == 1 ? 'place' : 'places'}$where',
        if (nearestKm != null) 'nearest ${distanceText(nearestKm)}',
      ].join(' · '),
  };
}

/// One kind of service on Find services: its icon, name, what it is, and
/// how many there are (and the nearest). Lifts under the pointer, its arrow
/// leaning in. (The welcome page has its own, numbered, with the 3D picture.)
class ServiceTypeCard extends StatefulWidget {
  final VenueType type;

  /// How many there are near them ([withinKm], when known) or in [inArea]
  /// (the area they chose), and all told.
  final int count;
  final int total;
  final int? withinKm;
  final String? inArea;
  final double? nearestKm;
  final VoidCallback onTap;

  const ServiceTypeCard(
      {super.key,
      required this.type,
      required this.count,
      required this.total,
      this.withinKm,
      this.inArea,
      this.nearestKm,
      required this.onTap});

  @override
  State<ServiceTypeCard> createState() => _ServiceTypeCardState();
}

class _ServiceTypeCardState extends State<ServiceTypeCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    // Its colour and cover photo, as the team set them in Service types.
    final accent = widget.type.colorOr(context.colors.primary);
    final photo = widget.type.photo;
    final hover = _hover && !reduceMotion(context);
    final duration = Motion.of(context, Motion.card);
    final none = widget.count == 0;
    final countText = serviceCountText(
        count: widget.count, total: widget.total, withinKm: widget.withinKm, inArea: widget.inArea, nearestKm: widget.nearestKm);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, hover ? -6 : 0, 0),
        decoration: BoxDecoration(
          color: brand.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: hover ? accent.withValues(alpha: 0.45) : brand.glassBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: hover ? 0.12 : 0.05),
              blurRadius: hover ? 32 : 16,
              offset: Offset(0, hover ? 16 : 6),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (photo != null)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(21)),
                    child: AspectRatio(
                      aspectRatio: 16 / 7,
                      // Drawing closer under the pointer.
                      child: AnimatedScale(
                        scale: hover ? 1.05 : 1,
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        child: Image.network(
                          photo,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => ColoredBox(color: accent.withValues(alpha: 0.1)),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AnimatedScale(
                            scale: hover ? 1.08 : 1,
                            duration: duration,
                            curve: Curves.easeOutBack,
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                              child: Icon(widget.type.iconData, size: 28, color: accent),
                            ),
                          ),
                          const Spacer(),
                          AnimatedSlide(
                            offset: Offset(hover ? 0.2 : 0, 0),
                            duration: duration,
                            child: Icon(Icons.arrow_forward_rounded, color: hover ? accent : brand.muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        widget.type.name,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: brand.ink),
                      ),
                      if (widget.type.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.type.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, height: 1.45, color: brand.muted),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Text(
                        countText,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: none ? brand.muted : accent),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A chip that opens a short menu of [options].
class _MenuChip<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<(T, String)> options;
  final ValueChanged<T> onSelected;

  const _MenuChip({required this.icon, required this.label, required this.options, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final (value, text) in options) MenuItemButton(onPressed: () => onSelected(value), child: Text(text)),
      ],
      builder: (context, controller, _) => ActionChip(
        avatar: Icon(icon, size: 18),
        label: Row(mainAxisSize: MainAxisSize.min, children: [Text(label), const Icon(Icons.arrow_drop_down_rounded, size: 20)]),
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// Public information about one gym: photos, where it is, its packages and
/// prices, its classes (anyone on Health Pro books those open to all), how to
/// reach it and how to join (ask in the app, or at its front desk), reviews.
/// Its staff also get a way into running it. Its QR code
/// opens it with [join]: asking to join comes first.
class GymDetailsScreen extends ConsumerWidget {
  final String venueId;

  /// Opened from the gym's QR code: asking to join comes first.
  final bool join;

  const GymDetailsScreen({super.key, required this.venueId, this.join = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venue = ref.watch(venueProvider(venueId));
    final signedIn = ref.watch(currentUserIdProvider) != null;
    final access = signedIn ? ref.watch(venueAccessProvider(venueId)).valueOrNull : null;

    // Opened straight (after a refresh, from a link or its QR code) there's
    // nothing to go back to: back leads to the list of gyms. In the app's
    // frame on a phone the bar keeps its menu button instead.
    final canGoBack = ModalRoute.of(context)?.canPop ?? false;
    final menu = AppShellScope.maybeOf(context)?.openMenu != null;
    return AppPage(
      title: venue.valueOrNull?.name ?? 'Gym',
      leading: canGoBack || menu
          ? null
          : IconButton(
              tooltip: 'All gyms',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.go(GymRoutes.gyms),
            ),
      body: AsyncValueView<Venue?>(
        value: venue,
        onRetry: () => ref.invalidate(venueProvider(venueId)),
        data: (gym) {
          if (gym == null || !gymModuleRuns(gym)) {
            return const EmptyState(icon: Icons.search_off_rounded, title: 'This gym is not on Health Pro');
          }
          final plans = ref.watch(gymPlansProvider((venueId: venueId, all: false)));
          final joinCard = JoinGymCard(gym: gym, plans: plans.valueOrNull ?? const [], highlight: join);
          final onSale = plans.valueOrNull ?? const <GymPlan>[];
          final prices = [for (final p in onSale) p.price];
          final brand = context.brand;
          final now = gym.openingHours?.at(BhutanTime.now());
          final promo = gym.promoVideo == null ? null : ref.watch(venueRepositoryProvider).promoVideoUrl(gym.promoVideo);
          final text = TextStyle(fontSize: 15, height: 1.7, color: brand.body);
          // Its prices, today's hours and its reviews, at a glance.
          final facts = GymFactsBar(
            facts: [
              (
                icon: Icons.payments_outlined,
                label: 'Packages',
                value: prices.isNotEmpty
                    ? priceRangeText(prices.reduce((a, b) => a < b ? a : b), prices.reduce((a, b) => a > b ? a : b))
                    : (plans.isLoading ? '…' : 'Prices at the desk'),
                color: prices.isEmpty ? brand.muted : null,
              ),
              if (now != null)
                (
                  icon: Icons.schedule_rounded,
                  label: 'Today',
                  value: now.label,
                  color: now.open ? brand.readable(brand.success) : null,
                ),
              if (gym.ratingCount > 0)
                (
                  icon: Icons.star_rounded,
                  label: 'Reviews',
                  value: '${gym.ratingAverage!.toStringAsFixed(1)} · ${gym.ratingCount} '
                      '${gym.ratingCount == 1 ? 'review' : 'reviews'}',
                  color: null,
                ),
            ],
          );
          final packages = GymSection(
            icon: Icons.sell_outlined,
            title: 'Packages',
            child: AsyncValueView<List<GymPlan>>(
              value: plans,
              onRetry: () => ref.invalidate(gymPlansProvider((venueId: venueId, all: false))),
              data: (list) => list.isEmpty
                  ? Text('This gym has not added its packages yet.', style: TextStyle(color: brand.muted))
                  : GymPackagesList(plans: list),
            ),
          );
          final about = gym.description == null
              ? null
              : GymSection(icon: Icons.info_outline_rounded, title: 'About', child: Text(gym.description!, style: text));
          final facilities = gym.facilities.isEmpty
              ? null
              : GymSection(icon: Icons.checklist_rounded, title: 'Facilities', child: GymFacilities(facilities: gym.facilities));
          final promoVideo = promo == null
              ? null
              : GymSection(
                  icon: Icons.play_circle_outline_rounded,
                  title: 'Take a look inside',
                  child: PromoVideoPlayer(key: ValueKey(promo), url: promo),
                );
          final videos = gym.videos.isEmpty
              ? null
              : GymSection(icon: Icons.smart_display_outlined, title: 'Videos', child: VenueVideosView(videos: gym.videos));
          final contact = GymContactPanel.shows(gym)
              ? GymSection(icon: Icons.support_agent_rounded, title: 'Contact', child: GymContactPanel(gym: gym))
              : null;
          final hours = gym.openingHours == null
              ? null
              : GymSection(icon: Icons.schedule_rounded, title: 'Opening hours', child: GymHoursList(hours: gym.openingHours!));
          final map = !gym.hasLocation
              ? null
              : GymSection(
                  icon: Icons.map_outlined,
                  title: 'Where it is',
                  child: VenueMap(latitude: gym.latitude!, longitude: gym.longitude!),
                );
          final cancellation = gym.cancellationPolicy == null
              ? null
              : GymSection(icon: Icons.policy_outlined, title: 'Cancellation and refunds', child: Text(gym.cancellationPolicy!, style: text));
          final trainers = _GymTrainers(venueId: gym.id);
          // Its classes this week, open to anyone on Health Pro.
          final timetable = ref.watch(gymClassesProvider(gym.id)).valueOrNull ?? const <GymClass>[];
          final member = signedIn && (ref.watch(myMembershipsProvider).valueOrNull?.gyms.any((g) => g.venueId == gym.id) ?? false);
          final classes = !timetable.any((c) => c.isActive)
              ? null
              : GymSection(
                  icon: Icons.event_note_outlined,
                  title: 'Classes',
                  child: ClassWeek(venueId: gym.id, signedIn: signedIn, member: member, explain: true),
                );
          // Its heading brings its own room above it.
          final reviews = GymSection(padding: const EdgeInsets.fromLTRB(18, 0, 18, 18), child: ReviewsSection(venue: gym));
          final trainHere = gym.isVerified ? TrainHereCard(gym: gym) : null;
          // From the gym's QR code, joining comes before anything else.
          final joinHere = join ? null : joinCard;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(venueProvider(venueId));
              ref.invalidate(gymPlansProvider((venueId: venueId, all: false)));
              ref.invalidate(myMembershipsProvider);
              ref.invalidate(gymClassesProvider(venueId));
              ref.invalidate(gymClassPlacesProvider(venueId));
            },
            child: ListView(
              padding: pagePadding(context),
              children: [
                // For its staff: the way to their dashboard, under the bar.
                if (access != null)
                  PageActions(
                    text: 'You work at this gym. This is its page as members see it.',
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => context.go(GymRoutes.dashboardFor(venueId)),
                        style: OutlinedButton.styleFrom(minimumSize: PageActions.buttonSize),
                        icon: const Icon(Icons.space_dashboard_rounded, size: 20),
                        label: const Text('Dashboard'),
                      ),
                    ],
                  ),
                if (!gym.isVerified)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: StatusChip(
                      label: 'Not live yet: only its staff can see this page',
                      color: context.brand.warning,
                      icon: Icons.visibility_off_outlined,
                    ),
                  ),
                if (join) ...[joinCard, const SizedBox(height: 16)],
                FadeSlideIn(offset: 14, child: GymProfileHero(gym: gym)),
                const SizedBox(height: 18),
                // Side by side on a computer: the gym on the left; joining,
                // packages and how to get there on the right. One column
                // otherwise, joining and the packages near the top.
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 900) {
                      return _stack([
                        facts,
                        joinHere,
                        packages,
                        classes,
                        about,
                        facilities,
                        contact,
                        hours,
                        map,
                        promoVideo,
                        videos,
                        trainers,
                        reviews,
                        trainHere,
                        cancellation,
                      ]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: _stack([facts, about, facilities, promoVideo, videos, trainers, reviews])),
                        const SizedBox(width: 22),
                        Expanded(
                          flex: 2,
                          child: _stack([joinHere, trainHere, packages, classes, contact, hours, map, cancellation], after: Motion.stagger),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// [parts] one under another, the ones a gym has (the trainers bring
  /// their own room, as they may have none), each rising into place as it
  /// scrolls into view: the first few in turn, [after] the page opens.
  static Widget _stack(List<Widget?> parts, {Duration after = Duration.zero}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, part) in parts.nonNulls.indexed) ...[
          if (i > 0 && part is! _GymTrainers) const SizedBox(height: 18),
          GymReveal(delay: after + Motion.stagger * (2 + (i < 3 ? i : 3)), child: part),
        ],
      ],
    );
  }
}

/// A gym's verified trainers, on its page: each opens their profile, with
/// their times here (and their others only as Not available).
class _GymTrainers extends ConsumerWidget {
  final String venueId;

  const _GymTrainers({required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainers = ref.watch(gymVerifiedTrainersProvider(venueId)).valueOrNull ?? const <TrainerProfile>[];
    if (trainers.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: GymSection(
        icon: Icons.sports_rounded,
        title: 'Trainers (${trainers.length})',
        child: Column(children: [for (final t in trainers) TrainerTile(trainer: t, venueId: venueId)]),
      ),
    );
  }
}
