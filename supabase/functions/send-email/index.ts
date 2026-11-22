// Sends the emails the database queues (private.email_outbox, migration
// 20261119000001): about a class someone has a place in, when it's booked,
// changed by the gym, or cancelled by the gym.
//
//   { send: true }    -> { sent, failed }   (the database, when it queues some)
//   { setup: true }   -> { configured }     (scripts/deploy_supabase.sh, each deploy)
//
// Anyone can call it, so it takes nothing from the caller: it claims what's
// waiting (email_claim_pending: each email by one call only), sends it over
// one SMTP connection, and says how each went (email_finish); one that
// failed is tried again with the next ones.
//
// Secrets: SMTP_HOST, SMTP_USER, SMTP_PASS, and SMTP_PORT, SMTP_FROM (see
// _shared/smtp.ts); SITE_URL, the website for links (myhealthpro.pages.dev
// by default). Without SMTP, setup tells the database, and nothing is queued.
// Deploy: supabase functions deploy send-email (verify_jwt off: the database
// calls it).
import { createClient } from 'npm:@supabase/supabase-js@2';

import { deliver, type Outgoing, SmtpSession, smtpFromEnv } from '../_shared/smtp.ts';
import { classEmail, type ClassDetails, type ClassEmailKind } from './class_emails.ts';

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

interface Queued {
  id: string;
  to: string;
  kind: ClassEmailKind;
  data: ClassDetails;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Use POST' }, 405);
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Send JSON' }, 400);
  }

  const url = Deno.env.get('SUPABASE_URL')!;
  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
  const smtp = smtpFromEnv();

  // Tells the database where this function is (its own address, never the
  // caller's), or that there's no SMTP to send with.
  if (body.setup === true) {
    const address = smtp ? `${url.replace(/\/$/, '')}/functions/v1/send-email` : null;
    const { error } = await admin.rpc('email_configure', { function_url: address });
    if (error) return json({ error: error.message }, 500);
    return json({ configured: smtp != null });
  }

  if (!smtp) return json({ error: 'Email is not set up', code: 'not_set_up' }, 503);
  if (body.send !== true) return json({ error: 'Send {"send": true}' }, 400);
  const site = (Deno.env.get('SITE_URL') || 'https://myhealthpro.pages.dev').replace(/\/+$/, '');

  let sent = 0;
  let failed = 0;
  // What's waiting, a batch at a time, a few batches at most per call.
  for (let round = 0; round < 4; round++) {
    const { data, error } = await admin.rpc('email_claim_pending', { max_count: 25 });
    if (error) {
      console.error('send-email: claim failed', error.message);
      return json({ error: 'Could not read the emails waiting' }, 500);
    }
    const batch = (data ?? []) as Queued[];
    if (!batch.length) break;
    const outgoing: Outgoing[] = [];
    const unreadable: { id: string; error: string }[] = [];
    for (const q of batch) {
      try {
        outgoing.push({ id: q.id, mail: { to: q.to, ...classEmail(q.kind, q.data, site) } });
      } catch (e) {
        unreadable.push({ id: q.id, error: `Could not write it: ${e instanceof Error ? e.message : e}` });
      }
    }
    const result = await deliver(outgoing, () => SmtpSession.open(smtp));
    const failures = [...unreadable, ...result.failed];
    for (const f of failures) console.warn(`send-email: ${f.id} not sent: ${f.error}`);
    const { error: finishError } = await admin.rpc('email_finish', { sent_ids: result.sent, failures });
    if (finishError) console.error('send-email: finish failed', finishError.message);
    sent += result.sent.length;
    failed += failures.length;
    if (failures.length === batch.length) break; // the server isn't taking any: wait for the next try
  }
  return json({ sent, failed });
});
