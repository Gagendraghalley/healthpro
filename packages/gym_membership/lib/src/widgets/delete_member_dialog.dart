import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/gym_repository.dart';
import '../data/registered_member.dart';

/// Asks before deleting [member] from [gymName]'s register; true once they're
/// deleted. [activeUntil]: the last day a package of theirs covers (running,
/// paused or to come), when there is one. Then it warns first, and Delete
/// waits for the desk to tick that the paid membership ends now.
Future<bool?> showDeleteMemberDialog(BuildContext context,
        {required GymMember member, required String gymName, DateTime? activeUntil}) =>
    showAppDialog<bool>(
      context: context,
      builder: (_) => DeleteMemberDialog(member: member, gymName: gymName, activeUntil: activeUntil),
    );

class DeleteMemberDialog extends ConsumerStatefulWidget {
  final GymMember member;
  final String gymName;
  final DateTime? activeUntil;

  const DeleteMemberDialog({super.key, required this.member, required this.gymName, this.activeUntil});

  @override
  ConsumerState<DeleteMemberDialog> createState() => _DeleteMemberDialogState();
}

class _DeleteMemberDialogState extends ConsumerState<DeleteMemberDialog> {
  bool _understood = false;
  bool _saving = false;

  bool get _active => widget.activeUntil != null;

  Future<void> _delete() async {
    setState(() => _saving = true);
    var told = false;
    final ok = await runAction(context, () async {
      told = await ref.read(gymRepositoryProvider).deleteMember(widget.member.id, evenIfActive: _active);
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    final name = widget.member.fullName;
    showFeedback(context, told ? 'Deleted $name. They were told in Health Pro.' : 'Deleted $name.');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final m = widget.member;
    final until = widget.activeUntil;
    final daysLeft = until == null ? 0 : BhutanTime.daysBetween(BhutanTime.today(), until) + 1;
    return AlertDialog(
      icon: Icon(Icons.person_remove_outlined, color: brand.danger),
      title: Text('Delete ${m.fullName}?'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (until != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: brand.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: brand.danger.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: brand.danger),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Their membership is still active until ${formatDate(until)} '
                          '(${daysLeft == 1 ? '1 day' : '$daysLeft days'} left). Deleting them ends it today, '
                          'and the days they paid for are not used.',
                          style: TextStyle(color: brand.danger, fontWeight: FontWeight.w600, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                CheckboxListTile(
                  value: _understood,
                  onChanged: _saving ? null : (v) => setState(() => _understood = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('I understand their paid membership ends now'),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                'They lose access to ${widget.gymName}: no check-in, and their packages, visits, progress and plans '
                'here are deleted. Their Health Pro account stays, so they can still sign in and join a gym again. '
                'If they have an account, they\'re told.',
                style: TextStyle(color: brand.muted, height: 1.4),
              ),
              const SizedBox(height: 10),
              const InfoRow(icon: Icons.receipt_long_outlined, text: 'Payments they made stay in your income.'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: brand.danger),
          onPressed: _saving || (_active && !_understood) ? null : _delete,
          icon: const Icon(Icons.delete_outline_rounded),
          label: Text(_active ? 'Delete anyway' : 'Delete member'),
        ),
      ],
    );
  }
}
