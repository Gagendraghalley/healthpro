import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/coaching.dart';
import '../gym_routes.dart';
import '../widgets/coaching_widgets.dart';

/// A trainer's members, gym by gym: their package, latest weight and plans;
/// each opens to their progress and plans.
class TrainerMembersScreen extends ConsumerWidget {
  const TrainerMembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppPage(
      title: 'My members',
      body: AsyncValueView<List<TrainerMember>>(
        value: ref.watch(trainerMembersProvider),
        onRetry: () => ref.invalidate(trainerMembersProvider),
        data: (members) {
          if (members.isEmpty) {
            return const EmptyState(
              icon: Icons.groups_outlined,
              title: 'No members yet',
              message: 'Members choose you as their trainer on My gym, or the front desk gives you to them. '
                  'They show here, with their progress and plans.',
            );
          }
          final today = BhutanTime.today();
          final gyms = <String, List<TrainerMember>>{};
          for (final m in members) {
            gyms.putIfAbsent(m.venueName, () => []).add(m);
          }
          final brand = context.brand;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(trainerMembersProvider),
            child: ListView(
              padding: pagePadding(context),
              children: [
                Text('${members.length} ${members.length == 1 ? 'member' : 'members'} you train: record their progress and '
                    'give them workout and diet plans.', style: TextStyle(color: brand.muted)),
                for (final gym in gyms.entries) ...[
                  SectionTitle(gym.key),
                  SectionCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (final m in gym.value)
                          ListTile(
                            onTap: () => context.push(GymRoutes.trainerMemberFor(m.gymMemberId)),
                            leading: CircleAvatar(
                              backgroundColor: brand.highlight.withValues(alpha: 0.12),
                              child: Text(m.fullName.characters.first.toUpperCase(),
                                  style: TextStyle(color: brand.readable(brand.highlight), fontWeight: FontWeight.w800)),
                            ),
                            title: Text(m.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text([
                              m.code,
                              m.paidUntil == null || m.paidUntil!.isBefore(today)
                                  ? 'no package now'
                                  : 'until ${formatShortDate(m.paidUntil!)}',
                              if (m.latestWeight != null) kgText(m.latestWeight!),
                              m.activePlans == 0 ? 'no plan' : '${m.activePlans} ${m.activePlans == 1 ? 'plan' : 'plans'}',
                            ].join(' · ')),
                            trailing: Icon(Icons.chevron_right_rounded, color: brand.muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One of a trainer's members: how to reach them, their progress and their
/// plans, which the trainer records and writes.
class TrainerMemberScreen extends ConsumerWidget {
  final String gymMemberId;

  const TrainerMemberScreen({super.key, required this.gymMemberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<List<TrainerMember>>(
      value: ref.watch(trainerMembersProvider),
      onRetry: () => ref.invalidate(trainerMembersProvider),
      data: (members) {
        final m = members.where((x) => x.gymMemberId == gymMemberId).firstOrNull;
        if (m == null) {
          return const AppPage(
            title: 'Member',
            body: EmptyState(
              icon: Icons.person_off_outlined,
              title: 'You don\'t train this member now',
              message: 'They may have chosen another trainer.',
            ),
          );
        }
        final brand = context.brand;
        return AppPage(
          title: m.fullName,
          body: ListView(
            padding: pagePadding(context),
            children: [
              SectionCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.fullName, style: context.text.headlineSmall),
                    Text('${m.code} · ${m.venueName} · yours since ${formatShortDate(BhutanTime.toBhutan(m.since))}',
                        style: TextStyle(color: brand.muted)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => callPhone(context, m.phone),
                          icon: const Icon(Icons.call_outlined),
                          label: Text(m.phone),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => openWhatsApp(context, m.phone),
                          icon: const Icon(Icons.chat_outlined),
                          label: const Text('WhatsApp'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SectionTitle('Progress'),
              MemberProgress(gymMemberId: m.gymMemberId, coach: true),
              const SectionTitle('Workout & diet plans'),
              MemberPlans(gymMemberId: m.gymMemberId, venueId: m.venueId, coach: true),
            ],
          ),
        );
      },
    );
  }
}
