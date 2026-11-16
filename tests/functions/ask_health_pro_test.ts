// What the ask-health-pro Edge Function (Health Pro's assistant for anyone)
// lets through from the model and the browser.
//
//   deno test tests/functions/
import { cleanHistory, messages, OTHER_ANSWER, sanitize, SYSTEM_PROMPT } from '../../supabase/functions/ask-health-pro/reply.ts';

function same(actual: unknown, expected: unknown) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`got ${a}\nexpected ${e}`);
}

Deno.test('finding gyms, in a dzongkhag spelled as Health Pro spells it', () => {
  same(sanitize({ kind: 'find_venues', venue_type: 'gym', dzongkhag: 'paro' }),
    { kind: 'find_venues', venue_type: 'gym', dzongkhag: 'Paro' });
  same(sanitize('{"kind":"find_venues","dzongkhag":"Wangdue Phodrang"}'),
    { kind: 'find_venues', venue_type: 'gym', dzongkhag: 'Wangdue Phodrang' });
});

Deno.test('a place that is not a dzongkhag means everywhere', () => {
  same(sanitize({ kind: 'find_venues', dzongkhag: 'Atlantis' }), { kind: 'find_venues', venue_type: 'gym' });
  same(sanitize({ kind: 'find_venues', venue_type: 'casino' }), { kind: 'find_venues', venue_type: 'gym' });
});

Deno.test('help: an answer and a page it knows', () => {
  same(sanitize({ kind: 'help', answer: '  Go to the gym:   the desk registers you. ', page: 'gyms' }),
    { kind: 'help', answer: 'Go to the gym: the desk registers you.', page: 'gyms' });
  same(sanitize({ kind: 'help', answer: 'Sign up first.', page: 'admin' }), { kind: 'help', answer: 'Sign up first.' });
  same(sanitize({ kind: 'help' }), { kind: 'other', answer: OTHER_ANSWER });
});

Deno.test('anything else is a friendly "other"', () => {
  same(sanitize('nonsense'), { kind: 'other', answer: OTHER_ANSWER });
  same(sanitize({ kind: 'report', report: 'revenue' }), { kind: 'other', answer: OTHER_ANSWER });
  same(sanitize({ kind: 'other', answer: 'I can help with Health Pro.' }), { kind: 'other', answer: 'I can help with Health Pro.' });
});

Deno.test('the browser\'s history is checked, kept short, and loses its answers', () => {
  same(cleanHistory([
    { question: 'gyms?', reply: { kind: 'find_venues', dzongkhag: 'Thimphu' } },
    { question: 'how to join', reply: { kind: 'help', answer: 'Long text', page: 'gyms' } },
    { question: '  ', reply: { kind: 'other' } },
    null,
  ]), [
    { question: 'gyms?', reply: { kind: 'find_venues', venue_type: 'gym', dzongkhag: 'Thimphu' } },
    { question: 'how to join', reply: { kind: 'help', page: 'gyms' } },
  ]);
});

Deno.test('the model gets the guide, the last turns, then the question', () => {
  const sent = messages('and in Paro?', [{ question: 'gyms in Thimphu', reply: { kind: 'find_venues', venue_type: 'gym', dzongkhag: 'Thimphu' } }]);
  same(sent.map((m) => m.role), ['system', 'user', 'assistant', 'user']);
  same(sent[0].content, SYSTEM_PROMPT);
  same(sent[3].content, 'and in Paro?');
});
