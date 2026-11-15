import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/gym_repository.dart';
import '../data/trainers.dart';
import '../gym_routes.dart';

/// A trainer's photo, or their initial.
class TrainerAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double size;

  const TrainerAvatar({super.key, required this.name, this.photoUrl, this.size = 44});

  @override
  Widget build(BuildContext context) {
    const color = BrandColors.blue;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: photoUrl == null
            ? ColoredBox(
                color: color.withValues(alpha: 0.14),
                child: Center(
                  child: Text(initial, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: size * 0.4)),
                ),
              )
            : Image.network(photoUrl!, fit: BoxFit.cover, semanticLabel: name,
                errorBuilder: (_, __, ___) => ColoredBox(color: color.withValues(alpha: 0.14))),
      ),
    );
  }
}

/// A trainer in a list: photo, name, what they do, rating; opens their
/// profile (seen from [venueId], when given).
class TrainerTile extends StatelessWidget {
  final TrainerProfile trainer;
  final String? venueId;
  final Widget? trailing;
  final VoidCallback? onTap;

  const TrainerTile({super.key, required this.trainer, this.venueId, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: TrainerAvatar(name: trainer.name, photoUrl: trainer.photoUrl),
      title: Text(trainer.name, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(
        [
          if (trainer.headline != null) trainer.headline!,
          if (trainer.ratingCount > 0) '★ ${trainer.ratingAverage!.toStringAsFixed(1)} (${trainer.ratingCount})',
          if (trainer.experienceYears != null) '${trainer.experienceYears} years',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: brand.muted),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
      onTap: onTap ?? () => context.push(GymRoutes.trainerFor(trainer.userId, venueId: venueId)),
    );
  }
}

/// A trainer's week, day by day. Times at other gyms (seen from one gym)
/// are only 'Not available'; with [showGym], each time says where.
class WeekSlotsView extends StatelessWidget {
  final List<TrainerSlot> slots;
  final bool showGym;

  const WeekSlotsView({super.key, required this.slots, this.showGym = false});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    if (slots.isEmpty) return Text('No times set yet.', style: TextStyle(color: brand.muted));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var day = 1; day <= 7; day++)
          if (slots.where((s) => s.weekday == day).toList() case final today when today.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 48,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(weekdayName(day), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in today)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: s.here ? brand.accent.withValues(alpha: 0.12) : brand.surfaceAlt,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              s.here
                                  ? [s.time, if (showGym && s.venueName != null) s.venueName!].join(' · ')
                                  : '${s.time} · Not available',
                              style: TextStyle(
                                color: s.here ? brand.readable(brand.accent) : brand.muted,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// A member's trainer at a gym, for its desk: who it is, and (with
/// [canChange]) assigning one or changing it. Nothing when the gym has no
/// verified trainers.
class MemberTrainerPicker extends ConsumerWidget {
  final String venueId;
  final String gymMemberId;
  final bool canChange;

  /// Under a check-in: a slim line.
  final bool compact;

  const MemberTrainerPicker({
    super.key,
    required this.venueId,
    required this.gymMemberId,
    this.canChange = false,
    this.compact = false,
  });

  Future<void> _set(BuildContext context, WidgetRef ref, String? trainerId, String label) async {
    final ok = await runAction(context, () => ref.read(gymRepositoryProvider).setMemberTrainer(gymMemberId, trainerId),
        success: label);
    if (ok) {
      ref.invalidate(memberTrainerProvider(gymMemberId));
      ref.invalidate(gymTrainersProvider(venueId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainers = ref.watch(gymVerifiedTrainersProvider(venueId)).valueOrNull ?? const <TrainerProfile>[];
    final current = ref.watch(memberTrainerProvider(gymMemberId));
    if (trainers.isEmpty || !current.hasValue) return const SizedBox.shrink();
    final brand = context.brand;
    final now = trainers.where((t) => t.userId == current.value).firstOrNull;
    final menu = MenuAnchor(
      menuChildren: [
        for (final t in trainers)
          MenuItemButton(
            leadingIcon: TrainerAvatar(name: t.name, photoUrl: t.photoUrl, size: 28),
            onPressed: t.userId == now?.userId ? null : () => _set(context, ref, t.userId, '${t.name} is their trainer now'),
            child: Text(t.name),
          ),
        if (now != null)
          MenuItemButton(
            leadingIcon: const Icon(Icons.person_off_outlined),
            onPressed: () => _set(context, ref, null, 'No trainer now'),
            child: const Text('No trainer'),
          ),
      ],
      builder: (context, controller, _) => TextButton.icon(
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        icon: Icon(now == null ? Icons.person_add_alt_1_rounded : Icons.swap_horiz_rounded, size: 18),
        label: Text(now == null ? 'Assign a trainer' : 'Change'),
      ),
    );
    final line = Row(
      children: [
        if (now != null) TrainerAvatar(name: now.name, photoUrl: now.photoUrl, size: 32) else Icon(Icons.sports_outlined, color: brand.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            now == null ? 'No trainer yet' : 'Trainer: ${now.name}',
            style: TextStyle(fontWeight: FontWeight.w700, color: now == null ? brand.muted : brand.ink),
          ),
        ),
        if (canChange) menu,
      ],
    );
    return compact
        ? Padding(padding: const EdgeInsets.only(top: 8), child: SectionCard(padding: const EdgeInsets.fromLTRB(14, 6, 6, 6), child: line))
        : SectionCard(padding: const EdgeInsets.fromLTRB(14, 8, 8, 8), child: line);
  }
}
