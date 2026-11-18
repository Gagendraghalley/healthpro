import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/coaching.dart';
import 'package_fields.dart' show DateField;

// ─── Progress ───────────────────────────────────────────────────────────────

/// A member's body progress: weight now, the change since their first, BMI,
/// a line of their weight, and their latest measurements. [coach] (the gym's
/// staff or their trainer) records and changes any; [self] (the member)
/// records, and changes their own.
class MemberProgress extends ConsumerWidget {
  final String gymMemberId;
  final bool coach;
  final bool self;

  const MemberProgress({super.key, required this.gymMemberId, this.coach = false, this.self = false});

  Future<void> _edit(BuildContext context, WidgetRef ref, [BodyMeasurement? m]) async {
    final saved = await showAppDialog<bool>(
      context: context,
      builder: (_) => _MeasurementDialog(gymMemberId: gymMemberId, measurement: m, canDelete: m != null),
    );
    if (saved == true) ref.invalidate(memberMeasurementsProvider(gymMemberId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    // Who's signed in matters only on the member's own page.
    final me = self ? ref.watch(myProfileProvider).valueOrNull?.id : null;
    final loaded = ref.watch(memberMeasurementsProvider(gymMemberId));
    final list = loaded.valueOrNull;
    if (list == null) {
      return loaded.hasError
          ? Text('Progress couldn\'t be loaded. Pull down to try again.', style: TextStyle(color: brand.muted))
          : const LoadingSkeleton.rows();
    }
    final summary = ProgressSummary.of(list);
    final weights = [for (final m in list.reversed) if (m.weightKg != null) m.weightKg!];
    final canAdd = coach || self;
    bool canEdit(BodyMeasurement m) => coach || (self && m.recordedBy == me);

    Widget stat(String label, String value, {String? note, Color? color}) => SizedBox(
          width: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: brand.muted, fontSize: 12.5)),
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color ?? brand.ink)),
              if (note != null) Text(note, style: TextStyle(color: color ?? brand.muted, fontSize: 12.5)),
            ],
          ),
        );

    final bmi = summary.bmi;
    final bmiColor = bmi == null
        ? null
        : bmi < 18.5 || bmi >= 30
            ? brand.danger
            : bmi >= 25
                ? brand.warning
                : brand.success;
    final change = summary.change;
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (list.isEmpty)
            Text(self ? 'Log your weight now and then to see your progress here.' : 'No measurements yet.',
                style: TextStyle(color: brand.muted))
          else ...[
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                if (summary.weightNow != null) stat('Weight', kgText(summary.weightNow!)),
                if (change != null)
                  stat('Change', '${change > 0 ? '+' : change < 0 ? '−' : ''}${kgText(change.abs())}',
                      note: 'since ${formatShortDate(summary.firstOn!)}'),
                if (bmi != null) stat('BMI', bmi.toStringAsFixed(1), note: bmiBand(bmi), color: bmiColor),
              ],
            ),
            if (weights.length >= 2) ...[
              const SizedBox(height: 12),
              Semantics(
                label: 'Weight over time, from ${kgText(weights.first)} to ${kgText(weights.last)}',
                child: SizedBox(height: 56, child: CustomPaint(painter: _Sparkline(weights, brand.highlight))),
              ),
            ],
            const SizedBox(height: 8),
            for (final m in list.take(5))
              InkWell(
                onTap: canEdit(m) ? () => _edit(context, ref, m) : null,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(formatShortDate(m.measuredOn), style: TextStyle(color: brand.muted, fontSize: 13)),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [if (m.weightKg != null) kgText(m.weightKg!), if (m.others.isNotEmpty) m.others].join(' · '),
                              style: TextStyle(color: brand.ink, fontWeight: FontWeight.w600),
                            ),
                            if (m.note != null) Text(m.note!, style: TextStyle(color: brand.body, fontSize: 13)),
                            if (m.recordedByName != null)
                              Text('By ${m.recordedByName}', style: TextStyle(color: brand.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                      if (canEdit(m)) Icon(Icons.edit_outlined, size: 16, color: brand.muted),
                    ],
                  ),
                ),
              ),
            if (list.length > 5)
              Text('and ${list.length - 5} earlier', style: TextStyle(color: brand.muted, fontSize: 12.5)),
          ],
          if (canAdd) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _edit(context, ref),
                icon: const Icon(Icons.monitor_weight_outlined),
                label: Text(self && !coach ? 'Log my weight' : 'Add measurement'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A line through [values] (oldest first), scaled to their own lowest and
/// highest, the last point marked.
class _Sparkline extends CustomPainter {
  final List<double> values;
  final Color color;

  _Sparkline(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final span = high - low == 0 ? 1 : high - low;
    Offset at(int i) => Offset(
          size.width * i / (values.length - 1),
          6 + (size.height - 12) * (1 - (values[i] - low) / span),
        );
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(at(values.length - 1), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Sparkline old) => old.values != values || old.color != color;
}

class _MeasurementDialog extends ConsumerStatefulWidget {
  final String gymMemberId;
  final BodyMeasurement? measurement;
  final bool canDelete;

  const _MeasurementDialog({required this.gymMemberId, this.measurement, this.canDelete = false});

  @override
  ConsumerState<_MeasurementDialog> createState() => _MeasurementDialogState();
}

class _MeasurementDialogState extends ConsumerState<_MeasurementDialog> {
  final _form = GlobalKey<FormState>();
  late DateTime _on = widget.measurement?.measuredOn ?? BhutanTime.today();
  late final Map<String, TextEditingController> _fields = {
    for (final (key, value) in [
      ('weight', widget.measurement?.weightKg),
      ('height', widget.measurement?.heightCm),
      ('fat', widget.measurement?.bodyFatPct),
      ('chest', widget.measurement?.chestCm),
      ('waist', widget.measurement?.waistCm),
      ('hips', widget.measurement?.hipsCm),
      ('arm', widget.measurement?.armCm),
      ('thigh', widget.measurement?.thighCm),
    ])
      key: TextEditingController(text: value == null ? '' : oneDecimal(value)),
  };
  late final _note = TextEditingController(text: widget.measurement?.note ?? '');
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  double? _value(String key) => double.tryParse(_fields[key]!.text.trim());

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final m = BodyMeasurement(
      id: widget.measurement?.id ?? '',
      gymMemberId: widget.gymMemberId,
      measuredOn: _on,
      weightKg: _value('weight'),
      heightCm: _value('height'),
      bodyFatPct: _value('fat'),
      chestCm: _value('chest'),
      waistCm: _value('waist'),
      hipsCm: _value('hips'),
      armCm: _value('arm'),
      thighCm: _value('thigh'),
      note: _note.text,
      createdAt: DateTime.now(),
    );
    setState(() => _saving = true);
    final ok = await runAction(context, () async {
      await ref.read(gymCoachingRepositoryProvider).saveMeasurement(widget.gymMemberId, m, measurementId: widget.measurement?.id);
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    showFeedback(context, 'Saved');
    Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final sure = await confirmAction(context, title: 'Remove this measurement?', confirmLabel: 'Remove', destructive: true);
    if (!sure || !mounted) return;
    final ok = await runAction(context, () => ref.read(gymCoachingRepositoryProvider).deleteMeasurement(widget.measurement!.id));
    if (ok && mounted) Navigator.pop(context, true);
  }

  Widget _number(String key, String label, String unit, double min, double max) => SizedBox(
        width: 150,
        child: TextFormField(
          controller: _fields[key],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: InputDecoration(labelText: label, suffixText: unit),
          validator: (v) {
            if ((v ?? '').trim().isEmpty) return null;
            final n = double.tryParse(v!.trim());
            return n == null || n < min || n > max ? '${oneDecimal(min)} to ${oneDecimal(max)}' : null;
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final today = BhutanTime.today();
    final brand = context.brand;
    return AlertDialog(
      title: Text(widget.measurement == null ? 'New measurement' : 'Measurement'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DateField(
                  label: 'Day measured',
                  value: _on,
                  required: true,
                  firstDate: DateTime(today.year - 1, today.month, today.day),
                  lastDate: today,
                  onChanged: (d) => setState(() => _on = d ?? _on),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _number('weight', 'Weight', 'kg', 10, 400),
                    _number('height', 'Height', 'cm', 50, 260),
                    _number('fat', 'Body fat', '%', 2, 75),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: Text('Tape measurements', style: TextStyle(fontWeight: FontWeight.w600, color: brand.ink)),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _number('chest', 'Chest', 'cm', 30, 250),
                    _number('waist', 'Waist', 'cm', 30, 250),
                    _number('hips', 'Hips', 'cm', 30, 250),
                    _number('arm', 'Arm', 'cm', 10, 100),
                    _number('thigh', 'Thigh', 'cm', 20, 150),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _note,
                  maxLength: 300,
                  decoration: const InputDecoration(labelText: 'Note', hintText: 'After a week off, before breakfast...'),
                  validator: (_) => _fields.values.every((c) => c.text.trim().isEmpty) ? 'Enter at least one measurement' : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (widget.canDelete)
          TextButton(
            onPressed: _saving ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: brand.danger),
            child: const Text('Remove'),
          ),
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

// ─── Plans ──────────────────────────────────────────────────────────────────

/// A member's workout and diet plans: the ones to follow, each opening to
/// the plan itself, and the earlier ones folded away. [coach] (the gym's
/// staff or their trainer) gives, changes, puts away and removes them.
class MemberPlans extends ConsumerWidget {
  final String gymMemberId;
  final bool coach;

  const MemberPlans({super.key, required this.gymMemberId, this.coach = false});

  Future<void> _edit(BuildContext context, WidgetRef ref, [MemberPlan? plan]) async {
    final saved = await showAppDialog<bool>(context: context, builder: (_) => _PlanDialog(gymMemberId: gymMemberId, plan: plan));
    if (saved == true) ref.invalidate(memberPlansProvider(gymMemberId));
  }

  Future<void> _setActive(BuildContext context, WidgetRef ref, MemberPlan p, bool active) async {
    final ok = await runAction(
      context,
      () => ref.read(gymCoachingRepositoryProvider).savePlan(gymMemberId,
          planId: p.id, kind: p.kind, title: p.title, content: p.content, isActive: active),
    );
    if (ok) ref.invalidate(memberPlansProvider(gymMemberId));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, MemberPlan p) async {
    final sure = await confirmAction(context, title: 'Remove "${p.title}"?', confirmLabel: 'Remove', destructive: true,
        message: 'To keep it for later, put it away instead.');
    if (!sure || !context.mounted) return;
    final ok = await runAction(context, () => ref.read(gymCoachingRepositoryProvider).deletePlan(p.id));
    if (ok) ref.invalidate(memberPlansProvider(gymMemberId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final loaded = ref.watch(memberPlansProvider(gymMemberId));
    final list = loaded.valueOrNull;
    if (list == null) {
      return loaded.hasError
          ? Text('Plans couldn\'t be loaded. Pull down to try again.', style: TextStyle(color: brand.muted))
          : const LoadingSkeleton.rows();
    }
    final active = list.where((p) => p.isActive).toList();
    final earlier = list.where((p) => !p.isActive).toList();

    Widget tile(MemberPlan p) => ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Icon(p.kind == PlanKind.workout ? Icons.fitness_center_rounded : Icons.restaurant_outlined,
              color: p.isActive ? brand.highlight : brand.muted),
          title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            '${p.kind.label} plan${p.authorName == null ? '' : ' · from ${p.authorName}'} · ${formatShortDate(BhutanTime.toBhutan(p.updatedAt))}',
            style: TextStyle(color: brand.muted, fontSize: 12.5),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(p.content, style: TextStyle(color: brand.body, height: 1.5)),
            if (coach)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                        onPressed: () => _edit(context, ref, p), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Change')),
                    TextButton(
                      onPressed: () => _setActive(context, ref, p, !p.isActive),
                      child: Text(p.isActive ? 'Put away' : 'Use again'),
                    ),
                    TextButton(
                      onPressed: () => _delete(context, ref, p),
                      style: TextButton.styleFrom(foregroundColor: brand.danger),
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              ),
          ],
        );

    return SectionCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (active.isEmpty)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                coach ? 'No plan yet. Give them a workout or diet plan to follow.' : 'No plan yet. Your trainer can give you one.',
                style: TextStyle(color: brand.muted),
              ),
            ),
          for (final p in active) tile(p),
          if (earlier.isNotEmpty)
            ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text('Earlier plans (${earlier.length})', style: TextStyle(color: brand.muted, fontSize: 14)),
              children: [for (final p in earlier) tile(p)],
            ),
          if (coach)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _edit(context, ref),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Give a plan'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanDialog extends ConsumerStatefulWidget {
  final String gymMemberId;
  final MemberPlan? plan;

  const _PlanDialog({required this.gymMemberId, this.plan});

  @override
  ConsumerState<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends ConsumerState<_PlanDialog> {
  final _form = GlobalKey<FormState>();
  late PlanKind _kind = widget.plan?.kind ?? PlanKind.workout;
  late final _title = TextEditingController(text: widget.plan?.title ?? '');
  late final _content = TextEditingController(text: widget.plan?.content ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final ok = await runAction(context, () async {
      await ref.read(gymCoachingRepositoryProvider).savePlan(widget.gymMemberId,
          planId: widget.plan?.id, kind: _kind, title: _title.text, content: _content.text, isActive: widget.plan?.isActive ?? true);
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    showFeedback(context, widget.plan == null ? 'Plan given' : 'Saved');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final workout = _kind == PlanKind.workout;
    return AlertDialog(
      title: Text(widget.plan == null ? 'New plan' : 'Change the plan'),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<PlanKind>(
                  segments: const [
                    ButtonSegment(value: PlanKind.workout, icon: Icon(Icons.fitness_center_rounded), label: Text('Workout')),
                    ButtonSegment(value: PlanKind.diet, icon: Icon(Icons.restaurant_outlined), label: Text('Diet')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (v) => setState(() => _kind = v.first),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _title,
                  maxLength: 100,
                  decoration: InputDecoration(
                    labelText: 'Title *',
                    hintText: workout ? 'Strength, 3 days a week' : 'Less sugar, more protein',
                  ),
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Give the plan a title' : null,
                ),
                TextFormField(
                  controller: _content,
                  maxLength: 8000,
                  minLines: 8,
                  maxLines: 16,
                  decoration: InputDecoration(
                    labelText: 'The plan *',
                    alignLabelWithHint: true,
                    hintText: workout
                        ? 'Day 1, legs: squats 4 x 8, lunges 3 x 12...\nDay 2, rest\nDay 3, chest and back: ...'
                        : 'Breakfast: 2 eggs, oats\nLunch: red rice, dal, vegetables\nDinner: ...\nDrink 2 litres of water a day',
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Write the plan' : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(widget.plan == null ? 'Give the plan' : 'Save')),
      ],
    );
  }
}
