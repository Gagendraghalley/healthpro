// Web Push, on WebCrypto alone (no library): sending a message to a phone or
// browser that subscribed (RFC 8030), signed with the server's VAPID key
// (RFC 8292) and encrypted for that device only (aes128gcm, RFC 8291).
//
// Keys, as base64url:
//   VAPID_PUBLIC_KEY   the public key: an uncompressed P-256 point (65 bytes)
//   VAPID_PRIVATE_KEY  its private key (32 bytes)
//   VAPID_SUBJECT      who sends: 'mailto:...' or the site's https address
// scripts/make_push_keys.ts makes a pair, once; the app gets the public one.

export interface Subscription {
  endpoint: string;
  /** The device's public key (65 bytes, base64url). */
  p256dh: string;
  /** The device's auth secret (16 bytes, base64url). */
  auth: string;
}

export interface Vapid {
  publicKey: string;
  privateKey: string;
  subject: string;
}

/** The VAPID keys from the function's secrets; null when push isn't set up. */
export function vapidFromEnv(): Vapid | null {
  const publicKey = Deno.env.get('VAPID_PUBLIC_KEY');
  const privateKey = Deno.env.get('VAPID_PRIVATE_KEY');
  if (!publicKey || !privateKey) return null;
  return { publicKey, privateKey, subject: Deno.env.get('VAPID_SUBJECT') || 'https://sporthubs.pages.dev' };
}

const text = new TextEncoder();

export function b64urlEncode(bytes: Uint8Array): string {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function b64urlDecode(value: string): Uint8Array {
  const b64 = value.replace(/-/g, '+').replace(/_/g, '/');
  const s = atob(b64 + '='.repeat((4 - (b64.length % 4)) % 4));
  return Uint8Array.from(s, (c) => c.charCodeAt(0));
}

function concat(...parts: (Uint8Array | number[])[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

/** [bytes] as WebCrypto takes them (typed arrays' typing differs across
 *  TypeScript versions; Supabase's Edge runtime and the newest Deno). */
const bs = (bytes: Uint8Array) => bytes as unknown as BufferSource;

async function hmac(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const k = await crypto.subtle.importKey('raw', bs(key), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', k, bs(data)));
}

/** The content key and nonce for one message (RFC 8291 section 3.3-3.4). */
export async function deriveKeys(
  ecdhSecret: Uint8Array,
  authSecret: Uint8Array,
  uaPublic: Uint8Array,
  asPublic: Uint8Array,
  salt: Uint8Array,
): Promise<{ cek: Uint8Array; nonce: Uint8Array }> {
  const prkKey = await hmac(authSecret, ecdhSecret);
  const ikm = await hmac(prkKey, concat(text.encode('WebPush: info\0'), uaPublic, asPublic, [1]));
  const prk = await hmac(salt, ikm);
  const cek = (await hmac(prk, concat(text.encode('Content-Encoding: aes128gcm\0'), [1]))).slice(0, 16);
  const nonce = (await hmac(prk, concat(text.encode('Content-Encoding: nonce\0'), [1]))).slice(0, 12);
  return { cek, nonce };
}

/** [payload] encrypted for one device: the aes128gcm body, a single record.
 *  [salt] and [sender] are for tests; each message gets fresh ones. */
export async function encryptPayload(
  payload: Uint8Array,
  uaPublic: Uint8Array,
  authSecret: Uint8Array,
  opts: { salt?: Uint8Array; sender?: CryptoKeyPair } = {},
): Promise<Uint8Array> {
  const sender = opts.sender ??
    (await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']) as CryptoKeyPair);
  const asPublic = new Uint8Array(await crypto.subtle.exportKey('raw', sender.publicKey));
  const device = await crypto.subtle.importKey('raw', bs(uaPublic), { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const ecdhSecret = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: device }, sender.privateKey, 256));
  const salt = opts.salt ?? crypto.getRandomValues(new Uint8Array(16));
  const { cek, nonce } = await deriveKeys(ecdhSecret, authSecret, uaPublic, asPublic, salt);
  const key = await crypto.subtle.importKey('raw', bs(cek), 'AES-GCM', false, ['encrypt']);
  // One record, the last: the content, then the delimiter 2, no padding.
  const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: bs(nonce) }, key, bs(concat(payload, [2]))));
  const header = new Uint8Array(16 + 4 + 1 + asPublic.length);
  header.set(salt, 0);
  new DataView(header.buffer).setUint32(16, 4096);
  header[20] = asPublic.length;
  header.set(asPublic, 21);
  return concat(header, sealed);
}

/** The VAPID private key, as WebCrypto takes it. */
async function signingKey(vapid: Vapid): Promise<CryptoKey> {
  const pub = b64urlDecode(vapid.publicKey);
  return crypto.subtle.importKey(
    'jwk',
    { kty: 'EC', crv: 'P-256', x: b64urlEncode(pub.slice(1, 33)), y: b64urlEncode(pub.slice(33, 65)), d: vapid.privateKey, ext: true },
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
}

/** The Authorization header for [endpoint]'s push service: a JWT for its
 *  origin, valid 12 hours, signed with the VAPID key. */
export async function vapidAuthorization(endpoint: string, vapid: Vapid, now = Date.now()): Promise<string> {
  const head = b64urlEncode(text.encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const claims = b64urlEncode(text.encode(JSON.stringify({
    aud: new URL(endpoint).origin,
    exp: Math.floor(now / 1000) + 12 * 3600,
    sub: vapid.subject,
  })));
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, await signingKey(vapid), bs(text.encode(`${head}.${claims}`))),
  );
  return `vapid t=${head}.${claims}.${b64urlEncode(signature)}, k=${vapid.publicKey}`;
}

/** Sends [message] to one device. Returns the push service's status: 201
 *  sent; 404 or 410 the device unsubscribed (forget it). */
export async function sendWebPush(sub: Subscription, message: string, vapid: Vapid, ttlSeconds = 86400): Promise<number> {
  const body = await encryptPayload(text.encode(message), b64urlDecode(sub.p256dh), b64urlDecode(sub.auth));
  const res = await fetch(sub.endpoint, {
    method: 'POST',
    headers: {
      'Content-Encoding': 'aes128gcm',
      'Content-Type': 'application/octet-stream',
      TTL: String(ttlSeconds),
      Urgency: 'normal',
      Authorization: await vapidAuthorization(sub.endpoint, vapid),
    },
    body: bs(body),
  });
  await res.body?.cancel();
  return res.status;
}

/** A new VAPID key pair, base64url (scripts/make_push_keys.ts). */
export async function generateVapidKeys(): Promise<{ publicKey: string; privateKey: string }> {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']) as CryptoKeyPair;
  const jwk = await crypto.subtle.exportKey('jwk', pair.privateKey);
  const point = concat([4], b64urlDecode(jwk.x!), b64urlDecode(jwk.y!));
  return { publicKey: b64urlEncode(point), privateKey: jwk.d! };
}
