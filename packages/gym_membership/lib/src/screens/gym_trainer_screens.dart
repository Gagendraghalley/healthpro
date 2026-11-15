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

/// The gym's trainers, for its staff who check them: requests waiting
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
        body: AsyncValueView<List<GymTrainer>>(
          value: ref.watch(gymTrainersProvider(venueId)),
          onRetry: () => ref.invalidate(gymTrainersProvider(venueId)),
          data: (list) {
            final waiting = list.where((t) => t.status == TrainerStatus.pending).toList();
            final verified = list.where((t) => t.status == TrainerStatus.verified).toList();
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
                    const EmptyState(
                      icon: Icons.sports_rounded,
                      title: 'No trainers yet',
                      message: 'Trainers make a profile on Health Pro (Trainer profile, in the menu) and ask to train here. '
                          'You check their certificates and verify them here.',
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final p = trainer.profile;
    final pending = trainer.status == TrainerStatus.pending;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TrainerAvatar(name: p.name, photoUrl: p.photoUrl, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text(
                        [
                          if (p.headline != null) p.headline!,
                          if (p.experienceYears != null) '${p.experienceYears} years',
                          if (p.ratingCount > 0) '★ ${p.ratingAverage!.toStringAsFixed(1)}',
                        ].join(' · '),
                        style: TextStyle(color: brand.muted),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => context.push(GymRoutes.trainerFor(p.userId, venueId: venueId)),
                  child: const Text('Profile'),
                ),
              ],
            ),
            if (trainer.message != null) ...[
              const SizedBox(height: 8),
              Text('"${trainer.message}"', style: TextStyle(color: brand.body, fontStyle: FontStyle.italic)),
            ],
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
            const SizedBox(height: 10),
            Text(pending ? 'The times they\'d like' : 'Their week', style: TextStyle(color: brand.muted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            WeekSlotsView(slots: trainer.slots),
            if (trainer.status == TrainerStatus.verified) ...[
              const Divider(height: 22),
              Row(
                children: [
                  Expanded(child: _Figure(value: '${trainer.attendance30Days}', label: 'days here, last 30')),
                  Expanded(child: _Figure(value: '${trainer.members}', label: trainer.members == 1 ? 'member' : 'members')),
                ],
              ),
              if (trainer.attendance.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Last here ${timeAgo(trainer.attendance.first)} · '
                  '${trainer.attendance.take(6).map((a) => '${formatShortDate(BhutanTime.toBhutan(a))} ${formatTime(a)}').join(', ')}',
                  style: TextStyle(color: brand.muted, fontSize: 12.5),
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
                if (pending || trainer.status == TrainerStatus.verified)
                  OutlinedButton(
                    onPressed: () => _decide(context, ref, approve: false),
                    child: Text(pending ? 'Don\'t verify' : 'Stop verifying'),
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
      maxWidth: AppPage.readableWidth,
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
                  for (final t in trainers) _Choice(trainer: t, gym: gym),
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
