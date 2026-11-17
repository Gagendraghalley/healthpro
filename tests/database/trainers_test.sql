-- Trainers: runs after profile_test.sql (it uses the t.* helpers and super
-- admin A from scenario_test.sql). Owner O10 runs Zeta Gym and Eta Gym; desk
-- D10 works at Zeta only, desk D11 at Eta only. Tandin trains at both; Ugyen
-- asks Eta and is turned down; Meto, a member at Zeta, chooses Tandin; X10
-- is a stranger.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000001001', 'owner10@gym.bt', now(), '{"full_name":"Oden Owner"}'),
  ('00000000-0000-0000-0000-000000001002', 'desk10@gym.bt', now(), '{"full_name":"Deki Desk"}'),
  ('00000000-0000-0000-0000-000000001003', 'desk11@gym.bt', now(), '{"full_name":"Dorji Desk"}'),
  ('00000000-0000-0000-0000-000000001004', 'tandin@x.bt', now(), '{"full_name":"Tandin W."}'),
  ('00000000-0000-0000-0000-000000001005', 'ugyen@x.bt', now(), '{"full_name":"Ugyen Tshering"}'),
  ('00000000-0000-0000-0000-000000001006', 'meto@x.bt', now(), '{"full_name":"Meto Lhamo"}'),
  ('00000000-0000-0000-0000-000000001007', 'x10@x.bt', now(), '{"full_name":"Xi Stranger"}');
set role authenticated;

select t.as_user('00000000-0000-0000-0000-000000001001');
select public.register_venue('{"type":"gym","name":"Zeta Gym","dzongkhag":"Thimphu","phone":"+97517100001"}') as zeta \gset
select public.register_venue('{"type":"gym","name":"Eta Gym","dzongkhag":"Thimphu","phone":"+97517100002"}') as eta \gset
select t.as_user('00000000-0000-0000-0000-00000000000a');
select public.review_venue(:'zeta', true);
select public.review_venue(:'eta', true);
select t.as_user('00000000-0000-0000-0000-000000001001');
select public.gym_save_plan(:'zeta', null, 'Monthly', null, 30, 1500, true) as plan \gset
select public.add_venue_staff(:'zeta', 'desk10@gym.bt', 'staff');
select public.add_venue_staff(:'eta', 'desk11@gym.bt', 'staff');

-- ---- Tandin's profile ---------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-000000001004');
select t.fails(format($$select public.trainer_request_gym(%L)$$, :'zeta'), 'trainer profile first');
select t.fails($$select public.trainer_save_profile('{"display_name":"T"}')$$, 'the name as members');
select t.fails($$select public.trainer_save_profile('{"display_name":"Tandin","experience_years":"lots"}')$$, 'as a number');
select public.trainer_save_profile(jsonb_build_object(
  'display_name', 'Tandin  Wangchuk', 'headline', 'Strength and conditioning coach', 'bio', 'Ten years of lifting.',
  'specialties', '["Strength", "Yoga", "Strength"]'::jsonb, 'experience_years', 6,
  'photo_url', 'https://x.supabase.co/storage/v1/object/public/trainer-media/00000000-0000-0000-0000-000000001004/me.jpg'));
select t.eq((select display_name || ' ' || cardinality(specialties) from public.trainer_profiles
             where user_id = '00000000-0000-0000-0000-000000001004'), 'Tandin Wangchuk 2', 'a profile, tidied');
select t.fails($$select public.trainer_add_certificate('NSCA CSCS', null, null, 'https://evil.example/cert.pdf')$$, 'Upload the certificate');
select public.trainer_add_certificate('NSCA CSCS', 'NSCA', date '2020-05-01',
  'https://x.supabase.co/storage/v1/object/public/trainer-media/00000000-0000-0000-0000-000000001004/cscs.pdf');

set role anon;
select t.as_user(null);
select t.eq((select count(*) from public.trainer_profiles)::int, 0, 'not public until a gym verifies them');
set role authenticated;

select t.as_user('00000000-0000-0000-0000-000000001004');
select public.trainer_request_gym(:'zeta', 'Mornings and evenings');
select public.trainer_request_gym(:'eta');
select t.fails(format($$select public.trainer_request_gym(%L)$$, :'zeta'), 'asked Zeta Gym already');
select t.fails(format($$select public.trainer_save_slots(%L, '[{"weekday":1,"starts":"11:00","ends":"12:00"},{"weekday":1,"starts":"11:30","ends":"13:00"}]')$$, :'zeta'),
               'overlap');
select t.fails(format($$select public.trainer_save_slots(%L, '[{"weekday":1,"starts":"12:00","ends":"11:00"}]')$$, :'zeta'), 'end after');
select public.trainer_save_slots(:'zeta', '[{"weekday":1,"starts":"11:00","ends":"12:00"},{"weekday":3,"starts":"06:00","ends":"08:00"}]');
select t.fails(format($$select public.trainer_save_slots(%L, '[{"weekday":1,"starts":"11:30","ends":"12:30"}]')$$, :'eta'),
               'your time at another gym');
select public.trainer_save_slots(:'eta', '[{"weekday":1,"starts":"14:00","ends":"15:00"}]');

-- ---- The gyms check him -----------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-000000001002');
select t.eq((select title from public.notifications where user_id = '00000000-0000-0000-0000-000000001002' order by created_at desc limit 1),
            'New trainer request', 'Zeta''s desk is told');
select t.eq((select count(*) from public.trainer_certificates where user_id = '00000000-0000-0000-0000-000000001004')::int, 1,
            '...and sees his certificates to check');
select public.gym_decide_trainer(:'zeta', '00000000-0000-0000-0000-000000001004', true);
select t.fails(format($$select public.gym_decide_trainer(%L, '00000000-0000-0000-0000-000000001004', true)$$, :'eta'),
               'check trainers');
select t.as_user('00000000-0000-0000-0000-000000001003');
select public.gym_decide_trainer(:'eta', '00000000-0000-0000-0000-000000001004', true);

select t.as_user('00000000-0000-0000-0000-000000001004');
select t.eq((select title from public.notifications where user_id = '00000000-0000-0000-0000-000000001004' order by created_at desc limit 1),
            'You''re verified at Eta Gym', 'he''s told');

-- Ugyen asks Eta, and is turned down; Zeta still never hears of him.
select t.as_user('00000000-0000-0000-0000-000000001005');
select public.trainer_save_profile('{"display_name":"Ugyen Tshering"}');
select public.trainer_request_gym(:'eta');
select t.as_user('00000000-0000-0000-0000-000000001003');
select public.gym_decide_trainer(:'eta', '00000000-0000-0000-0000-000000001005', false, 'We need a CPR certificate');
select t.as_user('00000000-0000-0000-0000-000000001005');
select t.eq((select body from public.notifications where user_id = '00000000-0000-0000-0000-000000001005' order by created_at desc limit 1),
            'We need a CPR certificate', 'Ugyen is told why');

-- ---- What the public sees -----------------------------------------------------------
set role anon;
select t.as_user(null);
select t.eq((select string_agg(display_name, ',') from public.trainer_profiles), 'Tandin Wangchuk', 'only verified trainers are public');
select t.eq((select count(*) from public.gym_trainers where user_id = '00000000-0000-0000-0000-000000001004')::int, 2,
            '...with the gyms that verified them');
select t.eq((select string_agg(coalesce(venue_name, 'Not available') || ' ' || weekday || ' ' || starts_at, ', ' order by weekday, starts_at)
             from public.trainer_timings('00000000-0000-0000-0000-000000001004', :'zeta')),
            'Zeta Gym 1 11:00, Not available 1 14:00, Zeta Gym 3 06:00',
            'from Zeta''s page, his time at another gym is only Not available');
select t.eq((select count(*) from public.trainer_timings('00000000-0000-0000-0000-000000001004') where venue_name is null)::int, 0,
            'on his own profile, every gym''s times');
set role authenticated;

select t.as_user('00000000-0000-0000-0000-000000001002');
select t.eq((select count(*) from public.trainer_slots where user_id = '00000000-0000-0000-0000-000000001004')::int, 2,
            'Zeta''s desk reads only Zeta''s times directly');
select t.eq((select count(*) from jsonb_array_elements(public.gym_trainers_overview(:'zeta') -> 0 -> 'slots') e
             where (e ->> 'here')::boolean = false)::int, 1, '...and the rest as times elsewhere, unnamed');

-- ---- Attendance: the desk scans him, at each gym ---------------------------------------
select t.as_user('00000000-0000-0000-0000-000000001004');
select public.my_person() ->> 'qr_token' as tandin_qr \gset
select t.as_user('00000000-0000-0000-0000-000000001002');
select public.gym_check_in_member(:'zeta', :'tandin_qr') as arrived \gset
select t.eq((:'arrived'::jsonb ->> 'trainer')::boolean, true, 'his QR code at Zeta: a trainer arriving, not a member');
select t.eq(:'arrived'::jsonb ->> 'member_name', 'Tandin Wangchuk', '...by name');
select t.eq((:'arrived'::jsonb ->> 'also_member')::boolean, false, '...not a member there');
select t.as_user('00000000-0000-0000-0000-000000001003');
select public.gym_check_in_member(:'eta', :'tandin_qr');
select public.gym_check_in_member(:'eta', :'tandin_qr') as again \gset
select t.eq((:'again'::jsonb ->> 'already_marked')::boolean, true, 'scanned again the same day: already marked');
select t.eq((select count(*) from public.trainer_check_ins)::int, 1, 'Eta''s desk sees only Eta''s record, once a day');
select t.as_user('00000000-0000-0000-0000-000000001002');
select t.eq((select count(*) from public.trainer_check_ins)::int, 1, 'Zeta''s desk only Zeta''s');
select t.eq((public.gym_trainers_overview(:'zeta') -> 0 ->> 'attendance_30_days')::int, 1, '...in its trainers'' list too');
select t.as_user('00000000-0000-0000-0000-000000001004');
select t.eq((select string_agg(g ->> 'venue_name' || ' ' || jsonb_array_length(g -> 'attendance'), ', ' order by g ->> 'venue_name')
             from jsonb_array_elements(public.my_trainer_overview() -> 'gyms') g),
            'Eta Gym 1, Zeta Gym 1', 'Tandin sees all of it, gym by gym');
select t.as_user('00000000-0000-0000-0000-000000001005');
select public.my_person() ->> 'qr_token' as ugyen_qr \gset
select t.as_user('00000000-0000-0000-0000-000000001003');
select t.eq(public.gym_check_in_member(:'eta', :'ugyen_qr') ->> 'not_member', 'true', 'a trainer Eta turned down isn''t one there');

-- ---- Meto chooses Tandin ---------------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-000000001006');
select public.my_person() ->> 'qr_token' as meto_qr \gset
select t.as_user('00000000-0000-0000-0000-000000001002');
select public.gym_register_member(:'zeta', '{"full_name":"Meto Lhamo","phone":"17100006"}', :'plan', 1, 1500, 'cash', null,
                                  :'meto_qr') ->> 'gym_member_id' as meto \gset
select t.as_user('00000000-0000-0000-0000-000000001007');
select t.fails(format($$select public.gym_set_member_trainer(%L, '00000000-0000-0000-0000-000000001004')$$, :'meto'), 'Only the member');
select t.fails(format($$select public.save_trainer_review('00000000-0000-0000-0000-000000001004', 5)$$), 'trained with them');
select t.as_user('00000000-0000-0000-0000-000000001006');
select t.fails(format($$select public.gym_set_member_trainer(%L, '00000000-0000-0000-0000-000000001005')$$, :'meto'), 'verified trainers');
select t.eq(public.can_review_trainer('00000000-0000-0000-0000-000000001004'), false, 'not before he trains her');
select public.gym_set_member_trainer(:'meto', '00000000-0000-0000-0000-000000001004');
select t.eq(public.my_gyms() -> 'gyms' -> 0 -> 'trainer' ->> 'name', 'Tandin Wangchuk', 'she sees her trainer');
select t.as_user('00000000-0000-0000-0000-000000001004');
select t.eq((select body from public.notifications where user_id = '00000000-0000-0000-0000-000000001004'
             and title = 'New member'), 'Meto Lhamo at Zeta Gym chose you as their trainer.', 'he''s told');
select t.eq(public.my_trainer_overview() -> 'gyms' -> 1 -> 'members' -> 0 ->> 'name', 'Meto Lhamo', '...and sees her among his members');

-- The desk changes it, and back: both trainers hear.
select t.as_user('00000000-0000-0000-0000-000000001002');
select public.gym_set_member_trainer(:'meto', null);
select public.gym_set_member_trainer(:'meto', '00000000-0000-0000-0000-000000001004');
select t.eq((select count(*) from public.trainer_links where gym_member_id = :'meto')::int, 2, 'the desk keeps the history');
select t.as_user('00000000-0000-0000-0000-000000001006');
select t.eq((select title from public.notifications where user_id = '00000000-0000-0000-0000-000000001006' order by created_at desc limit 1),
            'Your trainer at Zeta Gym', 'the desk choosing: she''s told');

-- ---- Reviews ------------------------------------------------------------------------
select t.eq(public.can_review_trainer('00000000-0000-0000-0000-000000001004'), true, 'having trained with him, she may review him');
select public.save_trainer_review('00000000-0000-0000-0000-000000001004', 5, 'Patient and strict');
select t.eq((select rating_count || ' ' || rating_average from public.trainer_profiles
             where user_id = '00000000-0000-0000-0000-000000001004'), '1 5.00', 'his rating');
select t.as_user('00000000-0000-0000-0000-000000001004');
select t.fails($$select public.save_trainer_review('00000000-0000-0000-0000-000000001004', 5)$$, 'review yourself');
select t.eq((select title from public.notifications where user_id = '00000000-0000-0000-0000-000000001004'
             order by created_at desc limit 1), 'New review: 5 stars', 'he''s told of the review');

-- ---- A trainer who is a member there too ---------------------------------------------
select t.as_user('00000000-0000-0000-0000-000000001002');
select public.gym_register_member(:'zeta', '{"full_name":"Tandin Wangchuk","phone":"17100004"}', :'plan', 1, 1500, 'cash', null,
                                  :'tandin_qr');
select t.eq((public.gym_check_in_member(:'zeta', :'tandin_qr') ->> 'also_member')::boolean, true,
            'a trainer who is also a member: arriving, with the choice to check in as a member');
select t.eq(public.gym_check_in_member(:'zeta', :'tandin_qr', true) ->> 'plan_name', 'Monthly', '...as a member');

-- ---- Leaving a gym --------------------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-000000001004');
select public.trainer_leave_gym(:'eta');
select t.eq((select count(*) from public.trainer_slots where venue_id = :'eta')::int, 0, 'leaving a gym takes his times there');
select t.eq((select status from public.gym_trainers where venue_id = :'eta' and user_id = '00000000-0000-0000-0000-000000001004'),
            'inactive', '...and he''s no longer its trainer (verified, so his history there stays)');

-- ---- The gym adds a trainer itself ---------------------------------------------------
select t.as_user('00000000-0000-0000-0000-000000001006');
select t.fails(format($$select public.gym_add_trainer(%L, '00000000-0000-0000-0000-000000001007', '{"display_name":"Xi"}')$$, :'zeta'),
               'Only the gym');
select t.as_user('00000000-0000-0000-0000-000000001002');
select t.eq(public.can_add_gym_trainer(:'zeta'), true, 'the desk at Zeta may add trainers');
select t.eq(public.can_add_gym_trainer(:'eta'), false, '...not at Eta');
select t.fails(format($$select public.gym_add_trainer(%L, '00000000-0000-0000-0000-000000001007',
  '{"display_name":"Xi Trainer","photo_url":"https://evil.example/x.jpg"}')$$, :'zeta'), 'Upload the photo');
select t.fails(format($$select public.gym_add_trainer(%L, '00000000-0000-0000-0000-000000001007',
  '{"display_name":"Xi Trainer","certificates":[{"title":"CPR","file_url":"https://evil.example/c.pdf"}]}')$$, :'zeta'),
  'Upload the certificate');
select t.fails(format($$select public.gym_add_trainer(%L, '00000000-0000-0000-0000-000000001007',
  '{"display_name":"Xi Trainer","slots":[{"weekday":2,"starts":"09:00","ends":"08:00"}]}')$$, :'zeta'), 'end after');
select t.eq((select count(*) from public.trainer_profiles where user_id = '00000000-0000-0000-0000-000000001007')::int, 0,
            'nothing is kept of an addition that failed');
select t.eq((public.gym_add_trainer(:'zeta', '00000000-0000-0000-0000-000000001007', jsonb_build_object(
  'display_name', 'Xi  Trainer', 'headline', 'Yoga teacher', 'specialties', '["Yoga"]'::jsonb, 'experience_years', 3,
  'photo_url', 'https://x.supabase.co/storage/v1/object/public/trainer-media/gym/' || :'zeta' || '/xi.jpg',
  'certificates', jsonb_build_array(jsonb_build_object('title', 'Yoga Alliance RYT 200', 'issuer', 'Yoga Alliance',
     'issued_on', '2022-03-01',
     'file_url', 'https://x.supabase.co/storage/v1/object/public/trainer-media/gym/' || :'zeta' || '/ryt.pdf')),
  'slots', '[{"weekday":2,"starts":"07:00","ends":"09:00"}]'::jsonb)) ->> 'profile_made')::boolean, true,
  'the desk adds a trainer with all their details: their profile is made');
select t.eq((select status || ' ' || source from public.gym_trainers
             where venue_id = :'zeta' and user_id = '00000000-0000-0000-0000-000000001007'), 'verified gym',
            '...verified here straight away, added by the gym');
select t.eq((select display_name from public.trainer_profiles where user_id = '00000000-0000-0000-0000-000000001007'),
            'Xi Trainer', '...their name, tidied');
select t.eq((select count(*) from public.trainer_certificates where user_id = '00000000-0000-0000-0000-000000001007')::int, 1,
            '...their certificate');
select t.eq((select count(*) from public.trainer_slots where venue_id = :'zeta'
             and user_id = '00000000-0000-0000-0000-000000001007')::int, 1, '...and their week');
select t.as_user('00000000-0000-0000-0000-000000001007');
select t.eq((select title from public.notifications where user_id = '00000000-0000-0000-0000-000000001007'
             order by created_at desc limit 1), 'You''re a trainer at Zeta Gym', 'they''re told');
select t.eq((select count(*) from public.people where user_id = '00000000-0000-0000-0000-000000001007')::int, 1,
            'they have a QR code for the desk to scan');
select t.as_user('00000000-0000-0000-0000-000000001002');
select t.fails(format($$select public.gym_add_trainer(%L, '00000000-0000-0000-0000-000000001007', '{"display_name":"Xi"}')$$, :'zeta'),
               'trains here already');
select t.eq((select o ->> 'source' || ' ' || (o ->> 'email') from jsonb_array_elements(public.gym_trainers_overview(:'zeta')) o
             where o ->> 'user_id' = '00000000-0000-0000-0000-000000001007'), 'gym x10@x.bt', 'the gym sees how to reach them');
select public.gym_save_trainer_slots(:'zeta', '00000000-0000-0000-0000-000000001007',
  '[{"weekday":2,"starts":"07:00","ends":"09:00"},{"weekday":4,"starts":"17:00","ends":"19:00"}]');
select t.eq((select count(*) from public.trainer_slots where venue_id = :'zeta'
             and user_id = '00000000-0000-0000-0000-000000001007')::int, 2, 'the gym changes their times');
select t.eq((public.gym_trainer_mark_arrived(:'zeta', '00000000-0000-0000-0000-000000001007') ->> 'trainer')::boolean, true,
            'the desk records their arrival without their QR code');
select t.fails(format($$select public.gym_trainer_mark_arrived(%L, '00000000-0000-0000-0000-000000001005')$$, :'zeta'),
               'isn''t verified here');

-- Someone who is a trainer already keeps their own profile; their times elsewhere hold.
select t.as_user('00000000-0000-0000-0000-000000001003');
select t.fails(format($$select public.gym_add_trainer(%L, '00000000-0000-0000-0000-000000001004',
  '{"display_name":"Somebody Else","slots":[{"weekday":1,"starts":"11:30","ends":"12:30"}]}')$$, :'eta'), 'not available at that time');
select t.eq((public.gym_add_trainer(:'eta', '00000000-0000-0000-0000-000000001004',
  '{"display_name":"Somebody Else","slots":[{"weekday":1,"starts":"14:00","ends":"15:00"}]}') ->> 'profile_made')::boolean, false,
  'a gym adds back a trainer who left');
select t.eq((select display_name from public.trainer_profiles where user_id = '00000000-0000-0000-0000-000000001004'),
            'Tandin Wangchuk', '...his own profile stays as he wrote it');

-- ---- No bank account set up: no paying online ----------------------------------------
select t.as_user('00000000-0000-0000-0000-000000001006');
select t.fails(format($$select public.gym_claim_payment(%L, %L, 1, 1500, 'JRN777888')$$, :'zeta', :'plan'), 'bank account');
select t.eq(public.my_gyms() -> 'gyms' -> 0 -> 'payment_account', 'null'::jsonb, '...and her gym shows none');

reset role;
do $$ begin raise notice 'ALL TRAINER CHECKS PASSED'; end $$;
