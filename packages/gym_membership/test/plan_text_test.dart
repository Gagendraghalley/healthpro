import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/src/widgets/plan_text.dart';

import 'coaching_test.dart' show pump;

// A plan's words laid out to read: days as cards, exercises with their sets
// and reps.

const drafted = '''Here is the plan:

Day 1: Chest and Triceps
- Bench Press: 3 x 8-10
- Tricep Dips: 3 x 12

**Day 2: Back and Biceps**
* Pull-ups 3x8-10
- Plank: 3 x 30 s
- Stretch well

Day 3: Rest

Warm up for 5 to 10 minutes. Rest 60 to 90 seconds between sets.''';

void main() {
  test('days, exercises and their sets and reps, and words as written', () {
    final s = readPlanText(drafted);
    expect([for (final x in s) '${x.label}|${x.title}|${x.lines.length}'],
        ['Day 1|Chest and Triceps|2', 'Day 2|Back and Biceps|3', 'Day 3|Rest|0', 'null|null|1'],
        reason: 'a heading with nothing under it is left out; a rest day stays');
    expect([for (final l in s[1].lines) '${l.text}|${l.dose}|${l.bullet}'],
        ['Pull-ups|3 × 8–10|true', 'Plank|3 × 30 s|true', 'Stretch well|null|true']);
    expect(s.last.lines.single.text, 'Warm up for 5 to 10 minutes. Rest 60 to 90 seconds between sets.');
    expect(prettyDose('4 x 8-10'), '4 × 8–10');
    expect(readPlanText('Breakfast: 2 eggs, oats\nDrink water').first.label, 'Breakfast', reason: 'hand-written plans read too');
  });

  testWidgets('laid out as cards', (tester) async {
    await pump(tester, const PlanTextView(content: drafted), const []);
    expect(find.text('Day 1'), findsOneWidget);
    expect(find.text('Chest and Triceps'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('3 × 8–10'), findsNWidgets(2));
    expect(find.text('Here is the plan:'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
