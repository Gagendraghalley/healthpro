// Firebase Cloud Messaging (HTTP v1), on WebCrypto alone (no library):
// sending a notification to the Android and iOS apps.
//
// Secret:
//   FCM_SERVICE_ACCOUNT  the Firebase project's service account key: the JSON
//                        file as downloaded (Project settings -> Service
//                        accounts -> Generate new private key), or that file in
//                        base64 (scripts/deploy_supabase.sh stores it so).
//
// Each send carries an OAuth access token: a JWT signed with the service
// account's private key (RS256), exchanged at Google's token address and kept
// for its hour, less a margin.
//
// A phone's address is its Firebase Installation ID (FID), FCM's replacement
// for registration tokens (push_devices.token): sent as message.fid.

import { b64urlEncode } from './web_push.ts';

export interface ServiceAccount {
  projectId: string;
  clientEmail: string;
  /** PKCS #8, PEM. */
  privateKey: string;
}

/** A phone app that turned notifications on (push_devices). */
export interface Device {
  token: string;
  platform: string;
}

/** What goes out: a notification's id, title, text and page. */
export interface Note {
  id: string;
  title: string;
  body: string;
  link: string;
}

/** sent; gone (FCM says this phone's app is no more: forget it); or failed. */
export type Outcome = 'sent' | 'gone' | 'failed';

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
/** As long as web push keeps one (send-push's web_push.ts): a day. */
const TTL_SECONDS = 86400;

const text = new TextEncoder();
const bs = (bytes: Uint8Array) => bytes as unknown as BufferSource;

/** The service account key [json] (or that file in base64). Throws when it
 *  isn't one. */
export function parseServiceAccount(json: string): ServiceAccount {
  const raw = json.trim();
  const decoded = raw.startsWith('{') ? raw : new TextDecoder().decode(Uint8Array.from(atob(raw), (c) => c.charCodeAt(0)));
  const key = JSON.parse(decoded);
  if (key?.type !== 'service_account' || !key.project_id || !key.client_email || !key.private_key) {
    throw new Error('Not a service account key');
  }
  return { projectId: key.project_id, clientEmail: key.client_email, privateKey: key.private_key };
}

/** The service account from the function's secrets; null when phone push
 *  isn't set up. */
export function fcmFromEnv(): ServiceAccount | null {
  const raw = Deno.env.get('FCM_SERVICE_ACCOUNT');
  if (!raw) return null;
  try {
    return parseServiceAccount(raw);
  } catch {
    console.error('send-push: FCM_SERVICE_ACCOUNT is not a service account key');
    return null;
  }
}

function pemToDer(pem: string): Uint8Array {
  const b64 = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '').replace(/\s+/g, '');
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

/** The signed JWT Google exchanges for an access token: for FCM only, valid
 *  an hour. */
export async function assertion(account: ServiceAccount, now = Date.now()): Promise<string> {
  const iat = Math.floor(now / 1000);
  const head = b64urlEncode(text.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const claims = b64urlEncode(text.encode(JSON.stringify({ iss: account.clientEmail, scope: SCOPE, aud: TOKEN_URL, iat, exp: iat + 3600 })));
  const key = await crypto.subtle.importKey(
    'pkcs8',
    bs(pemToDer(account.privateKey)),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, bs(text.encode(`${head}.${claims}`))));
  return `${head}.${claims}.${b64urlEncode(signature)}`;
}

let cached: { email: string; token: string; until: number } | null = null;

/** The next send asks Google for a new access token (FCM refused this one). */
export function forgetAccessToken() {
  cached = null;
}

/** An access token for FCM: kept while it's good, five minutes to spare. */
export async function accessToken(account: ServiceAccount, fetcher: typeof fetch = fetch, now = Date.now()): Promise<string> {
  if (cached && cached.email === account.clientEmail && now < cached.until) return cached.token;
  const res = await fetcher(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: await assertion(account, now),
    }),
  });
  if (!res.ok) {
    const detail = (await res.text()).slice(0, 200);
    throw new Error(`Google refused the service account (${res.status}): ${detail}`);
  }
  const body = await res.json();
  if (typeof body.access_token !== 'string') throw new Error('Google sent no access token');
  const seconds = typeof body.expires_in === 'number' ? body.expires_in : 3600;
  cached = { email: account.clientEmail, token: body.access_token, until: now + (seconds - 300) * 1000 };
  return cached.token;
}

/** FCM's message for [device]: the phone shows it as a notification (even
 *  when Health Pro is closed); [note]'s id and page come along as data, for
 *  the app to open on a tap. */
export function fcmMessage(device: Device, note: Note, now = Date.now()) {
  return {
    message: {
      fid: device.token,
      notification: { title: note.title, body: note.body },
      data: { id: note.id, link: note.link },
      android: {
        priority: 'HIGH',
        ttl: `${TTL_SECONDS}s`,
        // The same notification never shows twice; the app's own channel
        // (Android keeps its default one until the app makes it).
        notification: { tag: note.id, channel_id: 'health_pro', default_sound: true },
      },
      apns: {
        headers: {
          'apns-priority': '10',
          'apns-expiration': String(Math.floor(now / 1000) + TTL_SECONDS),
          'apns-collapse-id': note.id,
        },
        payload: { aps: { sound: 'default' } },
      },
    },
  };
}

/** What FCM's answer means for the phone: gone only when FCM says the app
 *  is unregistered, or that this address isn't one; any other refusal (our
 *  request, our account, FCM busy) leaves the phone alone. */
export function outcomeOf(status: number, answer: unknown): Outcome {
  if (status >= 200 && status < 300) return 'sent';
  if (status === 404) return 'gone';
  // deno-lint-ignore no-explicit-any
  const details: any[] = (answer as any)?.error?.details ?? [];
  if (details.some((d) => d?.errorCode === 'UNREGISTERED')) return 'gone';
  const badAddress = details.some((d) =>
    // deno-lint-ignore no-explicit-any
    (d?.fieldViolations ?? []).some((v: any) => v?.field === 'message.fid' || v?.field === 'message.token')
  );
  return status === 400 && badAddress ? 'gone' : 'failed';
}

/** Sends [note] to one phone app. On FCM refusing the access token (401),
 *  asks Google for a new one and tries once more. */
export async function sendFcm(account: ServiceAccount, device: Device, note: Note, fetcher: typeof fetch = fetch): Promise<Outcome> {
  const url = `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.projectId)}/messages:send`;
  const body = JSON.stringify(fcmMessage(device, note));
  for (let attempt = 0; attempt < 2; attempt++) {
    const res = await fetcher(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${await accessToken(account, fetcher)}` },
      body,
    });
    if (res.status === 401 && attempt === 0) {
      await res.body?.cancel();
      forgetAccessToken();
      continue;
    }
    const answer = res.ok ? (await res.body?.cancel(), null) : await res.json().catch(() => null);
    const outcome = outcomeOf(res.status, answer);
    if (outcome === 'failed') {
      // deno-lint-ignore no-explicit-any
      console.warn(`send-push: FCM answered ${res.status} ${(answer as any)?.error?.status ?? ''}`.trim());
    }
    return outcome;
  }
  return 'failed';
}
