import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../gym_routes.dart';
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

/// The gyms [all] as the list shows them: in [dzongkhag] (all when null),
/// with a package within [budget] (any when null), in [sort] order;
/// distances from [here] when known.
List<({Venue gym, ({int low, int high})? price, double? km})> arrangeGyms(
  List<Venue> all, {
  required Map<String, ({int low, int high})> prices,
  String? dzongkhag,
  int? budget,
  GymSort sort = GymSort.suggested,
  LatLng? here,
}) {
  final rows = [
    for (final g in all)
      if (dzongkhag == null || g.dzongkhag == dzongkhag)
        (
          gym: g,
          price: prices[g.id],
          km: here == null || !g.hasLocation ? null : distanceKm(here.latitude, here.longitude, g.latitude!, g.longitude!),
        ),
  ].where((r) => budget == null || (r.price != null && r.price!.low <= budget)).toList();
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

/// Public information: the verified gyms on Health Pro, each with its
/// photo, opening hours and price range. Near me (after allowing the
/// location) puts the nearest first, with how far; anyone can sort by price
/// and keep to a budget, or a dzongkhag. What the Welcome page's "Find a
/// gym" opens; no account needed.
class GymListScreen extends ConsumerStatefulWidget {
  /// Ask for the location straight away (Gyms near me).
  final bool nearMe;

  const GymListScreen({super.key, this.nearMe = false});

  @override
  ConsumerState<GymListScreen> createState() => _GymListScreenState();
}

class _GymListScreenState extends ConsumerState<GymListScreen> {
  String? _dzongkhag;
  int? _budget;
  GymSort? _sort;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    if (widget.nearMe && ref.read(myLocationProvider) == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _nearMe());
    }
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

  @override
  Widget build(BuildContext context) {
    const query = (type: gymVenueType, dzongkhag: null);
    final here = ref.watch(myLocationProvider);
    final prices = ref.watch(gymPriceRangesProvider).valueOrNull ?? const {};
    final sort = _sort ?? (here != null ? GymSort.nearest : GymSort.suggested);
    return AppPage(
      title: 'Gyms on Health Pro',
      leading: IconButton(
        tooltip: 'Back to Health Pro home',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => context.go(CoreRoutes.root),
      ),
      body: AsyncValueView<List<Venue>>(
        value: ref.watch(publicVenuesProvider(query)),
        onRetry: () => ref.invalidate(publicVenuesProvider(query)),
        data: (gyms) {
          final places = {for (final g in gyms) g.dzongkhag}.toList()..sort();
          final shown = arrangeGyms(gyms, prices: prices, dzongkhag: _dzongkhag, budget: _budget, sort: sort, here: here);
          final countText = [
            '${shown.length} ${shown.length == 1 ? 'gym' : 'gyms'}',
            if (_budget != null) 'with a package up to ${formatNu(_budget!)}',
            if (sort != GymSort.suggested) sort.label.toLowerCase(),
          ].join(' · ');
          return RefreshIndicator(
            onRefresh: () {
              ref.invalidate(gymPriceRangesProvider);
              return ref.refresh(publicVenuesProvider(query).future);
            },
            child: ListView(
              padding: pagePadding(context),
              children: [
                GymListHeader(
                  gyms: gyms.length,
                  places: places.length,
                  openNow: switch (gyms.where((g) => g.openingHours?.at(BhutanTime.now())?.open ?? false).length) {
                    0 => null,
                    final open => open,
                  },
                  filters: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _chips(
                        context,
                        [
                          FilterChip(
                            avatar: _locating
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.my_location_rounded, size: 18),
                            label: const Text('Near me'),
                            selected: here != null,
                            onSelected: _locating ? null : (_) => _nearMe(),
                          ),
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
                        ],
                      ),
                      if (places.length > 1) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Divider(height: 1, color: context.brand.glassBorder),
                        ),
                        _chips(
                          context,
                          [
                            Padding(
                              padding: const EdgeInsets.only(left: 2, right: 4),
                              child: Text(
                                'Dzongkhag',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.brand.muted),
                              ),
                            ),
                            for (final place in [null, ...places])
                              ChoiceChip(
                                label: Text(place ?? 'All'),
                                selected: _dzongkhag == place,
                                onSelected: (_) => setState(() => _dzongkhag = place),
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
                    key: ValueKey('empty $_budget'),
                    child: EmptyState(
                      icon: Icons.fitness_center_rounded,
                      title: _budget != null ? 'No gyms within that budget' : 'No gyms here yet',
                      message: _budget != null ? 'Try a higher budget.' : 'Run a gym? Register it on Health Pro.',
                      actionLabel: _budget != null ? 'Any budget' : 'Register your gym',
                      onAction: _budget != null ? () => setState(() => _budget = null) : () => context.push(CoreRoutes.registerVenue),
                    ),
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
                            onTap: () => context.push(GymRoutes.gymFor(row.gym.id)),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          );
        },
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
/// prices, how to reach it and how to join (ask in the app, or at its front
/// desk), reviews. Its staff also get a way into running it. Its QR code
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
          if (gym == null || gym.type != gymVenueType) {
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
                          child: _stack([joinHere, trainHere, packages, contact, hours, map, cancellation], after: Motion.stagger),
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
