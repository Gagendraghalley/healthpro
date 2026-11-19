import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/classes.dart';
import '../gym_routes.dart';

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// 'Today', 'Tomorrow', 'Wed 20 Nov'.
String classDayLabel(DateTime day, DateTime today) {
  final ahead = BhutanTime.daysBetween(today, day);
  if (ahead == 0) return 'Today';
  if (ahead == 1) return 'Tomorrow';
  return '${_days[day.weekday - 1]} ${formatShortDate(day)}';
}

/// On My gym: the gym's classes this week, day by day, with places left;
/// Book, or Cancel their own before it starts. Nothing when the gym has no
/// classes.
class MyClassesCard extends ConsumerWidget {
  final String venueId;

  const MyClassesCard({super.key, required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(gymClassesProvider(venueId)).valueOrNull ?? const <GymClass>[];
    if (!classes.any((c) => c.isActive)) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Classes'),
        SectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: ClassWeek(venueId: venueId, signedIn: true, member: true),
        ),
      ],
    );
  }
}

/// A gym's classes over the next 7 days, day by day, with places left: Book,
/// or Cancel one's own before it starts. Open classes are for anyone on
/// Health Pro; a members-only class shows as such to who isn't a [member].
/// Signed out, Book asks them to sign in, and brings them back here.
class ClassWeek extends ConsumerWidget {
  final String venueId;
  final bool signedIn;
  final bool member;

  /// Under the classes: who can book them (on the gym's public page).
  final bool explain;

  const ClassWeek({super.key, required this.venueId, required this.signedIn, required this.member, this.explain = false});

  Future<void> _book(BuildContext context, WidgetRef ref, ClassSession s) async {
    if (!signedIn) {
      context.go(CoreRoutes.signInFor(GymRoutes.gymFor(venueId)));
      return;
    }
    final ok = await runAction(context, () => ref.read(gymClassRepositoryProvider).book(s.gymClass.id, s.date));
    if (!ok) return;
    ref.invalidate(gymClassPlacesProvider(venueId));
    ref.invalidate(myClassBookingsProvider);
    if (context.mounted) {
      showFeedback(context, 'Booked: ${s.gymClass.name}, ${classDayLabel(s.date, BhutanTime.today())} at ${s.gymClass.time}');
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, ClassSession s) async {
    final sure = await confirmAction(
      context,
      title: 'Cancel your place in ${s.gymClass.name}?',
      message: '${classDayLabel(s.date, BhutanTime.today())} at ${s.gymClass.time}. Someone else can take it.',
      confirmLabel: 'Cancel my place',
      cancelLabel: 'Keep it',
    );
    if (!sure || !context.mounted) return;
    final ok = await runAction(context, () => ref.read(gymClassRepositoryProvider).cancel(s.myBookingId!));
    if (!ok) return;
    ref.invalidate(gymClassPlacesProvider(venueId));
    ref.invalidate(myClassBookingsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = (ref.watch(gymClassesProvider(venueId)).valueOrNull ?? const <GymClass>[]).where((c) => c.isActive).toList();
    final places = ref.watch(gymClassPlacesProvider(venueId)).valueOrNull ?? const <ClassPlaces>[];
    final today = BhutanTime.today();
    final now = BhutanTime.now();
    final sessions = sessionsFrom(classes, places, today).where((s) => !s.startedBy(now) || s.myBookingId != null).toList();
    final brand = context.brand;
    final days = <DateTime, List<ClassSession>>{};
    for (final s in sessions) {
      days.putIfAbsent(s.date, () => []).add(s);
    }
    final open = classes.any((c) => c.openToAll);
    final note = !explain
        ? null
        : [
            if (open) 'Anyone with a Health Pro account can book a place, member of the gym or not.',
            if (!signedIn) 'Sign in or create a free account to book.',
          ].join(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (days.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('No classes in the next 7 days.', style: TextStyle(color: brand.muted)),
          )
        else
          for (final (i, day) in days.entries.indexed) ...[
            _DayHeader(
              label: classDayLabel(day.key, today),
              count: day.value.length,
              top: i == 0 ? (explain ? 0 : 8) : 14,
            ),
            for (final s in day.value)
              _SessionRow(
                session: s,
                now: now,
                membersOnly: !s.gymClass.openToAll && !member,
                onBook: _book,
                onCancel: _cancel,
              ),
          ],
        if (note != null && note.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: brand.surfaceAlt, borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 17, color: brand.muted),
                const SizedBox(width: 10),
                Expanded(child: Text(note, style: TextStyle(color: brand.body, fontSize: 12.5, height: 1.5))),
              ],
            ),
          ),
      ],
    );
  }
}

/// 'Sat 21 Nov  2 classes ————': the day, then a hairline to the edge.
class _DayHeader extends StatelessWidget {
  final String label;
  final int count;
  final double top;

  const _DayHeader({required this.label, required this.count, required this.top});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 8),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: brand.ink, fontSize: 13, letterSpacing: 0.2)),
          const SizedBox(width: 8),
          Text(count == 1 ? '1 class' : '$count classes', style: TextStyle(color: brand.muted, fontSize: 12)),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: brand.fieldBorder.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}

class _SessionRow extends ConsumerWidget {
  final ClassSession session;
  final DateTime now;

  /// For members only, and they aren't one: no Book.
  final bool membersOnly;
  final Future<void> Function(BuildContext, WidgetRef, ClassSession) onBook;
  final Future<void> Function(BuildContext, WidgetRef, ClassSession) onCancel;

  const _SessionRow({
    required this.session,
    required this.now,
    this.membersOnly = false,
    required this.onBook,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final s = session;
    final c = s.gymClass;
    final started = s.startedBy(now);
    final mine = s.myBookingId != null;
    const size = Size(84, 38);
    const pad = EdgeInsets.symmetric(horizontal: 18);
    final Widget action;
    if (mine) {
      action = started
          ? StatusChip(label: 'Booked', color: brand.success, icon: Icons.check_rounded)
          : OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: size, padding: pad),
              onPressed: () => onCancel(context, ref, s),
              child: const Text('Cancel'),
            );
    } else if (s.isFull) {
      action = StatusChip(label: 'Full', color: brand.muted);
    } else if (membersOnly) {
      action = StatusChip(label: 'Members only', color: brand.muted, icon: Icons.lock_outline_rounded);
    } else {
      action = FilledButton(
        style: FilledButton.styleFrom(minimumSize: size, padding: pad),
        onPressed: () => onBook(context, ref, s),
        child: const Text('Book'),
      );
    }
    // A few places left: say so in amber.
    final low = !s.isFull && s.left <= (c.capacity ~/ 5).clamp(2, 5);
    final fill = c.capacity == 0 ? 1.0 : (s.booked / c.capacity).clamp(0.0, 1.0);
    final barColor = s.isFull ? brand.muted : (low ? brand.warning : brand.accent);
    final meta = [if (c.trainerName != null) 'with ${c.trainerName}', if (!c.openToAll) 'members only'];
    final time = SizedBox(
      width: 76,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.time, style: TextStyle(fontWeight: FontWeight.w800, color: brand.ink, fontSize: 14)),
          const SizedBox(height: 2),
          Text('${c.durationMinutes} min', style: TextStyle(color: brand.muted, fontSize: 12)),
        ],
      ),
    );
    final rule = Container(width: 1, height: 44, margin: const EdgeInsets.only(right: 14), color: brand.fieldBorder.withValues(alpha: 0.7));
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(c.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink, fontSize: 15)),
            ),
            if (mine) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle_rounded, size: 16, color: brand.success),
            ],
          ],
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(meta.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 12.5)),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 56,
              height: 4,
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(color: brand.fieldBorder.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2)),
              child: FractionallySizedBox(
                widthFactor: fill,
                child: DecoratedBox(decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(2))),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                s.isFull ? 'No places left' : '${s.left} of ${c.capacity} places left',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: low ? brand.warning : brand.muted, fontSize: 12, fontWeight: low ? FontWeight.w700 : FontWeight.w500),
              ),
            ),
          ],
        ),
      ],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: mine ? brand.success.withValues(alpha: 0.06) : brand.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: mine ? brand.success.withValues(alpha: 0.4) : brand.fieldBorder.withValues(alpha: 0.7)),
      ),
      // On a narrow phone the button drops under the class.
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth < 330
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [time, rule, Expanded(child: details)]),
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              )
            : Row(children: [time, rule, Expanded(child: details), const SizedBox(width: 12), action]),
      ),
    );
  }
}

/// On My dashboard: the classes the person has booked, at any gym,
/// day by day until each ends. Each opens its gym's page; Cancel before it
/// starts.
class MyClassBookingsList extends ConsumerWidget {
  final List<MyClassBooking> bookings;

  const MyClassBookingsList({super.key, required this.bookings});

  /// Those not over yet by [nowInBhutan].
  static List<MyClassBooking> ahead(List<MyClassBooking> all, DateTime nowInBhutan) =>
      all.where((b) => b.endsAt.isAfter(nowInBhutan)).toList();

  Future<void> _cancel(BuildContext context, WidgetRef ref, MyClassBooking b) async {
    final sure = await confirmAction(
      context,
      title: 'Cancel your place in ${b.name}?',
      message: '${b.venueName}, ${classDayLabel(b.date, BhutanTime.today())} at ${b.time}. Someone else can take it.',
      confirmLabel: 'Cancel my place',
      cancelLabel: 'Keep it',
    );
    if (!sure || !context.mounted) return;
    final ok = await runAction(context, () => ref.read(gymClassRepositoryProvider).cancel(b.id));
    if (!ok) return;
    ref.invalidate(myClassBookingsProvider);
    ref.invalidate(gymClassPlacesProvider(b.venueId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final today = BhutanTime.today();
    final now = BhutanTime.now();
    final days = <DateTime, List<MyClassBooking>>{};
    for (final b in ahead(bookings, now)) {
      days.putIfAbsent(b.date, () => []).add(b);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, day) in days.entries.indexed) ...[
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10, bottom: 2),
            child: Text(classDayLabel(day.key, today), style: TextStyle(fontWeight: FontWeight.w800, color: brand.muted, fontSize: 12.5)),
          ),
          for (final b in day.value)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => context.go(GymRoutes.gymFor(b.venueId)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(width: 72, child: Text(b.time, style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink))),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
                          Text([b.venueName, if (b.trainerName != null) 'with ${b.trainerName}', '${b.durationMinutes} min'].join(' · '),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    b.startsAt.isAfter(now)
                        ? TextButton(onPressed: () => _cancel(context, ref, b), child: const Text('Cancel'))
                        : StatusChip(label: 'On now', color: brand.success, icon: Icons.play_arrow_rounded),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}
