import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/classes.dart';

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

  Future<void> _book(BuildContext context, WidgetRef ref, ClassSession s) async {
    final ok = await runAction(context, () => ref.read(gymClassRepositoryProvider).book(s.gymClass.id, s.date));
    if (!ok) return;
    ref.invalidate(gymClassPlacesProvider(venueId));
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
    if (ok) ref.invalidate(gymClassPlacesProvider(venueId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = (ref.watch(gymClassesProvider(venueId)).valueOrNull ?? const <GymClass>[]).where((c) => c.isActive).toList();
    if (classes.isEmpty) return const SizedBox.shrink();
    final places = ref.watch(gymClassPlacesProvider(venueId)).valueOrNull ?? const <ClassPlaces>[];
    final today = BhutanTime.today();
    final now = BhutanTime.now();
    final sessions = sessionsFrom(classes, places, today).where((s) => !s.startedBy(now) || s.myBookingId != null).toList();
    final brand = context.brand;
    final days = <DateTime, List<ClassSession>>{};
    for (final s in sessions) {
      days.putIfAbsent(s.date, () => []).add(s);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Classes'),
        SectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: days.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text('No classes in the next 7 days.', style: TextStyle(color: brand.muted)),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final day in days.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 2),
                        child: Text(classDayLabel(day.key, today),
                            style: TextStyle(fontWeight: FontWeight.w800, color: brand.muted, fontSize: 12.5)),
                      ),
                      for (final s in day.value) _SessionRow(session: s, now: now, onBook: _book, onCancel: _cancel),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _SessionRow extends ConsumerWidget {
  final ClassSession session;
  final DateTime now;
  final Future<void> Function(BuildContext, WidgetRef, ClassSession) onBook;
  final Future<void> Function(BuildContext, WidgetRef, ClassSession) onCancel;

  const _SessionRow({required this.session, required this.now, required this.onBook, required this.onCancel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final s = session;
    final c = s.gymClass;
    final started = s.startedBy(now);
    final Widget action;
    if (s.myBookingId != null) {
      action = started
          ? StatusChip(label: 'Booked', color: brand.success, icon: Icons.check_rounded)
          : TextButton(onPressed: () => onCancel(context, ref, s), child: const Text('Cancel'));
    } else if (s.isFull) {
      action = StatusChip(label: 'Full', color: brand.muted);
    } else {
      action = FilledButton.tonal(onPressed: () => onBook(context, ref, s), child: const Text('Book'));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(c.time, style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(c.name, style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink))),
                    if (s.myBookingId != null) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.check_circle_rounded, size: 16, color: brand.success),
                    ],
                  ],
                ),
                Text(
                  [
                    if (c.trainerName != null) 'with ${c.trainerName}',
                    '${c.durationMinutes} min',
                    s.isFull ? 'full' : '${s.left} of ${c.capacity} places left',
                  ].join(' · '),
                  style: TextStyle(color: brand.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          action,
        ],
      ),
    );
  }
}
