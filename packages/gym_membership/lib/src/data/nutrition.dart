import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'coaching.dart';

// Goals, daily calories and protein, diet plans in meals, foods and plan
// templates (20261122000003_gym_goals_and_diet.sql).

double? _num(Object? v) => v == null ? null : (v as num).toDouble();

/// 2100 as '2,100'.
String thousands(num v) {
  final s = v.round().abs().toString();
  final out = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// '2,100 kcal · 120 g protein'.
String kcalAndProtein(num kcal, num proteinG) => '${thousands(kcal)} kcal · ${oneDecimal(proteinG.toDouble())} g protein';

enum GoalKind {
  loseFat('lose_fat', 'Lose fat'),
  buildMuscle('build_muscle', 'Build muscle'),
  gainWeight('gain_weight', 'Gain weight'),
  keepFit('keep_fit', 'Keep fit');

  const GoalKind(this.value, this.label);
  final String value;
  final String label;

  static GoalKind? from(String? v) => values.where((g) => g.value == v).firstOrNull;
}

enum Sex {
  female('female', 'Female'),
  male('male', 'Male');

  const Sex(this.value, this.label);
  final String value;
  final String label;

  static Sex? from(String? v) => values.where((s) => s.value == v).firstOrNull;
}

/// How active a member is, and what it multiplies their resting calories by.
enum Activity {
  light('light', 'Light', 'Training 1 to 2 days a week', 1.375),
  moderate('moderate', 'Moderate', 'Training 3 to 4 days a week', 1.55),
  active('active', 'Active', 'Training 5 to 6 days a week', 1.725),
  veryActive('very_active', 'Very active', 'Hard training every day, or heavy work', 1.9);

  const Activity(this.value, this.label, this.hint, this.factor);
  final String value;
  final String label;
  final String hint;
  final double factor;

  static Activity from(String? v) => values.where((a) => a.value == v).firstOrNull ?? moderate;
}

/// What a member is after: a goal, a target weight and day, and their sex
/// and how active they are (for their daily calories).
class MemberGoal {
  final String gymMemberId;
  final GoalKind? goal;
  final double? targetWeightKg;
  final DateTime? targetDate;
  final Sex? sex;
  final Activity activity;

  /// When the goal or target weight was last set: progress counts from here.
  final DateTime? startedOn;
  final String? setByName;

  const MemberGoal({
    required this.gymMemberId,
    this.goal,
    this.targetWeightKg,
    this.targetDate,
    this.sex,
    this.activity = Activity.moderate,
    this.startedOn,
    this.setByName,
  });

  Map<String, dynamic> toJson() => {
        'goal': goal?.value,
        'target_weight_kg': targetWeightKg,
        'target_date': targetDate == null ? null : isoDay(targetDate!),
        'sex': sex?.value,
        'activity': activity.value,
      };

  factory MemberGoal.fromJson(Map<String, dynamic> json) => MemberGoal(
        gymMemberId: json['gym_member_id'] as String,
        goal: GoalKind.from(json['goal'] as String?),
        targetWeightKg: _num(json['target_weight_kg']),
        targetDate: json['target_date'] == null ? null : BhutanTime.parseDate(json['target_date'] as String),
        sex: Sex.from(json['sex'] as String?),
        activity: Activity.from(json['activity'] as String?),
        startedOn: json['started_on'] == null ? null : BhutanTime.parseDate(json['started_on'] as String),
        setByName: json['set_by_name'] as String?,
      );
}

/// A day's calories and protein, and the calories that keep the weight.
class DailyTargets {
  final int kcal;
  final int proteinG;
  final int maintenanceKcal;

  const DailyTargets({required this.kcal, required this.proteinG, required this.maintenanceKcal});
}

/// What's still needed to work out daily calories: 'weight', 'height',
/// 'date of birth', 'sex'. Empty when nothing is.
List<String> missingForTargets({double? weightKg, double? heightCm, int? age, Sex? sex}) => [
      if (weightKg == null) 'weight',
      if (heightCm == null) 'height',
      if (age == null) 'date of birth',
      if (sex == null) 'sex',
    ];

/// Daily calories and protein for an adult (18 or over): resting calories
/// by the Mifflin-St Jeor equation, times how active they are, then 20% less
/// to lose fat (never under resting, nor 1,200 for women and 1,500 for men),
/// 10% more to build muscle, 15% more to gain weight. Protein: 2 g a kilo to
/// lose fat, 1.8 to build muscle, 1.6 to gain weight, 1.4 to keep fit, for
/// their weight up to a BMI of 25. Calories to the nearest 50, protein to 5.
DailyTargets? dailyTargets(
    {double? weightKg, double? heightCm, int? age, Sex? sex, Activity activity = Activity.moderate, GoalKind? goal}) {
  if (weightKg == null || heightCm == null || age == null || sex == null || age < 18) return null;
  final resting = 10 * weightKg + 6.25 * heightCm - 5 * age + (sex == Sex.male ? 5 : -161);
  final keep = resting * activity.factor;
  final kcal = switch (goal) {
    GoalKind.loseFat => math.max(keep * 0.8, math.max(resting, sex == Sex.male ? 1500.0 : 1200.0)),
    GoalKind.buildMuscle => keep * 1.1,
    GoalKind.gainWeight => keep * 1.15,
    GoalKind.keepFit || null => keep,
  };
  final perKg = switch (goal) {
    GoalKind.loseFat => 2.0,
    GoalKind.buildMuscle => 1.8,
    GoalKind.gainWeight => 1.6,
    GoalKind.keepFit || null => 1.4,
  };
  final forProtein = math.min(weightKg, 25 * (heightCm / 100) * (heightCm / 100));
  return DailyTargets(
    kcal: (kcal / 50).round() * 50,
    proteinG: (forProtein * perKg / 5).round() * 5,
    maintenanceKcal: (keep / 50).round() * 50,
  );
}

/// How far a member is toward their target weight: their weight when it was
/// set, now, and the target.
class GoalProgress {
  final double start;
  final double now;
  final double target;

  /// Going down to the target (else up).
  final bool losing;

  const GoalProgress({required this.start, required this.now, required this.target, required this.losing});

  bool get reached => losing ? now <= target : now >= target;

  /// 0 to 1.
  double get done {
    if (reached) return 1;
    final span = (start - target).abs();
    return span < 0.05 ? 0 : ((losing ? start - now : now - start) / span).clamp(0, 1);
  }

  double get toGo => target - now;

  /// Kilograms a week still needed to reach the target by [by].
  double? perWeekBy(DateTime by, DateTime today) {
    final days = by.difference(today).inDays;
    return days <= 0 || reached ? null : toGo / (days / 7);
  }
}

/// From a member's measurements (newest first): their weight on the day
/// their goal was set (or the first after), and now.
GoalProgress? goalProgress(MemberGoal goal, List<BodyMeasurement> newestFirst) {
  final target = goal.targetWeightKg;
  final weighed = newestFirst.where((m) => m.weightKg != null).toList();
  if (target == null || weighed.isEmpty) return null;
  final from = goal.startedOn;
  final start = (from == null ? null : weighed.where((m) => !m.measuredOn.isAfter(from)).firstOrNull) ?? weighed.last;
  final losing = switch (goal.goal) {
    GoalKind.loseFat => true,
    GoalKind.buildMuscle || GoalKind.gainWeight => false,
    GoalKind.keepFit || null => target < start.weightKg!,
  };
  return GoalProgress(start: start.weightKg!, now: weighed.first.weightKg!, target: target, losing: losing);
}

// ─── Diet plans in meals ────────────────────────────────────────────────────

/// One food in a meal: what, how much, and its calories and protein.
class DietItem {
  final String food;
  final String? amount;
  final double? kcal;
  final double? proteinG;

  const DietItem({required this.food, this.amount, this.kcal, this.proteinG});

  Map<String, dynamic> toJson() => {
        'food': food.trim(),
        if (amount != null && amount!.trim().isNotEmpty) 'amount': amount!.trim(),
        if (kcal != null) 'kcal': kcal,
        if (proteinG != null) 'protein_g': proteinG,
      };

  factory DietItem.fromJson(Map<String, dynamic> json) => DietItem(
        food: json['food'] as String? ?? '',
        amount: json['amount'] as String?,
        kcal: _num(json['kcal']),
        proteinG: _num(json['protein_g']),
      );
}

/// A meal of a diet plan: Breakfast, and its foods.
class DietMeal {
  final String name;
  final List<DietItem> items;

  const DietMeal({required this.name, this.items = const []});

  double get kcal => items.fold(0, (sum, i) => sum + (i.kcal ?? 0));
  double get proteinG => items.fold(0, (sum, i) => sum + (i.proteinG ?? 0));

  Map<String, dynamic> toJson() => {'name': name.trim(), 'items': [for (final i in items) i.toJson()]};

  factory DietMeal.fromJson(Map<String, dynamic> json) => DietMeal(
        name: json['name'] as String? ?? '',
        items: [for (final i in json['items'] as List? ?? const []) DietItem.fromJson(Map<String, dynamic>.from(i as Map))],
      );

  static List<DietMeal> listFrom(Object? json) =>
      [for (final m in json as List? ?? const []) DietMeal.fromJson(Map<String, dynamic>.from(m as Map))];
}

/// The meals' calories and protein together.
({double kcal, double proteinG}) mealTotals(List<DietMeal> meals) =>
    (kcal: meals.fold(0, (s, m) => s + m.kcal), proteinG: meals.fold(0, (s, m) => s + m.proteinG));

/// The usual meals of a day, to name the next one.
const mealNames = ['Breakfast', 'Lunch', 'Snack', 'Dinner'];

/// A food from the shared list, with approximate calories and protein for a
/// serving.
class DietFood {
  final String name;
  final String serving;
  final int kcal;
  final double proteinG;

  const DietFood({required this.name, required this.serving, required this.kcal, required this.proteinG});

  factory DietFood.fromJson(Map<String, dynamic> json) => DietFood(
        name: json['name'] as String,
        serving: json['serving'] as String,
        kcal: (json['kcal'] as num).toInt(),
        proteinG: (json['protein_g'] as num).toDouble(),
      );
}

/// One of a gym's plans to start a member's plan from.
class PlanTemplate {
  final String id;
  final PlanKind kind;
  final String title;
  final String content;
  final List<DietMeal> meals;
  final String? authorName;

  const PlanTemplate(
      {required this.id, required this.kind, required this.title, this.content = '', this.meals = const [], this.authorName});

  factory PlanTemplate.fromJson(Map<String, dynamic> json) => PlanTemplate(
        id: json['id'] as String,
        kind: PlanKind.from(json['kind'] as String?),
        title: json['title'] as String,
        content: json['content'] as String? ?? '',
        meals: DietMeal.listFrom(json['meals']),
        authorName: json['author_name'] as String?,
      );
}

/// A plan the AI drafted (draft-plan), to fill the plan form with: the coach
/// checks it before giving it. A diet's notes become the plan's words.
class PlanDraft {
  final PlanKind kind;
  final String title;
  final List<DietMeal> meals;
  final String content;

  /// AI drafts the coach has left today.
  final int? left;

  const PlanDraft({required this.kind, required this.title, this.meals = const [], this.content = '', this.left});

  factory PlanDraft.fromJson(Map<String, dynamic> json) {
    final kind = PlanKind.from(json['kind'] as String?);
    return PlanDraft(
      kind: kind,
      title: json['title'] as String? ?? '',
      meals: DietMeal.listFrom(json['meals']),
      content: (kind == PlanKind.diet ? json['notes'] : json['content']) as String? ?? '',
      left: (json['left'] as num?)?.toInt(),
    );
  }
}

/// The member's numbers the AI may see for a draft: never their name, phone
/// or medical notes.
Map<String, dynamic> draftFacts(
    {required List<BodyMeasurement> measurements, MemberGoal? goal, int? age, int? kcalTarget, int? proteinTargetG}) {
  final s = ProgressSummary.of(measurements);
  return {
    if (goal?.sex != null) 'sex': goal!.sex!.value,
    if (age != null) 'age': age,
    if (s.weightNow != null) 'weight_kg': s.weightNow,
    if (s.heightCm != null) 'height_cm': s.heightCm,
    if (s.bodyFatPct != null) 'body_fat_pct': s.bodyFatPct,
    if (goal?.goal != null) 'goal': goal!.goal!.value,
    if (goal?.targetWeightKg != null) 'target_weight_kg': goal!.targetWeightKg,
    if (goal != null) 'activity': goal.activity.value,
    if (kcalTarget != null) 'kcal_target': kcalTarget,
    if (proteinTargetG != null) 'protein_target_g': proteinTargetG,
  };
}

// ─── Reading and saving ─────────────────────────────────────────────────────

final gymNutritionRepositoryProvider = Provider<GymNutritionRepository>((ref) => GymNutritionRepository(ref.watch(supabaseProvider)));

/// A member's goal; null when none is set.
final memberGoalProvider = FutureProvider.autoDispose.family<MemberGoal?, String>(
  (ref, gymMemberId) => ref.watch(gymNutritionRepositoryProvider).goal(gymMemberId),
);

/// A member's age in years; null without a date of birth.
final memberAgeProvider = FutureProvider.autoDispose.family<int?, String>(
  (ref, gymMemberId) => ref.watch(gymNutritionRepositoryProvider).age(gymMemberId),
);

final dietFoodsProvider = FutureProvider<List<DietFood>>((ref) => ref.watch(gymNutritionRepositoryProvider).foods());

/// A gym's plan templates, by title.
final planTemplatesProvider = FutureProvider.autoDispose.family<List<PlanTemplate>, String>(
  (ref, venueId) => ref.watch(gymNutritionRepositoryProvider).templates(venueId),
);

class GymNutritionRepository {
  GymNutritionRepository(this._client);
  final SupabaseClient _client;

  Future<MemberGoal?> goal(String gymMemberId) async {
    final row = await _client.from('gym_member_goals').select().eq('gym_member_id', gymMemberId).maybeSingle();
    return row == null ? null : MemberGoal.fromJson(row);
  }

  Future<void> saveGoal(MemberGoal goal) =>
      _client.rpc('gym_save_member_goal', params: {'gym_member_id': goal.gymMemberId, 'details': goal.toJson()});

  Future<int?> age(String gymMemberId) async =>
      (await _client.rpc('gym_member_age', params: {'gym_member_id': gymMemberId}) as num?)?.toInt();

  Future<List<DietFood>> foods() async {
    final rows = await _client.from('diet_foods').select().order('sort').order('name');
    return rows.map(DietFood.fromJson).toList();
  }

  Future<List<PlanTemplate>> templates(String venueId) async {
    final rows = await _client.from('gym_plan_templates').select().eq('venue_id', venueId).order('title');
    return rows.map(PlanTemplate.fromJson).toList();
  }

  /// Keeps a template at [venueId]; one with the same kind and title is
  /// replaced.
  Future<void> saveTemplate(String venueId,
          {required PlanKind kind, required String title, String content = '', List<DietMeal> meals = const []}) =>
      _client.rpc('gym_save_plan_template', params: {
        'venue_id': venueId,
        'details': {'kind': kind.value, 'title': title.trim(), 'content': content.trim(), 'meals': [for (final m in meals) m.toJson()]},
      });

  Future<void> deleteTemplate(String id) => _client.rpc('gym_delete_plan_template', params: {'template_id': id});

  /// Asks the AI to draft a plan for [gymMemberId] from [facts] (see
  /// [draftFacts]) and the coach's [note]. Throws [AssistantProblem] with
  /// words to show.
  Future<PlanDraft> draftPlan(String gymMemberId, PlanKind kind, Map<String, dynamic> facts, {String? note}) async =>
      PlanDraft.fromJson(await invokeAssistant(_client, 'draft-plan', {
        'gym_member_id': gymMemberId,
        'kind': kind.value,
        'facts': facts,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      }));
}
