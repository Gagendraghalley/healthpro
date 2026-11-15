-- One QR code per person at every gym, and joining a gym by its QR code:
-- runs after registration_test.sql (it uses the t.* helpers and super admin
-- A from scenario_test.sql). Owner O7 runs gyms A and B, with front desk D
-- at both; Sonam walks in at A without an account and later signs up;
-- Jigme (account, email confirmed) asks to join A; Tashi asks to join B and
-- is declined; Unproven signs up with an email he hasn't confirmed.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000701', 'owner7@gym.bt', now(), '{"full_name":"Om Owner"}'),
  ('00000000-0000-0000-0000-000000000702', 'desk7@gym.bt', now(), '{"full_name":"Dee Desk"}'),
  ('00000000-0000-0000-0000-000000000703', 'jigme@x.bt', now(), '{"full_name":"Jigme Dorji","phone":"+97517700703"}'),
  ('00000000-0000-0000-0000-000000000704', 'tashi@x.bt', now(), '{"full_name":"Tashi Lhamo"}'),
  ('00000000-0000-0000-0000-000000000705', 'nosy7@x.bt', now(), '{"full_name":"Nosy Neighbour"}');
set role authenticated;

select t.as_user('00000000-0000-0000-0000-000000000701');
select public.register_venue('{"type":"gym","name":"Alpha Gym","dzongkhag":"Thimphu","phone":"+97517700701"}') as gym_a \gset
select public.register_venue('{"type":"gym","name":"Beta Gym","dzongkhag":"Paro","phone":"+97517700702"}') as gym_b \gset
select public.register_venue('{"type":"gym","name":"Unchecked Gym","dzongkhag":"Paro","phone":"+97517700709"}') as gym_new \gset
select t.as_user('00000000-0000-0000-0000-00000000000a');
select public.review_venue(:'gym_a', true);
select public.review_venue(:'gym_b', true);
select t.as_user('00000000-0000-0000-0000-000000000701');
select public.gym_save_plan(:'gym_a', null, 'Monthly', null, 30, 1500, true) as plan_a \gset
select public.gym_save_plan(:'gym_b', null, 'Monthly', null, 30, 2000, true) as plan_b \gset
select public.add_venue_staff(:'gym_a', 'desk7@gym.bt', 'staff');
select public.add_venue_staff(:'gym_b', 'desk7@gym.bt', 'staff');

-- ---- A walk-in at gym A gets one personal QR code ---------------------------
select t.as_user('00000000-0000-0000-0000-000000000702');
select public.gym_register_member(:'gym_a', jsonb_build_object(
  'full_name', 'Sonam Choden', 'phone', '17700777', 'email', 'Sonam@X.bt', 'blood_group', 'O+',
  'medical_notes', 'Knee surgery 2024', 'joined_on', public.bhutan_today()), :'plan_a', 1, 1500, 'cash') as reg \gset
select (:'reg'::jsonb ->> 'qr_token') as sonam_qr \gset
select (:'reg'::jsonb ->> 'person_id') as sonam \gset
select (:'reg'::jsonb ->> 'gym_member_id') as sonam_at_a \gset
select (select qr_token from public.gym_members where id = :'sonam_at_a') as sonam_card \gset
select t.eq((select (full_name, email, user_id is null)::text from public.people where id = :'sonam'),
            '("Sonam Choden",sonam@x.bt,t)', 'a walk-in is a person on Health Pro, without an account');
select t.eq(public.gym_check_in_member(:'gym_a', :'sonam_qr') ->> 'member_name', 'Sonam Choden',
            'their personal QR code checks them in at gym A');
select t.eq(public.gym_check_in_member(:'gym_a', :'sonam_card') ->> 'member_name', 'Sonam Choden',
            '...and so does gym A''s own card');

-- ---- ...and at gym B the desk adds them without typing it again --------------
select t.eq(public.gym_check_in_member(:'gym_b', :'sonam_qr') - 'person_token',
            '{"not_member": true, "member_name": "Sonam Choden"}'::jsonb, 'at gym B: not a member there yet');
select t.eq(public.gym_check_in_member(:'gym_b', :'sonam_card') ->> 'person_token', :'sonam_qr',
            '...gym A''s card says so too, with their QR code to add them by');
select t.eq(public.gym_person_details(:'gym_b', :'sonam_qr') -> 'details' ->> 'medical_notes', 'Knee surgery 2024',
            'the details they gave gym A fill the form');
select public.gym_register_member(:'gym_b', jsonb_build_object('full_name', 'Sonam Choden', 'phone', '17700777',
  'email', 'sonam@x.bt', 'joined_on', public.bhutan_today()), :'plan_b', 1, 2000, 'cash', null, :'sonam_qr') as reg_b \gset
select t.eq(:'reg_b'::jsonb ->> 'person_id', :'sonam', '...and it''s the same person');
select t.eq(:'reg_b'::jsonb ->> 'qr_token', :'sonam_qr', '...with the same QR code');
select t.eq(public.gym_check_in_member(:'gym_b', :'sonam_qr') ->> 'plan_name', 'Monthly', 'their QR code works at gym B now');
select t.eq(public.gym_check_in_member(:'gym_b', :'sonam_card') ->> 'member_name', 'Sonam Choden',
            '...and so does gym A''s card');
select t.fails(format($$select public.gym_register_member(%L, '{"full_name":"Sonam Choden","phone":"17700777"}',
                        null, null, 0, null, null, %L)$$, :'gym_b', :'sonam_qr'), 'registered here already');
select t.fails(format($$select public.gym_check_in_member(%L, %L)$$, :'gym_b', repeat('0', 32)), 'isn''t valid any more');

-- ---- Sonam signs up with the email the desk wrote down ----------------------
reset role;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000706', 'sonam@x.bt', now(), '{"full_name":"Sonam C."}'),
  ('00000000-0000-0000-0000-000000000707', 'unproven@x.bt', null, '{"full_name":"Un Proven"}');
set role authenticated;
select t.as_user('00000000-0000-0000-0000-000000000702');
select public.gym_register_member(:'gym_a', jsonb_build_object('full_name', 'Ugyen Proven', 'phone', '17700778',
  'email', 'unproven@x.bt', 'joined_on', public.bhutan_today())) ->> 'qr_token' as ugyen_qr \gset

select t.as_user('00000000-0000-0000-0000-000000000706');
select t.eq(public.my_person() ->> 'qr_token', :'sonam_qr', 'signed up with a confirmed email: the same QR code as at the desk');
select t.eq(jsonb_array_length(public.my_gyms() -> 'gyms'), 2, '...and both gyms in the app');
select t.eq((select count(*) from public.people where user_id = '00000000-0000-0000-0000-000000000706')::int, 1,
            '...one person');
select t.eq(jsonb_array_length(public.my_gyms() -> 'visits') >= 4, true, '...with their visits');

select t.as_user('00000000-0000-0000-0000-000000000707');
select t.eq((public.my_person() ->> 'qr_token') = :'ugyen_qr', false,
            'an email not yet confirmed takes nobody''s QR code');

-- ---- Jigme scans gym A's QR code and asks to join --------------------------
select t.as_user('00000000-0000-0000-0000-000000000703');
select t.fails(format($$select public.gym_request_to_join(%L)$$, :'gym_new'), 'isn''t taking members');
select t.fails(format($$select public.gym_request_to_join(%L, %L)$$, :'gym_a', :'plan_b'), 'one of the gym''s packages');
select public.gym_request_to_join(:'gym_a', :'plan_a', 'Mornings, please') as jigme_req \gset
select t.fails(format($$select public.gym_request_to_join(%L)$$, :'gym_a'), 'already asked');
select t.eq((select status from public.gym_join_requests where id = :'jigme_req'), 'pending', 'he sees his request waiting');
select t.eq(public.my_gyms() -> 'requests' -> 0 ->> 'plan_name', 'Monthly', '...with the package he chose');
select t.fails(format($$select public.gym_decline_join_request(%L)$$, :'jigme_req'), 'Only the gym''s staff');

select t.as_user('00000000-0000-0000-0000-000000000705');
select t.eq((select count(*) from public.gym_join_requests)::int, 0, 'a stranger sees nobody''s requests');
select public.my_person();
select t.eq((select count(*) from public.people)::int, 1, '...and of the people, only themselves');

select t.as_user('00000000-0000-0000-0000-000000000702');
select t.eq((select title from public.notifications where user_id = '00000000-0000-0000-0000-000000000702'
             order by created_at desc limit 1), 'New request to join', 'the front desk is told');
select t.eq((select p.full_name from public.gym_join_requests j join public.people p on p.id = j.person_id
             where j.id = :'jigme_req'), 'Jigme Dorji', '...and sees who asked');
select public.gym_person_details(:'gym_a', null, :'jigme_req') as jigme_details \gset
select t.eq(:'jigme_details'::jsonb -> 'details' ->> 'phone', '+97517700703', 'his account''s details fill the form');
select t.eq(:'jigme_details'::jsonb ->> 'plan_id', :'plan_a', '...with the package he asked for');
select public.gym_register_member(:'gym_a', jsonb_build_object('full_name', 'Jigme Dorji', 'phone', '17700703',
  'joined_on', public.bhutan_today()), :'plan_a', 1, 1500, 'cash', null, null, :'jigme_req') ->> 'gym_member_id' as jigme_at_a \gset
select t.eq((select (status, gym_member_id)::text from public.gym_join_requests where id = :'jigme_req'),
            '(approved,' || :'jigme_at_a' || ')', 'adding him approves the request');
select t.eq(public.gym_check_in_account(:'gym_a', '00000000-0000-0000-0000-000000000703') ->> 'member_name', 'Jigme Dorji',
            'his account''s old QR code checks him in where he''s registered');

select t.as_user('00000000-0000-0000-0000-000000000703');
select t.eq((select title from public.notifications where user_id = '00000000-0000-0000-0000-000000000703'
             order by created_at desc limit 1), 'Welcome to Alpha Gym', 'he''s told');
select t.eq(public.my_gyms() -> 'gyms' -> 0 ->> 'venue_name', 'Alpha Gym', '...and sees the gym in the app');
select t.fails(format($$select public.gym_request_to_join(%L)$$, :'gym_a'), 'already a member');
select t.fails(format($$select public.gym_check_in_member(%L, public.my_person() ->> 'qr_token')$$, :'gym_a'),
               'Only the gym''s staff');

-- ---- Tashi asks to join gym B and is declined ------------------------------
select t.as_user('00000000-0000-0000-0000-000000000704');
select public.gym_request_to_join(:'gym_b') as tashi_req \gset
select public.gym_request_to_join(:'gym_a') as tashi_req_a \gset
select public.gym_cancel_join_request(:'tashi_req_a');
select t.fails(format($$select public.gym_cancel_join_request(%L)$$, :'tashi_req_a'), 'isn''t waiting');
select t.as_user('00000000-0000-0000-0000-000000000702');
select public.gym_decline_join_request(:'tashi_req', 'We''re full until March');
select t.fails(format($$select public.gym_register_member(%L, '{"full_name":"Tashi Lhamo","phone":"17700704"}',
                        null, null, 0, null, null, null, %L)$$, :'gym_b', :'tashi_req'), 'isn''t waiting');
select t.as_user('00000000-0000-0000-0000-000000000704');
select t.eq((select body from public.notifications where user_id = '00000000-0000-0000-0000-000000000704'
             order by created_at desc limit 1), 'It wasn''t accepted. We''re full until March', 'she''s told why');
select t.eq((select string_agg(status, ',' order by created_at) from public.gym_join_requests), 'declined,cancelled',
            'she sees her own requests only');

-- ---- A new QR code -----------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-000000000706');
select public.my_person_new_qr() as sonam_new \gset
select t.as_user('00000000-0000-0000-0000-000000000702');
select t.fails(format($$select public.gym_check_in_member(%L, %L)$$, :'gym_a', :'sonam_qr'), 'isn''t valid any more');
select t.eq(public.gym_check_in_member(:'gym_a', :'sonam_new') ->> 'member_name', 'Sonam Choden',
            'the new one works (the desk sees the name the gym registered)');

reset role;
do $$ begin raise notice 'ALL PEOPLE CHECKS PASSED'; end $$;
