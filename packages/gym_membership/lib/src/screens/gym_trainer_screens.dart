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
                  _Notice(
                    icon: Icons.qr_code_scanner_rounded,
                    color: context.brand.accent,
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
    final status = trainer.status;
    final pending = status == TrainerStatus.pending;
    final verified = status == TrainerStatus.verified;
    final inactive = status == TrainerStatus.inactive;
    final rejected = status == TrainerStatus.rejected;
    final today = BhutanTime.today();
    final recentAttendance = uniqueTrainerAttendanceEntries(trainer.attendance);
    final arrivedToday = recentAttendance.any((at) {
      final local = BhutanTime.toBhutan(at);
      return local.year == today.year && local.month == today.month && local.day == today.day;
    });
    final statusChip = StatusChip(
      label: status.label,
      color: verified ? brand.success : pending ? brand.warning : brand.muted,
      icon: verified
          ? Icons.verified_rounded
          : inactive
              ? Icons.visibility_off_outlined
              : Icons.schedule_rounded,
    );
    final line = Divider(height: 1, thickness: 1, color: brand.glassBorder);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        padding: EdgeInsets.zero,
        child: LayoutBuilder(builder: (context, constraints) {
          // The status sits top right when there's room, under the name on a phone.
          final wide = constraints.maxWidth >= 480;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 10, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TrainerAvatar(name: p.name, photoUrl: p.photoUrl, size: 56),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: brand.ink, fontSize: 17, height: 1.25, fontWeight: FontWeight.w800)),
                          if ((p.headline ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(p.headline!,
                                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 13.5)),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (!wide) statusChip,
                              if (p.ratingCount > 0)
                                _Meta(
                                  icon: Icons.star_rounded,
                                  iconColor: BrandColors.amber,
                                  text: '${p.ratingAverage!.toStringAsFixed(1)} (${p.ratingCount} '
                                      '${p.ratingCount == 1 ? 'review' : 'reviews'})',
                                ),
                              if (p.experienceYears != null)
                                _Meta(icon: Icons.workspace_premium_outlined, text: '${p.experienceYears} years experience'),
                              if (trainer.addedByGym) const _Meta(icon: Icons.badge_outlined, text: 'Added by the gym'),
                              if (trainer.phone != null) _Meta(icon: Icons.call_outlined, text: trainer.phone!),
                              if (trainer.email != null) _Meta(icon: Icons.mail_outline_rounded, text: trainer.email!),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (wide) Padding(padding: const EdgeInsets.only(top: 2), child: statusChip),
                    if (verified)
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        icon: Icon(Icons.more_vert_rounded, color: brand.muted),
                        onSelected: (_) => _deactivate(context, ref),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'inactive',
                            child: Row(
                              children: [
                                Icon(Icons.person_off_outlined, size: 20, color: brand.danger),
                                const SizedBox(width: 12),
                                Text('Make inactive', style: TextStyle(color: brand.danger, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      )
                    else
                      const SizedBox(width: 8),
                  ],
                ),
              ),
              line,
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (trainer.message != null) ...[
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: brand.surfaceAlt,
                          borderRadius: BorderRadius.circular(10),
                          border: Border(left: BorderSide(color: brand.accent, width: 3)),
                        ),
                        child: Text('"${trainer.message}"', style: TextStyle(color: brand.body, fontStyle: FontStyle.italic)),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (inactive) ...[
                      _Notice(
                        icon: Icons.info_outline_rounded,
                        color: brand.muted,
                        text: 'Inactive at this gym. Their schedule and member assignments have been cleared.',
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (pending || rejected) ...[
                      const _Label(icon: Icons.workspace_premium_outlined, text: 'Certificates'),
                      const SizedBox(height: 8),
                      if (trainer.certificates.isEmpty)
                        Text('None added yet.', style: TextStyle(color: brand.danger))
                      else
                        for (final c in trainer.certificates)
                          _CertificateRow(
                            text: [c.title, if (c.issuer != null) c.issuer!, if (c.issuedOn != null) '${c.issuedOn!.year}']
                                .join(' · '),
                            onOpen: c.fileUrl == null ? null : () => openExternal(context, Uri.parse(c.fileUrl!)),
                          ),
                      if (trainer.decisionNote != null && rejected) ...[
                        const SizedBox(height: 6),
                        Text('You said: "${trainer.decisionNote}"', style: TextStyle(color: brand.muted)),
                      ],
                      const SizedBox(height: 16),
                    ],
                    if (verified) ...[
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: brand.fieldBorder),
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _Stat(
                                    value: '${trainerAttendanceDaysLast30(trainer.attendance, today)}',
                                    suffix: ' / 30',
                                    label: 'Days attended'),
                              ),
                              VerticalDivider(width: 1, thickness: 1, color: brand.fieldBorder),
                              Expanded(
                                  child: _Stat(value: '${trainer.members}', label: trainer.members == 1 ? 'Member' : 'Members')),
                              VerticalDivider(width: 1, thickness: 1, color: brand.fieldBorder),
                              Expanded(
                                child: _Stat(
                                  value: arrivedToday ? 'Arrived' : 'Not yet',
                                  label: 'Today',
                                  color: arrivedToday ? brand.readable(brand.success) : brand.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _Label(icon: Icons.history_rounded, text: 'Recent arrivals'),
                      const SizedBox(height: 8),
                      if (recentAttendance.isEmpty)
                        Text('No attendance here yet.', style: TextStyle(color: brand.muted, fontSize: 13))
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final at in recentAttendance.take(3))
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: brand.surfaceAlt, borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.login_rounded, size: 14, color: brand.muted),
                                    const SizedBox(width: 6),
                                    Text('${formatShortDate(BhutanTime.toBhutan(at))} · ${formatTime(at)}',
                                        style: TextStyle(color: brand.body, fontSize: 12.5, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: _Label(
                            icon: Icons.calendar_month_outlined,
                            text: inactive
                                ? 'Schedule at this gym'
                                : pending
                                    ? 'Requested weekly times'
                                    : 'Weekly availability',
                          ),
                        ),
                        if (pending || verified)
                          TextButton.icon(
                            onPressed: () => _changeTimes(context, ref),
                            icon: const Icon(Icons.edit_calendar_outlined, size: 16),
                            label: const Text('Change times'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              textStyle: const TextStyle(fontFamily: brandFont, fontSize: 13.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (inactive)
                      Text('No active times at this gym.', style: TextStyle(color: brand.muted))
                    else
                      WeekSlotsView(slots: trainer.slots),
                  ],
                ),
              ),
              line,
              Container(
                color: brand.subtle,
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                child: _CompactButtons(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (pending || rejected)
                        FilledButton.icon(
                          onPressed: () => _decide(context, ref, approve: true),
                          icon: const Icon(Icons.verified_rounded, size: 18),
                          label: const Text('Verify'),
                        ),
                      if (pending)
                        OutlinedButton(
                          onPressed: () => _decide(context, ref, approve: false),
                          child: const Text('Don\'t verify'),
                        ),
                      if (verified)
                        FilledButton.icon(
                          onPressed: arrivedToday ? null : () => _arrived(context, ref),
                          icon: Icon(arrivedToday ? Icons.event_available_rounded : Icons.login_rounded, size: 18),
                          label: Text(arrivedToday ? 'Already arrived today' : 'Mark arrived'),
                        ),
                      if (inactive)
                        FilledButton.icon(
                          onPressed: () => _reactivate(context, ref),
                          icon: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: const Text('Reactivate'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => context.push(GymRoutes.trainerFor(p.userId, venueId: venueId)),
                        icon: const Icon(Icons.person_outline_rounded, size: 18),
                        label: const Text('View profile'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// The app's filled and outlined buttons a size smaller, for a card's footer:
/// two sit side by side even on a phone.
class _CompactButtons extends StatelessWidget {
  final Widget child;

  const _CompactButtons({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const compact = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, 42)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
      textStyle: WidgetStatePropertyAll(TextStyle(fontFamily: brandFont, fontSize: 14.5, fontWeight: FontWeight.w700)),
    );
    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(style: compact.merge(theme.filledButtonTheme.style)),
        outlinedButtonTheme: OutlinedButtonThemeData(style: compact.merge(theme.outlinedButtonTheme.style)),
      ),
      child: child,
    );
  }
}

/// An icon and a short fact, in a trainer's header: rating, experience, phone.
class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? iconColor;

  const _Meta({required this.icon, required this.text, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: iconColor ?? brand.muted),
        const SizedBox(width: 5),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: brand.body, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// A part of the card's heading: a small icon and the name of what follows.
class _Label extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Label({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      children: [
        Icon(icon, size: 16, color: brand.muted),
        const SizedBox(width: 7),
        Flexible(child: Text(text, style: TextStyle(color: brand.ink, fontSize: 13.5, fontWeight: FontWeight.w800))),
      ],
    );
  }
}

/// One cell of the stats strip: the figure, and what it counts.
class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color? color;

  /// After [value], smaller: what it's out of.
  final String? suffix;

  const _Stat({required this.value, required this.label, this.color, this.suffix});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(text: value, children: [
              if (suffix != null)
                TextSpan(text: suffix, style: TextStyle(color: brand.muted, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color ?? brand.ink, fontSize: 19, height: 1.2, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: brand.muted, fontSize: 12, height: 1.3)),
        ],
      ),
    );
  }
}

/// A certificate to check: what it is, and opening the file when there is one.
class _CertificateRow extends StatelessWidget {
  final String text;
  final VoidCallback? onOpen;

  const _CertificateRow({required this.text, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: brand.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.description_outlined, size: 18, color: brand.readable(brand.accent)),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: TextStyle(color: brand.body, fontWeight: FontWeight.w600))),
                if (onOpen != null) ...[
                  const SizedBox(width: 8),
                  Text('See it', style: TextStyle(color: brand.accentText, fontWeight: FontWeight.w700, fontSize: 13)),
                  Icon(Icons.chevron_right_rounded, size: 18, color: brand.accentText),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A short note in a tinted box.
class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _Notice({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: brand.readable(color)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: brand.body, height: 1.4))),
        ],
      ),
    );
  }
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
