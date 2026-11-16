-- Paying online with a journal number, the gym's settings, and reminders:
-- runs after people_test.sql (it uses the t.* helpers and super admin A
-- from scenario_test.sql). Owner O8 with front desk D8 and manager M8;
-- Pema, a member with an account, pays online; Karma asks to join; X8 is
-- a stranger.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000801', 'owner8@gym.bt', now(), '{"full_name":"Oki Owner"}'),
  ('00000000-0000-0000-0000-000000000802', 'desk8@gym.bt', now(), '{"full_name":"Dorji Desk"}'),
  ('00000000-0000-0000-0000-000000000803', 'manager8@gym.bt', now(), '{"full_name":"Mindu Manager"}'),
  ('00000000-0000-0000-0000-000000000804', 'pema8@x.bt', now(), '{"full_name":"Pema Yangzom"}'),
  ('00000000-0000-0000-0000-000000000805', 'karma8@x.bt', now(), '{"full_name":"Karma Tenzin"}'),
  ('00000000-0000-0000-0000-000000000806', 'x8@x.bt', now(), '{"full_name":"Xa Stranger"}');
set role authenticated;

select t.as_user('00000000-0000-0000-0000-000000000801');
select public.register_venue('{"type":"gym","name":"Gamma Gym","dzongkhag":"Punakha","phone":"+97517800801"}') as gym \gset
select public.register_venue('{"type":"gym","name":"Delta Gym","dzongkhag":"Punakha","phone":"+97517800802"}') as other \gset
select t.as_user('00000000-0000-0000-0000-00000000000a');
select public.review_venue(:'gym', true);
select t.as_user('00000000-0000-0000-0000-000000000801');
select public.gym_save_plan(:'gym', null, 'Monthly', null, 30, 1500, true) as plan \gset
select public.add_venue_staff(:'gym', 'desk8@gym.bt', 'staff');
select public.add_venue_staff(:'gym', 'manager8@gym.bt', 'manager');

-- ---- The gym's settings ---------------------------------------------------
select t.eq((select count(*) from public.gym_settings where venue_id = :'gym')::int, 0, 'a new gym has the default settings');
select public.gym_save_settings(:'gym', 'Bank of Bhutan', ' 2001-2345 6789 ', ' Peak  Fitness ', '{3,7,3}', 'desk');
select t.eq((select reminder_days from public.gym_settings where venue_id = :'gym'), '{7,3}'::int[],
            'the owner sets reminders 7 and 3 days before the end');
select t.eq((select account_number || ' ' || account_name from public.gym_settings where venue_id = :'gym'),
            '200123456789 Peak Fitness', '...and the bank account members pay into, tidied');
select t.fails(format($$select public.gym_save_settings(%L, 'Bank of Bhutan', '200123456789', null, '{3}', 'desk')$$, :'gym'),
               'the account name');
select t.fails(format($$select public.gym_save_settings(%L, 'Bank of Bhutan', '12AB', 'Peak Fitness', '{3}', 'desk')$$, :'gym'),
               '6 to 20 digits');
select t.fails(format($$select public.gym_save_settings(%L, null, null, null, '{0}', 'desk')$$, :'gym'), '1 to 60 days');
select t.fails(format($$select public.gym_save_settings(%L, null, null, null, '{1,2,3,4,5,6}', 'desk')$$, :'gym'), 'up to 5');
select t.fails(format($$select public.gym_save_settings(%L, null, null, null, '{3}', 'nobody')$$, :'gym'), 'who answers');
select t.as_user('00000000-0000-0000-0000-000000000802');
select t.fails(format($$select public.gym_save_settings(%L, null, null, null, '{3}', 'desk')$$, :'gym'), 'Only those who edit');
select t.eq((select account_number from public.gym_settings where venue_id = :'gym'), '200123456789',
            'the front desk reads them');

-- ---- Pema pays online -------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-000000000804');
select public.my_person() ->> 'qr_token' as pema_qr \gset
select t.fails(format($$select public.gym_claim_payment(%L, %L, 1, 1500, 'JRN445566')$$, :'gym', :'plan'), 'not a member');
select t.as_user('00000000-0000-0000-0000-000000000802');
select public.gym_register_member(:'gym', '{"full_name":"Pema Yangzom","phone":"17800804"}', null, null, 0, null, null,
                                  :'pema_qr') ->> 'gym_member_id' as pema \gset
select t.fails(format($$select public.gym_check_in_member(%L, %L)$$, :'gym', :'pema_qr'), 'no package yet');

select t.as_user('00000000-0000-0000-0000-000000000804');
select t.fails(format($$select public.gym_claim_payment(%L, %L, 1, 1500, 'x')$$, :'gym', :'plan'), 'journal number');
select t.fails(format($$select public.gym_claim_payment(%L, null, 1, 1500, 'JRN445566')$$, :'gym'), 'one of the gym''s packages');
select t.fails(format($$select public.gym_claim_payment(%L, %L, 30, 1500, 'JRN445566')$$, :'gym', :'plan'), '1 to 24');
select public.gym_claim_payment(:'gym', :'plan', 1, 1500, ' jrn 4455 66 ') as claim \gset
select t.eq((select jrn from public.gym_payment_claims where id = :'claim'), 'JRN445566', 'the journal number, tidied');
select t.fails(format($$select public.gym_claim_payment(%L, %L, 1, 1500, 'JRN000111')$$, :'gym', :'plan'), 'sent a payment already');
select t.eq(public.my_gyms() -> 'gyms' -> 0 -> 'claim' ->> 'status', 'pending', 'she sees it waiting');
select t.eq(public.my_gyms() -> 'gyms' -> 0 -> 'payment_account' ->> 'account_number', '200123456789',
            '...beside the account to pay into');
select t.eq((select channel from public.gym_payment_claims where id = :'claim'), 'bank_account', 'paid into the bank account');

select t.as_user('00000000-0000-0000-0000-000000000806');
select t.eq((select count(*) from public.gym_payment_claims)::int, 0, 'a stranger sees nobody''s payments');

select t.as_user('00000000-0000-0000-0000-000000000802');
select t.eq((select body from public.notifications where user_id = '00000000-0000-0000-0000-000000000802'
             and title = 'Payment to confirm'),
            'Pema Yangzom paid Nu. 1500 online for Monthly (JRN JRN445566). Check it with the bank.',
            'the front desk, who take payments, is told');
select public.gym_confirm_payment_claim(:'claim') as confirmed \gset
select t.eq((:'confirmed'::jsonb ->> 'end_date')::date, (public.bhutan_today() + interval '1 month')::date,
            'confirming starts the package today, for the month paid');
select t.eq((select status from public.gym_payment_claims where id = :'claim'), 'confirmed', '...and closes the payment');
select t.fails(format($$select public.gym_confirm_payment_claim(%L)$$, :'claim'), 'answered already');
select t.eq(public.gym_check_in_member(:'gym', :'pema_qr') ->> 'plan_name', 'Monthly', 'now she checks in');

select t.as_user('00000000-0000-0000-0000-000000000801');
select t.eq((select p.method || ' ' || p.reference || ' ' || p.amount from public.payments p
             join public.gym_payment_claims c on c.payment_id = p.id where c.id = :'claim'),
            'bank JRN445566 1500', 'the owner sees the payment, with its journal number');

select t.as_user('00000000-0000-0000-0000-000000000804');
select t.eq((select title from public.notifications where user_id = '00000000-0000-0000-0000-000000000804'
             order by created_at desc limit 1), 'Payment confirmed', 'she''s told');
select t.eq((select body from public.notifications where user_id = '00000000-0000-0000-0000-000000000804'
             and title = 'Payment confirmed'),
            'Gamma Gym confirmed your payment of Nu. 1500 (JRN JRN445566). Monthly runs until '
              || to_char((:'confirmed'::jsonb ->> 'end_date')::date, 'FMDD Mon YYYY') || '.',
            '...once, with the journal number and until when');
select t.fails(format($$select public.gym_claim_payment(%L, %L, 1, 1500, 'JRN445566')$$, :'gym', :'plan'), 'used at Gamma Gym already');
select public.gym_claim_payment(:'gym', :'plan', 2, 3000, 'JRN777') as claim2 \gset

select t.as_user('00000000-0000-0000-0000-000000000802');
select public.gym_reject_payment_claim(:'claim2', 'Not in our statement');
select t.as_user('00000000-0000-0000-0000-000000000804');
select t.eq((select body from public.notifications where user_id = '00000000-0000-0000-0000-000000000804'
             order by created_at desc limit 1),
            'Gamma Gym couldn''t find your payment (JRN JRN777). Not in our statement Check the number, or ask at the front desk.',
            'a payment the gym can''t find: she''s told why');
select public.gym_claim_payment(:'gym', :'plan', 1, 1500, 'JRN888') as claim3 \gset
select public.gym_cancel_payment_claim(:'claim3');
select t.fails(format($$select public.gym_cancel_payment_claim(%L)$$, :'claim3'), 'isn''t waiting');

-- ---- Managers only answer requests to join ---------------------------------
select t.as_user('00000000-0000-0000-0000-000000000801');
select public.gym_save_settings(:'gym', 'Bank of Bhutan', '200123456789', 'Peak Fitness', '{7,3}', 'managers');
select t.as_user('00000000-0000-0000-0000-000000000805');
select public.gym_request_to_join(:'gym') as karma_req \gset
select t.as_user('00000000-0000-0000-0000-000000000802');
select t.eq((select count(*) from public.notifications where user_id = '00000000-0000-0000-0000-000000000802'
             and title = 'New request to join')::int, 0, 'managers only: the front desk isn''t told');
select t.fails(format($$select public.gym_decline_join_request(%L)$$, :'karma_req'), 'owner and managers');
select t.fails(format($$select public.gym_register_member(%L, '{"full_name":"Karma Tenzin","phone":"17800805"}',
                        null, null, 0, null, null, null, %L)$$, :'gym', :'karma_req'), 'owner and managers');
select t.as_user('00000000-0000-0000-0000-000000000803');
select t.eq((select count(*) from public.notifications where user_id = '00000000-0000-0000-0000-000000000803'
             and title = 'New request to join')::int, 1, '...the manager is');
select public.gym_decline_join_request(:'karma_req', 'Full this month');
select t.eq((select status from public.gym_join_requests where id = :'karma_req'), 'declined', '...and answers it');

-- ---- Reminders, on the gym's days ------------------------------------------
reset role;
select set_config('request.jwt.claim.sub', '', false);
update public.gym_subscriptions set end_date = public.bhutan_today() + 7 where gym_member_id = :'pema';
select t.eq((public.gym_daily_maintenance() ->> 'reminded')::int >= 1, true, 'daily: reminded 7 days before');
select t.eq((select count(*) from public.notifications where user_id = '00000000-0000-0000-0000-000000000804'
             and title = 'Your package ends in 7 days')::int, 1, '...Pema, on the gym''s first reminder day');
select public.gym_daily_maintenance();
select t.eq((select count(*) from public.notifications where user_id = '00000000-0000-0000-0000-000000000804'
             and title like 'Your package ends in%')::int, 1, '...once');
update public.gym_subscriptions set end_date = public.bhutan_today() + 5 where gym_member_id = :'pema';
select public.gym_daily_maintenance();
select t.eq((select count(*) from public.notifications where user_id = '00000000-0000-0000-0000-000000000804'
             and title like 'Your package ends in%')::int, 1, 'not on a day the gym didn''t choose');
update public.gym_subscriptions set end_date = public.bhutan_today() where gym_member_id = :'pema';
select public.gym_daily_maintenance();
select t.eq((select body from public.notifications where user_id = '00000000-0000-0000-0000-000000000804'
             and title = 'Your package at Gamma Gym ends today'),
            'Monthly ends today. Pay to renew it: online with your bank app (then enter the journal number in Health Pro), '
              || 'or cash at the front desk.', 'on its last day: it ends, and how to renew');

-- ---- Paying at the desk: the member is told too ----------------------------
set role authenticated;
select t.as_user('00000000-0000-0000-0000-000000000802');
select public.gym_renew_member(:'pema', :'plan', 1, 1500, 'cash') as cash \gset
select public.gym_renew_member(:'pema', :'plan', 2, 3000, 'mbob', ' 998877 ') as mbob \gset
select public.gym_renew_member(:'pema', :'plan', 1, 0) as free \gset
select t.as_user('00000000-0000-0000-0000-000000000804');
select t.eq((select count(*) from public.notifications where user_id = '00000000-0000-0000-0000-000000000804'
             and body = 'Gamma Gym confirmed your cash payment of Nu. 1500. Monthly runs until '
                        || to_char((:'cash'::jsonb ->> 'end_date')::date, 'FMDD Mon YYYY') || '.')::int,
            1, 'cash at the desk: she''s told it''s in, and until when');
select t.eq((select count(*) from public.notifications where user_id = '00000000-0000-0000-0000-000000000804'
             and body = 'Gamma Gym confirmed your payment of Nu. 3000 (JRN 998877). Monthly runs from '
                        || to_char((:'mbob'::jsonb ->> 'start_date')::date, 'FMDD Mon YYYY') || ' until '
                        || to_char((:'mbob'::jsonb ->> 'end_date')::date, 'FMDD Mon YYYY') || '.')::int,
            1, 'mBoB at the desk: the journal number, and from when it starts');
select t.eq((select count(*) from public.notifications where user_id = '00000000-0000-0000-0000-000000000804'
             and title = 'Your package was renewed' and body like 'Gamma Gym renewed your package. Monthly runs from %')::int,
            1, 'free of charge: renewed, no payment');
select t.eq((select count(*) from public.notifications where user_id = '00000000-0000-0000-0000-000000000804'
             and title = 'Payment confirmed')::int, 3, 'one notice each time (the online one included)');

do $$ begin raise notice 'ALL PAYMENT CHECKS PASSED'; end $$;
