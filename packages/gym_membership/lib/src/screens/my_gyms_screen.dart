import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/classes.dart';
import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../data/joining.dart';
import '../data/online_payments.dart';
import '../data/receipts.dart';
import '../data/registered_member.dart';
import '../data/trainers.dart';
import '../gym_routes.dart';
import '../widgets/pause_widgets.dart' show pauseSpan;
import '../widgets/receipt_view.dart';
import '../widgets/class_widgets.dart';
import '../widgets/coaching_widgets.dart';
import '../widgets/trainer_widgets.dart';

/// My gym, in a member's menu: the gym they belong to, in full. Its photos,
/// what it has (facilities), how to reach it, where it is, when it's open
/// and its trainers, beside their own membership there (package, days left,
/// member code, trainer, paying). With several gyms, one at a time, chosen
/// at the top; [gymId] opens on that one.
class MyGymScreen extends ConsumerStatefulWidget {
  final String? gymId;

  const MyGymScreen({super.key, this.gymId});

  @override
  ConsumerState<MyGymScreen> createState() => _MyGymScreenState();
}

class _MyGymScreenState extends ConsumerState<MyGymScreen> {
  late String? _chosen = widget.gymId;

  @override
  void didUpdateWidget(MyGymScreen old) {
    super.didUpdateWidget(old);
    if (widget.gymId != old.gymId && widget.gymId != null) _chosen = widget.gymId;
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'My gym',
      body: AsyncValueView<MyMemberships>(
        value: ref.watch(myMembershipsProvider),
        onRetry: () => ref.invalidate(myMembershipsProvider),
        data: (mine) {
          if (mine.gyms.isEmpty) {
            return ListView(padding: pagePadding(context), children: const [_HowToJoin()]);
          }
          final gym = mine.gyms.where((g) => g.venueId == _chosen).firstOrNull ?? mine.gyms.first;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(venueProvider(gym.venueId));
              ref.invalidate(gymVerifiedTrainersProvider(gym.venueId));
              return ref.refresh(myMembershipsProvider.future);
            },
            child: ListView(
              padding: pagePadding(context),
              children: [
                if (mine.gyms.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final g in mine.gyms)
                          ChoiceChip(
                            label: Text(g.venueName),
                            selected: g.venueId == gym.venueId,
                            onSelected: (_) => setState(() => _chosen = g.venueId),
                          ),
                      ],
                    ),
                  ),
                _MyGymDetails(key: ValueKey(gym.venueId), mine: gym),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One of their gyms in full, with their membership there.
class _MyGymDetails extends ConsumerWidget {
  final MyGym mine;

  const _MyGymDetails({super.key, required this.mine});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = BhutanTime.today();
    final membership = _MyGymCard(gym: mine, today: today, toPublicPage: true);
    final receipts = [
      if (mine.receipts.isNotEmpty) ...[const SectionTitle('Receipts'), _MyReceipts(receipts: mine.receipts)],
    ];
    return AsyncValueView<Venue?>(
      value: ref.watch(venueProvider(mine.venueId)),
      onRetry: () => ref.invalidate(venueProvider(mine.venueId)),
      loading: const LoadingSkeleton.rows(),
      data: (gym) {
        // The gym's page is gone (closed, or hidden): their membership alone.
        if (gym == null) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [membership, ...receipts]);
        }
        final trainers =
            ref.watch(gymVerifiedTrainersProvider(gym.id)).valueOrNull ?? const <TrainerProfile>[];
        return ResponsiveColumns(
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
            Align(alignment: Alignment.centerLeft, child: OpenNowChip(hours: gym.openingHours)),
            const SizedBox(height: 12),
            VenueContactButtons(venue: gym),
            const SizedBox(height: 8),
            VenueContactDetails(venue: gym),
            VenuePromoVideo(venue: gym, title: 'Take a look inside'),
            if (gym.description != null) ...[
              const SectionTitle('About'),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(gym.description!)),
            ],
            const SectionTitle('Facilities'),
            if (gym.facilities.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('This gym has not listed its facilities yet.', style: TextStyle(color: context.brand.muted)),
              )
            else
              FacilitiesView(facilities: gym.facilities),
            SectionTitle(trainers.isEmpty ? 'Trainers' : 'Trainers (${trainers.length})'),
            if (trainers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('This gym has no trainers on Health Pro yet.', style: TextStyle(color: context.brand.muted)),
              )
            else
              SectionCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [for (final t in trainers) TrainerTile(trainer: t, venueId: gym.id)]),
              ),
            MyClassesCard(venueId: gym.id),
            if (mine.gymMemberId != null) ...[
              const SectionTitle('My plans'),
              MemberPlans(gymMemberId: mine.gymMemberId!),
            ],
            if (gym.videos.isNotEmpty) ...[
              const SectionTitle('Videos'),
              VenueVideosView(videos: gym.videos),
            ],
          ],
          second: [
            const SectionTitle('My membership'),
            membership,
            if (mine.gymMemberId != null) ...[
              const SectionTitle('My progress'),
              MemberProgress(gymMemberId: mine.gymMemberId!, self: true),
            ],
            ...receipts,
            if (gym.openingHours != null) ...[
              const SectionTitle('Opening hours'),
              OpeningHoursView(hours: gym.openingHours!),
            ],
            if (gym.hasLocation) ...[
              const SectionTitle('Where it is'),
              VenueMap(latitude: gym.latitude!, longitude: gym.longitude!),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => context.go(GymRoutes.gymFor(gym.id)),
              icon: const Icon(Icons.storefront_outlined, size: 18),
              label: const Text('Packages and reviews'),
            ),
          ],
        );
      },
    );
  }
}

/// A member's part of their own dashboard, beside their QR code: how
/// things stand (gyms, running packages, days left, visits), every gym they
/// belong to with its package (several at once is fine: each runs to its
/// own end), their requests to join, and their visits. It sizes to its
/// content: the dashboard scrolls.
class MyGymsDashboard extends ConsumerWidget {
  const MyGymsDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workouts = ref.watch(myClassBookingsProvider).valueOrNull ?? const <MyClassBooking>[];
    return AsyncValueView<MyMemberships>(
      value: ref.watch(myMembershipsProvider),
      onRetry: () => ref.invalidate(myMembershipsProvider),
      loading: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [SkeletonBox(height: 112, radius: 20), SizedBox(height: 20), SkeletonBox(height: 240, radius: 20)],
      ),
      data: (m) => _MyGymsBody(mine: m, workouts: workouts, today: BhutanTime.today()),
    );
  }
}

/// Days left of a package that ends on [end], [today] included: 1 on its
/// last day, as the front desk counts it.
int _daysLeft(DateTime end, DateTime today) => end.difference(today).inDays + 1;

class _MyGymsBody extends StatelessWidget {
  final MyMemberships mine;

  /// The classes they've booked, at any gym (members or not).
  final List<MyClassBooking> workouts;
  final DateTime today;

  const _MyGymsBody({required this.mine, this.workouts = const [], required this.today});

  /// What they should act on, most pressing first: a payment the gym
  /// couldn't find, a package that ended or ends within a week, a gym with
  /// no package yet, a payment still waiting.
  List<Widget> _attention(BuildContext context) {
    final brand = context.brand;
    final rows = <(int, Widget)>[];
    for (final g in mine.gyms) {
      void open() => context.go(g.canPayOnline ? GymRoutes.payFor(g.venueId) : GymRoutes.gymFor(g.venueId));
      final renew = g.canPayOnline ? 'Pay online' : 'View gym';
      final claim = g.claim;
      if (g.isPausedOn(today)) {
        rows.add((
          2,
          _AttentionRow(
            icon: Icons.pause_circle_outline_rounded,
            color: brand.warning,
            title: 'Membership paused at ${g.venueName}',
            text: 'Until ${formatDate(g.pause!.endDate)}: no check-in till then. Back sooner? The front desk can resume it.',
            action: 'View gym',
            onTap: () => context.go(GymRoutes.myGymFor(g.venueId)),
          ),
        ));
      }
      if (claim?.status == ClaimStatus.rejected) {
        rows.add((
          0,
          _AttentionRow(
            icon: Icons.error_outline_rounded,
            color: brand.danger,
            title: "${g.venueName} couldn't find your payment",
            text: 'JRN ${claim!.jrn}${claim.decisionNote == null ? '' : ': ${claim.decisionNote}'}',
            action: renew,
            onTap: open,
          ),
        ));
      }
      if (claim?.status == ClaimStatus.pending) {
        rows.add((
          3,
          _AttentionRow(
            icon: Icons.hourglass_top_rounded,
            color: brand.warning,
            title: 'Payment waiting at ${g.venueName}',
            text: '${formatNu(claim!.amount)} for ${claim.planName} (JRN ${claim.jrn}). The gym is checking it.',
            action: 'View gym',
            onTap: () => context.go(GymRoutes.gymFor(g.venueId)),
          ),
        ));
      } else if (g.endDate == null) {
        rows.add((
          2,
          _AttentionRow(
            icon: Icons.sell_outlined,
            color: BrandColors.blue,
            title: 'No package yet at ${g.venueName}',
            text: g.canPayOnline ? 'Choose a package and pay online, or at the front desk.' : 'Pay at the front desk to start one.',
            action: renew,
            onTap: open,
          ),
        ));
      } else if (g.hasEndedBy(today)) {
        rows.add((
          1,
          _AttentionRow(
            icon: Icons.event_busy_rounded,
            color: brand.danger,
            title: 'Your package at ${g.venueName} ended',
            text: 'It ended on ${formatDate(g.endDate!)}. Renew it to check in again.',
            action: renew,
            onTap: open,
          ),
        ));
      } else if (g.isActiveOn(today) && _daysLeft(g.endDate!, today) <= 7) {
        final left = _daysLeft(g.endDate!, today);
        rows.add((
          1,
          _AttentionRow(
            icon: Icons.schedule_rounded,
            color: brand.warning,
            title: left == 1 ? 'Last day at ${g.venueName}' : '$left days left at ${g.venueName}',
            text: 'Your package ends on ${formatDate(g.endDate!)}. Renew it to keep coming.',
            action: renew,
            onTap: open,
          ),
        ));
      }
    }
    rows.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final r in rows) r.$2];
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final ink = ConsoleInk.of(context);
    final active = [
      for (final g in mine.gyms)
        if (g.isActiveOn(today)) g,
    ]..sort((a, b) => a.endDate!.compareTo(b.endDate!));
    // The package that ends first: the one to renew next.
    final next = active.firstOrNull;
    final waiting = mine.requests.where((r) => r.status == JoinRequestStatus.pending).length;
    final weekStart = today.subtract(const Duration(days: 6));
    final thisWeek =
        mine.visits.where((v) => !BhutanTime.dateOnly(BhutanTime.toBhutan(v.at)).isBefore(weekStart)).length;
    final lastVisit = mine.visits.firstOrNull;

    // Visits on each of the last 7 days, today last.
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final week = [
      for (var i = 0; i < 7; i++)
        (
          label: weekdays[weekStart.add(Duration(days: i)).weekday - 1],
          value: mine.visits
              .where((v) => BhutanTime.dateOnly(BhutanTime.toBhutan(v.at)) == weekStart.add(Duration(days: i)))
              .length as num,
        ),
    ];
    final left = next == null ? 0 : _daysLeft(next.endDate!, today);
    final length = next == null ? 0 : _daysLeft(next.endDate!, next.startDate!);

    final kpis = [
      ConsoleKpi(
        icon: Icons.fitness_center_rounded,
        color: BrandColors.blue,
        value: '${mine.gyms.length}',
        count: mine.gyms.length,
        label: 'My gyms',
        note: waiting == 0 ? 'Gyms you belong to' : '$waiting ${waiting == 1 ? 'request' : 'requests'} waiting',
      ),
      ConsoleKpi(
        icon: Icons.verified_rounded,
        color: BrandColors.green,
        value: '${active.length}',
        count: active.length,
        label: 'Active packages',
        note: next == null ? 'None running now' : 'Next ends ${formatDate(next.endDate!)}',
      ),
      ConsoleKpi(
        icon: Icons.hourglass_bottom_rounded,
        color: brand.warning,
        value: next == null ? '–' : '$left',
        count: next == null ? null : left,
        label: 'Days left',
        note: next == null ? 'No active package' : next.venueName,
        // What's left of the package that ends first.
        trailing: length <= 0 ? null : _Ring(share: (left / length).clamp(0.0, 1.0), color: brand.warning),
      ),
      ConsoleKpi(
        icon: Icons.login_rounded,
        color: brand.accent,
        value: '$thisWeek',
        count: thisWeek,
        label: 'Visits in 7 days',
        note: lastVisit == null ? 'No visits yet' : 'Last visit ${timeAgo(lastVisit.at)}',
        trailing: thisWeek == 0
            ? null
            : _Reveal(
                child: ConsoleSparkline(values: [for (final d in week) d.value], color: brand.accent, width: 66, height: 32),
              ),
      ),
    ];
    final attention = _attention(context);

    final booked = MyClassBookingsList.ahead(workouts, BhutanTime.now());
    final panels = [
      if (booked.isNotEmpty)
        ConsoleCard(
          icon: Icons.event_note_outlined,
          title: 'My classes',
          trailing: Text(
            '${booked.length} booked',
            style: TextStyle(color: brand.muted, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          child: Material(type: MaterialType.transparency, child: MyClassBookingsList(bookings: booked)),
        ),
      if (mine.gyms.isNotEmpty)
        ConsoleCard(
          icon: Icons.bar_chart_rounded,
          title: 'My week',
          trailing: Text(
            thisWeek == 1 ? '1 visit' : '$thisWeek visits',
            style: TextStyle(color: brand.muted, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          child: thisWeek == 0
              ? Text('No visits in the last 7 days. Show your QR code at the front desk when you go.',
                  style: TextStyle(color: brand.muted, height: 1.4))
              : ConsoleBarChart(
                  points: week,
                  format: (v) => '${v.toInt()}',
                  name: 'Your visits on each of the last 7 days',
                  color: brand.accent,
                  height: 170,
                ),
        ),
      if (mine.visits.isNotEmpty)
        ConsoleCard(
          icon: Icons.history_rounded,
          title: 'Recent visits',
          child: Column(children: [for (final v in mine.visits.take(8)) _VisitRow(gym: v.gym, at: v.at)]),
        ),
      if (mine.requests.isNotEmpty)
        ConsoleCard(
          icon: Icons.how_to_reg_rounded,
          title: 'Requests to join',
          child: Material(
            type: MaterialType.transparency,
            child: Column(children: [for (final r in mine.requests) _MyRequestTile(request: r)]),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) =>
              ConsoleCells(columns: constraints.maxWidth >= 760 ? 4 : 2, spacing: 14, children: staggered(kpis, offset: 14)),
        ),
        if (attention.isNotEmpty) ...[
          const SizedBox(height: 18),
          ConsoleCard(
            icon: Icons.priority_high_rounded,
            title: 'Needs your attention',
            child: Material(type: MaterialType.transparency, child: Column(children: staggered(attention, offset: 10))),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 24, 2, 12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [brand.highlight, brand.themedShade(const Color(0xFFFFB066))],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'My gyms',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink.heading, letterSpacing: -0.2),
                ),
              ),
              ConsoleLink(label: 'Find a gym', onPressed: () => context.go(GymRoutes.gyms)),
            ],
          ),
        ),
        if (mine.gyms.isEmpty)
          const _HowToJoin()
        else
          // As many columns as there are gyms (three at most), so a row is
          // never part empty: one gym takes the width, laid out sideways.
          LayoutBuilder(
            builder: (context, constraints) => ResponsiveGrid(
              minItemWidth: 300,
              maxColumns: mine.gyms.length.clamp(1, 3),
              spacing: 16,
              runSpacing: 16,
              children: staggered([
                for (final g in mine.gyms)
                  _MyGymCard(gym: g, today: today, sideways: mine.gyms.length == 1 && constraints.maxWidth >= 660),
              ]),
            ),
          ),
        if (panels.isNotEmpty) ...[const SizedBox(height: 18), _Panels(panels: panels)],
      ],
    );
  }
}

/// The cards under My gyms, in two columns of one height where there's
/// room (the third card under the first), so they end on one line; one
/// under the other on a phone.
class _Panels extends StatelessWidget {
  final List<Widget> panels;

  const _Panels({required this.panels});

  @override
  Widget build(BuildContext context) {
    const gap = 16.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (panels.length == 1 || constraints.maxWidth < 700) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, p) in panels.indexed) ...[if (i > 0) const SizedBox(height: gap), p],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: panels.length < 3
                    ? panels[0]
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [panels[0], const SizedBox(height: gap), Expanded(child: panels[2])],
                      ),
              ),
              const SizedBox(width: gap),
              Expanded(child: panels[1]),
            ],
          ),
        );
      },
    );
  }
}

/// With no gym yet: the three steps to one, and the way to find it.
class _HowToJoin extends StatelessWidget {
  const _HowToJoin();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.search_rounded, 'Find a gym', 'See gyms near you, their packages, prices and trainers.'),
      (Icons.how_to_reg_rounded, 'Ask to join', 'Send a request, or show your QR code at its front desk.'),
      (Icons.verified_rounded, 'Pay and check in', 'Pay at the desk or online. Your package shows here.'),
    ];
    return ConsoleCard(
      icon: Icons.fitness_center_rounded,
      title: "You're not a member of a gym yet",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ResponsiveGrid(
            minItemWidth: 200,
            maxColumns: 3,
            children: staggered(offset: 14, [
              for (final (i, (icon, title, text)) in steps.indexed)
                _JoinStep(number: i + 1, icon: icon, title: title, text: text),
            ]),
          ),
          const SizedBox(height: 18),
          IntrinsicWidth(
            child: ConsoleGlowButton(label: 'Find a gym', onPressed: () => context.go(GymRoutes.gyms)),
          ),
        ],
      ),
    );
  }
}

/// A step to their first gym: its icon on a bright square, its number
/// large and faint behind, what to do.
class _JoinStep extends StatelessWidget {
  final int number;
  final IconData icon;
  final String title;
  final String text;

  const _JoinStep({required this.number, required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    final brand = context.brand;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ink.tint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brand.glassBorder),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 12,
            top: -2,
            child: Text(
              '0$number',
              style: TextStyle(
                fontSize: 46,
                fontWeight: FontWeight.w800,
                height: 1,
                color: ink.heading.withValues(alpha: ink.dark ? 0.07 : 0.05),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [brand.themedShade(const Color(0xFFFFA24D)), brand.highlight],
                    ),
                    boxShadow: [
                      BoxShadow(color: brand.highlight.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 5)),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 14),
                Text(
                  'STEP $number',
                  style: TextStyle(
                    color: ink.dark ? brand.accent : brand.accentText,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(title, style: TextStyle(color: ink.heading, fontWeight: FontWeight.w800, fontSize: 15.5)),
                const SizedBox(height: 4),
                Text(text, style: TextStyle(color: ink.body, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A small ring of [share] (0 to 1) in [color], filling in when it shows.
class _Ring extends StatelessWidget {
  final double share;
  final Color color;

  const _Ring({required this.share, required this.color});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: share),
      duration: Motion.of(context, Motion.chart),
      curve: Motion.ease,
      builder: (context, v, _) => SizedBox(
        width: 38,
        height: 38,
        child: CircularProgressIndicator(
          value: v,
          strokeWidth: 4.5,
          strokeCap: StrokeCap.round,
          color: color,
          backgroundColor: color.withValues(alpha: 0.15),
          semanticsLabel: 'Package left',
        ),
      ),
    );
  }
}

/// [child] drawn in from the left when it shows (a sparkline).
class _Reveal extends StatelessWidget {
  final Widget child;

  const _Reveal({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.of(context, Motion.chart),
      curve: Motion.ease,
      child: child,
      builder: (context, t, child) => ClipRect(child: Align(alignment: Alignment.centerLeft, widthFactor: t, child: child)),
    );
  }
}

/// Something of theirs to act on: what, where it leads.
class _AttentionRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String text;
  final String action;
  final VoidCallback onTap;

  const _AttentionRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.13), shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: ink.heading, fontWeight: FontWeight.w800)),
                  Text(text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: ink.body, fontSize: 13, height: 1.35)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(action, style: TextStyle(color: context.brand.accent, fontWeight: FontWeight.w700, fontSize: 13)),
            Icon(Icons.chevron_right_rounded, size: 18, color: context.brand.accent),
          ],
        ),
      ),
    );
  }
}

/// One visit: the gym, and when.
class _VisitRow extends StatelessWidget {
  final String gym;
  final DateTime at;

  const _VisitRow({required this.gym, required this.at});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: ink.tint, shape: BoxShape.circle),
            child: Icon(Icons.login_rounded, size: 17, color: context.brand.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              gym,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, color: ink.heading),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${formatDate(BhutanTime.toBhutan(at))} · ${formatTime(at)}',
            style: TextStyle(color: context.brand.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _MyGymCard extends ConsumerWidget {
  final MyGym gym;
  final DateTime today;

  /// With the width to itself (their only gym): the package on one side,
  /// the details on the other.
  final bool sideways;

  /// Where a tap leads: My gym (from the dashboard), or the gym's public
  /// page with its packages and reviews (from My gym itself).
  final bool toPublicPage;

  const _MyGymCard({required this.gym, required this.today, this.sideways = false, this.toPublicPage = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final ink = ConsoleInk.of(context);
    final active = gym.isActiveOn(today);
    final (String label, Color color) = gym.endDate == null
        ? ('No package yet', brand.muted)
        : gym.isPausedOn(today)
            ? ('Paused until ${formatDate(gym.pause!.endDate)}', brand.warning)
        : active
            ? ('Active until ${formatDate(gym.endDate!)}', brand.success)
            : gym.hasEndedBy(today)
                ? ('Ended ${formatDate(gym.endDate!)}', brand.danger)
                : ('Starts ${formatDate(gym.startDate!)}', brand.warning);
    // How much of a running package is used up, and what's left of it.
    final left = active ? _daysLeft(gym.endDate!, today) : 0;
    final length = active ? _daysLeft(gym.endDate!, gym.startDate!) : 0;
    final initial = gym.venueName.trim().isEmpty ? 'G' : gym.venueName.trim().characters.first.toUpperCase();
    // The theme's own deep colour in the light (navy unless picked).
    final tone = themeTone(context, BrandColors.blue);
    return HoverLift(
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: ink.shadow),
        child: Material(
          color: ink.card,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.go(toPublicPage ? GymRoutes.gymFor(gym.venueId) : GymRoutes.myGymFor(gym.venueId)),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: brand.glassBorder),
              ),
              child: Builder(
                builder: (context) {
                  final header = Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: ink.dark ? 0.18 : 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          initial,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: ink.dark ? Colors.white : tone,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              gym.venueName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: ink.heading),
                            ),
                            Text(
                              gym.place,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: brand.muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: brand.muted),
                    ],
                  );
                  // How the package stands, and paying for the next.
                  final package = <Widget>[
                    StatusChip(label: label, color: color),
                    if (active) ...[
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        // Fills to how much is used up when it shows.
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: length <= 0 ? 0 : ((length - left) / length).clamp(0.0, 1.0)),
                          duration: Motion.of(context, Motion.chart),
                          curve: Motion.ease,
                          builder: (context, v, _) => LinearProgressIndicator(
                            value: v,
                            minHeight: 6,
                            backgroundColor: ink.tint,
                            color: left <= 7 ? brand.warning : brand.success,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        left == 1 ? 'Last day of your package' : '$left days left',
                        style: TextStyle(color: brand.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                    if (gym.pause != null && gym.endDate != null) ...[
                      const SizedBox(height: 10),
                      _PauseNote(pause: gym.pause!, runsUntil: gym.endDate!, today: today),
                    ],
                  ];
                  final paying = <Widget>[
                    if (gym.claim != null) _ClaimLine(gym: gym, claim: gym.claim!),
                    if (gym.canPayOnline) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () => context.go(GymRoutes.payFor(gym.venueId)),
                          icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                          label: Text(gym.endDate == null ? 'Pay online' : 'Renew: pay online'),
                        ),
                      ),
                    ] else if (gym.hasEndedBy(today) && gym.claim?.status != ClaimStatus.pending)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Renew at the front desk: pay, and they confirm it.',
                            style: TextStyle(color: brand.muted, fontSize: 12.5)),
                      ),
                  ];
                  final details = <Widget>[
                    if (gym.planName != null) InfoRow(icon: Icons.sell_outlined, text: gym.planName!),
                    if (gym.memberCode != null)
                      InfoRow(icon: Icons.badge_outlined, text: 'Member code ${gym.memberCode}'),
                    InfoRow(
                      icon: Icons.history_rounded,
                      text: gym.lastVisit == null ? 'No visits yet' : 'Last visit ${timeAgo(gym.lastVisit!)}',
                    ),
                    if (gym.phone != null) InfoRow(icon: Icons.phone_outlined, text: gym.phone!),
                    if (gym.gymMemberId != null)
                      Row(
                        children: [
                          Icon(Icons.sports_outlined, size: 20, color: brand.muted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(gym.trainer == null ? 'No trainer yet' : 'Trainer: ${gym.trainer!.name}'),
                          ),
                          TextButton(
                            onPressed: () => context.go(GymRoutes.chooseTrainerFor(gym.venueId)),
                            child: Text(gym.trainer == null ? 'Choose' : 'Change'),
                          ),
                        ],
                      ),
                  ];
                  if (sideways) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [header, const SizedBox(height: 14), ...package, ...paying],
                          ),
                        ),
                        const SizedBox(width: 28),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: details),
                        ),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      header,
                      const SizedBox(height: 14),
                      ...package,
                      const SizedBox(height: 10),
                      ...details,
                      ...paying,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Their pause at a gym, in words: running (no check-in until it ends) or
/// planned, and until when their package runs because of it.
class _PauseNote extends StatelessWidget {
  final GymPause pause;
  final DateTime runsUntil;
  final DateTime today;

  const _PauseNote({required this.pause, required this.runsUntil, required this.today});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final back = DateTime(pause.endDate.year, pause.endDate.month, pause.endDate.day + 1);
    final text = pause.isUpcomingOn(today)
        ? 'Pause planned ${pauseSpan(pause)}. Your package then runs until ${formatDate(runsUntil)}.'
        : 'Paused ${pauseSpan(pause)}: you can check in again from ${formatDate(back)}. Your package now runs '
            'until ${formatDate(runsUntil)}. Back sooner? The front desk can resume it.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.pause_circle_outline_rounded, size: 18, color: brand.warning),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: brand.body, fontSize: 13, height: 1.35))),
      ],
    );
  }
}

/// Their receipts at a gym, latest first: each opens to print or keep.
class _MyReceipts extends StatelessWidget {
  final List<ReceiptLine> receipts;

  const _MyReceipts({required this.receipts});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return SectionCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final r in receipts)
            ListTile(
              leading: Icon(Icons.receipt_long_outlined, color: brand.muted),
              title: Text('No. ${receiptNumber(r.receiptNo)}${r.planName == null ? '' : ' · ${r.planName}'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text([
                formatDate(BhutanTime.toBhutan(r.paidAt)),
                r.method.label,
                if (r.isRefunded) 'Refunded',
              ].join(' · ')),
              trailing: Text(formatNu(r.amount), style: TextStyle(fontWeight: FontWeight.w800, color: brand.ink)),
              onTap: () => showReceipt(context, r.paymentId, forMember: true),
            ),
        ],
      ),
    );
  }
}

/// Their online payment at a gym: waiting (and can be taken back), or what
/// the gym said.
class _ClaimLine extends ConsumerWidget {
  final MyGym gym;
  final MyClaim claim;

  const _ClaimLine({required this.gym, required this.claim});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final (IconData icon, Color color, String text) = switch (claim.status) {
      ClaimStatus.pending => (
          Icons.hourglass_top_rounded,
          brand.warning,
          'Payment sent: ${formatNu(claim.amount)} for ${claim.planName} (JRN ${claim.jrn}). Waiting for the gym to confirm it.'
        ),
      ClaimStatus.confirmed => (Icons.verified_rounded, brand.success, 'Payment confirmed (JRN ${claim.jrn}).'),
      ClaimStatus.rejected => (
          Icons.error_outline_rounded,
          brand.danger,
          "The gym couldn't find your payment (JRN ${claim.jrn})${claim.decisionNote == null ? '.' : ': ${claim.decisionNote}'}"
        ),
      ClaimStatus.cancelled => (Icons.undo_rounded, brand.muted, 'Payment taken back.'),
    };
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: TextStyle(color: brand.readable(color), fontSize: 13, height: 1.35))),
            ],
          ),
          if (claim.status == ClaimStatus.pending)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  final ok = await runAction(context, () => ref.read(gymRepositoryProvider).cancelClaim(claim.id),
                      success: 'Payment taken back');
                  if (ok) ref.invalidate(myMembershipsProvider);
                },
                child: const Text('Take it back'),
              ),
            ),
        ],
      ),
    );
  }
}

class _MyRequestTile extends ConsumerWidget {
  final MyJoinRequest request;

  const _MyRequestTile({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final color = switch (request.status) {
      JoinRequestStatus.approved => brand.success,
      JoinRequestStatus.declined => brand.danger,
      JoinRequestStatus.pending => brand.warning,
      JoinRequestStatus.cancelled => brand.muted,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(request.venueName),
      subtitle: Text(
        [
          'Asked ${timeAgo(request.createdAt)}',
          if (request.planName != null) request.planName!,
          if (request.decisionNote != null) request.decisionNote!,
        ].join(' · '),
      ),
      trailing: request.status == JoinRequestStatus.pending
          ? TextButton(
              onPressed: () async {
                final ok = await runAction(context, () => ref.read(gymRepositoryProvider).cancelJoinRequest(request.id),
                    success: 'Request taken back');
                if (ok) ref.invalidate(myMembershipsProvider);
              },
              child: const Text('Take back'),
            )
          : StatusChip(label: request.status.label, color: color),
      onTap: () => context.go(GymRoutes.gymFor(request.venueId)),
    );
  }
}

/// On a gym's public page: how to join it. Visitors sign in first; a member
/// sees their membership; someone who asked sees their request waiting;
/// anyone else asks to join (with the package they'd like), and the front
/// desk is told. [highlight] when they came from the gym's QR code.
class JoinGymCard extends ConsumerWidget {
  final Venue gym;
  final List<GymPlan> plans;
  final bool highlight;

  const JoinGymCard({super.key, required this.gym, required this.plans, this.highlight = false});

  Future<void> _ask(BuildContext context, WidgetRef ref) async {
    String? planId;
    final message = TextEditingController();
    final send = await showAppDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Ask to join ${gym.name}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('The front desk gets your request and your details, and lets you know.'),
                const SizedBox(height: 16),
                if (plans.isNotEmpty) ...[
                  DropdownButtonFormField<String?>(
                    initialValue: planId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Package you\'d like (optional)'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Decide at the desk')),
                      for (final p in plans)
                        DropdownMenuItem<String?>(
                          value: p.id,
                          child: Text('${p.name} · ${p.price == 0 ? 'Free' : formatNu(p.price)} / ${formatDuration(p.durationDays)}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => planId = v),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: message,
                  maxLines: 3,
                  minLines: 1,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Message for the desk (optional)', hintText: 'e.g. mornings'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send request')),
          ],
        ),
      ),
    );
    final text = message.text;
    message.dispose();
    if (send != true || !context.mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(gymRepositoryProvider).requestToJoin(gym.id, planId: planId, message: text),
      success: 'Sent. ${gym.name} will let you know.',
    );
    if (ok) ref.invalidate(myMembershipsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final signedIn = ref.watch(currentUserIdProvider) != null;
    final mine = signedIn ? ref.watch(myMembershipsProvider).valueOrNull : null;
    final member = mine?.at(gym.id);
    final waiting = mine?.waitingAt(gym.id);
    final declined = mine?.requests
        .where((r) => r.venueId == gym.id)
        .firstOrNull
        ?.let((r) => r.status == JoinRequestStatus.declined ? r : null);
    final today = BhutanTime.today();

    final Widget body;
    if (!signedIn) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sign in or create a free Health Pro account, then ask to join. The front desk adds you.',
              style: TextStyle(color: brand.body, height: 1.4)),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => context.go(CoreRoutes.signInFor(GymRoutes.gymJoinFor(gym.id))),
            icon: const Icon(Icons.login_rounded),
            label: const Text('Sign in to ask to join'),
          ),
        ],
      );
    } else if (member != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            member.isActiveOn(today)
                ? "You're a member here, until ${formatDate(member.endDate!)}."
                : member.hasEndedBy(today)
                    ? 'Your package here ended on ${formatDate(member.endDate!)}. Renew it at the front desk.'
                    : "You're a member here.",
            style: TextStyle(color: brand.body, height: 1.4),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => context.go(CoreRoutes.myQr),
            icon: const Icon(Icons.qr_code_2_rounded),
            label: const Text('Show my QR code'),
          ),
        ],
      );
    } else if (waiting != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('You asked ${timeAgo(waiting.createdAt)}. The front desk will let you know.',
              style: TextStyle(color: brand.body, height: 1.4)),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () async {
              final ok = await runAction(context, () => ref.read(gymRepositoryProvider).cancelJoinRequest(waiting.id),
                  success: 'Request taken back');
              if (ok) ref.invalidate(myMembershipsProvider);
            },
            child: const Text('Take my request back'),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            gym.isVerified
                ? 'Ask to join here: the front desk gets your details, so you don\'t fill in a form at the counter. '
                    'Or just visit the desk and show your QR code.'
                : 'This gym isn\'t taking requests on Health Pro yet. Visit its front desk.',
            style: TextStyle(color: brand.body, height: 1.4),
          ),
          if (declined?.decisionNote != null) ...[
            const SizedBox(height: 8),
            Text('Last time: "${declined!.decisionNote}"', style: TextStyle(color: brand.muted, fontSize: 13)),
          ],
          if (gym.isVerified) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _ask(context, ref),
              icon: const Icon(Icons.how_to_reg_rounded),
              label: const Text('Ask to join'),
            ),
          ],
        ],
      );
    }

    final accent = brand.accent;
    return Container(
      decoration: BoxDecoration(
        color: brand.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: highlight ? accent.withValues(alpha: 0.6) : brand.glassBorder, width: highlight ? 1.5 : 1),
        boxShadow: brand.cardShadow,
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(member != null ? Icons.verified_rounded : Icons.group_add_rounded, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  member != null
                      ? 'Your membership'
                      : waiting != null
                          ? 'Request sent'
                          : 'Join ${gym.name}',
                  style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          body,
          if (gym.paymentInfo != null) ...[
            const SizedBox(height: 12),
            InfoRow(icon: Icons.account_balance_wallet_outlined, text: 'How to pay: ${gym.paymentInfo!}'),
          ],
        ],
      ),
    );
  }
}

/// On a gym's public page, apart from joining as a member: for trainers.
/// Someone with no trainer profile makes one on the way (it asks the gym
/// when saved); a trainer asks with a note; one who asked sees it waiting;
/// one who trains here goes to their times and members.
class TrainHereCard extends ConsumerWidget {
  final Venue gym;

  const TrainHereCard({super.key, required this.gym});

  Future<void> _ask(BuildContext context, WidgetRef ref) async {
    final note = await askText(
      context,
      title: 'Apply to train at ${gym.name}',
      hint: 'A note for them (optional): e.g. mornings and weekends',
      confirmLabel: 'Send my application',
    );
    if (note == null || !context.mounted) return;
    final ok = await runAction(context, () => ref.read(gymRepositoryProvider).requestGym(gym.id, message: note),
        success: 'Sent. ${gym.name} will check your certificates and let you know.');
    if (ok) ref.invalidate(myTrainingProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final signedIn = ref.watch(currentUserIdProvider) != null;
    final mine = signedIn ? ref.watch(myTrainingProvider).valueOrNull : null;
    if (signedIn && mine == null) return const SizedBox.shrink();
    final here = mine?.gyms.where((g) => g.venueId == gym.id).firstOrNull;

    final String text;
    final String label;
    final IconData icon;
    final VoidCallback onPressed;
    if (!signedIn) {
      text = 'Sign in or create a free Health Pro account, then apply with your trainer profile and certificates.';
      label = 'Sign in to apply as a trainer';
      icon = Icons.login_rounded;
      onPressed = () => context.go(CoreRoutes.signInFor(GymRoutes.gymFor(gym.id)));
    } else if (here?.status == TrainerStatus.verified) {
      text = 'You train here. The front desk scans your QR code when you arrive.';
      label = 'My times and members';
      icon = Icons.event_available_rounded;
      onPressed = () => context.go(GymRoutes.trainerHome);
    } else if (here?.status == TrainerStatus.pending) {
      text = 'Your application is with ${gym.name}. They check your certificates, then let you know.';
      label = 'My trainer page';
      icon = Icons.hourglass_top_rounded;
      onPressed = () => context.go(GymRoutes.trainerHome);
    } else if (here?.status == TrainerStatus.inactive) {
      text = '${gym.name} has made your trainer role inactive here. Your times and member assignments were removed. Contact the gym if you would like to train here again.';
      label = 'My trainer page';
      icon = Icons.visibility_off_outlined;
      onPressed = () => context.go(GymRoutes.trainerHome);
    } else if (mine!.profile == null) {
      text = 'Apply with a trainer profile: who you are, what you do and your certificates. ${gym.name} checks them and '
          'verifies you; members here can then choose you.';
      label = 'Apply as a trainer';
      icon = Icons.sports_rounded;
      onPressed = () => context.go(GymRoutes.trainerProfileFor(gym.id));
    } else {
      text = here?.status == TrainerStatus.rejected
          ? 'Last time ${gym.name} didn\'t verify you${here!.decisionNote == null ? '.' : ': "${here.decisionNote}"'} '
              'You can apply again.'
          : 'Apply with your trainer profile. ${gym.name} checks your certificates and verifies you; members here can '
              'then choose you.';
      label = 'Apply to train here';
      icon = Icons.sports_rounded;
      onPressed = () => _ask(context, ref);
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: brand.fieldBorder)),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.sports_rounded, color: BrandColors.blue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  here?.status == TrainerStatus.verified
                      ? 'You\'re a trainer here'
                      : here?.status == TrainerStatus.inactive
                          ? 'Trainer role inactive here'
                          : 'Are you a trainer?',
                  style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(text, style: TextStyle(color: brand.body, height: 1.4)),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label)),
        ],
      ),
    );
  }
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
