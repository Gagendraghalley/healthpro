import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/src/data/coaching.dart';
import 'package:gym_membership/src/data/nutrition.dart';
import 'package:gym_membership/src/widgets/coaching_widgets.dart';
import 'package:health_pro_core/health_pro_core.dart';

import 'coaching_test.dart' show measured, pump;
import 'gym_screens_test.dart' show day, inDialog;

// Goals, daily calories and protein, and diet plans in meals (the database
// side: tests/database/coaching_test.sql).

MemberGoal loseFat({double? target = 60, int byInDays = 70}) => MemberGoal(
      gymMemberId: 'm1',
      goal: GoalKind.loseFat,
      targetWeightKg: target,
      targetDate: day(byInDays),
      sex: Sex.female,
      startedOn: day(-30),
    );

final week = [
  measured('b', 0, weight: 65),
  measured('a', 30, weight: 67, height: 165),
];

void main() {
  group('daily calories and protein', () {
    test('by Mifflin-St Jeor, for the goal', () {
      final lose = dailyTargets(weightKg: 65, heightCm: 165, age: 30, sex: Sex.female, goal: GoalKind.loseFat)!;
      expect([lose.kcal, lose.proteinG, lose.maintenanceKcal], [1700, 130, 2100]);
      final build = dailyTargets(weightKg: 80, heightCm: 180, age: 25, sex: Sex.male, goal: GoalKind.buildMuscle)!;
      expect([build.kcal, build.proteinG], [3100, 145], reason: 'protein for 80 kg, his weight at a BMI of 25');
      final heavy = dailyTargets(weightKg: 100, heightCm: 160, age: 35, sex: Sex.female, activity: Activity.light, goal: GoalKind.keepFit)!;
      expect(heavy.proteinG, 90, reason: 'protein for 64 kg (a BMI of 25), not 100');
      final small = dailyTargets(weightKg: 45, heightCm: 150, age: 60, sex: Sex.female, activity: Activity.light, goal: GoalKind.loseFat)!;
      expect(small.kcal, 1200, reason: 'never under 1,200 for a woman');
    });

    test('only for adults, with everything it needs', () {
      expect(dailyTargets(weightKg: 60, heightCm: 165, age: 16, sex: Sex.male), isNull);
      expect(dailyTargets(weightKg: 60, heightCm: 165, age: 30), isNull);
      expect(missingForTargets(weightKg: 70, sex: Sex.male), ['height', 'date of birth']);
      expect(thousands(2100), '2,100');
      expect(thousands(950), '950');
      expect(thousands(12345), '12,345');
    });
  });

  group('goal', () {
    test('progress from the weight on the day it was set', () {
      final p = goalProgress(loseFat(target: 65), [
        measured('c', 0, weight: 68),
        measured('b', 20, weight: 69),
        measured('a', 35, weight: 70),
      ])!;
      expect([p.start, p.now, p.target], [70, 68, 65]);
      expect(p.done, closeTo(0.4, 0.001));
      expect(p.perWeekBy(day(42), day(0)), closeTo(-0.5, 0.001));
      expect(goalProgress(loseFat(target: 65), [measured('a', 0, weight: 64.8)])!.reached, isTrue);
      expect(goalProgress(loseFat(target: null), week), isNull, reason: 'no target weight, no progress bar');
    });

    testWidgets('on the progress card: how far, the pace still needed, and the daily aim', (tester) async {
      await pump(tester, const MemberProgress(gymMemberId: 'm1', coach: true), [
        memberMeasurementsProvider.overrideWith((ref, id) async => week),
        memberGoalProvider.overrideWith((ref, id) async => loseFat()),
        memberAgeProvider.overrideWith((ref, id) async => 30),
      ]);
      expect(find.text('Lose fat · 60 kg by ${formatShortDate(day(70))}'), findsOneWidget);
      expect(find.text('2 kg lost · 5 kg to go'), findsOneWidget);
      expect(find.text('Needs 0.5 kg a week to make it by ${formatShortDate(day(70))}.'), findsOneWidget);
      expect(find.text('Daily aim: 1,700 kcal · 130 g protein'), findsOneWidget);
      expect(find.text('Set a goal'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without one, it can be set; without a date of birth, no calories', (tester) async {
      await pump(tester, const MemberProgress(gymMemberId: 'm1', self: true), [
        myProfileProvider.overrideWith((ref) async => Profile.fromJson({'id': 'me', 'full_name': 'Mindu Dema'})),
        memberMeasurementsProvider.overrideWith((ref, id) async => week),
        memberGoalProvider.overrideWith((ref, id) async => null),
        memberAgeProvider.overrideWith((ref, id) async => null),
      ]);
      await tester.tap(find.text('Set a goal'));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('Lose fat')));
      await tester.tap(inDialog(find.text('Female')));
      await tester.pumpAndSettle();
      expect(inDialog(find.text('Add the date of birth to work out daily calories.')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('diet plans in meals', () {
    final meals = DietMeal.listFrom([
      {
        'name': 'Breakfast',
        'items': [
          {'food': 'Red rice, cooked', 'amount': '1 cup', 'kcal': 215, 'protein_g': 4.5},
          {'food': 'Egg, boiled', 'kcal': 78, 'protein_g': 6.3},
        ],
      },
      {
        'name': 'Lunch',
        'items': [
          {'food': 'Ema datshi', 'amount': '1 bowl', 'kcal': 220, 'protein_g': 9},
        ],
      },
    ]);

    test('their calories and protein add up, and go back as they came', () {
      final t = mealTotals(meals);
      expect(t.kcal, 513);
      expect(t.proteinG, closeTo(19.8, 0.001));
      expect(meals.first.toJson()['items'], [
        {'food': 'Red rice, cooked', 'amount': '1 cup', 'kcal': 215.0, 'protein_g': 4.5},
        {'food': 'Egg, boiled', 'kcal': 78.0, 'protein_g': 6.3},
      ]);
    });

    testWidgets('the member reads the meals, the aim and what they add up to', (tester) async {
      await pump(tester, const MemberPlans(gymMemberId: 'm1'), [
        memberPlansProvider.overrideWith((ref, id) async => [
              MemberPlan(
                  id: 'p1',
                  gymMemberId: 'm1',
                  kind: PlanKind.diet,
                  title: 'Lean month',
                  content: 'Drink 2 litres of water a day',
                  meals: meals,
                  kcalTarget: 1700,
                  proteinTargetG: 130,
                  updatedAt: DateTime.utc(2026, 11, 20)),
            ]),
      ]);
      await tester.tap(find.text('Lean month'));
      await tester.pumpAndSettle();
      expect(find.text('513 of 1,700 kcal'), findsOneWidget, reason: 'the day against its aim');
      expect(find.text('19.8 of 130 g'), findsOneWidget);
      expect(find.text('Breakfast'), findsOneWidget, reason: 'each meal a card');
      expect(find.text('293 kcal · 10.8 g'), findsOneWidget, reason: 'what the meal adds up to');
      expect(find.text('Red rice, cooked'), findsOneWidget);
      expect(find.text('1 cup'), findsOneWidget);
      expect(find.text('215 kcal · 4.5 g'), findsOneWidget);
      expect(find.text('Drink 2 litres of water a day'), findsOneWidget);
    });

    testWidgets('a trainer writes one: the aim from the goal, foods from the list, from a template', (tester) async {
      await pump(tester, const MemberPlans(gymMemberId: 'm1', venueId: 'g1', coach: true), [
        memberPlansProvider.overrideWith((ref, id) async => const []),
        memberMeasurementsProvider.overrideWith((ref, id) async => week),
        memberGoalProvider.overrideWith((ref, id) async => loseFat()),
        memberAgeProvider.overrideWith((ref, id) async => 30),
        dietFoodsProvider.overrideWith((ref) async => const [
              DietFood(name: 'Ema datshi', serving: '1 bowl', kcal: 220, proteinG: 9),
              DietFood(name: 'Red rice, cooked', serving: '1 cup', kcal: 215, proteinG: 4.5),
            ]),
        planTemplatesProvider.overrideWith((ref, venueId) async => [
              PlanTemplate(id: 't1', kind: PlanKind.diet, title: 'Rice and dal', meals: [
                const DietMeal(name: 'Lunch', items: [DietItem(food: 'Dal', amount: '1 bowl', kcal: 180, proteinG: 9)]),
              ]),
            ]),
      ]);
      // Keep the dialog's fields on screen.
      tester.view.physicalSize = const Size(1200, 2400);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Give a plan'));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('Diet')));
      await tester.pumpAndSettle();
      expect((tester.widget(inDialog(find.widgetWithText(TextFormField, 'Calories'))) as TextFormField).controller!.text, '1700');
      expect(inDialog(find.text('Start from a template')), findsOneWidget);

      await tester.tap(inDialog(find.text('Add a meal')));
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.widgetWithText(TextFormField, 'Food')), 'datshi');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ema datshi'));
      await tester.pumpAndSettle();
      expect(inDialog(find.text('In all: 220 kcal · 9 g protein')), findsOneWidget);

      await tester.tap(inDialog(find.text('Start from a template')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rice and dal').last);
      await tester.pumpAndSettle();
      expect(inDialog(find.text('In all: 180 kcal · 9 g protein')), findsOneWidget, reason: 'the template\'s meals replace them');
      expect(tester.takeException(), isNull);
    });
  });
}
