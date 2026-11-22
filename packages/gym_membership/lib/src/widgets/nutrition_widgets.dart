import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/coaching.dart';
import '../data/nutrition.dart';
import 'package_fields.dart' show DateField;
import 'plan_text.dart';

// ─── Goal ───────────────────────────────────────────────────────────────────

/// Sets [gymMemberId]'s goal (a new one when [goal] is null).
Future<void> editGoal(BuildContext context, WidgetRef ref, String gymMemberId, MemberGoal? goal) async {
  final saved = await showAppDialog<bool>(context: context, builder: (_) => _GoalDialog(gymMemberId: gymMemberId, goal: goal));
  if (saved == true) ref.invalidate(memberGoalProvider(gymMemberId));
}

/// The daily calories and protein a member's goal and latest measurements
/// work out to, or why they can't yet.
({DailyTargets? targets, String? missing}) targetsFor(
    {required List<BodyMeasurement> newestFirst, required int? age, required MemberGoal? goal}) {
  final s = ProgressSummary.of(newestFirst);
  final targets = dailyTargets(
      weightKg: s.weightNow, heightCm: s.heightCm, age: age, sex: goal?.sex, activity: goal?.activity ?? Activity.moderate, goal: goal?.goal);
  if (targets != null) return (targets: targets, missing: null);
  if (age != null && age < 18) return (targets: null, missing: 'Daily calories are worked out for adults (18 and over).');
  final missing = missingForTargets(weightKg: s.weightNow, heightCm: s.heightCm, age: age, sex: goal?.sex);
  final list = missing.length == 1 ? missing.first : '${missing.take(missing.length - 1).join(', ')} and ${missing.last}';
  return (targets: null, missing: 'Add ${missing.contains('date of birth') ? 'the ' : ''}$list to work out daily calories.');
}

/// A member's goal at the top of their progress: what and by when, how far
/// they are, the pace still needed, and their daily calories and protein.
class MemberGoalSection extends ConsumerWidget {
  final String gymMemberId;
  final MemberGoal goal;

  /// Newest first.
  final List<BodyMeasurement> measurements;
  final bool canEdit;

  const MemberGoalSection({super.key, required this.gymMemberId, required this.goal, required this.measurements, this.canEdit = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final age = ref.watch(memberAgeProvider(gymMemberId)).valueOrNull;
    final today = BhutanTime.today();
    final target = goal.targetWeightKg, by = goal.targetDate;
    final progress = goalProgress(goal, measurements);
    final daily = targetsFor(newestFirst: measurements, age: age, goal: goal);

    final title = [
      goal.goal?.label ?? 'Goal',
      if (target != null) '${kgText(target)}${by == null ? '' : ' by ${formatShortDate(by)}'}' else if (by != null) 'by ${formatShortDate(by)}',
    ].join(' · ');

    Widget line(String text, {Color? color, double size = 13.5}) =>
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(text, style: TextStyle(color: color ?? brand.body, fontSize: size)));

    final notes = <Widget>[];
    if (progress != null) {
      final moved = progress.now - progress.start;
      if (progress.reached) {
        notes.add(line('Target reached.', color: brand.success));
      } else {
        notes.add(line([
          if (moved.abs() >= 0.05) '${kgText(moved.abs())} ${moved < 0 ? 'lost' : 'gained'}',
          '${kgText(progress.toGo.abs())} to go',
        ].join(' · ')));
        final perWeek = by == null ? null : progress.perWeekBy(by, today);
        if (by != null && !by.isAfter(today)) {
          notes.add(line('The target day has passed. Set a new one.', color: brand.warning));
        } else if (perWeek != null) {
          final tooFast = perWeek < -1 || perWeek > 0.5;
          notes.add(line(
            'Needs ${kgText(perWeek.abs())} a week to make it by ${formatShortDate(by!)}'
            '${tooFast ? ': faster than is healthy, so a later day is safer.' : '.'}',
            color: tooFast ? brand.warning : null,
          ));
        }
      }
    }

    final targets = daily.targets;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: brand.highlight.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.flag_outlined, size: 20, color: brand.highlight),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink))),
              if (canEdit)
                IconButton(
                  tooltip: 'Change the goal',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => editGoal(context, ref, gymMemberId, goal),
                  icon: Icon(Icons.edit_outlined, size: 18, color: brand.muted),
                ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            Semantics(
              label: '${(progress.done * 100).round()}% of the way to ${kgText(progress.target)}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.done,
                  minHeight: 8,
                  color: progress.reached ? brand.success : brand.highlight,
                  backgroundColor: brand.highlight.withValues(alpha: 0.15),
                ),
              ),
            ),
          ],
          ...notes,
          if (targets != null) ...[
            line('Daily aim: ${kcalAndProtein(targets.kcal, targets.proteinG)}', color: brand.ink),
            line('${thousands(targets.maintenanceKcal)} kcal a day keeps the weight · ${goal.activity.label} activity',
                color: brand.muted, size: 12.5),
          ] else if (daily.missing != null)
            line(daily.missing!, color: brand.muted, size: 12.5),
        ],
      ),
    );
  }
}

class _GoalDialog extends ConsumerStatefulWidget {
  final String gymMemberId;
  final MemberGoal? goal;

  const _GoalDialog({required this.gymMemberId, this.goal});

  @override
  ConsumerState<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends ConsumerState<_GoalDialog> {
  final _form = GlobalKey<FormState>();
  late GoalKind? _goal = widget.goal?.goal;
  late final _target = TextEditingController(text: widget.goal?.targetWeightKg == null ? '' : oneDecimal(widget.goal!.targetWeightKg!));
  late DateTime? _by = widget.goal?.targetDate;
  late Sex? _sex = widget.goal?.sex;
  late Activity _activity = widget.goal?.activity ?? Activity.moderate;
  bool _saving = false;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  MemberGoal get _draft => MemberGoal(
        gymMemberId: widget.gymMemberId,
        goal: _goal,
        targetWeightKg: double.tryParse(_target.text.trim()),
        targetDate: _by,
        sex: _sex,
        activity: _activity,
      );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final ok = await runAction(context, () => ref.read(gymNutritionRepositoryProvider).saveGoal(_draft));
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    showFeedback(context, 'Goal saved');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final today = BhutanTime.today();
    final measurements = ref.watch(memberMeasurementsProvider(widget.gymMemberId)).valueOrNull ?? const <BodyMeasurement>[];
    final age = ref.watch(memberAgeProvider(widget.gymMemberId)).valueOrNull;
    final daily = targetsFor(newestFirst: measurements, age: age, goal: _draft);
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: brand.ink)),
        );

    return AlertDialog(
      title: Text(widget.goal == null ? 'Set a goal' : 'Goal'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in GoalKind.values)
                      ChoiceChip(label: Text(g.label), selected: _goal == g, onSelected: (on) => setState(() => _goal = on ? g : null)),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    SizedBox(
                      width: 170,
                      child: TextFormField(
                        controller: _target,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                        decoration: const InputDecoration(labelText: 'Target weight', suffixText: 'kg'),
                        validator: (v) {
                          if ((v ?? '').trim().isEmpty) return null;
                          final n = double.tryParse(v!.trim());
                          return n == null || n < 20 || n > 300 ? '20 to 300' : null;
                        },
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: DateField(
                        label: 'By',
                        value: _by,
                        clearable: true,
                        firstDate: today.add(const Duration(days: 1)),
                        lastDate: today.add(const Duration(days: 730)),
                        onChanged: (d) => setState(() => _by = d),
                      ),
                    ),
                  ],
                ),
                label('For daily calories'),
                SegmentedButton<Sex>(
                  segments: [for (final s in Sex.values) ButtonSegment(value: s, label: Text(s.label))],
                  selected: {if (_sex != null) _sex!},
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => _sex = v.firstOrNull),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<Activity>(
                  initialValue: _activity,
                  decoration: InputDecoration(labelText: 'How active', helperText: _activity.hint),
                  items: [for (final a in Activity.values) DropdownMenuItem(value: a, child: Text(a.label))],
                  onChanged: (a) => setState(() => _activity = a ?? _activity),
                ),
                const SizedBox(height: 14),
                Text(
                  daily.targets == null ? daily.missing ?? '' : 'Daily aim: ${kcalAndProtein(daily.targets!.kcal, daily.targets!.proteinG)}',
                  style: TextStyle(color: daily.targets == null ? brand.muted : brand.ink, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

// ─── Diet plans in meals ────────────────────────────────────────────────────

/// A diet plan's meals to read: the day against its aim (calories and
/// protein, a bar each), then each meal as a card with its foods, their
/// amounts, calories and protein.
class DietMealsView extends StatelessWidget {
  final List<DietMeal> meals;
  final int? kcalTarget;
  final int? proteinTargetG;

  const DietMealsView({super.key, required this.meals, this.kcalTarget, this.proteinTargetG});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final totals = mealTotals(meals);
    const figures = [FontFeature.tabularFigures()];

    /// Calories or protein for the day: how much, against the aim. Calories
    /// within 10% of it are on target; protein from 90% of it.
    Widget meter(String label, double value, int? aim, String unit, {required bool atLeast}) {
      final share = aim == null || aim == 0 ? null : value / aim;
      final onTarget = share == null || (atLeast ? share >= 0.9 : (share - 1).abs() <= 0.1);
      final color = onTarget ? brand.success : brand.warning;
      final shown = unit == 'kcal' ? thousands(value) : oneDecimal(value);
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: brand.muted, fontSize: 12.5)),
            const SizedBox(height: 2),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: shown, style: TextStyle(color: brand.ink, fontSize: 18, fontWeight: FontWeight.w800, fontFeatures: figures)),
                TextSpan(
                  text: aim == null ? ' $unit' : ' of ${unit == 'kcal' ? thousands(aim) : aim} $unit',
                  style: TextStyle(color: brand.muted, fontSize: 13, fontFeatures: figures),
                ),
              ]),
            ),
            if (share != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    value: share.clamp(0, 1).toDouble(), minHeight: 6, color: color, backgroundColor: color.withValues(alpha: 0.15)),
              ),
            ],
          ],
        ),
      );
    }

    String amounts(double? kcal, double? protein) =>
        [if (kcal != null) '${thousands(kcal)} kcal', if (protein != null) '${oneDecimal(protein)} g'].join(' · ');
    final hasNumbers = totals.kcal > 0 || totals.proteinG > 0;

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasNumbers || kcalTarget != null || proteinTargetG != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: brand.highlight.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  meter('Calories', totals.kcal, kcalTarget, 'kcal', atLeast: false),
                  const SizedBox(width: 16),
                  meter('Protein', totals.proteinG, proteinTargetG, 'g', atLeast: true),
                ],
              ),
            ),
          for (final m in meals)
            PlanCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      PlanBadge(m.name),
                      const Spacer(),
                      if (m.kcal > 0 || m.proteinG > 0)
                        Text(amounts(m.kcal > 0 ? m.kcal : null, m.proteinG > 0 ? m.proteinG : null),
                            style: TextStyle(color: brand.muted, fontSize: 12.5, fontWeight: FontWeight.w600, fontFeatures: figures)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (var i = 0; i < m.items.length; i++)
                    PlanRow(
                      divided: i > 0,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.items[i].food,
                                    style: TextStyle(color: brand.ink, fontSize: 14.5, height: 1.35, fontWeight: FontWeight.w500)),
                                if (m.items[i].amount != null)
                                  Text(m.items[i].amount!, style: TextStyle(color: brand.muted, fontSize: 12.5)),
                              ],
                            ),
                          ),
                          if (m.items[i].kcal != null || m.items[i].proteinG != null) ...[
                            const SizedBox(width: 12),
                            PlanPill(amounts(m.items[i].kcal, m.items[i].proteinG)),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One food being written: what, how much, calories and protein.
class ItemDraft {
  final food = TextEditingController();
  final amount = TextEditingController();
  final kcal = TextEditingController();
  final protein = TextEditingController();
  final focus = FocusNode();

  ItemDraft([DietItem? from]) {
    if (from == null) return;
    food.text = from.food;
    amount.text = from.amount ?? '';
    kcal.text = from.kcal == null ? '' : oneDecimal(from.kcal!);
    protein.text = from.proteinG == null ? '' : oneDecimal(from.proteinG!);
  }

  List<TextEditingController> get _fields => [food, amount, kcal, protein];
  bool get isEmpty => _fields.every((c) => c.text.trim().isEmpty);

  DietItem get value => DietItem(
      food: food.text.trim(), amount: amount.text, kcal: double.tryParse(kcal.text.trim()), proteinG: double.tryParse(protein.text.trim()));

  void dispose() {
    for (final c in _fields) {
      c.dispose();
    }
    focus.dispose();
  }
}

/// One meal being written: its name and foods.
class MealDraft {
  final TextEditingController name;
  final List<ItemDraft> items;

  MealDraft(String name, [List<DietItem> from = const []])
      : name = TextEditingController(text: name),
        items = from.isEmpty ? [ItemDraft()] : [for (final i in from) ItemDraft(i)];

  void dispose() {
    name.dispose();
    for (final i in items) {
      i.dispose();
    }
  }
}

/// A diet plan's meals while they're written. Tells its listeners of any
/// change, so totals stay current.
class MealsDraft extends ChangeNotifier {
  final List<MealDraft> meals = [];

  void _watch(MealDraft m) {
    m.name.addListener(notifyListeners);
    for (final i in m.items) {
      _watchItem(i);
    }
  }

  void _watchItem(ItemDraft i) {
    for (final c in i._fields) {
      c.addListener(notifyListeners);
    }
  }

  /// Starts again from [from].
  void load(List<DietMeal> from) {
    for (final m in meals) {
      m.dispose();
    }
    meals
      ..clear()
      ..addAll([for (final m in from) MealDraft(m.name, m.items)]);
    meals.forEach(_watch);
    notifyListeners();
  }

  void addMeal() {
    final used = {for (final m in meals) m.name.text.trim().toLowerCase()};
    final m = MealDraft(mealNames.where((n) => !used.contains(n.toLowerCase())).firstOrNull ?? 'Meal ${meals.length + 1}');
    meals.add(m);
    _watch(m);
    notifyListeners();
  }

  void removeMeal(MealDraft m) {
    meals.remove(m);
    m.dispose();
    notifyListeners();
  }

  void addItem(MealDraft m) {
    final i = ItemDraft();
    m.items.add(i);
    _watchItem(i);
    notifyListeners();
  }

  void removeItem(MealDraft m, ItemDraft i) {
    m.items.remove(i);
    i.dispose();
    notifyListeners();
  }

  /// The meals as they'd be kept: foods left blank are left out.
  List<DietMeal> get value => [
        for (final m in meals)
          DietMeal(name: m.name.text.trim(), items: [for (final i in m.items) if (!i.isEmpty) i.value]),
      ];

  @override
  void dispose() {
    for (final m in meals) {
      m.dispose();
    }
    super.dispose();
  }
}

/// Writes a diet plan's meals: each a name and foods, a food picked from the
/// shared list fills in its serving, calories and protein.
class MealsEditor extends ConsumerWidget {
  final MealsDraft draft;

  const MealsEditor({super.key, required this.draft});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final foods = ref.watch(dietFoodsProvider).valueOrNull ?? const <DietFood>[];
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        final totals = mealTotals(draft.value);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final m in draft.meals)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
                decoration: BoxDecoration(border: Border.all(color: brand.muted.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: m.name,
                            maxLength: 40,
                            decoration: const InputDecoration(labelText: 'Meal', counterText: ''),
                            validator: (v) => (v ?? '').trim().isEmpty
                                ? 'Name the meal'
                                : m.items.every((i) => i.isEmpty)
                                    ? 'Add a food, or take the meal out'
                                    : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${thousands(DietMeal(name: '', items: [for (final i in m.items) i.value]).kcal)} kcal',
                            style: TextStyle(color: brand.muted, fontSize: 12.5)),
                        IconButton(
                          tooltip: 'Take the meal out',
                          onPressed: () => draft.removeMeal(m),
                          icon: Icon(Icons.close_rounded, size: 18, color: brand.muted),
                        ),
                      ],
                    ),
                    for (final i in m.items)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(width: 210, child: _FoodField(item: i, foods: foods)),
                            SizedBox(
                              width: 110,
                              child: TextFormField(
                                controller: i.amount,
                                maxLength: 40,
                                decoration: const InputDecoration(labelText: 'Amount', counterText: ''),
                              ),
                            ),
                            SizedBox(width: 80, child: _numberField(i.kcal, 'kcal', 3000)),
                            SizedBox(width: 80, child: _numberField(i.protein, 'Protein g', 300)),
                            IconButton(
                              tooltip: 'Take the food out',
                              onPressed: () => draft.removeItem(m, i),
                              icon: Icon(Icons.remove_circle_outline_rounded, size: 18, color: brand.muted),
                            ),
                          ],
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () => draft.addItem(m),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add a food'),
                    ),
                  ],
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(onPressed: draft.addMeal, icon: const Icon(Icons.add_rounded), label: const Text('Add a meal')),
                if (totals.kcal > 0 || totals.proteinG > 0)
                  Text('In all: ${kcalAndProtein(totals.kcal, totals.proteinG)}',
                      style: TextStyle(color: brand.ink, fontWeight: FontWeight.w600)),
              ],
            ),
            if (draft.meals.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Foods from the list fill in an approximate serving. Change the numbers for other amounts.',
                    style: TextStyle(color: brand.muted, fontSize: 12.5)),
              ),
          ],
        );
      },
    );
  }

  static Widget _numberField(TextEditingController c, String label, double max) => TextFormField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: InputDecoration(labelText: label),
        validator: (v) {
          if ((v ?? '').trim().isEmpty) return null;
          final n = double.tryParse(v!.trim());
          return n == null || n > max ? 'Up to ${max.round()}' : null;
        },
      );
}

/// A food's name, suggesting foods from the shared list as it's typed.
class _FoodField extends StatelessWidget {
  final ItemDraft item;
  final List<DietFood> foods;

  const _FoodField({required this.item, required this.foods});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return RawAutocomplete<DietFood>(
      textEditingController: item.food,
      focusNode: item.focus,
      displayStringForOption: (f) => f.name,
      optionsBuilder: (typed) {
        final q = typed.text.trim().toLowerCase();
        if (q.isEmpty) return const [];
        return foods.where((f) => f.name.toLowerCase().contains(q)).take(8);
      },
      onSelected: (f) {
        item.amount.text = f.serving;
        item.kcal.text = '${f.kcal}';
        item.protein.text = oneDecimal(f.proteinG);
      },
      fieldViewBuilder: (context, controller, focus, onSubmitted) => TextFormField(
        controller: controller,
        focusNode: focus,
        maxLength: 80,
        decoration: const InputDecoration(labelText: 'Food', counterText: ''),
        onFieldSubmitted: (_) => onSubmitted(),
        validator: (v) => (v ?? '').trim().isEmpty && !item.isEmpty ? 'Name the food' : null,
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280, maxWidth: 340),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              children: [
                for (final f in options)
                  ListTile(
                    dense: true,
                    title: Text(f.name),
                    subtitle: Text('${f.serving} · ${f.kcal} kcal · ${oneDecimal(f.proteinG)} g protein',
                        style: TextStyle(color: brand.muted)),
                    onTap: () => onSelected(f),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
