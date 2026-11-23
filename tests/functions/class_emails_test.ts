// The emails about a class (supabase/functions/send-email/class_emails.ts):
// booked, changed by the gym, cancelled by the gym.
//
//   deno test tests/functions/
import {
  classEmail,
  type ClassDetails,
  clock,
  duration,
  longDate,
  timeSpan,
} from '../../supabase/functions/send-email/class_emails.ts';

function same(actual: unknown, expected: unknown) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`got ${a}\nexpected ${e}`);
}

function has(text: string, ...parts: string[]) {
  for (const p of parts) if (!text.includes(p)) throw new Error(`no "${p}" in:\n${text}`);
}

const site = 'https://myhealthpro.pages.dev';
const spin: ClassDetails = {
  class: 'Spin',
  date: '2026-11-21',
  weekday: 6,
  starts_at: '09:00',
  minutes: 45,
  trainer: 'Tashi',
  venue_id: 'g1',
  gym: 'Coach Gym',
  address: 'Norzin Lam, Thimphu',
  phone: '+97517000701',
  latitude: 27.4728,
  longitude: 89.639,
  name: 'Xo Out',
};

Deno.test('days and times as people say them', () => {
  same(longDate('2026-11-21'), 'Saturday, 21 November 2026');
  same([clock('00:30'), clock('09:00'), clock('12:00'), clock('18:45')], ['12:30 AM', '9:00 AM', '12:00 PM', '6:45 PM']);
  same(timeSpan('23:30', 60), '11:30 PM to 12:30 AM');
  same([duration(45), duration(60), duration(90), duration(120)], ['45 minutes', '1 hour', '1 hour 30 minutes', '2 hours']);
});

Deno.test('booked: the class, day, time, trainer, gym, where it is and its phone', () => {
  const e = classEmail('class_booked', spin, site);
  same(e.subject, 'Booked: Spin on Sat 21 Nov at 9:00 AM');
  has(e.text, 'Hi Xo,', 'Your place in Spin at Coach Gym is booked.', 'Saturday, 21 November 2026', '9:00 AM to 9:45 AM (45 minutes)',
    'Trainer:', 'Tashi', 'Coach Gym', 'Norzin Lam, Thimphu https://www.google.com/maps/search/?api=1&query=27.4728,89.639',
    '+975 17000701', 'View the gym: https://myhealthpro.pages.dev/#/gyms/g1');
  has(e.html, '>You&#39;re booked in<', 'Tashi', 'Norzin Lam, Thimphu', 'Open in Maps', 'href="https://myhealthpro.pages.dev/#/gyms/g1"',
    'href="tel:+97517000701"');
});

Deno.test('booked without a trainer, address or name: those lines are left out', () => {
  const e = classEmail('class_booked', { ...spin, trainer: null, address: null, latitude: null, longitude: null, phone: null, name: null },
    site);
  has(e.text, 'Hello,');
  for (const gone of ['Trainer', 'Where', 'Phone', 'maps']) if (e.text.includes(gone)) throw new Error(`"${gone}" in:\n${e.text}`);
});

Deno.test('what the gym typed is never taken as HTML', () => {
  const e = classEmail('class_booked', { ...spin, gym: '<b>Gym & Co</b>', class: 'Yoga "flow"' }, site);
  has(e.html, '&lt;b&gt;Gym &amp; Co&lt;/b&gt;', 'Yoga &quot;flow&quot;');
  if (e.html.includes('<b>Gym')) throw new Error('raw HTML from the gym');
});

Deno.test('changed: what changed, for each day they\'re booked', () => {
  const e = classEmail('class_changed', {
    ...spin,
    starts_at: '10:00',
    trainer: 'Kinley',
    dates: ['2026-11-21', '2026-11-28'],
    before: { class: 'Spin', starts_at: '09:00', minutes: 45, trainer: 'Tashi' },
  }, site);
  same(e.subject, 'New time for Spin: 10:00 AM, Sat 21 Nov and after');
  has(e.text, 'Coach Gym has changed Spin, which you\'re booked into. Your place is kept.',
    'Time: 9:00 AM to 9:45 AM -> now 10:00 AM to 10:45 AM', 'Trainer: Tashi -> now Kinley',
    'Your days:', 'Saturday, 21 November 2026 and Saturday, 28 November 2026');
  has(e.html, 'What changed', '<strong style="color:#111827;">10:00 AM to 10:45 AM</strong>');
  same(classEmail('class_changed', { ...spin, trainer: 'Kinley', before: { class: 'Spin', starts_at: '09:00', minutes: 45, trainer: 'Tashi' } },
    site).subject, 'Spin has changed: Sat 21 Nov');
});

Deno.test('changed: places, who can book, and what it\'s about', () => {
  const before = { class: 'Spin', starts_at: '09:00', minutes: 45, trainer: 'Tashi', description: null, capacity: 5, open_to_all: true };
  const e = classEmail('class_changed', { ...spin, before, description: 'Bring water', capacity: 8, open_to_all: false }, site);
  same(e.subject, 'Spin has changed: Sat 21 Nov');
  has(e.text, 'Places: 5 -> now 8', "Who can book: Everyone on Health Pro -> now The gym's members only", 'About: None -> now Bring water');
  if (e.text.includes('  Time:')) throw new Error('the time didn\'t change');
  // Queued before places and who can book were sent: those are left out.
  const old = classEmail('class_changed', { ...spin, trainer: 'Kinley', capacity: 8, open_to_all: false,
    before: { class: 'Spin', starts_at: '09:00', minutes: 45, trainer: 'Tashi' } }, site);
  for (const gone of ['Places', 'Who can book', 'About']) if (old.text.includes(gone)) throw new Error(`"${gone}" in:\n${old.text}`);
});

Deno.test('cancelled: why, and where to book another', () => {
  same(classEmail('class_cancelled', { ...spin, reason: 'gym' }, site).subject, 'Cancelled: Spin on Sat 21 Nov at Coach Gym');
  has(classEmail('class_cancelled', { ...spin, reason: 'moved', weekday: 2 }, site).text,
    'Coach Gym has moved Spin to Tuesdays, so your place on Saturday, 21 November 2026 was cancelled.');
  has(classEmail('class_cancelled', { ...spin, reason: 'off' }, site).text, 'has taken Spin off its timetable',
    'Questions? Call Coach Gym on +975 17000701.');
  has(classEmail('class_cancelled', { ...spin, reason: 'day', note: 'Public holiday.' }, site).text,
    'Coach Gym isn\'t holding Spin on Saturday, 21 November 2026, so your place was cancelled. Public holiday.');
});
