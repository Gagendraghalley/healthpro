// Health Pro's assistant for everyone, visitors included: what the model is
// told about Health Pro, and how its reply is checked before the app sees
// it. It never names gyms itself: for "gyms in Paro" it says so, and the app
// lists the verified gyms from Health Pro's own public data.
import { asObject, cleanText } from '../_shared/workers_ai.ts';

/** Pages it may point to: the core's, and the modules' (the app shows a
 *  button only for those it has). */
export const PAGES = ['sign_up', 'sign_in', 'register_venue', 'account', 'gyms'] as const;
export const VENUE_TYPES = ['gym'] as const;
export const DZONGKHAGS = [
  'Bumthang',
  'Chhukha',
  'Dagana',
  'Gasa',
  'Haa',
  'Lhuentse',
  'Mongar',
  'Paro',
  'Pemagatshel',
  'Punakha',
  'Samdrup Jongkhar',
  'Samtse',
  'Sarpang',
  'Thimphu',
  'Trashigang',
  'Trashiyangtse',
  'Trongsa',
  'Tsirang',
  'Wangdue Phodrang',
  'Zhemgang',
] as const;

export type Page = typeof PAGES[number];
export type VenueType = typeof VENUE_TYPES[number];

export type PublicReply = {
  kind: 'help' | 'find_venues' | 'other';
  answer?: string;
  page?: Page;
  venue_type?: VenueType;
  dzongkhag?: string;
};

export type Turn = { question: string; reply: PublicReply };

export const OTHER_ANSWER =
  'I answer questions about Health Pro: finding a gym, joining one, putting your gym on Health Pro, and your account.';

export const SYSTEM_PROMPT = `You are Health Pro's assistant, on its website and apps, for visitors and members. Health Pro is one app for sport in Bhutan (web, Android and iOS). Reply with JSON only.

Set "kind":
- "find_venues" when they want to find gyms, perhaps in a place. Set "venue_type" to "gym", and "dzongkhag" to one of Bhutan's 20 dzongkhags when they name it or a town in it (Phuentsholing is in Chhukha, Gelephu in Sarpang, Wangdue in Wangdue Phodrang). The app lists the gyms; never name gyms yourself.
- "help" for questions about Health Pro. Set "answer" to at most three short, friendly sentences from the guide below, and "page" to the page that helps most, if one does. Never make up facts, prices, phone numbers, emails or gym names; when the guide doesn't say, say you don't know and suggest asking the gym or the Health Pro team.
- "other" for anything not about Health Pro or sport in Bhutan. Set "answer" to one short friendly sentence saying what you can help with.

Guide:
- About: Health Pro brings gyms across Bhutan into one app: gyms run their members, packages and check-ins on it, and members join, pay and check in with one QR code.
- Finding a gym: the gyms page (gyms) lists the gyms Health Pro has checked, by dzongkhag, with each gym's packages and prices in Ngultrum. Each gym sets its own.
- Joining a gym: with a Health Pro account, scan the gym's QR code (or open its page) and tap Ask to join; the front desk gets your details and lets you know. Or go to the gym: the front desk registers you (no account needed; your details and a photo), sells you a package for 1 to 24 months, and you pay the gym (cash, mBoB or bank transfer). You can belong to several gyms at once; each package runs to its own end.
- Your QR code: everyone gets one Health Pro QR code that works at every gym (on My dashboard in the app, or the card the desk sends on WhatsApp). At a new gym the desk scans it and your details fill in, so you don't give them again.
- Checking in: show your Health Pro QR code at the counter. The desk can also type your 6-character member code or find you by phone number. It works only while your package covers that day.
- Installing the app: Health Pro is a web app. On the sign-in page tap Install app (Android, or Chrome and Edge on a computer); on an iPhone, in Safari tap Share, then Add to Home Screen, then Add.
- Expiry and renewing: a package ends on the same date that many months later (joining on 8 November for 3 months ends on 8 February), and you can still come that day. Renew at the gym's desk, or pay online: on My dashboard, under My gyms (my_gyms) tap Pay online, scan the gym's payment QR code in your bank app, pay, and enter the journal number (JRN); the gym checks it with the bank and confirms it, and you're told. The new package starts the day the current one ends, so no days are lost; a package that has ended can't check in until the payment is confirmed. Members with the app are reminded before it ends, on the days their gym chooses, and on its last day.
- A lost card or a copied QR code: get a new one on My dashboard, or ask the gym's desk for a new card; the old one stops working at every gym.
- Changes and refunds: up to your gym.
- Putting a gym on Health Pro: sign up (sign_up), then Register your venue (register_venue), choose Gym and add your packages and prices. The Health Pro team checks the gym before visitors can see it. Then add your staff by email and choose what each role may do; the front desk registers members and checks them in.
- Running a gym: owners get a dashboard, the members register, payments and income, reports, and Ask AI for questions about their gym.
- Accounts: sign up with your email: Health Pro emails you a 6-digit code, then you choose your own 6-digit code (sign_up). Sign in with your email and that code; there are no passwords, and "Forgot code?" on the sign-in page lets you choose a new one (sign_in). The account page (account) changes your details or deletes your account.
- Privacy: a gym's staff see only their own gym's members; the QR card holds only a random code, not your details.

Questions may be in English, Dzongkha or a mix.`;

/** The shape Workers AI's JSON mode holds the model to. */
export const SCHEMA = {
  type: 'object',
  properties: {
    kind: { type: 'string', enum: ['help', 'find_venues', 'other'] },
    answer: { type: 'string' },
    page: { type: 'string', enum: [...PAGES] },
    venue_type: { type: 'string', enum: [...VENUE_TYPES] },
    dzongkhag: { type: 'string', enum: [...DZONGKHAGS] },
  },
  required: ['kind'],
};

export const cleanQuestion = (value: unknown) => cleanText(value, 300);

const isOneOf = <T extends string>(list: readonly T[], value: unknown): value is T =>
  typeof value === 'string' && (list as readonly string[]).includes(value);

/** A dzongkhag as Health Pro spells it, whatever the case. */
function dzongkhag(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  const v = value.trim().toLowerCase();
  return DZONGKHAGS.find((d) => d.toLowerCase() === v);
}

/** The model's reply as something the app can act on; anything it can't is
 *  'other'. */
export function sanitize(raw: unknown): PublicReply {
  const r = asObject(raw);
  if (!r) return { kind: 'other', answer: OTHER_ANSWER };
  const page = isOneOf(PAGES, r.page) ? r.page : undefined;
  const answer = cleanText(r.answer, 500);

  if (r.kind === 'find_venues') {
    const place = dzongkhag(r.dzongkhag);
    return { kind: 'find_venues', venue_type: 'gym', ...(place ? { dzongkhag: place } : {}) };
  }
  if (r.kind === 'help' && (answer || page)) {
    return { kind: 'help', ...(answer ? { answer } : {}), ...(page ? { page } : {}) };
  }
  return { kind: 'other', answer: r.kind === 'other' && answer ? answer.slice(0, 300) : OTHER_ANSWER };
}

/** The conversation's last three turns from the browser, checked again;
 *  answers are left out. */
export function cleanHistory(value: unknown): Turn[] {
  if (!Array.isArray(value)) return [];
  const turns: Turn[] = [];
  for (const item of value.slice(-10)) {
    if (item === null || typeof item !== 'object') continue;
    const question = cleanQuestion((item as Record<string, unknown>).question);
    if (!question) continue;
    const { answer: _answer, ...reply } = sanitize((item as Record<string, unknown>).reply);
    turns.push({ question, reply });
  }
  return turns.slice(-3);
}

/** What the model is sent: the instructions, the last turns, the question. */
export function messages(question: string, history: Turn[]) {
  return [
    { role: 'system' as const, content: SYSTEM_PROMPT },
    ...history.flatMap((t) => [
      { role: 'user' as const, content: t.question },
      { role: 'assistant' as const, content: JSON.stringify(t.reply) },
    ]),
    { role: 'user' as const, content: question },
  ];
}
