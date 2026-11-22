// Firebase Cloud Messaging without a library (supabase/functions/_shared/fcm.ts):
// the service account's JWT as Google would check it, the access token kept
// for its hour, the message the phones get, and what FCM's answers mean for
// the phone. Google is played by a fake fetch: nothing goes out.
//
//   deno test tests/functions
import {
  accessToken,
  assertion,
  fcmMessage,
  forgetAccessToken,
  outcomeOf,
  parseServiceAccount,
  sendFcm,
  type ServiceAccount,
} from '../../supabase/functions/_shared/fcm.ts';
import { b64urlDecode } from '../../supabase/functions/_shared/web_push.ts';

function same(actual: unknown, expected: unknown, label = '') {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${label}\n  got:      ${a}\n  expected: ${e}`);
}

const bs = (bytes: Uint8Array) => bytes as unknown as BufferSource;

/** A service account of our own: its key pair, and the JSON file as Firebase
 *  hands it out. */
async function serviceAccount(): Promise<{ pair: CryptoKeyPair; json: string; account: ServiceAccount }> {
  const pair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true,
    ['sign', 'verify'],
  ) as CryptoKeyPair;
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der)).match(/.{1,64}/g)!.join('\n')}\n-----END PRIVATE KEY-----\n`;
  const json = JSON.stringify({
    type: 'service_account',
    project_id: 'health-pro-test',
    private_key_id: 'abc123',
    private_key: pem,
    client_email: 'firebase-adminsdk@health-pro-test.iam.gserviceaccount.com',
    token_uri: 'https://oauth2.googleapis.com/token',
  }, null, 2);
  return { pair, json, account: parseServiceAccount(json) };
}

/** Google, faked: the token address hands out ya29.token-1, -2...; FCM gives
 *  [answers] in turn. */
function google(answers: Response[]) {
  let tokens = 0;
  const sends: { url: string; auth: string | null; body: Record<string, unknown> }[] = [];
  const fetcher = ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    if (url === 'https://oauth2.googleapis.com/token') {
      tokens++;
      return Promise.resolve(Response.json({ access_token: `ya29.token-${tokens}`, expires_in: 3600, token_type: 'Bearer' }));
    }
    sends.push({ url, auth: new Headers(init?.headers).get('Authorization'), body: JSON.parse(String(init?.body)) });
    const answer = answers.shift();
    if (!answer) return Promise.reject(new Error(`nothing more to answer ${url}`));
    return Promise.resolve(answer);
  }) as typeof fetch;
  return { fetcher, sends, tokens: () => tokens };
}

const pem = (account: ServiceAccount) => account.privateKey;
const note = { id: '6f1c1a52-0c3e-4d7e-9a43-1d5a3c1e2b77', title: 'Payment confirmed', body: 'Monthly runs until 15 Dec.', link: '/gyms/my' };
const phone = { token: 'cXyZ3abcDEF-ghij_KLmno', platform: 'android' };

Deno.test('the service account key: as downloaded, or in base64; nothing else', async () => {
  const { json, account } = await serviceAccount();
  same(account.projectId, 'health-pro-test');
  same(account.clientEmail, 'firebase-adminsdk@health-pro-test.iam.gserviceaccount.com');
  same(pem(parseServiceAccount(btoa(json))), pem(account), 'base64, as deploy_supabase.sh stores it');
  for (const wrong of ['{"type":"authorized_user","client_email":"x"}', '{}', 'not json']) {
    let failed = false;
    try {
      parseServiceAccount(wrong);
    } catch {
      failed = true;
    }
    same(failed, true, `refused: ${wrong}`);
  }
});

Deno.test("the JWT Google exchanges: for FCM only, an hour, signed with the account's key", async () => {
  const { pair, account } = await serviceAccount();
  const now = Date.UTC(2026, 10, 22, 8, 0, 0);
  const jwt = await assertion(account, now);
  const [head, claims, signature] = jwt.split('.');
  same(JSON.parse(new TextDecoder().decode(b64urlDecode(head))), { alg: 'RS256', typ: 'JWT' });
  same(JSON.parse(new TextDecoder().decode(b64urlDecode(claims))), {
    iss: account.clientEmail,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now / 1000,
    exp: now / 1000 + 3600,
  });
  const ok = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    pair.publicKey,
    bs(b64urlDecode(signature)),
    bs(new TextEncoder().encode(`${head}.${claims}`)),
  );
  same(ok, true, 'Google can check it with the public key');
});

Deno.test('an access token is kept for its hour (five minutes to spare), then asked for again', async () => {
  forgetAccessToken();
  const { account } = await serviceAccount();
  const g = google([]);
  const now = Date.UTC(2026, 10, 22, 8, 0, 0);
  same(await accessToken(account, g.fetcher, now), 'ya29.token-1');
  same(await accessToken(account, g.fetcher, now + 50 * 60_000), 'ya29.token-1', 'kept');
  same(g.tokens(), 1);
  same(await accessToken(account, g.fetcher, now + 56 * 60_000), 'ya29.token-2', 'a new one near the hour');
});

Deno.test("the message: to the phone's FID, shown even when closed, with its page", () => {
  const now = Date.UTC(2026, 10, 22, 8, 0, 0);
  same(fcmMessage(phone, note, now), {
    message: {
      fid: 'cXyZ3abcDEF-ghij_KLmno',
      notification: { title: 'Payment confirmed', body: 'Monthly runs until 15 Dec.' },
      data: { id: note.id, link: '/gyms/my' },
      android: {
        priority: 'HIGH',
        ttl: '86400s',
        notification: { tag: note.id, channel_id: 'health_pro', default_sound: true },
      },
      apns: {
        headers: { 'apns-priority': '10', 'apns-expiration': String(now / 1000 + 86400), 'apns-collapse-id': note.id },
        payload: { aps: { sound: 'default' } },
      },
    },
  });
});

Deno.test("FCM's answers: sent; gone (unregistered, or not an address); anything else leaves the phone alone", () => {
  const error = (status: string, details: unknown[]) => ({ error: { status, details } });
  same(outcomeOf(200, null), 'sent');
  same(outcomeOf(404, error('NOT_FOUND', [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode: 'UNREGISTERED' }])), 'gone');
  same(outcomeOf(404, null), 'gone', 'unregistered, however it says so');
  same(
    outcomeOf(400, error('INVALID_ARGUMENT', [{ '@type': 'type.googleapis.com/google.rpc.BadRequest', fieldViolations: [{ field: 'message.fid' }] }])),
    'gone',
    "that address isn't one",
  );
  same(
    outcomeOf(400, error('INVALID_ARGUMENT', [{ '@type': 'type.googleapis.com/google.rpc.BadRequest', fieldViolations: [{ field: 'message.android.ttl' }] }])),
    'failed',
    'our request: never the phone',
  );
  same(outcomeOf(403, error('PERMISSION_DENIED', [{ errorCode: 'SENDER_ID_MISMATCH' }])), 'failed', 'our account: never the phone');
  same(outcomeOf(429, error('RESOURCE_EXHAUSTED', [{ errorCode: 'QUOTA_EXCEEDED' }])), 'failed');
  same(outcomeOf(503, null), 'failed');
});

Deno.test("sending: to the project's FCM, with the access token; a refused token is asked for again, once", async () => {
  forgetAccessToken();
  const { account } = await serviceAccount();
  const g = google([new Response('{"error":{"status":"UNAUTHENTICATED"}}', { status: 401 }), Response.json({ name: 'projects/health-pro-test/messages/1' })]);
  same(await sendFcm(account, phone, note, g.fetcher), 'sent');
  same(g.sends.length, 2);
  same(g.sends[0].url, 'https://fcm.googleapis.com/v1/projects/health-pro-test/messages:send');
  same(g.sends[0].auth, 'Bearer ya29.token-1');
  same(g.sends[1].auth, 'Bearer ya29.token-2', 'a new token after the 401');
  same((g.sends[1].body.message as { fid: string }).fid, phone.token);

  const refused = google([401, 401].map((status) => new Response('{}', { status })));
  forgetAccessToken();
  same(await sendFcm(account, phone, note, refused.fetcher), 'failed', 'refused twice: given up');
  same(refused.sends.length, 2);
});

Deno.test("sending to a phone whose app is gone: send-push forgets it", async () => {
  forgetAccessToken();
  const { account } = await serviceAccount();
  const g = google([
    Response.json({ error: { code: 404, status: 'NOT_FOUND', details: [{ errorCode: 'UNREGISTERED' }] } }, { status: 404 }),
  ]);
  same(await sendFcm(account, phone, note, g.fetcher), 'gone');
});
