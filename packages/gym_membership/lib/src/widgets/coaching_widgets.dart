import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/coaching.dart';
import '../data/nutrition.dart';
import '../data/recommendations.dart';
import 'nutrition_widgets.dart';
import 'plan_text.dart';
import 'package_fields.dart' show DateField;

// ─── Progress ───────────────────────────────────────────────────────────────

/// The colour a reading is told in.
Color toneColor(Brand brand, ReadingTone tone) => switch (tone) {
      ReadingTone.good => brand.success,
      ReadingTone.watch => brand.warning,
      ReadingTone.alert => brand.danger,
      ReadingTone.neutral => brand.muted,
    };

/// A member's body progress: weight now, the change since their first, BMI,
/// body fat as fat and lean mass, waist to height, a line of any measure over
/// time, what it all says, and their latest measurements. [coach] (the gym's
/// staff or their trainer) records and changes any; [self] (the member)
/// records, and changes their own.
class MemberProgress extends ConsumerStatefulWidget {
  final String gymMemberId;
  final bool coach;
  final bool self;

  const MemberProgress({super.key, required this.gymMemberId, this.coach = false, this.self = false});

  @override
  ConsumerState<MemberProgress> createState() => _MemberProgressState();
}

class _MemberProgressState extends ConsumerState<MemberProgress> {
  /// The measure the line shows.
  BodyMeasure _trend = BodyMeasure.weight;

  Future<void> _edit([BodyMeasurement? m]) async {
    final saved = await showAppDialog<bool>(
      context: context,
      builder: (_) => _MeasurementDialog(gymMemberId: widget.gymMemberId, measurement: m, canDelete: m != null),
    );
    if (saved == true) ref.invalidate(memberMeasurementsProvider(widget.gymMemberId));
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final coach = widget.coach, self = widget.self;
    // Who's signed in matters only on the member's own page.
    final me = self ? ref.watch(myProfileProvider).valueOrNull?.id : null;
    final loaded = ref.watch(memberMeasurementsProvider(widget.gymMemberId));
    final list = loaded.valueOrNull;
    if (list == null) {
      return loaded.hasError
          ? Text('Progress couldn\'t be loaded. Pull down to try again.', style: TextStyle(color: brand.muted))
          : const LoadingSkeleton.rows();
    }
    final goalLoaded = ref.watch(memberGoalProvider(widget.gymMemberId));
    final goal = goalLoaded.valueOrNull;
    final summary = ProgressSummary.of(list);
    final readings = progressReadings(summary, today: BhutanTime.today(), self: self && !coach);
    final suggestions = coachingSuggestions(
      measurements: list,
      goal: goal,
      age: ref.watch(memberAgeProvider(widget.gymMemberId)).valueOrNull,
      plans: ref.watch(memberPlansProvider(widget.gymMemberId)).valueOrNull,
      today: BhutanTime.today(),
      self: self && !coach,
    );
    final trends = summary.trends;
    final trend = trends.containsKey(_trend) ? _trend : trends.keys.firstOrNull;
    final points = trend == null ? null : trends[trend]!;
    final canAdd = coach || self;
    bool canEdit(BodyMeasurement m) => coach || (self && m.recordedBy == me);

    Widget stat(String label, String value, {String? note, Color? color, String? tip}) {
      final shown = ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 150),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: brand.muted, fontSize: 12.5)),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color ?? brand.ink)),
            if (note != null) Text(note, style: TextStyle(color: color ?? brand.muted, fontSize: 12.5)),
          ],
        ),
      );
      return tip == null ? shown : Tooltip(message: tip, child: shown);
    }

    IconData icon(ProgressReading r) => switch (r.kind) {
          ReadingKind.check => Icons.error_outline_rounded,
          ReadingKind.pace => summary.pacePerWeek! <= -0.1
              ? Icons.trending_down_rounded
              : summary.pacePerWeek! >= 0.1
                  ? Icons.trending_up_rounded
                  : Icons.trending_flat_rounded,
          ReadingKind.composition => Icons.donut_small_outlined,
          ReadingKind.due => Icons.event_outlined,
        };

    final bmi = summary.bmi, bmiBand = summary.bmiBand;
    final waist = summary.waistToHeight, waistBand = summary.waistBand;
    final change = summary.change;
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (goal != null) ...[
            MemberGoalSection(gymMemberId: widget.gymMemberId, goal: goal, measurements: list, canEdit: canAdd),
            const SizedBox(height: 14),
          ],
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
                if (bmi != null)
                  stat('BMI', bmi.toStringAsFixed(1), note: bmiBand!.label, color: toneColor(brand, bmiBand.tone),
                      tip: 'Asian bands (WHO): healthy 18.5 to 22.9, overweight from 23, obese from 27.5'),
                if (summary.fatKg != null)
                  stat('Body fat', '${oneDecimal(summary.bodyFatPct!)}%',
                      note: '${kgText(summary.fatKg!)} fat · ${kgText(summary.leanKg!)} lean'),
                if (waist != null)
                  stat('Waist to height', waist.toStringAsFixed(2), note: waistBand!.label, color: toneColor(brand, waistBand.tone),
                      tip: 'Waist over height. Under 0.5 is healthy for men and women.'),
              ],
            ),
            if (trend != null && points != null) ...[
              const SizedBox(height: 14),
              if (trends.length > 1)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final m in trends.keys)
                      ChoiceChip(label: Text(m.label), selected: m == trend, onSelected: (_) => setState(() => _trend = m)),
                  ],
                ),
              const SizedBox(height: 8),
              Semantics(
                label: '${trend.label} over time, from ${trend.show(points.first.value)} to ${trend.show(points.last.value)}',
                child: SizedBox(
                    height: 56, child: CustomPaint(painter: _Sparkline([for (final p in points) p.value], brand.highlight))),
              ),
              const SizedBox(height: 4),
              ExcludeSemantics(
                child: Text(
                  '${trend.label} since ${formatShortDate(points.first.on)}: '
                  '${trend.show(points.first.value)} → ${trend.show(points.last.value)}',
                  style: TextStyle(color: brand.muted, fontSize: 12.5),
                ),
              ),
            ],
            if (readings.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final r in readings)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon(r), size: 18, color: toneColor(brand, r.tone)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r.text, style: TextStyle(color: brand.body, fontSize: 13.5))),
                    ],
                  ),
                ),
            ],
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: brand.highlight.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline_rounded, size: 18, color: brand.highlight),
                        const SizedBox(width: 8),
                        Text('Suggestions', style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
                      ],
                    ),
                    for (final s in suggestions)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 6, left: 4, right: 10),
                              child: Icon(Icons.circle, size: 7, color: toneColor(brand, s.tone == ReadingTone.neutral ? ReadingTone.good : s.tone)),
                            ),
                            Expanded(child: Text(s.text, style: TextStyle(color: brand.body, fontSize: 13.5))),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            for (final m in list.take(5))
              InkWell(
                onTap: canEdit(m) ? () => _edit(m) : null,
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _edit(),
                  icon: const Icon(Icons.monitor_weight_outlined),
                  label: Text(self && !coach ? 'Log my weight' : 'Add measurement'),
                ),
                if (goal == null && goalLoaded.hasValue)
                  OutlinedButton.icon(
                    onPressed: () => editGoal(context, ref, widget.gymMemberId, null),
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Set a goal'),
                  ),
              ],
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

  /// What looked wrong at the last Save; the next Save saves anyway, unless a
  /// number changes first.
  List<String> _warnings = const [];
  final _warningsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    for (final c in _fields.values) {
      c.addListener(_changed);
    }
  }

  void _changed() {
    if (_warnings.isNotEmpty) setState(() => _warnings = const []);
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  double? _value(String key) => double.tryParse(_fields[key]!.text.trim());

  /// The member's other measurements, newest first.
  List<BodyMeasurement> get _others => ref.read(memberMeasurementsProvider(widget.gymMemberId)).valueOrNull ?? const [];

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
    if (_warnings.isEmpty) {
      final warnings = measurementWarnings(m, _others);
      if (warnings.isNotEmpty) {
        setState(() => _warnings = warnings);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final shown = _warningsKey.currentContext;
          if (shown != null && shown.mounted) Scrollable.ensureVisible(shown);
        });
        return;
      }
    }
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

  Widget _number(String key, String label, String unit, double min, double max, {String? helper}) => SizedBox(
        width: 150,
        child: TextFormField(
          controller: _fields[key],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: InputDecoration(labelText: label, suffixText: unit, helperText: helper, helperMaxLines: 2),
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
    // A new measurement keeps the last height for BMI when it's left blank.
    final others = ref.watch(memberMeasurementsProvider(widget.gymMemberId)).valueOrNull ?? const <BodyMeasurement>[];
    final lastHeight = widget.measurement == null ? others.where((o) => o.heightCm != null).firstOrNull?.heightCm : null;
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
                  onChanged: (d) => setState(() {
                    _on = d ?? _on;
                    _warnings = const [];
                  }),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _number('weight', 'Weight', 'kg', 10, 400),
                    _number('height', 'Height', 'cm', 50, 260,
                        helper: lastHeight == null ? null : 'Blank keeps ${oneDecimal(lastHeight)} cm'),
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
                if (_warnings.isNotEmpty)
                  Container(
                    key: _warningsKey,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: brand.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: brand.warning.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 20, color: brand.warning),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Check these before saving',
                                  style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
                            ),
                          ],
                        ),
                        for (final w in _warnings)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(w, style: TextStyle(color: brand.body, fontSize: 13.5)),
                          ),
                      ],
                    ),
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
        FilledButton(onPressed: _saving ? null : _save, child: Text(_warnings.isEmpty ? 'Save' : 'Save anyway')),
      ],
    );
  }
}

// ─── Plans ──────────────────────────────────────────────────────────────────

/// A member's workout and diet plans: the ones to follow, each opening to
/// the plan itself, and the earlier ones folded away. [coach] (the gym's
/// staff or their trainer) gives, changes, puts away and removes them, and
/// with the gym's [venueId] starts from and keeps its templates.
class MemberPlans extends ConsumerWidget {
  final String gymMemberId;
  final String? venueId;
  final bool coach;

  const MemberPlans({super.key, required this.gymMemberId, this.venueId, this.coach = false});

  Future<void> _edit(BuildContext context, WidgetRef ref, [MemberPlan? plan]) async {
    final saved = await showAppDialog<bool>(
        context: context, builder: (_) => _PlanDialog(gymMemberId: gymMemberId, venueId: venueId, plan: plan));
    if (saved == true) ref.invalidate(memberPlansProvider(gymMemberId));
  }

  Future<void> _setActive(BuildContext context, WidgetRef ref, MemberPlan p, bool active) async {
    final ok = await runAction(
      context,
      () => ref.read(gymCoachingRepositoryProvider).savePlan(gymMemberId,
          planId: p.id,
          kind: p.kind,
          title: p.title,
          content: p.content,
          meals: p.meals,
          kcalTarget: p.kcalTarget,
          proteinTargetG: p.proteinTargetG,
          isActive: active),
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
            if (p.meals.isNotEmpty || p.kcalTarget != null || p.proteinTargetG != null)
              DietMealsView(meals: p.meals, kcalTarget: p.kcalTarget, proteinTargetG: p.proteinTargetG),
            if (p.content.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: p.meals.isEmpty ? 0 : 12),
                child: PlanTextView(content: p.content),
              ),
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
  final String? venueId;
  final MemberPlan? plan;

  const _PlanDialog({required this.gymMemberId, this.venueId, this.plan});

  @override
  ConsumerState<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends ConsumerState<_PlanDialog> {
  final _form = GlobalKey<FormState>();
  late PlanKind _kind = widget.plan?.kind ?? PlanKind.workout;
  late final _title = TextEditingController(text: widget.plan?.title ?? '');
  late final _content = TextEditingController(text: widget.plan?.content ?? '');
  late final _kcal = TextEditingController(text: widget.plan?.kcalTarget?.toString() ?? '');
  late final _protein = TextEditingController(text: widget.plan?.proteinTargetG?.toString() ?? '');
  final _meals = MealsDraft();
  PlanTemplate? _template;
  bool _keepTemplate = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _meals.load(widget.plan?.meals ?? const []);
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _kcal.dispose();
    _protein.dispose();
    _meals.dispose();
    super.dispose();
  }

  /// A new diet plan's aim was filled in from the member's goal.
  bool _aimFilled = false;

  /// Asking the AI for a draft; it filled the form ([_left] drafts left today).
  bool _drafting = false;
  bool _drafted = false;

  /// The plan's words shown laid out, as the member will read them.
  bool _preview = false;
  int? _left;

  bool get _blank => _content.text.trim().isEmpty && _meals.value.every((m) => m.items.isEmpty);

  /// Why the last draft couldn't be made, shown under the Draft button: a
  /// message at the foot of the page would be behind this form.
  String? _draftProblem;
  final _kcalKey = GlobalKey<FormFieldState<String>>();
  final _proteinKey = GlobalKey<FormFieldState<String>>();

  Future<void> _draft() async {
    final kind = _kind;
    final diet = kind == PlanKind.diet;
    setState(() => _draftProblem = null);
    final kcal = int.tryParse(_kcal.text.trim());
    if (diet) {
      // The daily aim, checked here (and marked on its fields): the draft is planned around it.
      final kcalOk = _kcalKey.currentState?.validate() ?? true;
      final proteinOk = _proteinKey.currentState?.validate() ?? true;
      final problem = kcal == null
          ? 'Set the daily calories first: the draft is planned around them.'
          : !kcalOk
              ? 'Daily calories are 800 to 6,000 kcal. Change them first: the draft is planned around them.'
              : !proteinOk
                  ? 'Daily protein is 20 to 400 g. Change it, or leave it empty.'
                  : null;
      if (problem != null) {
        setState(() => _draftProblem = problem);
        return;
      }
    }
    final note = await showAppDialog<String>(context: context, builder: (_) => _DraftNoteDialog(replaces: !_blank));
    if (note == null || !mounted) return;
    final id = widget.gymMemberId;
    final facts = draftFacts(
      measurements: ref.read(memberMeasurementsProvider(id)).valueOrNull ?? const [],
      goal: ref.read(memberGoalProvider(id)).valueOrNull,
      age: ref.read(memberAgeProvider(id)).valueOrNull,
      kcalTarget: diet ? kcal : null,
      proteinTargetG: diet ? int.tryParse(_protein.text.trim()) : null,
    );
    setState(() => _drafting = true);
    final PlanDraft d;
    try {
      d = await ref.read(gymNutritionRepositoryProvider).draftPlan(id, kind, facts, note: note);
    } catch (e) {
      if (mounted) {
        setState(() {
          _drafting = false;
          _draftProblem = friendlyError(e);
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _drafting = false);
    if (_kind != kind) return;
    _title.text = d.title;
    _content.text = d.content;
    if (diet) _meals.load(d.meals);
    setState(() {
      _drafted = true;
      _preview = d.content.trim().isNotEmpty || d.meals.isNotEmpty;
      _left = d.left;
    });
  }

  void _useTargets(DailyTargets t) {
    _kcal.text = '${t.kcal}';
    _protein.text = '${t.proteinG}';
    // Clears a mark left on the fields, and a problem about them.
    _kcalKey.currentState?.validate();
    _proteinKey.currentState?.validate();
    if (_draftProblem != null) setState(() => _draftProblem = null);
  }

  void _useTemplate(PlanTemplate? t) {
    setState(() => _template = t);
    if (t == null) return;
    _title.text = t.title;
    _content.text = t.content;
    _meals.load(t.meals);
  }

  Future<void> _removeTemplate(PlanTemplate t) async {
    final sure = await confirmAction(context, title: 'Remove the template "${t.title}"?', confirmLabel: 'Remove', destructive: true,
        message: 'Plans already given from it stay as they are.');
    if (!sure || !mounted) return;
    final ok = await runAction(context, () => ref.read(gymNutritionRepositoryProvider).deleteTemplate(t.id));
    if (!ok || !mounted) return;
    ref.invalidate(planTemplatesProvider(widget.venueId!));
    setState(() => _template = null);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      // The words' error shows only while writing.
      if (_preview) setState(() => _preview = false);
      return;
    }
    final diet = _kind == PlanKind.diet;
    final meals = diet ? _meals.value : const <DietMeal>[];
    final keep = _keepTemplate && widget.venueId != null;
    setState(() => _saving = true);
    final ok = await runAction(context, () async {
      await ref.read(gymCoachingRepositoryProvider).savePlan(widget.gymMemberId,
          planId: widget.plan?.id,
          kind: _kind,
          title: _title.text,
          content: _content.text,
          meals: meals,
          kcalTarget: diet ? int.tryParse(_kcal.text.trim()) : null,
          proteinTargetG: diet ? int.tryParse(_protein.text.trim()) : null,
          isActive: widget.plan?.isActive ?? true);
      if (keep) {
        await ref
            .read(gymNutritionRepositoryProvider)
            .saveTemplate(widget.venueId!, kind: _kind, title: _title.text, content: _content.text, meals: meals);
      }
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    if (keep) ref.invalidate(planTemplatesProvider(widget.venueId!));
    showFeedback(context, widget.plan == null ? 'Plan given' : 'Saved');
    Navigator.pop(context, true);
  }

  Widget _whole(TextEditingController c, String label, String unit, int min, int max, {Key? key}) => SizedBox(
        width: 150,
        child: TextFormField(
          key: key,
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, suffixText: unit),
          validator: (v) {
            if ((v ?? '').trim().isEmpty) return null;
            final n = int.tryParse(v!.trim());
            return n == null || n < min || n > max ? '${thousands(min)} to ${thousands(max)}' : null;
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final workout = _kind == PlanKind.workout;
    final diet = !workout;
    // What the member's goal and measurements work out to, or why they can't.
    final id = widget.gymMemberId;
    final worked = targetsFor(
      newestFirst: ref.watch(memberMeasurementsProvider(id)).valueOrNull ?? const [],
      age: ref.watch(memberAgeProvider(id)).valueOrNull,
      goal: ref.watch(memberGoalProvider(id)).valueOrNull,
    );
    final aim = worked.targets;
    if (diet && widget.plan == null && !_aimFilled && aim != null && _kcal.text.isEmpty && _protein.text.isEmpty) {
      _aimFilled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _useTargets(aim);
      });
    }
    final templates = widget.venueId == null || widget.plan != null
        ? const <PlanTemplate>[]
        : [...?ref.watch(planTemplatesProvider(widget.venueId!)).valueOrNull?.where((t) => t.kind == _kind)];
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: brand.ink)),
        );
    // A heading, with the Write / Preview switch beside it when [toggle]
    // (by the meals for a diet, by the plan's words for a workout).
    Widget heading(String text, {bool toggle = false}) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 10),
          child: Row(
            children: [
              Expanded(child: Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: brand.ink))),
              if (toggle)
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, icon: Icon(Icons.edit_outlined, size: 18), label: Text('Write')),
                    ButtonSegment(value: true, icon: Icon(Icons.visibility_outlined, size: 18), label: Text('Preview')),
                  ],
                  selected: {_preview},
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  onSelectionChanged: (v) => setState(() => _preview = v.first),
                ),
            ],
          ),
        );

    return AlertDialog(
      title: Text(widget.plan == null ? 'New plan' : 'Change the plan'),
      content: SizedBox(
        width: diet ? 700 : 600,
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
                  onSelectionChanged: (v) => setState(() {
                    _template = null;
                    _kind = v.first;
                  }),
                ),
                if (templates.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<PlanTemplate>(
                          key: ValueKey(_kind),
                          initialValue: _template,
                          decoration: const InputDecoration(labelText: 'Start from a template'),
                          items: [for (final t in templates) DropdownMenuItem(value: t, child: Text(t.title))],
                          onChanged: _useTemplate,
                        ),
                      ),
                      if (_template != null)
                        IconButton(
                          tooltip: 'Remove this template',
                          onPressed: () => _removeTemplate(_template!),
                          icon: Icon(Icons.delete_outline_rounded, color: brand.muted),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _drafting || _saving ? null : _draft,
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: Text(_drafting ? 'Drafting...' : 'Draft with AI'),
                    ),
                    if (_drafting) ...[
                      const SizedBox(width: 12),
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Expanded(child: Text('This can take half a minute.', style: TextStyle(color: brand.muted, fontSize: 12.5))),
                    ],
                  ],
                ),
                if (_draftProblem != null)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: brand.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 18, color: brand.danger),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_draftProblem!, style: TextStyle(color: brand.ink, fontSize: 13))),
                      ],
                    ),
                  ),
                if (_drafted)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: brand.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.auto_awesome_outlined, size: 18, color: brand.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Drafted by AI from their numbers and goal. Check every line before giving it.'
                            '${_left == null ? '' : ' $_left AI drafts left today.'}',
                            style: TextStyle(color: brand.body, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
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
                if (diet) ...[
                  label('Daily aim'),
                  ListenableBuilder(
                    listenable: Listenable.merge([_kcal, _protein]),
                    builder: (context, _) {
                      final t = aim;
                      final same = t != null && _kcal.text == '${t.kcal}' && _protein.text == '${t.proteinG}';
                      return Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _whole(_kcal, 'Calories', 'kcal', 800, 6000, key: _kcalKey),
                          _whole(_protein, 'Protein', 'g', 20, 400, key: _proteinKey),
                          if (t != null && !same)
                            TextButton(onPressed: () => _useTargets(t), child: Text('Use their goal: ${kcalAndProtein(t.kcal, t.proteinG)}')),
                          if (t == null && worked.missing != null)
                            Text(worked.missing!, style: TextStyle(color: brand.muted, fontSize: 12.5)),
                        ],
                      );
                    },
                  ),
                  heading('Meals', toggle: true),
                  Offstage(offstage: _preview, child: MealsEditor(draft: _meals)),
                  if (_preview)
                    _meals.value.every((m) => m.items.isEmpty)
                        ? Text('No meals yet.', style: TextStyle(color: brand.muted))
                        : DietMealsView(
                            meals: [for (final m in _meals.value) if (m.items.isNotEmpty) m],
                            kcalTarget: int.tryParse(_kcal.text.trim()),
                            proteinTargetG: int.tryParse(_protein.text.trim()),
                          ),
                  const SizedBox(height: 8),
                ],
                heading(diet ? 'Notes' : 'The plan *', toggle: workout),
                Offstage(
                  offstage: _preview,
                  child: TextFormField(
                    controller: _content,
                    maxLength: 8000,
                    minLines: diet ? 3 : 8,
                    maxLines: 16,
                    style: const TextStyle(fontSize: 14.5, height: 1.5),
                    decoration: InputDecoration(
                      hintText: workout
                          ? 'Day 1: Legs\n- Squats: 4 x 8\n- Lunges: 3 x 12\n\nDay 2: Chest and back\n- Bench press: 4 x 8'
                          : 'Drink 2 litres of water a day. Less sugar in tea.\nOr write the whole plan here instead of meals.',
                    ),
                    validator: (v) => (v ?? '').trim().isNotEmpty || (diet && _meals.value.any((m) => m.items.isNotEmpty))
                        ? null
                        : diet
                            ? 'Add a meal, or write the plan'
                            : 'Write the plan',
                  ),
                ),
                if (_preview && diet)
                  _content.text.trim().isEmpty
                      ? Text('No notes.', style: TextStyle(color: brand.muted))
                      : PlanTextView(content: _content.text)
                else if (_preview)
                  Container(
                    constraints: const BoxConstraints(minHeight: 120),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: brand.muted.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _content.text.trim().isEmpty
                        ? Text('Nothing written yet.', style: TextStyle(color: brand.muted))
                        : PlanTextView(content: _content.text),
                  ),
                if (widget.venueId != null)
                  CheckboxListTile(
                    value: _keepTemplate,
                    onChanged: (v) => setState(() => _keepTemplate = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Keep as a template for the gym'),
                    subtitle: const Text('Without the daily aim, which is worked out for each member'),
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

/// What the coach wants the AI to keep in mind for a draft (may be blank);
/// null when they think better of it. [replaces]: the form already has a plan.
class _DraftNoteDialog extends StatefulWidget {
  final bool replaces;

  const _DraftNoteDialog({this.replaces = false});

  @override
  State<_DraftNoteDialog> createState() => _DraftNoteDialogState();
}

class _DraftNoteDialogState extends State<_DraftNoteDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return AlertDialog(
      title: const Text('Draft with AI'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _note,
              maxLength: 200,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Anything to keep in mind?', hintText: 'Vegetarian, no pork, 3 days a week...'),
            ),
            Text(
              'The AI sees their numbers and goal, not their name or medical notes. Leave out names here too.'
              '${widget.replaces ? ' The draft replaces what\'s written.' : ''}',
              style: TextStyle(color: brand.muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _note.text), child: const Text('Draft')),
      ],
    );
  }
}
