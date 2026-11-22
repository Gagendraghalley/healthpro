// Drafts a workout or diet plan for one member, for their trainer or the
// gym's staff to check, change and give (the app only fills its plan form):
//
//   { gym_member_id, kind: 'diet' | 'workout', facts: {...}, note? }
//     -> { kind, title, meals? | content?, notes?, left }
//
// Cloudflare Workers AI gets the member's numbers, the shared food list and
// the coach's note (see draft.ts), never their name, phone or medical notes.
// The database counts each draft first, as the caller (ai_take_plan_draft:
// the member's coaches, 10 a day each).
//
// Secrets: see _shared/workers_ai.ts.
// Deploy: supabase functions deploy draft-plan
import { createClient } from 'npm:@supabase/supabase-js@2';

import { AskError, askWorkersAi, cors, reply, workersAi } from '../_shared/workers_ai.ts';
import { cleanFacts, cleanKind, cleanNote, type Food, messages, sanitize } from './draft.ts';

const uuid = (value: unknown): string | null =>
  typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value) ? value : null;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return reply({ error: 'Use POST' }, 405);

  const authorization = req.headers.get('Authorization');
  if (!authorization) return reply({ error: 'Please sign in again.' }, 401);

  const ai = workersAi();
  if (!ai) return reply({ error: "AI drafts aren't set up yet. Write the plan yourself for now.", code: 'not_set_up' }, 503);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return reply({ error: 'Send JSON' }, 400);
  }
  const memberId = uuid(body.gym_member_id);
  const kind = cleanKind(body.kind);
  const facts = cleanFacts(body.facts);
  if (!memberId) return reply({ error: 'Which member?' }, 400);
  if (!kind) return reply({ error: 'A workout or a diet plan?' }, 400);
  if (kind === 'diet' && facts.kcal_target === undefined) {
    return reply({ error: 'Set the daily calories first: the draft is planned around them.' }, 400);
  }

  const asCaller = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: who, error: whoError } = await asCaller.auth.getUser();
  if (whoError || !who.user) return reply({ error: 'Please sign in again.' }, 401);

  // The member's trainer or the gym's staff, within today's allowance.
  const { data: left, error: takeError } = await asCaller.rpc('ai_take_plan_draft', { gym_member_id: memberId });
  if (takeError) return reply({ error: takeError.message }, 403);

  let foods: Food[] = [];
  if (kind === 'diet') {
    const { data, error } = await asCaller.from('diet_foods').select('name, serving, kcal, protein_g').order('sort');
    if (error || !data?.length) return reply({ error: "The food list couldn't be read. Please try again.", left }, 502);
    foods = data.map((f) => ({ ...f, protein_g: Number(f.protein_g) }));
  }

  try {
    // Plain text in a set form (draft.ts), not JSON mode: it can't always
    // hold a long, nested answer to a schema.
    const raw = await askWorkersAi(ai, messages(kind, facts, foods, cleanNote(body.note)), null, {
      maxTokens: 1500,
      temperature: 0.3,
      timeoutMs: 50_000,
    });
    const draft = sanitize(kind, raw, foods, facts);
    if (!draft) {
      // What the model wrote (numbers only, no one's name): Supabase → Edge Functions → draft-plan → Logs.
      console.error('draft-plan: unusable', kind, (typeof raw === 'string' ? raw : JSON.stringify(raw) ?? 'nothing').slice(0, 3000));
      return reply({ error: "The AI's draft wasn't usable. Please try again.", left }, 502);
    }
    return reply({ ...draft, left }, 200);
  } catch (e) {
    if (e instanceof AskError) return reply({ error: e.message, left }, 502);
    console.error('draft-plan failed', e);
    return reply({ error: "The AI couldn't draft the plan just now. Please try again.", left }, 502);
  }
});
