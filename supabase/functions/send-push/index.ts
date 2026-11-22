// Sends a notification to its person's browsers (web push) and to their
// Android and iOS apps (Firebase Cloud Messaging).
//
//   { notification_id }   -> { sent, removed }          (the database, for each new one)
//   { setup: true }       -> { configured, keys, fcm }  (scripts/deploy_supabase.sh)
//
// The database calls it for every new notification (the notifications_push
// trigger, through pg_net). Anyone can call it, so it takes nothing from the
// caller but an id: it sends a notification only once, only one made in the
// last 15 minutes, and only to that notification's own person
// (push_claim_notification). Browsers and phones their push service says are
// gone are forgotten.
//
// Secrets, each optional (without one, that kind of device is skipped):
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT: web push (see
//     _shared/web_push.ts; scripts/make_push_keys.ts makes the keys).
//   FCM_SERVICE_ACCOUNT: the phone apps (see _shared/fcm.ts).
// Deploy: supabase functions deploy send-push (verify_jwt off: the database
// calls it).
import { createClient } from 'npm:@supabase/supabase-js@2';

import { type Device, fcmFromEnv, sendFcm } from '../_shared/fcm.ts';
import { sendWebPush, type Subscription, vapidFromEnv } from '../_shared/web_push.ts';

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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

  // Tells the database where this function is: its own address, never the
  // caller's.
  if (body.setup === true) {
    const { error } = await admin.rpc('push_configure', { function_url: `${url.replace(/\/$/, '')}/functions/v1/send-push` });
    if (error) return json({ error: error.message }, 500);
    return json({ configured: true, keys: vapidFromEnv() != null, fcm: fcmFromEnv() != null });
  }

  const vapid = vapidFromEnv();
  const fcm = fcmFromEnv();
  if (!vapid && !fcm) return json({ error: 'Push notifications are not set up', code: 'not_set_up' }, 503);
  const id = body.notification_id;
  if (typeof id !== 'string' || !uuid.test(id)) return json({ error: 'Send notification_id' }, 400);

  const { data, error } = await admin.rpc('push_claim_notification', { notification_id: id });
  if (error) {
    console.error('send-push: claim failed', error.message);
    return json({ error: 'Could not read the notification' }, 500);
  }
  if (!data) return json({ sent: 0, removed: 0 }); // sent already, too old, or none

  const note = { id, title: data.title as string, body: (data.body ?? '') as string, link: (data.link ?? '/notifications') as string };
  let sent = 0;
  const gone: string[] = [];
  if (vapid) {
    const message = JSON.stringify(note);
    for (const sub of (data.subscriptions ?? []) as Subscription[]) {
      try {
        const status = await sendWebPush(sub, message, vapid);
        if (status === 404 || status === 410) gone.push(sub.endpoint);
        else if (status >= 200 && status < 300) sent++;
        else console.warn(`send-push: ${new URL(sub.endpoint).host} answered ${status}`);
      } catch (e) {
        console.error('send-push: sending failed', e);
      }
    }
  }
  const goneDevices: string[] = [];
  if (fcm) {
    for (const device of (data.devices ?? []) as Device[]) {
      try {
        const outcome = await sendFcm(fcm, device, note);
        if (outcome === 'sent') sent++;
        else if (outcome === 'gone') goneDevices.push(device.token);
      } catch (e) {
        console.error('send-push: FCM sending failed', e);
      }
    }
  }
  if (gone.length) await admin.rpc('push_forget_subscriptions', { endpoints: gone });
  if (goneDevices.length) await admin.rpc('push_forget_devices', { tokens: goneDevices });
  return json({ sent, removed: gone.length + goneDevices.length });
});
