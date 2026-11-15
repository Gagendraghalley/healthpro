import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../data/joining.dart';
import '../data/online_payments.dart';
import '../gym_routes.dart';

/// A member's own: their QR code, every gym they belong to with its package
/// (several at once is fine: each runs to its own end), their requests to
/// join, and their visits.
class MyGymsScreen extends ConsumerWidget {
  const MyGymsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myMembershipsProvider);
    return AppPage(
      title: 'My gyms',
      maxWidth: 1100,
      body: AsyncValueView<MyMemberships>(
        value: mine,
        onRetry: () => ref.invalidate(myMembershipsProvider),
        data: (m) {
          final today = BhutanTime.today();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(myMembershipsProvider.future),
            child: ListView(
              padding: pagePadding(context),
              children: [
                SectionCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: CircleAvatar(
                      backgroundColor: context.brand.accent.withValues(alpha: 0.12),
                      child: Icon(Icons.qr_code_2_rounded, color: context.brand.accent),
                    ),
                    title: const Text('My QR code', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: const Text('Show it at the front desk of any of your gyms to check in'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go(CoreRoutes.myQr),
                  ),
                ),
                const SectionTitle('Your gyms'),
                if (m.gyms.isEmpty)
                  EmptyState(
                    icon: Icons.fitness_center_rounded,
                    title: "You're not a member of a gym yet",
                    message: 'Find a gym and ask to join, or show your QR code at its front desk.',
                    actionLabel: 'Find a gym',
                    onAction: () => context.go(GymRoutes.gyms),
                  )
                else
                  ResponsiveGrid(
                    minItemWidth: 320,
                    maxColumns: 3,
                    equalHeight: false,
                    children: [for (final g in m.gyms) _MyGymCard(gym: g, today: today)],
                  ),
                if (m.requests.isNotEmpty) ...[
                  const SectionTitle('Requests to join'),
                  SectionCard(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(children: [for (final r in m.requests) _MyRequestTile(request: r)]),
                  ),
                ],
                if (m.visits.isNotEmpty) ...[
                  const SectionTitle('Recent visits'),
                  SectionCard(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        for (final v in m.visits.take(15))
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.login_rounded, size: 20),
                            title: Text(v.gym),
                            trailing: Text('${formatDate(BhutanTime.toBhutan(v.at))} · ${formatTime(v.at)}'),
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

class _MyGymCard extends ConsumerWidget {
  final MyGym gym;
  final DateTime today;

  const _MyGymCard({required this.gym, required this.today});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final (String label, Color color) = gym.endDate == null
        ? ('No package yet', brand.muted)
        : gym.isActiveOn(today)
            ? ('Active until ${formatDate(gym.endDate!)}', brand.success)
            : gym.hasEndedBy(today)
                ? ('Ended ${formatDate(gym.endDate!)}', brand.danger)
                : ('Starts ${formatDate(gym.startDate!)}', brand.warning);
    return HoverLift(
      child: SectionCard(
        padding: const EdgeInsets.all(16),
        child: InkWell(
          onTap: () => context.go(GymRoutes.gymFor(gym.venueId)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(gym.venueName, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text(gym.place, style: TextStyle(color: brand.muted)),
              const SizedBox(height: 10),
              StatusChip(label: label, color: color),
              const SizedBox(height: 10),
              if (gym.planName != null) InfoRow(icon: Icons.sell_outlined, text: gym.planName!),
              if (gym.memberCode != null) InfoRow(icon: Icons.badge_outlined, text: 'Member code ${gym.memberCode}'),
              InfoRow(
                icon: Icons.history_rounded,
                text: gym.lastVisit == null ? 'No visits yet' : 'Last visit ${timeAgo(gym.lastVisit!)}',
              ),
              if (gym.gymMemberId != null)
                Row(
                  children: [
                    Icon(Icons.sports_outlined, size: 18, color: brand.muted),
                    const SizedBox(width: 10),
                    Expanded(child: Text(gym.trainer == null ? 'No trainer yet' : 'Trainer: ${gym.trainer!.name}')),
                    TextButton(
                      onPressed: () => context.go(GymRoutes.chooseTrainerFor(gym.venueId)),
                      child: Text(gym.trainer == null ? 'Choose' : 'Change'),
                    ),
                  ],
                ),
              if (gym.claim != null) _ClaimLine(gym: gym, claim: gym.claim!),
              if (gym.canPayOnline) ...[
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: () => context.go(GymRoutes.payFor(gym.venueId)),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: Text(gym.endDate == null ? 'Pay online' : 'Renew: pay online'),
                ),
              ] else if (gym.hasEndedBy(today) && gym.claim?.status != ClaimStatus.pending)
                Text('Renew at the front desk: pay, and they confirm it.', style: TextStyle(color: brand.muted, fontSize: 12.5)),
            ],
          ),
        ),
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

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
