// What the draft-plan Edge Function sends the model and lets through.
//
//   deno test tests/functions/
import {
  cleanFacts,
  cleanKind,
  describe,
  dietMeals,
  type Food,
  matchFood,
  messages,
  readDiet,
  readItem,
  readWorkout,
  sanitize,
  workoutContent,
} from '../../supabase/functions/draft-plan/draft.ts';

function same(actual: unknown, expected: unknown) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`got ${a}\nexpected ${e}`);
}

const foods: Food[] = [
  { name: 'Red rice, cooked', serving: '1 cup', kcal: 215, protein_g: 4.5 },
  { name: 'Ema datshi', serving: '1 bowl', kcal: 220, protein_g: 9 },
  { name: 'Egg, boiled', serving: '1 egg', kcal: 78, protein_g: 6.3 },
];

Deno.test('the member\'s numbers are checked again; names and anything else are left out', () => {
  same(
    cleanFacts({ sex: 'female', age: 30, weight_kg: 65, height_cm: 1650, goal: 'lose_fat', activity: 'sofa', kcal_target: '1700',
      full_name: 'Mindu Dema', phone: '17700001' }),
    { sex: 'female', age: 30, weight_kg: 65, goal: 'lose_fat', kcal_target: 1700 },
  );
  same(cleanFacts('nonsense'), {});
  same(cleanKind('diet'), 'diet');
  same(cleanKind('yoga'), null);
});

Deno.test('the model reads numbers, the note and the food list, never a name', () => {
  same(describe({ sex: 'male', age: 25, weight_kg: 80, goal: 'build_muscle', target_weight_kg: 85, activity: 'active', kcal_target: 3100,
    protein_target_g: 145 }),
    'Member: male, 25 years, 80 kg.\nGoal: build muscle (target 85 kg).\nActivity: active (training 5 to 6 days a week).\n' +
      'Daily aim: 3100 kcal, 145 g protein.');
  const sent = messages('diet', { weight_kg: 65, kcal_target: 1700 }, foods, 'vegetarian');
  same(sent.map((m) => m.role), ['system', 'user']);
  if (!sent[1].content.includes("Trainer's note: vegetarian")) throw new Error('no note');
  if (!sent[1].content.includes('Ema datshi: 1 bowl, 220 kcal, 9 g')) throw new Error('no food list');
  if (messages('workout', {}, foods, null)[1].content.includes('Ema datshi')) throw new Error('a workout needs no foods');
});

Deno.test('a diet: listed foods only, in halves of a serving, the numbers worked out here', () => {
  same(
    dietMeals({
      meals: [
        { name: 'Breakfast', items: [{ food: 'egg, boiled', servings: 2.2 }, { food: 'Pizza', servings: 1 }] },
        { name: 'Lunch', items: [{ food: 'Red rice, cooked', servings: 1 }, { food: 'Ema datshi', servings: '1' }] },
        { name: 'Dinner', items: [{ food: 'Pizza', servings: 2 }] },
      ],
    }, foods),
    [
      { name: 'Breakfast', items: [{ food: 'Egg, boiled', amount: '2 × 1 egg', kcal: 156, protein_g: 12.6 }] },
      {
        name: 'Lunch',
        items: [
          { food: 'Red rice, cooked', amount: '1 cup', kcal: 215, protein_g: 4.5 },
          { food: 'Ema datshi', amount: '1 bowl', kcal: 220, protein_g: 9 },
        ],
      },
    ],
  );
  same(dietMeals({ meals: [{ name: 'Lunch', items: [{ food: 'Pizza', servings: 1 }] }] }, foods), null);
  same(dietMeals('not json', foods), null);
});

Deno.test('a diet far from the aim is scaled toward it', () => {
  // 215 + 220 = 435 kcal against an aim of 870: every serving doubled.
  const meals = dietMeals({ meals: [{ name: 'Lunch', items: [{ food: 'Red rice, cooked', servings: 1 }, { food: 'Ema datshi', servings: 1 }] }] },
    foods, 870)!;
  same(meals[0].items.map((i) => [i.amount, i.kcal]), [['2 × 1 cup', 430], ['2 × 1 bowl', 440]]);
  // Within 10%: left as it is.
  same(dietMeals({ meals: [{ name: 'Lunch', items: [{ food: 'Red rice, cooked', servings: 2 }] }] }, foods, 450)![0].items[0].kcal, 430);
});

Deno.test('a workout becomes the plan\'s words', () => {
  same(
    workoutContent({
      days: [
        { name: 'Day 1: Legs', exercises: [{ name: 'Squats', sets: 4, reps: '8-10' }, { name: 'Plank', sets: 3, reps: 30 }] },
        { name: 'Day 2: Rest', exercises: [] },
        { name: 'Day 3: Upper body', exercises: [{ name: 'Bench press', sets: 4, reps: '8' }] },
      ],
      notes: 'Warm up for 5 minutes first.',
    }),
    'Day 1: Legs\n- Squats: 4 x 8-10\n- Plank: 3 x 30\n\nDay 3: Upper body\n- Bench press: 4 x 8\n\nWarm up for 5 minutes first.',
  );
  same(workoutContent({ days: [] }), null);
});

Deno.test('the draft: a title always, notes when given; nothing usable is null', () => {
  same(sanitize('workout', { days: [{ name: 'Day 1', exercises: [{ name: 'Run', sets: 1, reps: '20 min' }] }] }, foods, {}),
    { kind: 'workout', title: 'Workout plan', content: 'Day 1\n- Run: 1 x 20 min' });
  same(sanitize('diet', { title: ' Lean  month ', meals: [{ name: 'Lunch', items: [{ food: 'Ema datshi', servings: 1 }] }], notes: 'Drink water.' },
    foods, {}),
    { kind: 'diet', title: 'Lean month', meals: [{ name: 'Lunch', items: [{ food: 'Ema datshi', amount: '1 bowl', kcal: 220, protein_g: 9 }] }],
      notes: 'Drink water.' });
  same(sanitize('diet', { title: 'x', meals: [] }, foods, {}), null);
});

// The model writes plain text in a set form; it isn't always tidy.
const workoutText = `Here is the plan:
**Title:** Beginner strength, 3 days

## Day 1: Legs
- Squats: 4 x 8-10
* Leg press: 3 x 12

**Day 2: Upper body**
1. Bench press: 4 x 8
2. Seated row: 3 x 10

Day 3: Cardio and core
- Treadmill walk: 1 x 20 min
- Plank: 3 x 30 s
Notes: Warm up for 5 to 10 minutes. Rest 60 to 90 seconds between sets.`;

Deno.test('a workout written as text becomes the plan\'s words, tidied', () => {
  same(sanitize('workout', workoutText, foods, {}), {
    kind: 'workout',
    title: 'Beginner strength, 3 days',
    content: 'Here is the plan:\n\nDay 1: Legs\n- Squats: 4 x 8-10\n- Leg press: 3 x 12\n\nDay 2: Upper body\n- Bench press: 4 x 8\n' +
      '- Seated row: 3 x 10\n\nDay 3: Cardio and core\n- Treadmill walk: 1 x 20 min\n- Plank: 3 x 30 s\n\n' +
      'Warm up for 5 to 10 minutes. Rest 60 to 90 seconds between sets.',
  });
  same(sanitize('workout', 'Sorry, I cannot help with that.', foods, {}), null);
  same(sanitize('workout', null, foods, {}), null);
});

Deno.test('a diet written as text: listed foods only, near names matched, servings read', () => {
  const text = `Title: Lean day
Meal: Breakfast
- Egg, boiled | 2
- Pizza | 1
**Lunch:**
- Red rice cooked - 1
- 1 x ema datshi
Meal: Dinner
- Ema Datshi | ½
Notes:
- Drink 2 litres of water.
- Less sugar in tea.`;
  same(sanitize('diet', text, foods, {}), {
    kind: 'diet',
    title: 'Lean day',
    meals: [
      { name: 'Breakfast', items: [{ food: 'Egg, boiled', amount: '2 × 1 egg', kcal: 156, protein_g: 12.6 }] },
      {
        name: 'Lunch',
        items: [
          { food: 'Red rice, cooked', amount: '1 cup', kcal: 215, protein_g: 4.5 },
          { food: 'Ema datshi', amount: '1 bowl', kcal: 220, protein_g: 9 },
        ],
      },
      { name: 'Dinner', items: [{ food: 'Ema datshi', amount: '0.5 × 1 bowl', kcal: 110, protein_g: 4.5 }] },
    ],
    notes: 'Drink 2 litres of water. Less sugar in tea.',
  });
  same(sanitize('diet', 'Title: Nothing\nMeal: Lunch\n- Pizza | 2', foods, {}), null);
});

Deno.test('a food line, however it is written', () => {
  same(readItem('- Egg, boiled | 2', foods), { food: 'Egg, boiled', servings: 2 });
  same(readItem('* 1.5 × Red rice, cooked', foods), { food: 'Red rice, cooked', servings: 1.5 });
  same(readItem('- Ema datshi (1 bowl)', foods), { food: 'Ema datshi', servings: 1 });
  same(readItem('- Pizza | 2', foods), null);
  same(matchFood('rice', foods)?.name, 'Red rice, cooked');
  same(readDiet('- Egg, boiled | 1', foods).meals, [{ name: 'Meal', items: [{ food: 'Egg, boiled', servings: 1 }] }]);
  same(readWorkout('Title: x\nDay 1\nSquats').content, null);
});
