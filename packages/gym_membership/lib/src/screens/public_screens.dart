import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../gym_routes.dart';
import '../widgets/gym_widgets.dart';
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
          return RefreshIndicator(
            onRefresh: () {
              ref.invalidate(gymPriceRangesProvider);
              return ref.refresh(publicVenuesProvider(query).future);
            },
            child: ListView(
              padding: pagePadding(context),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
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
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final place in [null, ...places])
                        ChoiceChip(
                          label: Text(place ?? 'All'),
                          selected: _dzongkhag == place,
                          onSelected: (_) => setState(() => _dzongkhag = place),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  [
                    '${shown.length} ${shown.length == 1 ? 'gym' : 'gyms'}',
                    if (_budget != null) 'with a package up to ${formatNu(_budget!)}',
                    if (sort != GymSort.suggested) sort.label.toLowerCase(),
                  ].join(' · '),
                  style: TextStyle(color: context.brand.muted),
                ),
                const SizedBox(height: 10),
                if (shown.isEmpty)
                  EmptyState(
                    icon: Icons.fitness_center_rounded,
                    title: _budget != null ? 'No gyms within that budget' : 'No gyms here yet',
                    message: _budget != null ? 'Try a higher budget.' : 'Run a gym? Register it on Health Pro.',
                    actionLabel: _budget != null ? 'Any budget' : 'Register your gym',
                    onAction: _budget != null ? () => setState(() => _budget = null) : () => context.push(CoreRoutes.registerVenue),
                  )
                else
                  ResponsiveGrid(
                    minItemWidth: 320,
                    maxColumns: 4,
                    equalHeight: false,
                    children: [
                      for (final row in shown)
                        VenueCard(
                          venue: row.gym,
                          placeholderIcon: Icons.fitness_center_rounded,
                          onTap: () => context.push(GymRoutes.gymFor(row.gym.id)),
                          details: _GymFacts(price: row.price, hours: row.gym.openingHours, km: row.km),
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

/// A gym's prices, hours today and distance, on its card.
class _GymFacts extends StatelessWidget {
  final ({int low, int high})? price;
  final OpeningHours? hours;
  final double? km;

  const _GymFacts({required this.price, required this.hours, required this.km});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          price == null ? 'Prices at the desk' : priceRangeText(price!.low, price!.high),
          style: TextStyle(fontWeight: FontWeight.w800, color: price == null ? brand.muted : brand.ink),
        ),
        if (km != null)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.near_me_outlined, size: 15, color: brand.muted),
            const SizedBox(width: 3),
            Text('${distanceText(km!)} away', style: TextStyle(color: brand.muted)),
          ]),
        OpenNowChip(hours: hours),
      ],
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

    return AppPage(
      title: venue.valueOrNull?.name ?? 'Gym',
      actions: [
        if (access != null)
          TextButton.icon(
            onPressed: () => context.go(GymRoutes.dashboardFor(venueId)),
            icon: const Icon(Icons.space_dashboard_rounded),
            label: const Text('Dashboard'),
          ),
      ],
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
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(venueProvider(venueId));
              ref.invalidate(gymPlansProvider((venueId: venueId, all: false)));
              ref.invalidate(myMembershipsProvider);
            },
            child: ListView(
              padding: pagePadding(context),
              children: [
                if (!gym.isVerified)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: StatusChip(
                      label: 'Not live yet: only its staff can see this page',
                      color: context.brand.warning,
                      icon: Icons.visibility_off_outlined,
                    ),
                  ),
                // From the gym's QR code: joining, before anything else.
                if (join) ...[joinCard, const SizedBox(height: 16)],
                ResponsiveColumns(
                  flex: (3, 2),
                  first: [
                    VenuePhotoCarousel(photos: gym.photos, placeholderIcon: Icons.fitness_center_rounded),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: Text(gym.name, style: context.text.headlineSmall)),
                        if (gym.isVerified) VerificationChip(status: gym.verificationStatus),
                      ],
                    ),
                    const SizedBox(height: 4),
                    InfoRow(icon: Icons.place_outlined, text: [gym.place, if (gym.address != null) gym.address!].join(' · ')),
                    if (gym.ratingCount > 0)
                      Row(children: [
                        RatingStars(rating: gym.ratingAverage!),
                        Text('  ${gym.ratingAverage!.toStringAsFixed(1)} · ${gym.ratingCount} reviews'),
                      ]),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (prices.isNotEmpty)
                          Text(
                            priceRangeText(prices.reduce((a, b) => a < b ? a : b), prices.reduce((a, b) => a > b ? a : b)),
                            style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        OpenNowChip(hours: gym.openingHours),
                      ],
                    ),
                    const SizedBox(height: 12),
                    VenueContactButtons(venue: gym),
                    const SizedBox(height: 8),
                    VenueContactDetails(venue: gym),
                    VenuePromoVideo(venue: gym, title: 'Take a look inside'),
                    if (gym.description != null) ...[
                      const SectionTitle('About'),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(gym.description!)),
                    ],
                    if (gym.facilities.isNotEmpty) ...[
                      const SectionTitle('Facilities'),
                      FacilitiesView(facilities: gym.facilities),
                    ],
                    if (gym.videos.isNotEmpty) ...[
                      const SectionTitle('Videos'),
                      VenueVideosView(videos: gym.videos),
                    ],
                    _GymTrainers(venueId: gym.id),
                    ReviewsSection(venue: gym),
                  ],
                  second: [
                    if (!join) ...[const SectionTitle('How to join'), joinCard],
                    if (gym.isVerified) TrainHereCard(gym: gym),
                    if (gym.openingHours != null) ...[
                      const SectionTitle('Opening hours'),
                      OpeningHoursView(hours: gym.openingHours!),
                    ],
                    if (gym.hasLocation) ...[
                      const SectionTitle('Where it is'),
                      VenueMap(latitude: gym.latitude!, longitude: gym.longitude!),
                    ],
                    const SectionTitle('Packages'),
                    AsyncValueView<List<GymPlan>>(
                      value: plans,
                      onRetry: () => ref.invalidate(gymPlansProvider((venueId: venueId, all: false))),
                      data: (list) => list.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Text('This gym has not added its packages yet.'),
                            )
                          : Column(
                              children: [
                                for (final plan in list)
                                  Padding(padding: const EdgeInsets.only(bottom: 10), child: PlanCard(plan: plan)),
                              ],
                            ),
                    ),
                    if (gym.cancellationPolicy != null) ...[
                      const SectionTitle('Cancellation and refunds'),
                      SectionCard(child: Text(gym.cancellationPolicy!)),
                    ],
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

/// A gym's verified trainers, on its page: each opens their profile, with
/// their times here (and their others only as Not available).
class _GymTrainers extends ConsumerWidget {
  final String venueId;

  const _GymTrainers({required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainers = ref.watch(gymVerifiedTrainersProvider(venueId)).valueOrNull ?? const <TrainerProfile>[];
    if (trainers.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('Trainers (${trainers.length})'),
        SectionCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [for (final t in trainers) TrainerTile(trainer: t, venueId: venueId)]),
        ),
      ],
    );
  }
}
