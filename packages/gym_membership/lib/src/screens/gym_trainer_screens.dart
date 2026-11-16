import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/gym_repository.dart';
import '../data/joining.dart';
import '../data/trainers.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import '../widgets/gym_widgets.dart';
import '../widgets/trainer_widgets.dart';
import 'trainer_screens.dart' show pickTrainerSlots;

/// The gym's trainers, for its staff who check them: adding one themselves
/// (Add trainer: all their details, verified straight away), requests waiting
/// (their profile and certificates, to verify them or not), and the
/// verified ones with their week here (their times at other gyms only as
/// Not available), their attendance here (the desk scans their QR code when
/// they arrive) and their members here.
class GymTrainersScreen extends ConsumerWidget {
  final String venueId;

  const GymTrainersScreen({super.key, required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GymStaffPage(
      venueId: venueId,
      title: 'Trainers',
      permission: GymPermission.trainers,
      builder: (context, access) => AppPage(
        title: 'Trainers',
        actions: [
          FilledButton.icon(
            onPressed: () => context.go(GymRoutes.addTrainerFor(venueId)),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('Add trainer'),
          ),
          const SizedBox(width: 8),
        ],
        body: AsyncValueView<List<GymTrainer>>(
          value: ref.watch(gymTrainersProvider(venueId)),
          onRetry: () => ref.invalidate(gymTrainersProvider(venueId)),
          data: (list) {
            final waiting = list.where((t) => t.status == TrainerStatus.pending).toList();
            final verified = list.where((t) => t.status == TrainerStatus.verified).toList();
            final inactive = list.where((t) => t.status == TrainerStatus.inactive).toList();
            final declined = list.where((t) => t.status == TrainerStatus.rejected).toList();
            return RefreshIndicator(
              onRefresh: () => ref.refresh(gymTrainersProvider(venueId).future),
              child: ListView(
                padding: pagePadding(context),
                children: [
                  const InfoRow(
                    icon: Icons.qr_code_scanner_rounded,
                    text: 'Attendance: scan a trainer\'s Health Pro QR code at Check-in when they arrive, as for members. '
                        'Each gym keeps its own record.',
                  ),
                  if (list.isEmpty)
                    EmptyState(
                      icon: Icons.sports_rounded,
                      title: 'No trainers yet',
                      message: 'Add your trainers here with their details and certificates. Trainers can also apply from '
                          'your gym\'s page on Health Pro; you check their certificates and verify them here.',
                      actionLabel: 'Add trainer',
                      onAction: () => context.go(GymRoutes.addTrainerFor(venueId)),
                    ),
                  if (waiting.isNotEmpty) ...[
                    SectionTitle('Asking to train here (${waiting.length})'),
                    for (final t in waiting) _TrainerCard(trainer: t, venueId: venueId),
                  ],
                  if (verified.isNotEmpty) ...[
                    SectionTitle('Our trainers (${verified.length})'),
                    ResponsiveGrid(
                      minItemWidth: 360,
                      maxColumns: 2,
                      equalHeight: false,
                      children: [for (final t in verified) _TrainerCard(trainer: t, venueId: venueId)],
                    ),
                  ],
                  if (inactive.isNotEmpty) ...[
                    SectionTitle('Inactive at this gym (${inactive.length})'),
                    ResponsiveGrid(
                      minItemWidth: 360,
                      maxColumns: 2,
                      equalHeight: false,
                      children: [for (final t in inactive) _TrainerCard(trainer: t, venueId: venueId)],
                    ),
                  ],
                  if (declined.isNotEmpty) ...[
                    const SectionTitle('Not verified'),
                    for (final t in declined) _TrainerCard(trainer: t, venueId: venueId),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TrainerCard extends ConsumerWidget {
  final GymTrainer trainer;
  final String venueId;

  const _TrainerCard({required this.trainer, required this.venueId});

  Future<void> _decide(BuildContext context, WidgetRef ref, {required bool approve}) async {
    final p = trainer.profile;
    String? note;
    if (approve) {
      final sure = await confirmAction(
        context,
        title: 'Verify ${p.name}?',
        message: 'You\'ve checked their certificates. They\'ll train here, members can choose them, and the desk takes '
            'their attendance.',
        confirmLabel: 'Verify',
      );
      if (!sure) return;
    } else {
      note = await askText(context, title: 'Not verify ${p.name}?', hint: 'Why, for them: e.g. we need a CPR certificate',
          confirmLabel: 'Tell them');
      if (note == null) return;
    }
    if (!context.mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(gymRepositoryProvider).decideTrainer(venueId, p.userId, approve: approve, note: note),
      success: approve ? '${p.name} is verified here' : '${p.name} is told',
    );
    if (ok) refreshGym(ref, venueId);
  }

  Future<void> _changeTimes(BuildContext context, WidgetRef ref) async {
    final p = trainer.profile;
    final saved = await pickTrainerSlots(
      context,
      title: '${p.name}\'s times here',
      initial: trainer.slots.where((s) => s.here).toList(),
      note: 'Add one row for each day and time. If they\'re already scheduled elsewhere, that time is unavailable. They\'re told when their schedule changes.',
    );
    if (saved == null || !context.mounted) return;
    final ok = await runAction(context, () => ref.read(gymRepositoryProvider).saveTrainerSlots(venueId, p.userId, saved),
        success: 'Times saved');
    if (ok) refreshGym(ref, venueId);
  }

  Future<void> _arrived(BuildContext context, WidgetRef ref) async {
    final p = trainer.profile;
    var alreadyMarked = false;
    final ok = await runAction(context, () async {
      alreadyMarked = await ref.read(gymRepositoryProvider).markTrainerArrived(venueId, p.userId);
    });
    if (ok && context.mounted) {
      showFeedback(context, alreadyMarked
          ? '${p.name} is already marked for today. No new attendance was added.'
          : '${p.name} arrived',
          problem: alreadyMarked);
      refreshGym(ref, venueId);
    }
  }

  Future<void> _deactivate(BuildContext context, WidgetRef ref) async {
    final p = trainer.profile;
    final sure = await confirmAction(
      context,
      title: 'Make ${p.name} inactive at this gym?',
      message: 'They will be removed from this gym\'s public trainer list. Their weekly times will be cleared, members assigned to them will be unassigned, and the trainer and affected members will be notified.',
      confirmLabel: 'Make inactive',
      destructive: true,
    );
    if (!sure || !context.mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(gymRepositoryProvider).deactivateTrainer(venueId, p.userId),
      success: '${p.name} is inactive at this gym; affected members and the trainer were notified',
    );
    if (ok && context.mounted) refreshGym(ref, venueId);
  }

  Future<void> _reactivate(BuildContext context, WidgetRef ref) async {
    final p = trainer.profile;
    final sure = await confirmAction(
      context,
      title: 'Reactivate ${p.name} at this gym?',
      message: 'They will appear in this gym\'s trainer list again. Their old schedule and member assignments stay cleared; set new times and assign members again as needed.',
      confirmLabel: 'Reactivate',
    );
    if (!sure || !context.mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(gymRepositoryProvider).reactivateTrainer(venueId, p.userId),
      success: '${p.name} is active at this gym again',
    );
    if (ok && context.mounted) refreshGym(ref, venueId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final p = trainer.profile;
    final pending = trainer.status == TrainerStatus.pending;
    final today = BhutanTime.today();
    final recentAttendance = uniqueTrainerAttendanceEntries(trainer.attendance);
    final arrivedToday = recentAttendance.any((at) {
      final local = BhutanTime.toBhutan(at);
      return local.year == today.year && local.month == today.month && local.day == today.day;
    });
    final contact = [if (trainer.phone != null) trainer.phone!, if (trainer.email != null) trainer.email!].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TrainerAvatar(name: p.name, photoUrl: p.photoUrl, size: 58),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      if ((p.headline ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(p.headline!, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: brand.muted)),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 7,
                        runSpacing: 6,
                        children: [
                          StatusChip(
                            label: trainer.status.label,
                            color: trainer.status == TrainerStatus.verified
                                ? brand.success
                                : trainer.status == TrainerStatus.pending
                                    ? brand.warning
                                    : brand.muted,
                            icon: trainer.status == TrainerStatus.verified
                                ? Icons.verified_rounded
                                : trainer.status == TrainerStatus.inactive
                                    ? Icons.visibility_off_outlined
                                    : Icons.schedule_rounded,
                          ),
                          if (p.experienceYears != null)
                            StatusChip(label: '${p.experienceYears} years experience', color: BrandColors.blue),
                          if (p.ratingCount > 0)
                            StatusChip(
                              label: '★ ${p.ratingAverage!.toStringAsFixed(1)} · ${p.ratingCount}',
                              color: BrandColors.amber,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'View trainer profile',
                  onPressed: () => context.push(GymRoutes.trainerFor(p.userId, venueId: venueId)),
                  icon: const Icon(Icons.open_in_new_rounded),
                  style: IconButton.styleFrom(backgroundColor: brand.surfaceAlt),
                ),
              ],
            ),
            if (trainer.addedByGym || contact.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (trainer.addedByGym) StatusChip(label: 'Added by the gym', color: BrandColors.blue, icon: Icons.badge_outlined),
                  if (contact.isNotEmpty) Text(contact, style: TextStyle(color: brand.muted, fontSize: 12.5)),
                ],
              ),
            ],
            if (trainer.message != null) ...[
              const SizedBox(height: 8),
              Text('"${trainer.message}"', style: TextStyle(color: brand.body, fontStyle: FontStyle.italic)),
            ],
            if (trainer.status == TrainerStatus.inactive)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Inactive at this gym. Their schedule and member assignments have been cleared.',
                    style: TextStyle(color: brand.muted)),
              ),
            if (pending || trainer.status == TrainerStatus.rejected) ...[
              const SizedBox(height: 10),
              Text('Certificates', style: TextStyle(color: brand.muted, fontWeight: FontWeight.w700)),
              if (trainer.certificates.isEmpty)
                Text('None added yet.', style: TextStyle(color: brand.danger))
              else
                for (final c in trainer.certificates)
                  InkWell(
                    onTap: c.fileUrl == null ? null : () => openExternal(context, Uri.parse(c.fileUrl!)),
                    child: InfoRow(
                      icon: Icons.workspace_premium_rounded,
                      text: [c.title, if (c.issuer != null) c.issuer!, if (c.issuedOn != null) '${c.issuedOn!.year}',
                              if (c.fileUrl != null) '(see it)']
                          .join(' · '),
                    ),
                  ),
            ],
            if (trainer.decisionNote != null && trainer.status == TrainerStatus.rejected)
              Text('You said: "${trainer.decisionNote}"', style: TextStyle(color: brand.muted)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: brand.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_month_rounded, size: 18, color: brand.muted),
                      const SizedBox(width: 8),
                      Text(
                          trainer.status == TrainerStatus.inactive
                              ? 'Schedule at this gym'
                              : pending
                                  ? 'Requested weekly times'
                                  : 'Weekly availability',
                          style: TextStyle(color: brand.ink, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (trainer.status == TrainerStatus.inactive)
                    Text('No active times at this gym.', style: TextStyle(color: brand.muted))
                  else
                    WeekSlotsView(slots: trainer.slots),
                ],
              ),
            ),
            if (trainer.status == TrainerStatus.verified) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _Figure(value: '${trainerAttendanceDaysLast30(trainer.attendance, today)}', label: 'attendance days · last 30')),
                  Expanded(child: _Figure(value: '${trainer.members}', label: trainer.members == 1 ? 'member' : 'members')),
                ],
              ),
            if (recentAttendance.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Recent arrivals', style: TextStyle(color: brand.muted, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final at in recentAttendance.take(3))
                      Chip(
                        avatar: const Icon(Icons.login_rounded, size: 15),
                        visualDensity: VisualDensity.compact,
                        label: Text('${formatShortDate(BhutanTime.toBhutan(at))} · ${formatTime(at)}'),
                      ),
                  ],
                ),
              ] else
                Text('No attendance here yet.', style: TextStyle(color: brand.muted, fontSize: 12.5)),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (pending || trainer.status == TrainerStatus.rejected)
                  FilledButton.icon(
                    onPressed: () => _decide(context, ref, approve: true),
                    icon: const Icon(Icons.verified_rounded, size: 18),
                    label: const Text('Verify'),
                  ),
                if (trainer.status == TrainerStatus.verified)
                  FilledButton.tonalIcon(
                    onPressed: arrivedToday ? null : () => _arrived(context, ref),
                    icon: Icon(arrivedToday ? Icons.event_available_rounded : Icons.login_rounded, size: 18),
                    label: Text(arrivedToday ? 'Already arrived today' : 'Mark arrived'),
                  ),
                if (trainer.status == TrainerStatus.inactive)
                  FilledButton.icon(
                    onPressed: () => _reactivate(context, ref),
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: const Text('Reactivate'),
                  ),
                if (pending || trainer.status == TrainerStatus.verified)
                  OutlinedButton.icon(
                    onPressed: () => _changeTimes(context, ref),
                    icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                    label: const Text('Change times'),
                  ),
                if (pending || trainer.status == TrainerStatus.verified)
                  OutlinedButton(
                    onPressed: pending
                        ? () => _decide(context, ref, approve: false)
                        : () => _deactivate(context, ref),
                    child: Text(pending ? 'Don\'t verify' : 'Make inactive'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String value;
  final String label;

  const _Figure({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(color: context.brand.muted, fontSize: 12.5)),
        ],
      );
}

/// A member chooses their trainer at one of their gyms: its verified
/// trainers, with their rating and their times there, and switching any
/// time (the old trainer is told).
class ChooseTrainerScreen extends ConsumerWidget {
  final String venueId;

  const ChooseTrainerScreen({super.key, required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppPage(
      title: 'Choose your trainer',
      body: AsyncValueView<MyMemberships>(
        value: ref.watch(myMembershipsProvider),
        onRetry: () => ref.invalidate(myMembershipsProvider),
        data: (mine) {
          final gym = mine.at(venueId);
          if (gym?.gymMemberId == null) {
            return EmptyState(
              icon: Icons.fitness_center_rounded,
              title: "You're not a member of this gym yet",
              actionLabel: 'Open the gym',
              onAction: () => context.go(GymRoutes.gymFor(venueId)),
            );
          }
          return AsyncValueView<List<TrainerProfile>>(
            value: ref.watch(gymVerifiedTrainersProvider(venueId)),
            onRetry: () => ref.invalidate(gymVerifiedTrainersProvider(venueId)),
            data: (trainers) {
              if (trainers.isEmpty) {
                return EmptyState(
                  icon: Icons.sports_outlined,
                  title: '${gym!.venueName} has no trainers on Health Pro yet',
                  message: 'Ask at the front desk.',
                );
              }
              return ListView(
                padding: pagePadding(context),
                children: [
                  Text(gym!.venueName, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    gym.trainer == null
                        ? 'Read their profiles and reviews, then choose. You can change any time.'
                        : 'Your trainer now: ${gym.trainer!.name}. Choose another any time; they\'re told.',
                    style: TextStyle(color: context.brand.muted),
                  ),
                  const SizedBox(height: 14),
                  ResponsiveGrid(
                    minItemWidth: 340,
                    maxColumns: 3,
                    runSpacing: 2,
                    equalHeight: false,
                    children: [for (final t in trainers) _Choice(trainer: t, gym: gym)],
                  ),
                  if (gym.trainer != null)
                    TextButton(
                      onPressed: () => _choose(context, ref, gym, null, 'You have no trainer now'),
                      child: const Text('I don\'t want a trainer'),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

Future<void> _choose(BuildContext context, WidgetRef ref, MyGym gym, String? trainerId, String done) async {
  final ok = await runAction(context, () => ref.read(gymRepositoryProvider).setMemberTrainer(gym.gymMemberId!, trainerId),
      success: done);
  if (!ok || !context.mounted) return;
  ref.invalidate(myMembershipsProvider);
  context.go(GymRoutes.my);
}

class _Choice extends ConsumerWidget {
  final TrainerProfile trainer;
  final MyGym gym;

  const _Choice({required this.trainer, required this.gym});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = gym.trainer?.id == trainer.userId;
    final times =
        ref.watch(trainerTimingsProvider((trainerId: trainer.userId, venueId: gym.venueId))).valueOrNull ?? const <TrainerSlot>[];
    final here = times.where((s) => s.here).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TrainerTile(trainer: trainer, venueId: gym.venueId),
            if (here.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Here: ${slotsText(here)}', style: TextStyle(color: context.brand.body)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: mine
                  ? const StatusChip(label: 'Your trainer', color: BrandColors.green, icon: Icons.check_rounded)
                  : FilledButton.tonal(
                      onPressed: () => _choose(context, ref, gym, trainer.userId, '${trainer.name} is your trainer now'),
                      child: Text('Choose ${trainer.name.split(' ').first}'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
