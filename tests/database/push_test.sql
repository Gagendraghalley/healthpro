-- Push notifications: runs after trainers_test.sql (it uses the t.*
-- helpers). Pem and Kinley each turn notifications on, on a phone;
-- send-push (the service role) claims each notification once. The local
-- database has no pg_net, so nothing actually goes out: the point is that
-- notifications never fail because of push.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
-- send-push's role uses the test helpers here too.
grant usage on schema t to service_role;
grant execute on all functions in schema t to service_role;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000001101', 'pem@x.bt', now(), '{"full_name":"Pem Choki"}'),
  ('00000000-0000-0000-0000-000000001102', 'kinley@x.bt', now(), '{"full_name":"Kinley Om"}');
set role authenticated;

\set phone 'https://fcm.googleapis.com/fcm/send/phone-1'
\set p256dh 'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4'
\set auth 'BTBZMqHH6r4Tts7J_aSIgg'

select t.as_user('00000000-0000-0000-0000-000000001101');
select t.fails($$select public.save_push_subscription('http://insecure.example/x', 'k', 'a')$$, 'isn''t a push subscription');
select public.save_push_subscription(:'phone', :'p256dh', :'auth', 'Mozilla/5.0 (iPhone)');
select public.save_push_subscription(:'phone', :'p256dh', :'auth', 'Mozilla/5.0 (iPhone)');
select t.eq((select count(*) from public.push_subscriptions)::int, 1, 'her phone, once');

select t.as_user('00000000-0000-0000-0000-000000001102');
select t.eq((select count(*) from public.push_subscriptions)::int, 0, 'nobody sees another''s devices');

-- A notification for Pem, push not set up yet: it's made as always.
reset role;
select set_config('request.jwt.claim.sub', '', false);
select public.notify('00000000-0000-0000-0000-000000001101', null, 'Payment confirmed', 'Monthly runs until 15 Dec.', '/gyms/my');
select t.eq((select count(*) from public.notifications where user_id = '00000000-0000-0000-0000-000000001101')::int, 1,
            'without push set up, the notification is made');

-- Push set up (send-push's address), but no pg_net here: still made.
select t.fails($$select public.push_configure('https://evil.example/steal')$$, 'send-push function''s address');
select public.push_configure('https://abc.supabase.co/functions/v1/send-push');
select t.eq((select value from private.settings where key = 'push_function_url'), 'https://abc.supabase.co/functions/v1/send-push',
            'send-push''s address kept, out of the app''s reach');
select public.notify('00000000-0000-0000-0000-000000001101', null, 'New member', 'Meto chose you.', '/gyms/trainer');
select t.eq((select count(*) from public.notifications where user_id = '00000000-0000-0000-0000-000000001101')::int, 2,
            'a push that can''t be sent never stops the notification');

-- send-push claims each notification once, for its own person's devices.
select id as note from public.notifications where user_id = '00000000-0000-0000-0000-000000001101' and title = 'New member' \gset
set role service_role;
select public.push_claim_notification(:'note') as claimed \gset
select t.eq(:'claimed'::jsonb ->> 'title', 'New member', 'send-push gets the notification');
select t.eq(:'claimed'::jsonb -> 'subscriptions' -> 0 ->> 'endpoint', :'phone', '...and her phone');
select t.eq(public.push_claim_notification(:'note'), null::jsonb, 'once only');
reset role;
update public.notifications set created_at = now() - interval '1 hour', pushed_at = null where id = :'note';
set role service_role;
select t.eq(public.push_claim_notification(:'note'), null::jsonb, 'not an old one');
select public.push_forget_subscriptions(array[:'phone']);
reset role;
select t.eq((select count(*) from public.push_subscriptions)::int, 0, 'a device its push service says is gone is forgotten');

set role authenticated;
select t.as_user('00000000-0000-0000-0000-000000001101');
select t.fails(format($$select public.push_claim_notification(%L)$$, :'note'), 'permission denied');

-- A phone passed from Pem to Kinley (Pem signed out, Kinley signed in).
select public.save_push_subscription(:'phone', :'p256dh', :'auth');
select t.as_user('00000000-0000-0000-0000-000000001102');
select public.save_push_subscription(:'phone', :'p256dh', :'auth');
select t.eq((select count(*) from public.push_subscriptions)::int, 1, 'the phone is Kinley''s now');
select t.as_user('00000000-0000-0000-0000-000000001101');
select t.eq((select count(*) from public.push_subscriptions)::int, 0, '...not Pem''s');
select t.as_user('00000000-0000-0000-0000-000000001102');
select public.remove_push_subscription(:'phone');
select t.eq((select count(*) from public.push_subscriptions)::int, 0, 'and off again');

-- The phone apps (FCM tokens): Pem turns them on in the Android app.
\set android 'dY3xQ9-hR0e:APA91bHq_Z9cZ8n2kLx-android-phone-1'
select t.as_user('00000000-0000-0000-0000-000000001101');
select t.fails($$select public.save_push_device('not a token!', 'android')$$, 'isn''t a push token');
select t.fails(format($$select public.save_push_device(%L, 'windows')$$, :'android'), 'Android and iOS');
select public.save_push_device(:'android', 'android');
select public.save_push_device(:'android', 'android');
select t.eq((select count(*) from public.push_devices)::int, 1, 'her Android phone, once');
select t.fails(format($$insert into public.push_devices (user_id, token, platform) values (%L, 'aaaaaaaaaaaaaaaaaaaaaaaa', 'ios')$$,
                      '00000000-0000-0000-0000-000000001101'), 'permission denied');
select t.as_user('00000000-0000-0000-0000-000000001102');
select t.eq((select count(*) from public.push_devices)::int, 0, 'nobody sees another''s phones');

-- With only the phone app on (no browser), the notification is still made and
-- send-push gets her phone with it.
reset role;
select set_config('request.jwt.claim.sub', '', false);
select public.notify('00000000-0000-0000-0000-000000001101', null, 'Package ending', 'Monthly ends tomorrow.', '/gyms/my');
select id as note2 from public.notifications where user_id = '00000000-0000-0000-0000-000000001101' and title = 'Package ending' \gset
set role service_role;
select public.push_claim_notification(:'note2') as claimed2 \gset
select t.eq(:'claimed2'::jsonb -> 'devices' -> 0 ->> 'token', :'android', 'send-push gets her phone app');
select t.eq(:'claimed2'::jsonb -> 'devices' -> 0 ->> 'platform', 'android', '...as Android');
select t.eq(jsonb_array_length(:'claimed2'::jsonb -> 'subscriptions'), 0, '...and no browsers');
select public.push_forget_devices(array[:'android']);
reset role;
select t.eq((select count(*) from public.push_devices)::int, 0, 'a phone FCM says is gone is forgotten');

set role authenticated;
select t.as_user('00000000-0000-0000-0000-000000001101');
select t.fails(format($$select public.push_forget_devices(array[%L])$$, :'android'), 'permission denied');

-- A phone passed from Pem to Kinley, now an iPhone app.
select public.save_push_device(:'android', 'android');
select t.as_user('00000000-0000-0000-0000-000000001102');
select public.save_push_device(:'android', 'ios');
select t.eq((select platform from public.push_devices), 'ios', 'the phone is Kinley''s now');
select t.as_user('00000000-0000-0000-0000-000000001101');
select t.eq((select count(*) from public.push_devices)::int, 0, '...not Pem''s');
select t.as_user('00000000-0000-0000-0000-000000001102');
select public.remove_push_device(:'android');
select t.eq((select count(*) from public.push_devices)::int, 0, 'and off again on the phone');

-- Twenty phones at most: the oldest makes room for a new one.
select public.save_push_device('kinley-phone-' || lpad(i::text, 12, '0'), 'ios') from generate_series(1, 21) i;
select t.eq((select count(*) from public.push_devices)::int, 20, 'twenty phones at most');
select t.eq((select count(*) from public.push_devices where token = 'kinley-phone-000000000021')::int, 1, '...the newest kept');
select public.save_push_device('kinley-phone-000000000021', 'ios');
select t.eq((select count(*) from public.push_devices)::int, 20, 'saving one again doesn''t push another out');

reset role;
delete from private.settings;
do $$ begin raise notice 'ALL PUSH CHECKS PASSED'; end $$;
