import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/src/data/coaching.dart';
import 'package:gym_membership/src/data/nutrition.dart';
import 'package:gym_membership/src/data/recommendations.dart';
import 'package:gym_membership/src/widgets/coaching_widgets.dart';
import 'package:health_pro_core/health_pro_core.dart';

import 'coaching_test.dart' show measured, pump;
import 'gym_screens_test.dart' show day, inDialog;

// Suggestions from progress, goal and plans, and AI drafts of plans (the
// database side: the nudges and the draft count in
// tests/database/coaching_test.sql; the Edge Function in
// tests/functions/draft_plan_test.ts).

MemberGoal goalOf(GoalKind kind, {double? target}) =>
    MemberGoal(gymMemberId: 'm1', goal: kind, targetWeightKg: target, sex: Sex.female, startedOn: day(-60));

MemberPlan dietPlan({int? kcal, bool active = true}) => MemberPlan(
    id: 'd1',
    gymMemberId: 'm1',
    kind: PlanKind.diet,
    title: 'Lean month',
    content: 'Eat well',
    kcalTarget: kcal,
    isActive: active,
    updatedAt: DateTime.utc(2026, 11, 1));

List<String> said(
        {required List<BodyMeasurement> measurements,
        MemberGoal? goal,
        int? age = 30,
        List<MemberPlan>? plans = const [],
        bool self = false}) =>
    [
      for (final s in coachingSuggestions(measurements: measurements, goal: goal, age: age, plans: plans, today: day(0), self: self))
        s.text,
    ];

/// Weight flat for 3 weeks: 65 kg now, 65.1 kg 25 days ago.
final flat = [measured('b', 2, weight: 65), measured('a', 27, weight: 65.1, height: 165)];

void main() {
  group('suggestions', () {
    test('3 weeks without moving toward the goal, as the daily nudge sees it', () {
      expect(threeWeekChange(flat, day(0)), closeTo(-0.1, 0.001));
      expect(threeWeekChange(flat, day(20)), isNull, reason: 'the latest weighing is too old');
      expect(threeWeekChange([measured('b', 0, weight: 65), measured('a', 10, weight: 66)], day(0)), isNull, reason: 'not 3 weeks apart');

      expect(said(measurements: flat, goal: goalOf(GoalKind.loseFat), plans: [dietPlan(kcal: 1700)]),
          ['No weight lost in 3 weeks. Try about 150 kcal less a day (1,550 kcal), or more walking.']);
      expect(said(measurements: flat, goal: goalOf(GoalKind.gainWeight), age: null, plans: null),
          ['No weight gained in 3 weeks. Check the diet plan\'s calories.']);
      expect(said(measurements: flat, goal: goalOf(GoalKind.loseFat), plans: [dietPlan(kcal: 1700)], self: true),
          ['Your weight hasn\'t moved in 3 weeks. Ask your trainer about adjusting your plan.']);
      expect(said(measurements: flat, goal: goalOf(GoalKind.loseFat, target: 66), plans: [dietPlan(kcal: 1700)]), isEmpty,
          reason: 'the target is reached');
      expect(said(measurements: flat, goal: goalOf(GoalKind.keepFit), plans: [dietPlan(kcal: 2100)]), isEmpty,
          reason: 'keeping fit: a steady weight is the point');
    });

    test('building muscle without gaining weight, while lean mass grows, is fine', () {
      final recomposing = [measured('b', 2, weight: 65, fat: 20), measured('a', 27, weight: 65.1, height: 165, fat: 22)];
      expect(said(measurements: recomposing, goal: goalOf(GoalKind.buildMuscle), age: null, plans: [dietPlan(kcal: 2200)]), isEmpty);
    });

    test('going the wrong way, and underweight with a fat-loss goal', () {
      final up = [measured('b', 0, weight: 72), measured('a', 21, weight: 70, height: 170)];
      expect(said(measurements: up, goal: goalOf(GoalKind.loseFat), age: null, plans: [dietPlan()]),
          ['Weight is going up (0.7 kg a week), away from the goal. Check the diet plan\'s calories.']);
      final under = [measured('a', 0, weight: 50, height: 170)];
      expect(said(measurements: under, goal: goalOf(GoalKind.loseFat), age: null, plans: [dietPlan()]),
          ['Underweight (BMI 17.3): losing fat isn\'t advised. Building muscle or gaining weight would suit better.']);
      expect(said(measurements: under, goal: goalOf(GoalKind.loseFat), age: null, plans: [dietPlan()], self: true),
          ['You\'re underweight (BMI 17.3). Talk to your trainer before trying to lose fat.']);
    });

    test('a diet plan to give, or to bring in line with the goal', () {
      final now = [measured('a', 0, weight: 65, height: 165)];
      expect(said(measurements: now, goal: goalOf(GoalKind.loseFat)),
          ['No diet plan yet. Give one for their daily aim of 1,700 kcal · 130 g protein.']);
      expect(said(measurements: now, goal: goalOf(GoalKind.loseFat), plans: [dietPlan(active: false)], self: true),
          ['Ask your trainer for a diet plan to match your goal.']);
      expect(said(measurements: now, goal: goalOf(GoalKind.loseFat), plans: [dietPlan(kcal: 2400)]),
          ['The diet plan aims for 2,400 kcal; their goal now works out to 1,700 kcal. Update the plan?']);
      expect(said(measurements: now, goal: goalOf(GoalKind.loseFat), plans: [dietPlan(kcal: 1800)]), isEmpty, reason: 'within 15%');
      expect(said(measurements: now, goal: goalOf(GoalKind.loseFat), plans: null), isEmpty, reason: 'plans not known');
      expect(said(measurements: now, goal: null), isEmpty, reason: 'no goal, nothing to measure against');
    });

    test('losing more lean mass than fat', () {
      final losingMuscle = [measured('b', 0, weight: 63, fat: 24), measured('a', 21, weight: 65, height: 165, fat: 22)];
      expect(said(measurements: losingMuscle, goal: goalOf(GoalKind.keepFit), plans: [dietPlan(kcal: 2100)]),
          ['Most of the loss is lean mass. Aim for 90 g protein a day and keep strength training in the plan.']);
    });

    testWidgets('on the progress card', (tester) async {
      await pump(tester, const MemberProgress(gymMemberId: 'm1', coach: true), [
        memberMeasurementsProvider.overrideWith((ref, id) async => flat),
        memberGoalProvider.overrideWith((ref, id) async => goalOf(GoalKind.loseFat)),
        memberAgeProvider.overrideWith((ref, id) async => 30),
        memberPlansProvider.overrideWith((ref, id) async => [dietPlan(kcal: 1700)]),
      ]);
      expect(find.text('Suggestions'), findsOneWidget);
      expect(find.text('No weight lost in 3 weeks. Try about 150 kcal less a day (1,550 kcal), or more walking.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('AI drafts', () {
    testWidgets('a draft fills the form, from numbers only, for the coach to check', (tester) async {
      final ai = _FakeNutrition();
      await pump(tester, const MemberPlans(gymMemberId: 'm1', coach: true), [
        gymNutritionRepositoryProvider.overrideWithValue(ai),
        memberPlansProvider.overrideWith((ref, id) async => const []),
        memberMeasurementsProvider.overrideWith((ref, id) async => flat),
        memberGoalProvider.overrideWith((ref, id) async => goalOf(GoalKind.loseFat, target: 60)),
        memberAgeProvider.overrideWith((ref, id) async => 30),
        dietFoodsProvider.overrideWith((ref) async => const []),
      ]);
      tester.view.physicalSize = const Size(1200, 2400);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Give a plan'));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('Diet')));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('Draft with AI')));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Anything to keep in mind?'), 'vegetarian');
      await tester.tap(find.text('Draft'));
      await tester.pumpAndSettle();

      expect(ai.asked, {
        'kind': 'diet',
        'note': 'vegetarian',
        'facts': {
          'sex': 'female',
          'age': 30,
          'weight_kg': 65.0,
          'height_cm': 165.0,
          'goal': 'lose_fat',
          'target_weight_kg': 60.0,
          'activity': 'moderate',
          'kcal_target': 1700,
          'protein_target_g': 130,
        },
      });
      expect((tester.widget(inDialog(find.widgetWithText(TextFormField, 'Title *'))) as TextFormField).controller!.text, 'Veg lean day');
      expect(inDialog(find.text('1,700 of 1,700 kcal')), findsOneWidget, reason: 'opens in Preview, as the member will read it');
      expect(inDialog(find.text('Dal')), findsOneWidget);
      expect(inDialog(find.text('Drink water.')), findsOneWidget);
      await tester.tap(inDialog(find.text('Write')));
      await tester.pumpAndSettle();
      expect(inDialog(find.text('In all: 1,700 kcal · 60 g protein')), findsOneWidget, reason: 'and back to the meals to change');
      expect(inDialog(find.textContaining('Drafted by AI from their numbers and goal. Check every line before giving it. 9 AI drafts left today.')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    Future<void> openDiet(WidgetTester tester, _FakeNutrition ai) async {
      await pump(tester, const MemberPlans(gymMemberId: 'm1', coach: true), [
        gymNutritionRepositoryProvider.overrideWithValue(ai),
        memberPlansProvider.overrideWith((ref, id) async => const []),
        memberMeasurementsProvider.overrideWith((ref, id) async => flat),
        memberGoalProvider.overrideWith((ref, id) async => goalOf(GoalKind.loseFat, target: 60)),
        memberAgeProvider.overrideWith((ref, id) async => 30),
        dietFoodsProvider.overrideWith((ref) async => const []),
      ]);
      tester.view.physicalSize = const Size(1200, 2400);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Give a plan'));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('Diet')));
      await tester.pumpAndSettle();
    }

    testWidgets('daily calories out of range: said in the form, by the field, before asking', (tester) async {
      final ai = _FakeNutrition();
      await openDiet(tester, ai);
      await tester.enterText(inDialog(find.widgetWithText(TextFormField, 'Calories')), '21');
      await tester.tap(inDialog(find.text('Draft with AI')));
      await tester.pumpAndSettle();
      expect(inDialog(find.text('Daily calories are 800 to 6,000 kcal. Change them first: the draft is planned around them.')),
          findsOneWidget);
      expect(inDialog(find.text('800 to 6,000')), findsOneWidget, reason: 'the field is marked');
      expect(find.text('Anything to keep in mind?'), findsNothing, reason: 'the AI isn\'t asked');
      expect(ai.asked, isNull);

      await tester.tap(inDialog(find.text('Use their goal: 1,700 kcal · 130 g protein')));
      await tester.pumpAndSettle();
      expect(inDialog(find.textContaining('Daily calories are')), findsNothing);
      expect(inDialog(find.text('800 to 6,000')), findsNothing);
    });

    testWidgets('a draft that fails says why in the form, not behind it', (tester) async {
      final ai = _FakeNutrition(fails: AssistantProblem("Today's free AI questions are used up.", left: 0));
      await openDiet(tester, ai);
      await tester.tap(inDialog(find.text('Draft with AI')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Draft'));
      await tester.pumpAndSettle();
      expect(inDialog(find.text("Today's free AI questions are used up.")), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Drafts without the AI, and keeps what it was asked.
class _FakeNutrition implements GymNutritionRepository {
  _FakeNutrition({this.fails});

  /// Thrown instead of drafting.
  final Object? fails;
  Map<String, dynamic>? asked;

  @override
  Future<PlanDraft> draftPlan(String gymMemberId, PlanKind kind, Map<String, dynamic> facts, {String? note}) async {
    asked = {'kind': kind.value, 'note': note, 'facts': facts};
    if (fails != null) throw fails!;
    return const PlanDraft(kind: PlanKind.diet, title: 'Veg lean day', content: 'Drink water.', left: 9, meals: [
      DietMeal(name: 'Lunch', items: [DietItem(food: 'Dal', amount: '2 × 1 bowl', kcal: 1700, proteinG: 60)]),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
