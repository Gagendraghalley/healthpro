// Web Push without a library (supabase/functions/_shared/web_push.ts):
// encryption checked against RFC 8291's own example, and as a device would
// decrypt it; the VAPID signature as a push service would check it.
//
//   deno test tests/functions
import {
  b64urlDecode,
  b64urlEncode,
  deriveKeys,
  encryptPayload,
  generateVapidKeys,
  vapidAuthorization,
} from '../../supabase/functions/_shared/web_push.ts';

function same(actual: unknown, expected: unknown, label = '') {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${label}\n  got:      ${a}\n  expected: ${e}`);
}

const bs = (bytes: Uint8Array) => bytes as unknown as BufferSource;

/** An ECDH key pair from its base64url public point and private scalar. */
async function ecdhPair(publicKey: string, privateKey: string): Promise<CryptoKeyPair> {
  const pub = b64urlDecode(publicKey);
  const jwk = { kty: 'EC', crv: 'P-256', x: b64urlEncode(pub.slice(1, 33)), y: b64urlEncode(pub.slice(33, 65)) };
  return {
    publicKey: await crypto.subtle.importKey('jwk', jwk, { name: 'ECDH', namedCurve: 'P-256' }, true, []),
    privateKey: await crypto.subtle.importKey('jwk', { ...jwk, d: privateKey }, { name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']),
  };
}

/** What the device does: decrypt an aes128gcm body with its own keys. */
async function decrypt(body: Uint8Array, device: CryptoKeyPair, authSecret: Uint8Array): Promise<string> {
  const salt = body.slice(0, 16);
  const idLength = body[20];
  const asPublic = body.slice(21, 21 + idLength);
  const sender = await crypto.subtle.importKey('raw', bs(asPublic), { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const ecdhSecret = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: sender }, device.privateKey, 256));
  const uaPublic = new Uint8Array(await crypto.subtle.exportKey('raw', device.publicKey));
  const { cek, nonce } = await deriveKeys(ecdhSecret, authSecret, uaPublic, asPublic, salt);
  const key = await crypto.subtle.importKey('raw', bs(cek), 'AES-GCM', false, ['decrypt']);
  const plain = new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: bs(nonce) }, key, bs(body.slice(21 + idLength))));
  if (plain[plain.length - 1] !== 2) throw new Error('not the last record');
  return new TextDecoder().decode(plain.slice(0, -1));
}

Deno.test('base64url, both ways', () => {
  const bytes = Uint8Array.from([0, 250, 251, 252, 253, 254, 255, 62, 63]);
  same([...b64urlDecode(b64urlEncode(bytes))], [...bytes]);
  same(b64urlEncode(Uint8Array.from([251, 255])), '-_8');
});

Deno.test("encryption: RFC 8291's example, byte for byte", async () => {
  // RFC 8291, Appendix A.
  const plaintext = new TextEncoder().encode('When I grow up, I want to be a watermelon');
  const authSecret = b64urlDecode('BTBZMqHH6r4Tts7J_aSIgg');
  const uaPublic = b64urlDecode('BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4');
  const sender = await ecdhPair(
    'BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8',
    'yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw',
  );
  const body = await encryptPayload(plaintext, uaPublic, authSecret, { salt: b64urlDecode('DGv6ra1nlYgDCS1FRnbzlw'), sender });
  same(
    b64urlEncode(body),
    'DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN',
  );
  const device = await ecdhPair(
    'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4',
    'q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94',
  );
  same(await decrypt(body, device, authSecret), 'When I grow up, I want to be a watermelon', 'the device reads it');
});

Deno.test('a fresh message decrypts on the device it was for, and only there', async () => {
  const device = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']) as CryptoKeyPair;
  const other = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']) as CryptoKeyPair;
  const authSecret = crypto.getRandomValues(new Uint8Array(16));
  const uaPublic = new Uint8Array(await crypto.subtle.exportKey('raw', device.publicKey));
  const message = JSON.stringify({ title: 'Payment confirmed', body: 'Monthly runs until 15 Dec 2026.', link: '/gyms/my' });
  const body = await encryptPayload(new TextEncoder().encode(message), uaPublic, authSecret);
  same(await decrypt(body, device, authSecret), message);
  let failed = false;
  try {
    await decrypt(body, other, authSecret);
  } catch {
    failed = true;
  }
  same(failed, true, 'another device cannot read it');
});

Deno.test('VAPID: a JWT for the push service, signed with the key the app subscribed with', async () => {
  const keys = await generateVapidKeys();
  same(b64urlDecode(keys.publicKey).length, 65, 'an uncompressed P-256 point');
  same(b64urlDecode(keys.privateKey).length, 32);
  const vapid = { ...keys, subject: 'https://sporthubs.pages.dev' };
  const header = await vapidAuthorization('https://fcm.googleapis.com/fcm/send/abc', vapid, Date.UTC(2026, 10, 15) );
  const m = header.match(/^vapid t=([^.]+)\.([^.]+)\.([^,]+), k=(.+)$/)!;
  same(m[4], keys.publicKey, 'k is the public key');
  const claims = JSON.parse(new TextDecoder().decode(b64urlDecode(m[2])));
  same(claims.aud, 'https://fcm.googleapis.com', 'for the push service only');
  same(claims.exp, Date.UTC(2026, 10, 15) / 1000 + 12 * 3600, 'valid 12 hours');
  same(claims.sub, 'https://sporthubs.pages.dev');
  const pub = b64urlDecode(keys.publicKey);
  const verifier = await crypto.subtle.importKey(
    'jwk',
    { kty: 'EC', crv: 'P-256', x: b64urlEncode(pub.slice(1, 33)), y: b64urlEncode(pub.slice(33, 65)) },
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['verify'],
  );
  const ok = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    verifier,
    bs(b64urlDecode(m[3])),
    bs(new TextEncoder().encode(`${m[1]}.${m[2]}`)),
  );
  same(ok, true, 'the push service can check it');
});
