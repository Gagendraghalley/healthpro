-- Body progress, workout and diet plans, and group classes: runs after
-- scenario_test.sql (it uses its t.* helpers and super admin A). Owner Wangmo
-- runs Coach Gym with front desk Dechen; Tashi trains Mindu there (Mindu has
-- the app); Sonam and Pem have no app; Kinley is another trainer, not
-- Mindu's; Xo is an outsider.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000f3001', 'coach.owner@gym.bt', '{"full_name":"Wangmo Owner"}'),
  ('00000000-0000-0000-0000-0000000f3002', 'coach.desk@gym.bt', '{"full_name":"Dechen Desk"}'),
  ('00000000-0000-0000-0000-0000000f3003', 'coach.tashi@x.bt', '{"full_name":"Tashi Trainer"}'),
  ('00000000-0000-0000-0000-0000000f3004', 'coach.mindu@x.bt', '{"full_name":"Mindu Member"}'),
  ('00000000-0000-0000-0000-0000000f3005', 'coach.outsider@x.bt', '{"full_name":"Xo Out"}'),
  ('00000000-0000-0000-0000-0000000f3006', 'coach.kinley@x.bt', '{"full_name":"Kinley Trainer"}');
-- Mindu's notifications, whoever is signed in.
create function t.mindu_notes() returns setof public.notifications language sql security definer as $$
  select * from public.notifications where user_id = '00000000-0000-0000-0000-0000000f3004'
$$;
grant execute on function t.mindu_notes() to authenticated;
set role authenticated;

select t.as_user('00000000-0000-0000-0000-0000000f3001');
select public.register_venue('{"type":"gym","name":"Coach Gym","dzongkhag":"Thimphu","phone":"+97517000701"}') as gym \gset
select t.as_user('00000000-0000-0000-0000-00000000000a');
select public.review_venue(:'gym', true);
select t.as_user('00000000-0000-0000-0000-0000000f3001');
select public.gym_save_plan(:'gym', null, 'Monthly', null, 30, 1500, true) as plan \gset
select public.add_venue_staff(:'gym', 'coach.desk@gym.bt', 'staff');

-- Tashi and Kinley train at Coach Gym.
select t.as_user('00000000-0000-0000-0000-0000000f3003');
select public.trainer_save_profile('{"display_name":"Tashi Trainer"}');
select public.trainer_request_gym(:'gym');
select t.as_user('00000000-0000-0000-0000-0000000f3006');
select public.trainer_save_profile('{"display_name":"Kinley Trainer"}');
select public.trainer_request_gym(:'gym');
select t.as_user('00000000-0000-0000-0000-0000000f3001');
select public.gym_decide_trainer(:'gym', '00000000-0000-0000-0000-0000000f3003', true);
select public.gym_decide_trainer(:'gym', '00000000-0000-0000-0000-0000000f3006', true);

-- Mindu (with the app) joins and chooses Tashi; Sonam and Pem join at the desk.
select t.as_user('00000000-0000-0000-0000-0000000f3004');
select public.my_person() ->> 'qr_token' as mindu_qr \gset
select t.as_user('00000000-0000-0000-0000-0000000f3002');
select public.gym_register_member(:'gym', '{"full_name":"Mindu Dema","phone":"17700001"}', :'plan', 1, 1500, 'cash', null,
                                  :'mindu_qr') ->> 'gym_member_id' as mindu \gset
select public.gym_register_member(:'gym', '{"full_name":"Sonam Coach","phone":"17700002"}', :'plan', 1, 1500, 'cash', null)
  ->> 'gym_member_id' as sonam \gset
select public.gym_register_member(:'gym', '{"full_name":"Pem Nopackage","phone":"17700003"}') ->> 'gym_member_id' as pem \gset
select t.as_user('00000000-0000-0000-0000-0000000f3004');
select public.gym_set_member_trainer(:'mindu', '00000000-0000-0000-0000-0000000f3003');

-- ---- Progress ------------------------------------------------------------------
select public.gym_save_measurement(:'mindu', null, jsonb_build_object('weight_kg', 70.25)) as mine \gset
select t.eq((select weight_kg::text || '|' || measured_on || '|' || recorded_by_name from public.gym_body_measurements where id = :'mine'),
            '70.3|' || public.bhutan_today() || '|Mindu Member', 'Mindu logs her own weight, today, to one decimal');
select t.fails(format($$select public.gym_save_measurement(%L, null, '{"note":"felt good"}')$$, :'mindu'), 'at least one');
select t.fails(format($$select public.gym_save_measurement(%L, null, '{"weight_kg":5}')$$, :'mindu'), '10 to 400 kg');
select t.fails(format($$select public.gym_save_measurement(%L, null, jsonb_build_object('weight_kg', 70,
                        'measured_on', public.bhutan_today() + 1))$$, :'mindu'), 'today or before');

select t.as_user('00000000-0000-0000-0000-0000000f3003');
select public.gym_save_measurement(:'mindu', null, '{"weight_kg":69.5,"height_cm":172,"waist_cm":80}') as tashis \gset
select t.eq((select recorded_by_name || '|' || height_cm::text from public.gym_body_measurements where id = :'tashis'),
            'Tashi Trainer|172.0', 'her trainer records weight, height and waist');
select t.eq((select count(*) from public.gym_body_measurements where gym_member_id = :'mindu')::int, 2, 'and sees both');
select t.fails(format($$select public.gym_save_measurement(%L, null, '{"weight_kg":80}')$$, :'sonam'), 'Only the member');

select t.as_user('00000000-0000-0000-0000-0000000f3004');
select t.fails(format($$select public.gym_save_measurement(%L, %L, '{"weight_kg":60}')$$, :'mindu', :'tashis'),
               'Only your trainer or the gym');
select t.fails(format($$select public.gym_delete_measurement(%L)$$, :'tashis'), 'Only your trainer or the gym');
select public.gym_delete_measurement(:'mine');
select t.eq((select count(*) from public.gym_body_measurements)::int, 1, 'she removes her own, and sees the rest');

select t.as_user('00000000-0000-0000-0000-0000000f3006');
select t.fails(format($$select public.gym_save_measurement(%L, null, '{"weight_kg":60}')$$, :'mindu'), 'Only the member');
select t.eq((select count(*) from public.gym_body_measurements)::int, 0, 'another trainer sees none of hers');
select t.as_user('00000000-0000-0000-0000-0000000f3005');
select t.eq((select count(*) from public.gym_body_measurements)::int, 0, 'nor an outsider');
select t.as_user('00000000-0000-0000-0000-0000000f3002');
select public.gym_save_measurement(:'sonam', null, '{"weight_kg":82,"body_fat_pct":24}');
select t.eq((select count(*) from public.gym_body_measurements where venue_id = :'gym')::int, 2, 'the desk records and sees anyone''s');

-- ---- Plans -----------------------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-0000000f3003');
select public.gym_save_member_plan(:'mindu', null, '{"kind":"workout","title":"Strength, 3 days","content":"Day 1: squats 3x10"}')
  as workout \gset
select t.eq((select author_name || '|' || kind || '|' || is_active from public.gym_member_plans where id = :'workout'),
            'Tashi Trainer|workout|true', 'her trainer gives her a workout plan');
select t.eq((select title || '|' || body from t.mindu_notes()
             order by created_at desc limit 1),
            'A new workout plan for you|Strength, 3 days, from Tashi Trainer. Open My gym to read it.', 'and she''s told');
select t.fails(format($$select public.gym_save_member_plan(%L, null, '{"kind":"yoga","title":"x y","content":"z"}')$$, :'mindu'),
               'workout or a diet');
select t.fails(format($$select public.gym_save_member_plan(%L, null, '{"title":"Strength","content":" "}')$$, :'mindu'),
               'Write the plan');
select public.gym_save_member_plan(:'mindu', :'workout', '{"kind":"workout","title":"Strength, 3 days","content":"Day 1: squats 4x8"}');
select t.eq((select title from t.mindu_notes()
             order by created_at desc limit 1), 'Your workout plan was updated', 'new words: she''s told again');
select count(*) as told from t.mindu_notes() \gset
select public.gym_save_member_plan(:'mindu', :'workout',
  '{"kind":"workout","title":"Strength, 3 days","content":"Day 1: squats 4x8","is_active":false}');
select t.eq((select count(*) from t.mindu_notes())::int, :told,
            'put away, not told');
select public.gym_save_member_plan(:'mindu', :'workout', '{"kind":"workout","title":"Strength, 3 days","content":"Day 1: squats 4x8"}');

select t.as_user('00000000-0000-0000-0000-0000000f3004');
select t.eq((select count(*) from public.gym_member_plans)::int, 1, 'Mindu reads her plan');
select t.fails(format($$select public.gym_save_member_plan(%L, null, '{"title":"My own","content":"run"}')$$, :'mindu'),
               'trainer and the gym''s staff');
select t.as_user('00000000-0000-0000-0000-0000000f3006');
select t.eq((select count(*) from public.gym_member_plans)::int, 0, 'another trainer doesn''t');
select t.as_user('00000000-0000-0000-0000-0000000f3002');
select public.gym_save_member_plan(:'sonam', null, '{"kind":"diet","title":"Less sugar","content":"Breakfast: eggs"}') as diet \gset
select public.gym_delete_member_plan(:'diet');
select t.eq((select count(*) from public.gym_member_plans where gym_member_id = :'sonam')::int, 0,
            'the desk gives Sonam (no app) a diet plan, and removes it');

select t.as_user('00000000-0000-0000-0000-0000000f3003');
select t.eq((select m ->> 'full_name' || '|' || (m ->> 'latest_weight') || '|' || (m ->> 'active_plans') || '|' || (m ->> 'venue_name')
             from jsonb_array_elements(public.trainer_my_members()) m),
            'Mindu Dema|69.5|1|Coach Gym', 'Tashi sees his member: latest weight, plans, gym');
select t.as_user('00000000-0000-0000-0000-0000000f3006');
select t.eq(jsonb_array_length(public.trainer_my_members()), 0, 'Kinley has no members');

-- ---- Classes --------------------------------------------------------------------
select public.bhutan_today() + 1 as tomorrow \gset
select extract(isodow from date :'tomorrow')::int as dow \gset
select extract(isodow from public.bhutan_today())::int as today_dow \gset
select t.as_user('00000000-0000-0000-0000-0000000f3001');
select public.gym_save_class(:'gym', null, jsonb_build_object('name', 'Yoga', 'trainer_name', 'Tashi', 'weekday', :dow,
                             'starts_at', '07:00', 'duration_minutes', 60, 'capacity', 1)) as yoga \gset
select public.gym_save_class(:'gym', null, jsonb_build_object('name', 'Midnight run', 'weekday', :today_dow,
                             'starts_at', '00:00', 'capacity', 10)) as early \gset
select t.fails(format($$select public.gym_save_class(%L, null, '{"name":"Zumba","weekday":9,"starts_at":"18:00","capacity":5}')$$,
                      :'gym'), 'day of the week');
select t.fails(format($$select public.gym_save_class(%L, null, '{"name":"Zumba","weekday":1,"starts_at":"18:00","capacity":0}')$$,
                      :'gym'), 'Places');
select t.as_user('00000000-0000-0000-0000-0000000f3002');
select t.fails(format($$select public.gym_save_class(%L, null, '{"name":"Zumba","weekday":1,"starts_at":"18:00","capacity":5}')$$,
                      :'gym'), 'change its timetable');
set role anon;
select t.eq((select count(*) from public.gym_classes where venue_id = :'gym')::int, 2, 'anyone sees the timetable');
set role authenticated;

select t.as_user('00000000-0000-0000-0000-0000000f3004');
select public.gym_book_class(:'yoga', :'tomorrow') as booking \gset
select t.eq((select p ->> 'booked' || '|' || (p ->> 'my_booking_id')
             from jsonb_array_elements(public.gym_class_places(:'gym', public.bhutan_today())) p where p ->> 'class_id' = :'yoga'),
            '1|' || :'booking', 'Mindu books herself into tomorrow''s Yoga, and sees it''s hers');
select t.fails(format($$select public.gym_book_class(%L, %L)$$, :'yoga', :'tomorrow'), 'booked in already');
select t.fails(format($$select public.gym_book_class(%L, %L::date + 1)$$, :'yoga', :'tomorrow'), 'isn''t on that day');
select t.fails(format($$select public.gym_book_class(%L, %L::date + 14)$$, :'yoga', :'tomorrow'), 'two weeks ahead');
select t.fails(format($$select public.gym_book_class(%L, public.bhutan_today())$$, :'early'), 'started already');
select t.fails(format($$select public.gym_book_class(%L, %L, %L)$$, :'yoga', :'tomorrow', :'sonam'), 'Only the gym''s staff');

select t.as_user('00000000-0000-0000-0000-0000000f3002');
select t.fails(format($$select public.gym_book_class(%L, %L, %L)$$, :'yoga', :'tomorrow', :'sonam'), 'is full');
select t.fails(format($$select public.gym_book_class(%L, %L, %L)$$, :'yoga', :'tomorrow', :'pem'), 'has no package');
select t.as_user('00000000-0000-0000-0000-0000000f3001');
select public.gym_save_class(:'gym', :'yoga', jsonb_build_object('name', 'Yoga', 'trainer_name', 'Tashi', 'weekday', :dow,
                             'starts_at', '07:00', 'duration_minutes', 60, 'capacity', 2));
select t.as_user('00000000-0000-0000-0000-0000000f3002');
select public.gym_book_class(:'yoga', :'tomorrow', :'sonam') as sonam_booking \gset
select t.eq((select count(*) from public.gym_class_bookings where class_id = :'yoga' and status = 'booked')::int, 2,
            'two places: the desk books Sonam too, and sees both');
select public.gym_pause_member(:'mindu', (date :'tomorrow' + 7), 1);
select t.fails(format($$select public.gym_book_class(%L, %L::date + 7, %L)$$, :'yoga', :'tomorrow', :'mindu'), 'paused on');

select t.as_user('00000000-0000-0000-0000-0000000f3004');
select t.eq((select count(*) from public.gym_class_bookings)::int, 1, 'Mindu sees only her own booking');
select t.fails(format($$select public.gym_cancel_class_booking(%L)$$, :'sonam_booking'), 'Only the member and the gym');
select public.gym_cancel_class_booking(:'booking');
select t.eq((select status from public.gym_class_bookings where id = :'booking'), 'cancelled', 'and cancels it');
select public.gym_book_class(:'yoga', :'tomorrow') as booking \gset
select t.as_user('00000000-0000-0000-0000-0000000f3005');
select t.fails(format($$select public.gym_book_class(%L, %L)$$, :'yoga', :'tomorrow'), 'Only members of this gym');

-- Off the timetable: tomorrow's bookings are cancelled, and Mindu is told.
select t.as_user('00000000-0000-0000-0000-0000000f3001');
select public.gym_save_class(:'gym', :'yoga', jsonb_build_object('name', 'Yoga', 'weekday', :dow, 'starts_at', '07:00',
                             'capacity', 2, 'is_active', false));
select t.eq((select count(*) from public.gym_class_bookings where class_id = :'yoga' and status = 'booked')::int, 0,
            'taking Yoga off the timetable cancels its bookings');
select t.eq((select title from t.mindu_notes()
             order by created_at desc limit 1), 'Yoga on ' || to_char(date :'tomorrow', 'FMDy FMDD Mon') || ' was cancelled',
            'and Mindu is told');
select t.eq((select count(*) from public.gym_classes where venue_id = :'gym')::int, 2, 'the owner still sees it');
set role anon;
select t.eq((select count(*) from public.gym_classes where venue_id = :'gym')::int, 1, 'the public doesn''t');

reset role;
do $$ begin raise notice 'ALL PROGRESS, PLAN AND CLASS CHECKS PASSED'; end $$;
