import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/follow_ups.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import '../widgets/gym_widgets.dart';

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// 'Today', 'Yesterday', 'Monday, 16 Nov 2026'.
String _dayLabel(DateTime day, DateTime today) {
  final ago = BhutanTime.daysBetween(day, today);
  if (ago == 0) return 'Today';
  if (ago == 1) return 'Yesterday';
  return '${_weekdays[day.weekday - 1]}, ${formatDate(day)}';
}

DateTime _dayOf(AuditEntry e) => BhutanTime.dateOnly(BhutanTime.toBhutan(e.createdAt));

/// The gym's activity log, for its owner and managers: who registered, sold,
/// took payments, confirmed, paused or cancelled what, newest first, a day
/// at a time. Narrowed by kind, by who did it, or by a name; an entry about
/// a member opens them. Nobody can change it.
class ActivityLogScreen extends ConsumerStatefulWidget {
  final String venueId;

  const ActivityLogScreen({super.key, required this.venueId});

  @override
  ConsumerState<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends ConsumerState<ActivityLogScreen> {
  AuditArea? _area;
  String? _by;
  String _search = '';
  int _limit = 100;

  bool _passes(AuditEntry e) {
    if (_area != null && e.area != _area) return false;
    if (_by != null && e.by != _by) return false;
    if (_search.isEmpty) return true;
    return '${e.summary} ${e.details} ${e.memberName ?? ''}'.toLowerCase().contains(_search);
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.venueId;
    return GymStaffPage(
      venueId: id,
      title: 'Activity log',
      permission: GymPermission.activity,
      builder: (context, access) {
        final query = (venueId: id, gymMemberId: null, limit: _limit);
        return AppPage(
          title: 'Activity log',
          body: AsyncValueView<List<AuditEntry>>(
            value: ref.watch(gymAuditLogProvider(query)),
            onRetry: () => ref.invalidate(gymAuditLogProvider(query)),
            data: (all) {
              final today = BhutanTime.today();
              final people = {for (final e in all) e.by}.toList()..sort();
              final shown = all.where(_passes).toList();
              final days = <DateTime, List<AuditEntry>>{};
              for (final e in shown) {
                days.putIfAbsent(_dayOf(e), () => []).add(e);
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(gymAuditLogProvider(query)),
                child: ListView(
                  padding: pagePadding(context, bottom: 40),
                  children: [
                    FadeSlideIn(
                      child: WelcomeBand(
                        eyebrow: access.venue.name,
                        title: 'Activity log',
                        subtitle: 'Who did what at the gym, newest first. Nobody can change or delete it, the owner included.',
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search_rounded),
                              hintText: 'Search by member, package or journal number',
                            ),
                            onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _peoplePicker(context, people),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final area in <AuditArea?>[null, ...AuditArea.values])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(area?.label ?? 'Everything'),
                                selected: _area == area,
                                onSelected: (_) => setState(() => _area = area),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (all.isEmpty)
                      const EmptyState(
                        icon: Icons.manage_history_rounded,
                        title: 'Nothing yet',
                        message: 'Registrations, sales, payments, pauses and changes to packages or staff show here as they happen.',
                      )
                    else if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(child: Text('Nothing matches.', style: TextStyle(color: context.brand.muted))),
                      )
                    else
                      for (final day in days.entries) ...[
                        SectionTitle(_dayLabel(day.key, today),
                            trailing: Text('${day.value.length}', style: TextStyle(color: context.brand.muted))),
                        SectionCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (var i = 0; i < day.value.length; i++) ...[
                                if (i > 0) const Divider(height: 1),
                                AuditEntryTile(
                                  entry: day.value[i],
                                  onTap: day.value[i].gymMemberId == null
                                      ? null
                                      : () => context.push(GymRoutes.memberFor(id, day.value[i].gymMemberId!)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    if (all.length >= _limit)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Center(
                          child: OutlinedButton.icon(
                            onPressed: () => setState(() => _limit += 100),
                            icon: const Icon(Icons.history_rounded),
                            label: const Text('Show older'),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// Who did it: everyone, or one of the people in the log.
  Widget _peoplePicker(BuildContext context, List<String> people) {
    return PopupMenuButton<String>(
      tooltip: 'Who did it',
      onSelected: (v) => setState(() => _by = v.isEmpty ? null : v),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(value: '', checked: _by == null, child: const Text('Everyone')),
        for (final p in people) CheckedPopupMenuItem(value: p, checked: _by == p, child: Text(p)),
      ],
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: context.brand.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.brand.fieldBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_search_outlined, size: 20),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(_by ?? 'Everyone', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

/// On a member's page, for those who see the log: what was done for them,
/// newest first.
class MemberActivity extends ConsumerWidget {
  final String venueId;
  final String gymMemberId;

  const MemberActivity({super.key, required this.venueId, required this.gymMemberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries =
        ref.watch(gymAuditLogProvider((venueId: venueId, gymMemberId: gymMemberId, limit: 20))).valueOrNull ?? const <AuditEntry>[];
    if (entries.isEmpty) return const FormHint('Nothing recorded yet.');
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            AuditEntryTile(entry: entries[i], withDate: true),
          ],
        ],
      ),
    );
  }
}

/// One entry: what (with its details), who and when.
class AuditEntryTile extends StatelessWidget {
  final AuditEntry entry;
  final VoidCallback? onTap;

  /// The date as well as the time (where entries aren't under their day).
  final bool withDate;

  const AuditEntryTile({super.key, required this.entry, this.onTap, this.withDate = false});

  (IconData, Color) _look(BuildContext context) {
    final brand = context.brand;
    final blue = themeTone(context, BrandColors.blue);
    final a = entry.action;
    return switch (a) {
      'member.registered' => (Icons.person_add_alt_1_rounded, blue),
      'member.edited' => (Icons.edit_outlined, blue),
      'member.card_reissued' => (Icons.qr_code_2_rounded, blue),
      'member.removed' => (Icons.person_remove_outlined, brand.danger),
      'member.reminded' => (Icons.chat_outlined, brand.success),
      'member.wished' => (Icons.cake_outlined, brand.highlight),
      'membership.cancelled' => (Icons.cancel_outlined, brand.danger),
      'membership.requested' => (Icons.hourglass_top_rounded, brand.warning),
      'payment.received' => (Icons.payments_outlined, brand.success),
      'payment.refunded' => (Icons.undo_rounded, brand.danger),
      'claim.sent' => (Icons.phone_iphone_rounded, brand.warning),
      'claim.confirmed' => (Icons.fact_check_outlined, brand.success),
      'claim.rejected' || 'claim.cancelled' => (Icons.block_rounded, brand.danger),
      _ when a.startsWith('membership.pause') || a == 'membership.resumed' => (Icons.pause_circle_outline_rounded, brand.warning),
      _ when a.startsWith('membership.') => (Icons.autorenew_rounded, brand.success),
      _ when a.startsWith('expense.') => (Icons.receipt_long_outlined, brand.danger),
      _ when a.startsWith('offer.') => (Icons.local_offer_outlined, blue),
      _ when a.startsWith('plan.') => (Icons.sell_outlined, blue),
      _ when a.startsWith('staff.') => (Icons.badge_outlined, blue),
      _ => (Icons.history_rounded, brand.muted),
    };
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final (icon, color) = _look(context);
    final when = withDate
        ? '${formatShortDate(BhutanTime.toBhutan(entry.createdAt))}, ${formatTime(entry.createdAt)}'
        : formatTime(entry.createdAt);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(icon, size: 18, color: brand.readable(color)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.summary, style: TextStyle(fontWeight: FontWeight.w600, color: brand.ink)),
                  if (entry.details.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(entry.details, style: TextStyle(color: brand.body, fontSize: 13)),
                    ),
                  const SizedBox(height: 3),
                  Text('${entry.by} · $when', style: TextStyle(color: brand.muted, fontSize: 12)),
                ],
              ),
            ),
            if (onTap != null) Icon(Icons.chevron_right_rounded, color: brand.muted),
          ],
        ),
      ),
    );
  }
}
