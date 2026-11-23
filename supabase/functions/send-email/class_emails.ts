// The emails about a class (migration 20261119000001 queues them): booked,
// changed by the gym, or cancelled by the gym. Each has a subject, a plain
// text and an HTML body with the class, its day and time, the trainer, and
// the gym, where it is (with a map link) and its phone.

export type ClassEmailKind = 'class_booked' | 'class_changed' | 'class_cancelled';

export interface ClassDetails {
  class: string;
  /** '2026-11-21'. */
  date: string;
  /** The class's day now, 1 Monday to 7 Sunday. */
  weekday?: number;
  /** '09:00', Bhutan time. */
  starts_at: string;
  minutes: number;
  trainer?: string | null;
  description?: string | null;
  /** Places in it. */
  capacity?: number;
  /** Anyone on Health Pro may book it, or the gym's members only. */
  open_to_all?: boolean;
  venue_id: string;
  gym: string;
  address?: string | null;
  phone?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  /** Who it's for. */
  name?: string | null;
  /** Cancelled: taken off the timetable, moved to another day, not held that day, or the gym cancelled the place. */
  reason?: 'off' | 'moved' | 'day' | 'gym' | null;
  /** Not held that day: the gym's note on why. */
  note?: string | null;
  /** Changed: the days they're booked on, and the class as it was. */
  dates?: string[];
  before?: {
    class: string;
    starts_at: string;
    minutes: number;
    trainer?: string | null;
    description?: string | null;
    capacity?: number;
    open_to_all?: boolean;
  };
}

export interface RenderedEmail {
  subject: string;
  text: string;
  html: string;
}

const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

function parts(iso: string): { day: number; month: number; year: number; weekday: number } {
  const [year, month, day] = iso.slice(0, 10).split('-').map(Number);
  const weekday = (new Date(Date.UTC(year, month - 1, day)).getUTCDay() + 6) % 7; // Monday 0
  return { day, month: month - 1, year, weekday };
}

/** 'Saturday, 21 November 2026'. */
export function longDate(iso: string): string {
  const p = parts(iso);
  return `${days[p.weekday]}, ${p.day} ${months[p.month]} ${p.year}`;
}

/** 'Sat 21 Nov'. */
export function shortDate(iso: string): string {
  const p = parts(iso);
  return `${days[p.weekday].slice(0, 3)} ${p.day} ${months[p.month].slice(0, 3)}`;
}

/** '9:00 AM' from '09:00'. */
export function clock(hhmm: string): string {
  const [h, m] = hhmm.split(':').map(Number);
  return `${h % 12 === 0 ? 12 : h % 12}:${String(m).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
}

/** '9:00 AM to 9:45 AM'. */
export function timeSpan(hhmm: string, minutes: number): string {
  const [h, m] = hhmm.split(':').map(Number);
  const end = (h * 60 + m + minutes) % (24 * 60);
  const endText = `${String(Math.floor(end / 60)).padStart(2, '0')}:${String(end % 60).padStart(2, '0')}`;
  return `${clock(hhmm)} to ${clock(endText)}`;
}

/** '45 minutes', '1 hour', '1 hour 30 minutes'. */
export function duration(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  const hours = h === 0 ? '' : h === 1 ? '1 hour' : `${h} hours`;
  const mins = m === 0 ? '' : `${m} minutes`;
  return [hours, mins].filter(Boolean).join(' ') || '0 minutes';
}

/** '+975 17000701'. */
export function phoneText(phone: string): string {
  return phone.replace(/^\+975(\d{8})$/, '+975 $1');
}

export function mapLink(d: ClassDetails): string | null {
  if (d.latitude == null || d.longitude == null) return null;
  return `https://www.google.com/maps/search/?api=1&query=${d.latitude},${d.longitude}`;
}

/** The gym's page in the app (the website uses /#/ addresses). */
export function gymLink(site: string, venueId: string): string {
  return `${site.replace(/\/+$/, '')}/#/gyms/${encodeURIComponent(venueId)}`;
}

function esc(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function joinDates(dates: string[]): string {
  const all = dates.map(longDate);
  return all.length <= 1 ? (all[0] ?? '') : `${all.slice(0, -1).join(', ')} and ${all[all.length - 1]}`;
}

interface Row {
  label: string;
  value: string;
  link?: { href: string; text: string } | null;
}

interface Layout {
  subject: string;
  preheader: string;
  heading: string;
  intro: string;
  changes?: { label: string; was: string; now: string }[];
  rows: Row[];
  button: { href: string; text: string };
  note: string;
  footer: string;
}

export function classEmail(kind: ClassEmailKind, d: ClassDetails, site: string): RenderedEmail {
  const greeting = d.name?.trim() ? `Hi ${d.name.trim().split(/\s+/)[0]},` : 'Hello,';
  const map = mapLink(d);
  const gymPage = gymLink(site, d.venue_id);
  const when = `${shortDate(d.date)} at ${clock(d.starts_at)}`;
  const time = `${timeSpan(d.starts_at, d.minutes)} (${duration(d.minutes)})`;
  const where: Row[] = [
    { label: 'Gym', value: d.gym },
    ...(d.address ? [{ label: 'Where', value: d.address, link: map ? { href: map, text: 'Open in Maps' } : null }] : []),
    ...(!d.address && map ? [{ label: 'Where', value: '', link: { href: map, text: 'Open in Maps' } }] : []),
    ...(d.phone ? [{ label: 'Phone', value: phoneText(d.phone), link: { href: `tel:${d.phone}`, text: 'Call' } }] : []),
  ];
  const footer = `You're getting this email because you have a place in a class at ${d.gym} on Health Pro.`;

  let layout: Layout;
  if (kind === 'class_booked') {
    layout = {
      subject: `Booked: ${d.class} on ${when}`,
      preheader: `${d.class} at ${d.gym}, ${longDate(d.date)} at ${clock(d.starts_at)}.`,
      heading: "You're booked in",
      intro: `Your place in ${d.class} at ${d.gym} is booked. Here are the details.`,
      rows: [
        { label: 'Class', value: d.class },
        { label: 'Day', value: longDate(d.date) },
        { label: 'Time', value: time },
        ...(d.trainer ? [{ label: 'Trainer', value: d.trainer }] : []),
        ...where,
      ],
      button: { href: gymPage, text: 'View the gym' },
      note: "Can't make it? Cancel your place in Health Pro before the class starts, so someone else can take it.",
      footer,
    };
  } else if (kind === 'class_changed') {
    const b = d.before ?? { class: d.class, starts_at: d.starts_at, minutes: d.minutes, trainer: d.trainer };
    const dates = d.dates?.length ? d.dates : [d.date];
    const changes: NonNullable<Layout['changes']> = [];
    const timeChanged = b.starts_at !== d.starts_at || b.minutes !== d.minutes;
    if (b.class !== d.class) changes.push({ label: 'Class', was: b.class, now: d.class });
    if (timeChanged) changes.push({ label: 'Time', was: timeSpan(b.starts_at, b.minutes), now: timeSpan(d.starts_at, d.minutes) });
    if ((b.trainer ?? '') !== (d.trainer ?? '')) {
      changes.push({ label: 'Trainer', was: b.trainer || 'None', now: d.trainer || 'None' });
    }
    // Emails queued before 20261119000002 don't have these: left out then.
    if (b.capacity != null && d.capacity != null && b.capacity !== d.capacity) {
      changes.push({ label: 'Places', was: String(b.capacity), now: String(d.capacity) });
    }
    if (typeof b.open_to_all === 'boolean' && typeof d.open_to_all === 'boolean' && b.open_to_all !== d.open_to_all) {
      const who = (open: boolean) => (open ? 'Everyone on Health Pro' : "The gym's members only");
      changes.push({ label: 'Who can book', was: who(b.open_to_all), now: who(d.open_to_all) });
    }
    if (b.description !== undefined && (b.description ?? '') !== (d.description ?? '')) {
      const was = b.description || 'None';
      changes.push({ label: 'About', was: was.length > 80 ? `${was.slice(0, 79).trimEnd()}…` : was, now: d.description || 'None' });
    }
    const first = shortDate(dates[0]) + (dates.length > 1 ? ' and after' : '');
    layout = {
      subject: timeChanged
        ? `New time for ${b.class}: ${clock(d.starts_at)}, ${first}`
        : `${b.class} has changed: ${first}`,
      preheader: changes.length
        ? changes.map((c) => `${c.label}: now ${c.now}`).join('. ') + '.'
        : `${d.gym} has changed ${b.class}.`,
      heading: 'Your class has changed',
      intro: `${d.gym} has changed ${b.class}, which you're booked into. Your place is kept.`,
      changes,
      rows: [
        { label: 'Class', value: d.class },
        { label: dates.length > 1 ? 'Your days' : 'Day', value: joinDates(dates) },
        { label: 'Time', value: time },
        ...(d.trainer ? [{ label: 'Trainer', value: d.trainer }] : []),
        ...where,
      ],
      button: { href: gymPage, text: 'View the gym' },
      note: "If the new details don't suit you, cancel your place in Health Pro, so someone else can take it.",
      footer,
    };
  } else {
    const day = longDate(d.date);
    const intro = d.reason === 'off'
      ? `${d.gym} has taken ${d.class} off its timetable, so your place on ${day} was cancelled.`
      : d.reason === 'moved' && d.weekday
      ? `${d.gym} has moved ${d.class} to ${days[d.weekday - 1]}s, so your place on ${day} was cancelled. You can book it on its new day.`
      : d.reason === 'day'
      ? `${d.gym} isn't holding ${d.class} on ${day}, so your place was cancelled.${d.note ? ` ${d.note}` : ''}`
      : `${d.gym} has cancelled your place in ${d.class} on ${day}.`;
    layout = {
      subject: `Cancelled: ${d.class} on ${shortDate(d.date)} at ${d.gym}`,
      preheader: intro,
      heading: 'Your place was cancelled',
      intro,
      rows: [
        { label: 'Class', value: d.class },
        { label: 'Day', value: day },
        ...where,
      ],
      button: { href: gymPage, text: "See the gym's classes" },
      note: d.phone
        ? `Questions? Call ${d.gym} on ${phoneText(d.phone)}. You can book another class in Health Pro.`
        : 'You can book another class in Health Pro.',
      footer,
    };
  }
  return { subject: layout.subject, text: text(greeting, layout), html: html(greeting, layout) };
}

function text(greeting: string, l: Layout): string {
  const width = Math.max(...l.rows.map((r) => r.label.length)) + 2;
  const lines = [greeting, '', l.intro, ''];
  if (l.changes?.length) {
    lines.push('What changed:');
    for (const c of l.changes) lines.push(`  ${c.label}: ${c.was} -> now ${c.now}`);
    lines.push('');
  }
  for (const r of l.rows) {
    const value = [r.value, r.link && r.link.text === 'Open in Maps' ? r.link.href : ''].filter(Boolean).join(' ');
    lines.push(`${(r.label + ':').padEnd(width)}${value}`);
  }
  lines.push('', `${l.button.text}: ${l.button.href}`, '', l.note, '', 'Health Pro', '', '--', l.footer, '');
  return lines.join('\n');
}

// Inline styles and tables only: what every email app shows the same.
const ink = '#111827';
const body = '#374151';
const muted = '#6b7280';
const brand = '#ff790f';
const action = '#c2410c';
const font = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif";

function html(greeting: string, l: Layout): string {
  const rows = l.rows.map((r, i) => {
    const border = i === 0 ? '' : 'border-top:1px solid #e5e7eb;';
    const link = r.link
      ? `${r.value ? '<br>' : ''}<a href="${esc(r.link.href)}" style="color:${action};font-weight:600;font-size:13px;text-decoration:none;">${esc(r.link.text)}</a>`
      : '';
    return `<tr>
          <td valign="top" style="${border}padding:11px 16px;width:84px;font-size:13px;color:${muted};">${esc(r.label)}</td>
          <td valign="top" style="${border}padding:11px 16px;font-size:15px;line-height:1.45;color:${ink};font-weight:600;">${esc(r.value)}${link}</td>
        </tr>`;
  }).join('\n        ');
  const changes = l.changes?.length
    ? `<tr><td style="padding:20px 28px 0;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:separate;background:#fff7ed;border:1px solid #fed7aa;border-radius:12px;">
        <tr><td style="padding:14px 16px 4px;font-size:12px;font-weight:700;letter-spacing:.6px;text-transform:uppercase;color:${action};">What changed</td></tr>
        ${l.changes.map((c) => `<tr><td style="padding:4px 16px 12px;font-size:14px;line-height:1.5;color:${body};">
          <span style="color:${muted};">${esc(c.label)}:</span>
          <span style="text-decoration:line-through;color:${muted};">${esc(c.was)}</span>
          &rarr; <strong style="color:${ink};">${esc(c.now)}</strong></td></tr>`).join('\n        ')}
      </table>
    </td></tr>`
    : '';
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<title>${esc(l.subject)}</title>
</head>
<body style="margin:0;padding:0;background:#f3f4f6;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${esc(l.preheader)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f3f4f6;">
  <tr><td align="center" style="padding:24px 12px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border:1px solid #e5e7eb;border-radius:16px;font-family:${font};">
      <tr><td style="height:6px;line-height:6px;font-size:0;background:${brand};border-radius:16px 16px 0 0;">&nbsp;</td></tr>
      <tr><td style="padding:22px 28px 0;font-size:15px;font-weight:800;color:${action};letter-spacing:.2px;">Health Pro</td></tr>
      <tr><td style="padding:14px 28px 0;">
        <h1 style="margin:0;font-size:22px;line-height:1.3;color:${ink};">${esc(l.heading)}</h1>
        <p style="margin:14px 0 0;font-size:15px;line-height:1.6;color:${body};">${esc(greeting)}</p>
        <p style="margin:8px 0 0;font-size:15px;line-height:1.6;color:${body};">${esc(l.intro)}</p>
      </td></tr>
      ${changes}
      <tr><td style="padding:20px 28px 0;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:separate;background:#f9fafb;border:1px solid #e5e7eb;border-radius:12px;">
        ${rows}
        </table>
      </td></tr>
      <tr><td style="padding:24px 28px 0;">
        <a href="${esc(l.button.href)}" style="display:inline-block;background:${action};color:#ffffff;text-decoration:none;font-weight:700;font-size:15px;padding:12px 22px;border-radius:10px;">${esc(l.button.text)}</a>
      </td></tr>
      <tr><td style="padding:20px 28px 28px;font-size:14px;line-height:1.6;color:${body};">${esc(l.note)}</td></tr>
    </table>
    <p style="max-width:560px;margin:16px auto 0;font-family:${font};font-size:12px;line-height:1.5;color:#9ca3af;">${esc(l.footer)}</p>
  </td></tr>
</table>
</body>
</html>
`;
}
