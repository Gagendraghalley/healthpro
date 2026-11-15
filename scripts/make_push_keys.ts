// Makes the VAPID key pair for push notifications, once:
//
//   deno run scripts/make_push_keys.ts
//
// Keep both somewhere safe (a password manager). Deploy with them
// (scripts/deploy_supabase.sh): the private key becomes the send-push
// function's secret, the public one goes into the app (env.json). Don't
// change them later: every phone that turned notifications on would have to
// turn them on again.
import { generateVapidKeys } from '../supabase/functions/_shared/web_push.ts';

const keys = await generateVapidKeys();
console.log(`VAPID_PUBLIC_KEY=${keys.publicKey}`);
console.log(`VAPID_PRIVATE_KEY=${keys.privateKey}`);
