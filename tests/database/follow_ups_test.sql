-- The activity log, enquiries and free trials, WhatsApp reminders and
-- birthday wishes: runs after scenario_test.sql (it uses its t.* helpers and
-- super admin A). Owner Oki runs Log Gym with manager Maya, front desk Dawa
-- and trainer Tashi; Xo is an outsider; Mindu has the app.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000f1001', 'log.owner@gym.bt', '{"full_name":"Oki Owner"}'),
  ('00000000-0000-0000-0000-0000000f1002', 'log.manager@gym.bt', '{"full_name":"Maya Manager"}'),
  ('00000000-0000-0000-0000-0000000f1003', 'log.desk@gym.bt', '{"full_name":"Dawa Desk"}'),
  ('00000000-0000-0000-0000-0000000f1004', 'log.trainer@gym.bt', '{"full_name":"Tashi Trainer"}'),
  ('00000000-0000-0000-0000-0000000f1005', 'log.outsider@x.bt', '{"full_name":"Xo Out"}'),
  ('00000000-0000-0000-0000-0000000f1006', 'log.mindu@x.bt', '{"full_name":"Mindu Member"}');
set role authenticated;

select t.as_user('00000000-0000-0000-0000-0000000f1001');
select public.register_venue('{"type":"gym","name":"Log Gym","dzongkhag":"Thimphu","phone":"+97517000501"}') as gym \gset
select t.as_user('00000000-0000-0000-0000-00000000000a');
select public.review_venue(:'gym', true);
select t.as_user('00000000-0000-0000-0000-0000000f1001');
select public.gym_save_plan(:'gym', null, 'Monthly', null, 30, 1500, true) as plan \gset
select public.gym_save_settings(:'gym', 'Bank of Bhutan', '200123456789', 'Log Gym', :'gym' || '/payment-qr.png', '{3}', 'desk');
select public.add_venue_staff(:'gym', 'log.manager@gym.bt', 'manager');
select public.add_venue_staff(:'gym', 'log.desk@gym.bt', 'staff');
select public.add_venue_staff(:'gym', 'log.trainer@gym.bt', 'trainer');

-- The gym's latest entry, as the owner sees it: 'action|summary|details|by|amount'.
create function pg_temp.last_entry(v uuid) returns text language sql as $$
  select action || '|' || summary || '|' || details || '|' || actor_name || '|' || coalesce(amount::text, '')
  from public.gym_audit_log where venue_id = v order by id desc limit 1
$$;
create function pg_temp.d(n int) returns text language sql as $$ select to_char(public.bhutan_today() + n, 'FMDD Mon YYYY') $$;
create function pg_temp.months(n int) returns text language sql as $$
  select to_char((public.bhutan_today() + make_interval(months => n))::date, 'FMDD Mon YYYY')
$$;

-- ---- The activity log ----------------------------------------------------
select t.eq(pg_temp.last_entry(:'gym'), 'staff.added|Added Tashi Trainer to the staff|As Trainer|Oki Owner|',
            'adding staff is logged, with their role');
select t.eq((select string_agg(details, ',' order by id) from public.gym_audit_log where venue_id = :'gym' and action = 'staff.added'),
            'As Owner,As Manager,As Front desk,As Trainer', 'the owner first, as the gym was registered');
select t.eq((select summary || '|' || details from public.gym_audit_log where venue_id = :'gym' and action = 'plan.added'),
            'Added the package Monthly|Nu. 1,500 for 30 days', 'and the new package, with its price');

select t.as_user('00000000-0000-0000-0000-0000000f1003');
select (public.gym_register_member(:'gym', jsonb_build_object('full_name', 'Sonam Log', 'phone', '17500001',
          'joined_on', public.bhutan_today()), :'plan', 3, 4500, 'cash', null) ->> 'gym_member_id') as sonam \gset
select code as sonam_code from public.gym_members where id = :'sonam' \gset
select t.as_user('00000000-0000-0000-0000-0000000f1001');
select t.eq(pg_temp.last_entry(:'gym'),
            'member.registered|Registered Sonam Log (' || :'sonam_code' || ')|Monthly, ' || pg_temp.d(0) || ' to ' || pg_temp.months(3)
              || ' · Nu. 4,500 cash · receipt 1|Dawa Desk|4500',
            'registering with a package and cash is one entry: the member, package, money and receipt, by the desk');

select t.as_user('00000000-0000-0000-0000-0000000f1003');
select public.gym_renew_member(:'sonam', :'plan', 1, 1500, 'mbob', '123456789');
select t.as_user('00000000-0000-0000-0000-0000000f1001');
select t.eq(pg_temp.last_entry(:'gym'),
            'membership.sold|Renewed Sonam Log''s membership|Monthly, ' || pg_temp.months(3) || ' to ' || pg_temp.months(4)
              || ' · Nu. 1,500 mBoB, JRN 123456789 · receipt 2|Dawa Desk|1500',
            'a renewal: the dates, the mBoB journal number and receipt');

select t.as_user('00000000-0000-0000-0000-0000000f1003');
select public.gym_update_member(:'sonam', jsonb_build_object('full_name', 'Sonam Log', 'phone', '17500009',
          'joined_on', public.bhutan_today(), 'blood_group', 'O+'));
select t.as_user('00000000-0000-0000-0000-0000000f1001');
select t.eq(pg_temp.last_entry(:'gym'),
            'member.edited|Changed Sonam Log''s details|Changed phone (was +97517500001), blood group|Dawa Desk|',
            'changed details say which, and the old phone number');
select t.as_user('00000000-0000-0000-0000-0000000f1003');
select public.gym_reissue_member_qr(:'sonam');
select t.as_user('00000000-0000-0000-0000-0000000f1001');
select t.eq(pg_temp.last_entry(:'gym'),
            'member.card_reissued|Gave Sonam Log a new QR card|Their old card no longer works|Dawa Desk|', 'a new card');

select t.as_user('00000000-0000-0000-0000-0000000f1003');
select public.gym_pause_member(:'sonam', public.bhutan_today() + 10, 14, 'Travelling');
select t.as_user('00000000-0000-0000-0000-0000000f1001');
select t.eq(pg_temp.last_entry(:'gym'),
            'membership.paused|Paused Sonam Log''s membership for 14 days|' || pg_temp.d(10) || ' to ' || pg_temp.d(23)
              || ' · Travelling|Dawa Desk|',
            'a pause, its days and why (the dates it moves aren''t entries of their own)');
select t.as_user('00000000-0000-0000-0000-0000000f1003');
select id as pause_id from public.gym_membership_pauses where gym_member_id = :'sonam' \gset
select public.gym_resume_member(:'pause_id');
select t.as_user('00000000-0000-0000-0000-0000000f1001');
select t.eq(pg_temp.last_entry(:'gym'),
            'membership.pause_taken_back|Took back Sonam Log''s pause|It was to run ' || pg_temp.d(10) || ' to ' || pg_temp.d(23)
              || '|Dawa Desk|',
            'and taking it back');

select public.gym_save_plan(:'gym', :'plan', 'Monthly', null, 30, 1600, true);
select t.eq(pg_temp.last_entry(:'gym'), 'plan.changed|Changed the package Monthly|price Nu. 1,500 to Nu. 1,600|Oki Owner|',
            'a new price, from what to what');

-- Mindu, on the app, pays online; the desk confirms it.
select t.as_user('00000000-0000-0000-0000-0000000f1006');
select public.my_person() ->> 'qr_token' as mindu_qr \gset
select t.as_user('00000000-0000-0000-0000-0000000f1003');
select public.gym_register_member(:'gym', '{"full_name":"Mindu Dema","phone":"17500002"}', null, null, 0, null, null,
                                  :'mindu_qr') ->> 'gym_member_id' as mindu \gset
select t.as_user('00000000-0000-0000-0000-0000000f1006');
select public.gym_claim_payment(:'gym', :'plan', 1, 1600, 'jrn778899') as claim \gset
select t.as_user('00000000-0000-0000-0000-0000000f1001');
select t.eq(pg_temp.last_entry(:'gym'), 'claim.sent|Mindu Dema paid Nu. 1,600 online|Monthly, 1 month · JRN JRN778899|Mindu Member|1600',
            'the member''s online payment, by them');
select t.as_user('00000000-0000-0000-0000-0000000f1003');
select public.gym_confirm_payment_claim(:'claim');
select t.as_user('00000000-0000-0000-0000-0000000f1001');
select t.eq(pg_temp.last_entry(:'gym'),
            'claim.confirmed|Confirmed Mindu Dema''s online payment of Nu. 1,600|Monthly, ' || pg_temp.d(0) || ' to ' || pg_temp.months(1)
              || ' · Nu. 1,600 bank transfer, JRN JRN778899 · receipt 3|Dawa Desk|1600',
            'confirming it is one entry, with the package and receipt it made');
select t.eq((select count(*) from public.gym_audit_log where gym_member_id = :'mindu')::int, 3,
            'Mindu''s: registered, paid online, confirmed');

-- Who sees it, and nobody changes it.
select count(*) as entries from public.gym_audit_log where venue_id = :'gym' \gset
select t.fails('delete from public.gym_audit_log', 'permission denied');
select t.fails(format($$update public.gym_audit_log set summary = 'x' where venue_id = %L$$, :'gym'), 'permission denied');
select t.fails(format($$insert into public.gym_audit_log (venue_id, action, summary) values (%L, 'x', 'x')$$, :'gym'),
               'permission denied');
select t.fails(format($$select public.gym_audit(%L, 'x', 'x')$$, :'gym'), 'permission denied');
select t.as_user('00000000-0000-0000-0000-0000000f1002');
select t.eq((select count(*) from public.gym_audit_log where venue_id = :'gym')::int, :entries, 'the manager sees it all');
select t.as_user('00000000-0000-0000-0000-0000000f1003');
select t.eq((select count(*) from public.gym_audit_log)::int, 0, 'the front desk doesn''t');
select t.as_user('00000000-0000-0000-0000-0000000f1005');
select t.eq((select count(*) from public.gym_audit_log)::int, 0, 'nor an outsider');

-- Without someone signed in (the daily job, the database itself): nothing.
reset role;
select set_config('request.jwt.claim.sub', '', false);
update public.gym_plans set price = 1700 where id = :'plan';
select t.eq((select count(*) from public.gym_audit_log where venue_id = :'gym')::int, :entries, 'no entry without a person');
set role authenticated;

-- ---- Enquiries and free trials ---------------------------------------------
select t.as_user('00000000-0000-0000-0000-0000000f1003');
select public.gym_save_enquiry(:'gym', null, jsonb_build_object('full_name', ' Karma Walkin ', 'phone', '17 50 00 21',
          'source', 'walk_in', 'interest', 'Weight loss, evenings', 'status', 'trial',
          'trial_starts_on', public.bhutan_today(), 'trial_ends_on', public.bhutan_today() + 2,
          'follow_up_on', public.bhutan_today() + 3)) as karma \gset
select t.eq((select full_name || '|' || phone || '|' || status || '|' || (trial_ends_on - trial_starts_on + 1)
             from public.gym_enquiries where id = :'karma'),
            'Karma Walkin|+97517500021|trial|3', 'the desk adds a walk-in on a 3-day free trial, tidied');
select t.fails(format($$select public.gym_save_enquiry(%L, null, '{"full_name":"Pem","phone":"17500022","status":"trial"}')$$,
                      :'gym'), 'first and last day');
select t.fails(format($$select public.gym_save_enquiry(%L, null, jsonb_build_object('full_name', 'Pem', 'phone', '17500022',
                        'status', 'trial', 'trial_starts_on', public.bhutan_today(), 'trial_ends_on', public.bhutan_today() + 30))$$,
                      :'gym'), '1 to 30 days');
select t.fails(format($$select public.gym_save_enquiry(%L, null, '{"full_name":"Pem","phone":"17500022","source":"radio"}')$$,
                      :'gym'), 'how they heard');
select t.fails(format($$select public.gym_save_enquiry(%L, null, '{"full_name":"Karma Again","phone":"+97517500021"}')$$,
                      :'gym'), 'on the enquiries list already');
select t.fails(format($$select public.gym_save_enquiry(%L, null, '{"full_name":"Sonam","phone":"17500009"}')$$, :'gym'),
               'registered here already');
select public.gym_save_enquiry(:'gym', :'karma', jsonb_build_object('full_name', 'Karma Walkin', 'phone', '17500021',
          'status', 'open', 'trial_starts_on', public.bhutan_today(), 'trial_ends_on', public.bhutan_today() + 2,
          'follow_up_on', public.bhutan_today() + 7, 'notes', 'Liked it; asks about couple rates'));
select t.eq((select status || '|' || follow_up_on || '|' || notes || '|' || source from public.gym_enquiries where id = :'karma'),
            'open|' || (public.bhutan_today() + 7) || '|Liked it; asks about couple rates|walk_in',
            'after the trial: following up in a week, the trial kept');

select t.as_user('00000000-0000-0000-0000-0000000f1004');
select t.fails(format($$select public.gym_save_enquiry(%L, null, '{"full_name":"Pem","phone":"17500022"}')$$, :'gym'),
               'can''t keep enquiries');
select t.eq((select count(*) from public.gym_enquiries)::int, 0, 'a trainer doesn''t see them');
select t.fails(format($$select public.gym_delete_enquiry(%L)$$, :'karma'), 'can''t keep enquiries');
select t.as_user('00000000-0000-0000-0000-0000000f1005');
select t.eq((select count(*) from public.gym_enquiries)::int, 0, 'nor an outsider');
select t.fails(format($$update public.gym_enquiries set status = 'lost' where id = %L$$, :'karma'), 'permission denied');
select t.as_user('00000000-0000-0000-0000-0000000f1002');
select t.eq((select count(*) from public.gym_enquiries where venue_id = :'gym')::int, 1, 'the manager does');

select t.as_user('00000000-0000-0000-0000-0000000f1003');
select (public.gym_register_member(:'gym', jsonb_build_object('full_name', 'Karma Walkin', 'phone', '+97517500021',
          'joined_on', public.bhutan_today()), :'plan', 1, 1600, 'cash', null) ->> 'gym_member_id') as karma_member \gset
select t.eq((select status || '|' || (gym_member_id = :'karma_member')::text from public.gym_enquiries where id = :'karma'),
            'joined|true', 'registering the same phone number marks the enquiry joined');
select public.gym_save_enquiry(:'gym', null, '{"full_name":"Pem Typo","phone":"17500022","source":"phone"}') as pem \gset
select public.gym_delete_enquiry(:'pem');
select t.eq((select count(*) from public.gym_enquiries where id = :'pem')::int, 0, 'a mistake comes off the list');

-- ---- WhatsApp reminders and wishes -----------------------------------------
select public.gym_note_message(:'sonam', 'renewal');
select t.as_user('00000000-0000-0000-0000-0000000f1001');
select t.eq(pg_temp.last_entry(:'gym'), 'member.reminded|Reminded Sonam Log on WhatsApp to renew||Dawa Desk|',
            'a reminder sent from the desk is noted, and logged');
select t.as_user('00000000-0000-0000-0000-0000000f1004');
select public.gym_note_message(:'mindu', 'birthday');
select t.eq((select count(*) from public.gym_member_messages where venue_id = :'gym')::int, 2,
            'a trainer, who sees members, wishes one too, and sees both');
select t.fails(format($$select public.gym_note_message(%L, 'promo')$$, :'sonam'), 'renewal reminder or a birthday');
select t.as_user('00000000-0000-0000-0000-0000000f1005');
select t.fails(format($$select public.gym_note_message(%L, 'renewal')$$, :'sonam'), 'can''t message members');
select t.eq((select count(*) from public.gym_member_messages)::int, 0, 'an outsider sees none');

-- ---- Birthday wishes ---------------------------------------------------------
reset role;
select t.eq(public.gym_is_birthday('1996-02-29', '2027-02-28'), true, 'born on 29 February: the 28th in other years');
select t.eq(public.gym_is_birthday('1996-02-29', '2028-02-28'), false, '...but the 29th in a leap year');
select t.eq(public.gym_is_birthday('1996-02-29', '2028-02-29'), true, '...which is their day');
select t.eq(public.gym_is_birthday('1990-11-18', '2026-11-18'), true, 'the same day and month');
select t.eq(public.gym_is_birthday(null, '2026-11-18'), false, 'no date of birth, no birthday');

select set_config('request.jwt.claim.sub', '', false);
update public.gym_members set date_of_birth = (public.bhutan_today() - interval '30 years')::date
where id in (:'mindu', :'sonam');
select public.gym_birthday_wishes();
select t.eq((select title from public.notifications where user_id = '00000000-0000-0000-0000-0000000f1006'
             order by created_at desc limit 1), 'Happy birthday, Mindu!', 'Mindu, with the app and a package, gets a wish');
select t.eq((select count(*) from public.gym_birthday_wishes_sent where gym_member_id in (:'mindu', :'sonam'))::int, 1,
            'Sonam, without the app, doesn''t');
select public.gym_birthday_wishes();
select t.eq((select count(*) from public.notifications where user_id = '00000000-0000-0000-0000-0000000f1006'
             and title like 'Happy birthday%')::int, 1, 'once a year');
set role authenticated;
select t.fails('select public.gym_birthday_wishes()', 'permission denied');

reset role;
do $$ begin raise notice 'ALL ACTIVITY, ENQUIRY AND FOLLOW-UP CHECKS PASSED'; end $$;
