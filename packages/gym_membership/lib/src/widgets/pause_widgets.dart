import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../data/registered_member.dart';

/// '20 Nov to 3 Dec 2026 (14 days)'.
String pauseSpan(GymPause p) => '${formatDate(p.startDate)} to ${formatDate(p.endDate)} (${_days(p.days)})';

String _days(int n) => n == 1 ? '1 day' : '$n days';

/// On a member's page: their pause running or planned, with Resume (or Take
/// back, before it begins) for staff who take payments; and the pauses
/// before it, in a line each.
class MemberPauses extends ConsumerWidget {
  final String venueId;
  final String gymMemberId;
  final String memberName;
  final bool canChange;

  const MemberPauses({
    super.key,
    required this.venueId,
    required this.gymMemberId,
    required this.memberName,
    required this.canChange,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pauses = ref.watch(gymMemberPausesProvider(gymMemberId)).valueOrNull ?? const <GymPause>[];
    if (pauses.isEmpty) return const SizedBox.shrink();
    final today = BhutanTime.today();
    final open = openPauseOf(pauses, gymMemberId, today);
    final past = pauses.where((p) => p != open).take(3).toList();
    final brand = context.brand;

    Future<void> resume(GymPause p) async {
      final before = p.isUpcomingOn(today);
      final sure = await confirmAction(
        context,
        title: before ? 'Take back this pause?' : 'Resume $memberName\'s membership today?',
        message: before
            ? 'Their package keeps its dates, as if it was never paused.'
            : 'They can check in again from today. The ${_days(BhutanTime.daysBetween(today, p.endDate) + 1)} '
                'not used come off their package.',
        confirmLabel: before ? 'Take back' : 'Resume',
      );
      if (!sure || !context.mounted) return;
      DateTime? until;
      final ok = await runAction(context, () async {
        until = await ref.read(gymRepositoryProvider).resumeMember(p.id);
      });
      if (!ok) return;
      refreshGym(ref, venueId);
      if (context.mounted && until != null) showFeedback(context, 'Their package runs until ${formatDate(until!)}');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (open != null)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              color: brand.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: brand.warning.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(Icons.pause_circle_outline_rounded, color: brand.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(open.isUpcomingOn(today) ? 'Pause planned' : 'Paused: no check-in until it ends',
                          style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
                      Text(pauseSpan(open) + (open.reason == null ? '' : ' · ${open.reason}'),
                          style: TextStyle(color: brand.muted)),
                    ],
                  ),
                ),
                if (canChange)
                  TextButton(
                    onPressed: () => resume(open),
                    child: Text(open.isUpcomingOn(today) ? 'Take back' : 'Resume'),
                  ),
              ],
            ),
          ),
        for (final p in past)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Paused ${pauseSpan(p)}${p.endedAt == null ? '' : ', resumed early'}',
              style: TextStyle(color: brand.muted, fontSize: 13),
            ),
          ),
      ],
    );
  }
}

/// Pauses [member]'s membership: from when, for how many days, and why;
/// what it does to their dates shows as they choose. True once paused.
Future<bool?> showPauseDialog(BuildContext context,
        {required GymMember member, required List<GymSubscription> subscriptions}) =>
    showAppDialog<bool>(
      context: context,
      builder: (_) => _PauseDialog(member: member, subscriptions: subscriptions),
    );

class _PauseDialog extends ConsumerStatefulWidget {
  final GymMember member;
  final List<GymSubscription> subscriptions;

  const _PauseDialog({required this.member, required this.subscriptions});

  @override
  ConsumerState<_PauseDialog> createState() => _PauseDialogState();
}

class _PauseDialogState extends ConsumerState<_PauseDialog> {
  final _form = GlobalKey<FormState>();
  final _dayField = TextEditingController(text: '14');
  final _reason = TextEditingController();
  late DateTime _start = BhutanTime.today();
  bool _saving = false;

  static const _quick = [7, 14, 30, 60];

  @override
  void dispose() {
    _dayField.dispose();
    _reason.dispose();
    super.dispose();
  }

  int? get _dayCount {
    final n = int.tryParse(_dayField.text.trim());
    return n == null || n < 1 || n > maxPauseDays ? null : n;
  }

  /// The last day a package of theirs covers: a pause can start up to then.
  DateTime get _lastCovered {
    var last = BhutanTime.today();
    for (final s in widget.subscriptions) {
      if (s.status == SubscriptionStatus.active && s.endDate != null && s.endDate!.isAfter(last)) last = s.endDate!;
    }
    return last;
  }

  Future<void> _pickStart() async {
    final today = BhutanTime.today();
    final picked = await showDatePicker(context: context, initialDate: _start, firstDate: today, lastDate: _lastCovered);
    if (picked != null && mounted) setState(() => _start = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _dayCount == null) return;
    setState(() => _saving = true);
    DateTime? until;
    final ok = await runAction(context, () async {
      until = await ref
          .read(gymRepositoryProvider)
          .pauseMember(widget.member.id, start: _start, days: _dayCount!, reason: _reason.text);
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    showFeedback(context, 'Paused. Their package now runs until ${formatDate(until!)}');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final today = BhutanTime.today();
    final days = _dayCount;
    final running = runningOn(widget.subscriptions, _start);
    final until = days == null ? null : runsUntilAfterPause(widget.subscriptions, _start, days);
    final lastPaused = days == null ? null : DateTime(_start.year, _start.month, _start.day + days - 1);
    final brand = context.brand;
    return AlertDialog(
      title: Text('Pause ${widget.member.fullName}\'s membership'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'For travel, illness or an injury: they can\'t check in while it\'s paused, and their package '
                  '(and any renewal after it) moves later by the same days, so nothing they paid for is lost.',
                  style: TextStyle(color: brand.muted, height: 1.4),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _pickStart,
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(_start == today ? 'From today' : 'From ${formatDate(_start)}'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _dayField,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                  decoration: const InputDecoration(labelText: 'Days *', prefixIcon: Icon(Icons.pause_circle_outline_rounded)),
                  validator: (v) => _dayCount == null ? 'From 1 to $maxPauseDays days' : null,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final n in _quick)
                      ChoiceChip(
                        label: Text(_days(n)),
                        selected: days == n,
                        onSelected: (_) => setState(() => _dayField.text = '$n'),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _reason,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Reason', hintText: 'Travelling, injured...'),
                ),
                const SizedBox(height: 4),
                if (running == null)
                  InfoRow(icon: Icons.info_outline_rounded, text: 'No package of theirs runs on ${formatDate(_start)}.')
                else if (until != null && lastPaused != null)
                  InfoRow(
                    icon: Icons.event_available_rounded,
                    text: 'Paused ${formatDate(_start)} to ${formatDate(lastPaused)}. '
                        'Their package then runs until ${formatDate(until)}.',
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving || running == null ? null : _save,
          child: const Text('Pause'),
        ),
      ],
    );
  }
}
