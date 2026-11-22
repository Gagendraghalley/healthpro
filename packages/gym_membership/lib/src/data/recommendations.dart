import 'coaching.dart';
import 'nutrition.dart';

// Suggestions from a member's progress, goal and plans: rules a coach can
// read and check, worked out in the app (the daily nudges in
// 20261122000004_coaching_nudges_and_plan_drafts.sql use the same 3-week
// rule).

enum SuggestionKind { underweightLosing, wrongWay, plateau, noDietPlan, aimOff, leanLoss }

/// One thing to do about a member's progress, said to their coach or to them.
class Suggestion {
  final SuggestionKind kind;
  final ReadingTone tone;
  final String text;

  const Suggestion(this.kind, this.tone, this.text);

  @override
  String toString() => text;
}

/// How much the weight moved over 3 weeks: the latest weighing (in the last
/// 14 days) against the latest one 21 to 35 days before it. Null without
/// both.
double? threeWeekChange(List<BodyMeasurement> newestFirst, DateTime today) {
  final weighed = newestFirst.where((m) => m.weightKg != null).toList();
  final now = weighed.firstOrNull;
  if (now == null || today.difference(now.measuredOn).inDays > 14) return null;
  final before = weighed.where((m) {
    final apart = now.measuredOn.difference(m.measuredOn).inDays;
    return apart >= 21 && apart <= 35;
  }).firstOrNull;
  return before == null ? null : now.weightKg! - before.weightKg!;
}

/// What to do next for a member, most pressing first. [plans] null: not
/// known (no plan suggestions). [self]: said to the member, who can't change
/// their own plans.
List<Suggestion> coachingSuggestions({
  required List<BodyMeasurement> measurements,
  required MemberGoal? goal,
  required int? age,
  required List<MemberPlan>? plans,
  required DateTime today,
  bool self = false,
}) {
  final out = <Suggestion>[];
  final s = ProgressSummary.of(measurements);
  final kind = goal?.goal;
  final losing = kind == GoalKind.loseFat;
  final gaining = kind == GoalKind.buildMuscle || kind == GoalKind.gainWeight;
  final aim = dailyTargets(
      weightKg: s.weightNow, heightCm: s.heightCm, age: age, sex: goal?.sex, activity: goal?.activity ?? Activity.moderate, goal: kind);
  final diet = plans?.where((p) => p.isActive && p.kind == PlanKind.diet).firstOrNull;
  final dietKcal = diet?.kcalTarget ?? aim?.kcal;
  final progress = goal == null ? null : goalProgress(goal, measurements);
  final onTheWay = progress == null || !progress.reached;

  if (losing && s.bmiBand == BmiBand.under) {
    final bmi = s.bmi!.toStringAsFixed(1);
    out.add(Suggestion(SuggestionKind.underweightLosing, ReadingTone.alert,
        self
            ? 'You\'re underweight (BMI $bmi). Talk to your trainer before trying to lose fat.'
            : 'Underweight (BMI $bmi): losing fat isn\'t advised. Building muscle or gaining weight would suit better.'));
  }

  final pace = s.pacePerWeek;
  final wrongWay = pace != null && onTheWay && ((losing && pace >= 0.25) || (gaining && pace <= -0.25));
  if (wrongWay) {
    final which = pace > 0 ? 'up' : 'down';
    out.add(Suggestion(SuggestionKind.wrongWay, ReadingTone.watch,
        self
            ? 'Your weight is going $which, away from your goal. Your trainer can help adjust your plan.'
            : 'Weight is going $which (${kgText(pace.abs())} a week), away from the goal. Check the diet plan\'s calories.'));
  }

  final change = threeWeekChange(measurements, today);
  final buildingWell = kind == GoalKind.buildMuscle && (s.leanChange ?? 0) > 0.3;
  final stuck = change != null && onTheWay && !wrongWay && !buildingWell && ((losing && change > -0.3) || (gaining && change < 0.3));
  if (stuck) {
    final step = losing ? -150 : 200;
    out.add(Suggestion(SuggestionKind.plateau, ReadingTone.watch, switch ((self, dietKcal)) {
      (true, _) => 'Your weight hasn\'t moved in 3 weeks. Ask your trainer about adjusting your plan.',
      (false, final int kcal) => 'No weight ${losing ? 'lost' : 'gained'} in 3 weeks. Try about ${step.abs()} kcal '
          '${losing ? 'less' : 'more'} a day (${thousands(kcal + step)} kcal)${losing ? ', or more walking' : ''}.',
      (false, null) => 'No weight ${losing ? 'lost' : 'gained'} in 3 weeks. Check the diet plan\'s calories.',
    }));
  }

  if (kind != null && plans != null && diet == null) {
    out.add(Suggestion(SuggestionKind.noDietPlan, ReadingTone.neutral,
        self
            ? 'Ask your trainer for a diet plan to match your goal.'
            : 'No diet plan yet. Give one${aim == null ? '' : ' for their daily aim of ${kcalAndProtein(aim.kcal, aim.proteinG)}'}.'));
  }

  final planned = diet?.kcalTarget;
  if (!self && planned != null && aim != null && (planned - aim.kcal).abs() > aim.kcal * 0.15) {
    out.add(Suggestion(SuggestionKind.aimOff, ReadingTone.watch,
        'The diet plan aims for ${thousands(planned)} kcal; their goal now works out to ${thousands(aim.kcal)} kcal. Update the plan?'));
  }

  final fat = s.fatChange, lean = s.leanChange;
  if (fat != null && lean != null && lean < -0.5 && -lean > -fat) {
    final protein = aim == null ? 'more protein' : '${aim.proteinG} g protein a day';
    out.add(Suggestion(SuggestionKind.leanLoss, ReadingTone.watch,
        self
            ? 'Most of your loss is lean mass. More protein and strength training help keep muscle.'
            : 'Most of the loss is lean mass. Aim for $protein and keep strength training in the plan.'));
  }
  return out;
}
