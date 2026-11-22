// What the model is told to draft, and how its draft is read and checked
// before the app sees it. The model sees the member's numbers (sex, age,
// weight, height, body fat, goal, activity, daily aim), the shared food list
// and the coach's note: never their name, phone or medical notes.
//
// It writes the plan as plain text in a set form (Title:, Day 1: / Meal:,
// "- " lines, Notes:), read here line by line: Workers AI's JSON mode can't
// always hold a long, nested answer to a schema. A diet is written in
// servings of listed foods, so its calories and protein are worked out here,
// not by the model.
import { asObject, cleanText } from '../_shared/workers_ai.ts';

export const KINDS = ['diet', 'workout'] as const;
export const GOALS = ['lose_fat', 'build_muscle', 'gain_weight', 'keep_fit'] as const;
export const ACTIVITIES = ['light', 'moderate', 'active', 'very_active'] as const;

export type Kind = typeof KINDS[number];
export type Food = { name: string; serving: string; kcal: number; protein_g: number };
export type Facts = {
  sex?: 'female' | 'male';
  age?: number;
  weight_kg?: number;
  height_cm?: number;
  body_fat_pct?: number;
  goal?: typeof GOALS[number];
  target_weight_kg?: number;
  activity?: typeof ACTIVITIES[number];
  kcal_target?: number;
  protein_target_g?: number;
};
export type Item = { food: string; amount: string; kcal: number; protein_g: number };
export type Meal = { name: string; items: Item[] };
export type Draft =
  | { kind: 'diet'; title: string; meals: Meal[]; notes?: string }
  | { kind: 'workout'; title: string; content: string };

const isOneOf = <T extends string>(list: readonly T[], value: unknown): value is T =>
  typeof value === 'string' && (list as readonly string[]).includes(value);

function numberIn(value: unknown, min: number, max: number): number | undefined {
  const n = typeof value === 'number' ? value : typeof value === 'string' ? Number(value) : NaN;
  return Number.isFinite(n) && n >= min && n <= max ? n : undefined;
}

export const cleanKind = (value: unknown): Kind | null => (isOneOf(KINDS, value) ? value : null);
export const cleanNote = (value: unknown) => cleanText(value, 200);

/** The member's numbers from the app, checked again: they come from the
 *  browser. Anything else, or out of range, is left out. */
export function cleanFacts(value: unknown): Facts {
  const f = (value !== null && typeof value === 'object' ? value : {}) as Record<string, unknown>;
  const out: Facts = {};
  if (f.sex === 'female' || f.sex === 'male') out.sex = f.sex;
  const set = <K extends keyof Facts>(key: K, v: Facts[K] | undefined) => {
    if (v !== undefined) out[key] = v;
  };
  set('age', numberIn(f.age, 10, 100));
  set('weight_kg', numberIn(f.weight_kg, 10, 400));
  set('height_cm', numberIn(f.height_cm, 50, 260));
  set('body_fat_pct', numberIn(f.body_fat_pct, 2, 75));
  if (isOneOf(GOALS, f.goal)) out.goal = f.goal;
  set('target_weight_kg', numberIn(f.target_weight_kg, 20, 300));
  if (isOneOf(ACTIVITIES, f.activity)) out.activity = f.activity;
  set('kcal_target', numberIn(f.kcal_target, 800, 6000));
  set('protein_target_g', numberIn(f.protein_target_g, 20, 400));
  return out;
}

const ACTIVITY_WORDS: Record<string, string> = {
  light: 'light (training 1 to 2 days a week)',
  moderate: 'moderate (training 3 to 4 days a week)',
  active: 'active (training 5 to 6 days a week)',
  very_active: 'very active (hard training every day, or heavy work)',
};

/** The member in a few lines, for the model. */
export function describe(f: Facts): string {
  const body = [
    f.sex,
    f.age !== undefined ? `${Math.round(f.age)} years` : undefined,
    f.weight_kg !== undefined ? `${f.weight_kg} kg` : undefined,
    f.height_cm !== undefined ? `${f.height_cm} cm` : undefined,
    f.body_fat_pct !== undefined ? `body fat ${f.body_fat_pct}%` : undefined,
  ].filter(Boolean);
  const lines = [`Member: ${body.length ? body.join(', ') : 'not given'}.`];
  if (f.goal) {
    lines.push(`Goal: ${f.goal.replace('_', ' ')}${f.target_weight_kg !== undefined ? ` (target ${f.target_weight_kg} kg)` : ''}.`);
  }
  if (f.activity) lines.push(`Activity: ${ACTIVITY_WORDS[f.activity]}.`);
  if (f.kcal_target !== undefined || f.protein_target_g !== undefined) {
    lines.push(`Daily aim: ${[
      f.kcal_target !== undefined ? `${Math.round(f.kcal_target)} kcal` : undefined,
      f.protein_target_g !== undefined ? `${Math.round(f.protein_target_g)} g protein` : undefined,
    ].filter(Boolean).join(', ')}.`);
  }
  return lines.join('\n');
}

export const DIET_PROMPT = `You draft a one-day diet plan for a gym member in Bhutan, for their trainer to check and change.
Write it in exactly this form, with nothing before or after it:
Title: <a short name for the plan>
Meal: Breakfast
- <food name exactly as in the list> | <servings>
- <food name exactly as in the list> | <servings>
Meal: Lunch
- <food name exactly as in the list> | <servings>
Notes: <up to three short sentences of practical advice: water, timing, easy swaps>

Rules:
- Use only foods from the list, with their exact names. Servings is how many of the listed serving: 0.5 to 4, in halves.
- Plan 3 to 5 meals (for example Breakfast, Lunch, Snack, Dinner), each with 1 to 6 foods.
- The day's calories should come within 10% of the daily aim, and protein close to its aim.
- Prefer meals people in Bhutan eat: red rice, datshi dishes, dal, vegetables, eggs, meat or fish. Keep sugar, soft drinks and instant noodles low.
- Follow the trainer's note (for example vegetarian, or no pork).
- This is general fitness guidance, not medical advice: no fasting, no extreme diets, no supplements other than whey protein.`;

export const WORKOUT_PROMPT = `You draft a weekly workout plan for a gym member in Bhutan, for their trainer to check and change.
Write it in exactly this form, with nothing before or after it:
Title: <a short name for the plan>
Day 1: <what it works, for example Legs>
- <exercise>: <sets> x <reps>
- <exercise>: <sets> x <reps>
Day 2: <what it works>
- <exercise>: <sets> x <reps>
Notes: <up to three short sentences: warm-up, rest, how to progress>

Rules:
- Training days a week from their activity: light 2, moderate 3 to 4, active 5, very active 5 to 6. Not told: 3. List training days only.
- Use exercises an ordinary gym has: barbells, dumbbells, machines, cables, bodyweight, treadmill or bike.
- 4 to 7 exercises a day. Reps like 8-10, 12, 30 s or 20 min.
- Fit the goal: lose fat (strength with some cardio), build muscle (strength, 8 to 12 reps, more over the weeks), gain weight (heavy compound lifts), keep fit (a mix).
- Keep it safe for their age, as for a beginner unless the note says otherwise. Follow the trainer's note.
- This is general fitness guidance, not medical advice.`;

/** What the model is sent. */
export function messages(kind: Kind, facts: Facts, foods: Food[], note: string | null) {
  const parts = [describe(facts)];
  if (note) parts.push(`Trainer's note: ${note}`);
  if (kind === 'diet') {
    parts.push('Foods (name: serving, kcal, protein):');
    parts.push(...foods.map((f) => `${f.name}: ${f.serving}, ${f.kcal} kcal, ${f.protein_g} g`));
  }
  return [
    { role: 'system' as const, content: kind === 'diet' ? DIET_PROMPT : WORKOUT_PROMPT },
    { role: 'user' as const, content: parts.join('\n') },
  ];
}

// ─── Reading the model's text ──────────────────────────────────────────────

/** A line without markdown: '**Title:** x' as 'Title: x', '## Day 1' as 'Day 1'. */
const plain = (line: string) => line.replace(/\*\*|__|`/g, '').replace(/^\s*#+\s*/, '').trim();
const BULLET = /^(?:[-*•]|\d+[.)])\s+/;
const TITLE = /^title\s*:\s*(.+)$/i;
const NOTES = /^notes?\s*:\s*(.*)$/i;

/** '2', '1.5', '½' as a number. */
function servingsIn(text: string): number | undefined {
  const m = text.replace('½', '0.5').match(/(\d+(?:\.\d+)?)/);
  return m ? Number(m[1]) : undefined;
}

/** 'Suja (butter tea)' as 'suja butter tea': case and punctuation aside. */
const bare = (text: string) => text.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();

/** The listed food [text] names: by its name (case and punctuation aside),
 *  else the longest listed name in it (or that has it in). */
export function matchFood(text: string, foods: Food[]): Food | undefined {
  const t = bare(text);
  if (t.length < 3) return undefined;
  const exact = foods.find((f) => bare(f.name) === t);
  if (exact) return exact;
  return foods
    .filter((f) => ` ${t} `.includes(` ${bare(f.name)} `) || bare(f.name).includes(t))
    .sort((a, b) => b.name.length - a.name.length)[0];
}

/** '- Egg, boiled | 2' (or 'Egg, boiled - 2', '2 x Egg, boiled') as a listed
 *  food and its servings; null when it names none. */
export function readItem(line: string, foods: Food[]): { food: string; servings: number } | null {
  let text = line.replace(BULLET, '').trim();
  let servings: number | undefined;
  const bar = text.lastIndexOf('|');
  if (bar >= 0) {
    servings = servingsIn(text.slice(bar + 1));
    text = text.slice(0, bar);
  } else {
    const after = text.match(/^(.*?)\s*(?:[:–—-]|\bx\b|×)\s*(\d+(?:\.\d+)?|½)\s*(?:x|×|servings?)?\s*$/i);
    const before = text.match(/^(\d+(?:\.\d+)?|½)\s*(?:x|×)\s*(.+)$/i);
    if (after) {
      text = after[1];
      servings = servingsIn(after[2]);
    } else if (before) {
      text = before[2];
      servings = servingsIn(before[1]);
    }
  }
  const food = matchFood(text, foods);
  return food ? { food: food.name, servings: servings ?? 1 } : null;
}

/** A diet as the model wrote it: its title, meals (listed foods only) and
 *  notes. */
export function readDiet(text: string, foods: Food[]) {
  let title: string | undefined;
  const notes: string[] = [];
  const meals: { name: string; items: { food: string; servings: number }[] }[] = [];
  let inNotes = false;
  for (const raw of text.split('\n')) {
    const line = plain(raw);
    if (!line) continue;
    let m: RegExpMatchArray | null;
    if ((m = line.match(TITLE))) {
      title = m[1];
      inNotes = false;
    } else if ((m = line.match(NOTES))) {
      inNotes = true;
      if (m[1]) notes.push(m[1]);
    } else if (
      (m = line.match(/^meal\s*\d*\s*:\s*(.+)$/i)) ||
      (m = line.match(/^((?:early |mid-?morning |morning |afternoon |evening )?(?:breakfast|lunch|dinner|supper|snack)|pre-workout|post-workout)\s*:?\s*$/i))
    ) {
      meals.push({ name: m[1].replace(/:$/, '').trim(), items: [] });
      inNotes = false;
    } else if (inNotes) {
      notes.push(line.replace(BULLET, ''));
    } else {
      const item = readItem(line, foods);
      if (!item) continue;
      if (meals.length === 0) meals.push({ name: 'Meal', items: [] });
      meals[meals.length - 1].items.push(item);
    }
  }
  return { title, meals, notes: notes.join(' ') };
}

/** A workout as the model wrote it: its title, and the plan's words (each
 *  day and its exercises, then the notes). */
export function readWorkout(text: string) {
  let title: string | undefined;
  const body: string[] = [];
  const notes: string[] = [];
  let inNotes = false;
  for (const raw of text.split('\n')) {
    const line = plain(raw);
    if (!line) continue;
    let m: RegExpMatchArray | null;
    if ((m = line.match(TITLE))) {
      title = m[1];
    } else if ((m = line.match(NOTES))) {
      inNotes = true;
      if (m[1]) notes.push(m[1]);
    } else if (inNotes) {
      notes.push(line.replace(BULLET, ''));
    } else if (/^day\s*\d+/i.test(line)) {
      if (body.length) body.push('');
      body.push(line);
    } else if (BULLET.test(line)) {
      body.push(`- ${line.replace(BULLET, '')}`);
    } else {
      body.push(line);
    }
  }
  const exercises = body.some((l) => l.startsWith('- '));
  const notesText = cleanText(notes.join(' '), 400);
  const content = exercises ? [body.join('\n'), ...(notesText ? [notesText] : [])].join('\n\n').slice(0, 6000) : null;
  return { title, content };
}

// ─── Checking the draft ────────────────────────────────────────────────────

const round1 = (n: number) => Math.round(n * 10) / 10;
const halves = (n: number) => Math.min(4, Math.max(0.5, Math.round(n * 2) / 2));

/** '1 cup', or '2 × 1 cup'. */
const amountOf = (servings: number, serving: string) => (servings === 1 ? serving : `${servings} × ${serving}`);

/** A diet's meals ({meals: [{name, items: [{food, servings}]}]}): listed
 *  foods only, in halves of a serving; then, when the day is more than 10%
 *  off [kcalAim], every serving scaled toward it. Null when nothing usable
 *  is left. */
export function dietMeals(raw: unknown, foods: Food[], kcalAim?: number): Meal[] | null {
  const r = asObject(raw);
  if (!r || !Array.isArray(r.meals)) return null;
  const byName = new Map(foods.map((f) => [f.name.toLowerCase(), f]));
  const picked: { name: string; items: { food: Food; servings: number }[] }[] = [];
  for (const m of r.meals.slice(0, 6)) {
    if (m === null || typeof m !== 'object') continue;
    const meal = m as Record<string, unknown>;
    const name = cleanText(meal.name, 40);
    if (!name || !Array.isArray(meal.items)) continue;
    const items: { food: Food; servings: number }[] = [];
    for (const i of meal.items.slice(0, 8)) {
      if (i === null || typeof i !== 'object') continue;
      const item = i as Record<string, unknown>;
      const food = typeof item.food === 'string' ? byName.get(item.food.trim().toLowerCase()) : undefined;
      const servings = numberIn(item.servings, 0.1, 10);
      if (food && servings !== undefined) items.push({ food, servings: halves(servings) });
    }
    if (items.length > 0) picked.push({ name, items });
  }
  if (picked.length === 0) return null;

  const total = picked.flatMap((m) => m.items).reduce((s, i) => s + i.food.kcal * i.servings, 0);
  if (kcalAim && total > 0 && Math.abs(total - kcalAim) > kcalAim * 0.1) {
    const scale = kcalAim / total;
    for (const m of picked) for (const i of m.items) i.servings = halves(i.servings * scale);
  }
  return picked.map((m) => ({
    name: m.name,
    items: m.items.map((i) => ({
      food: i.food.name,
      amount: amountOf(i.servings, i.food.serving),
      kcal: Math.round(i.food.kcal * i.servings),
      protein_g: round1(i.food.protein_g * i.servings),
    })),
  }));
}

/** A workout given as JSON ({days: [{name, exercises: [{name, sets, reps}]}]})
 *  as the plan's words. Null when there are no days with exercises. */
export function workoutContent(raw: unknown): string | null {
  const r = asObject(raw);
  if (!r || !Array.isArray(r.days)) return null;
  const days: string[] = [];
  for (const d of r.days.slice(0, 7)) {
    if (d === null || typeof d !== 'object') continue;
    const day = d as Record<string, unknown>;
    const name = cleanText(day.name, 60);
    if (!name || !Array.isArray(day.exercises)) continue;
    const lines: string[] = [];
    for (const e of day.exercises.slice(0, 10)) {
      if (e === null || typeof e !== 'object') continue;
      const ex = e as Record<string, unknown>;
      const exercise = cleanText(ex.name, 60);
      const sets = numberIn(ex.sets, 1, 10);
      const reps = cleanText(typeof ex.reps === 'number' ? String(ex.reps) : ex.reps, 20);
      if (exercise) lines.push(`- ${exercise}${sets !== undefined && reps ? `: ${Math.round(sets)} x ${reps}` : reps ? `: ${reps}` : ''}`);
    }
    if (lines.length > 0) days.push([name, ...lines].join('\n'));
  }
  if (days.length === 0) return null;
  const notes = cleanText(r.notes, 400);
  return [...days, ...(notes ? [notes] : [])].join('\n\n');
}

/** The model's reply (its text, or JSON if it answered so) as a draft the
 *  app can fill into the plan form; null when it isn't usable. */
export function sanitize(kind: Kind, raw: unknown, foods: Food[], facts: Facts): Draft | null {
  const r = asObject(raw);
  const structured = r !== null && (Array.isArray(r.meals) || Array.isArray(r.days));
  const text = typeof raw === 'string' ? raw : '';
  if (kind === 'diet') {
    const read = structured ? null : readDiet(text, foods);
    const meals = dietMeals(structured ? raw : { meals: read!.meals }, foods, facts.kcal_target);
    if (!meals) return null;
    const title = cleanText(structured ? r!.title : read!.title, 100) ?? 'Diet plan';
    const notes = cleanText(structured ? r!.notes : read!.notes, 400);
    return { kind, title, meals, ...(notes ? { notes } : {}) };
  }
  const read = structured ? null : readWorkout(text);
  const content = structured ? workoutContent(raw) : read!.content;
  if (!content) return null;
  return { kind, title: cleanText(structured ? r!.title : read!.title, 100) ?? 'Workout plan', content };
}
