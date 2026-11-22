-- Emails about classes (20261119000001), and the app told of every change
-- (20261119000002): runs after coaching_test.sql (its Coach Gym, owner
-- Wangmo, front desk Dechen, Mindu with the app, Sonam without one, and Xo,
-- who isn't a member). Nothing goes out here (no pg_net): the point is
-- what's queued, for whom, and that send-email claims each email once.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
select id as gym from public.venues where name = 'Coach Gym' \gset
select id as sonam from public.gym_members where venue_id = :'gym' and full_name = 'Sonam Coach' \gset
update public.venues set address = 'Norzin Lam', town = 'Thimphu' where id = :'gym';
select public.bhutan_today() + 1 as tomorrow \gset
select extract(isodow from date :'tomorrow')::int as dow \gset
select to_char(date :'tomorrow', 'FMDy FMDD Mon') as day \gset
set role authenticated;

select t.as_user('00000000-0000-0000-0000-0000000f3001');
select public.gym_save_class(:'gym', null, jsonb_build_object('name', 'Spin', 'trainer_name', 'Tashi', 'weekday', :dow,
                             'starts_at', '09:00', 'duration_minutes', 45, 'capacity', 5)) as spin \gset

-- Until send-email is set up, nothing is queued; the app is still told of a change.
select t.as_user('00000000-0000-0000-0000-0000000f3005');
select public.gym_book_class(:'spin', :'tomorrow') as xo_booking \gset
select t.as_user('00000000-0000-0000-0000-0000000f3001');
select public.gym_save_class(:'gym', :'spin', jsonb_build_object('name', 'Spin', 'description', 'Bring water', 'trainer_name', 'Tashi',
                             'weekday', :dow, 'starts_at', '09:00', 'duration_minutes', 45, 'capacity', 5));
reset role;
select t.eq((select count(*) from private.email_outbox)::int, 0, 'until send-email is set up, nothing is queued');
select t.eq((select string_agg(concat_ws('|', title, body, link), ',') from public.notifications
             where user_id = '00000000-0000-0000-0000-0000000f3005' and title = 'Spin has changed'),
            'Spin has changed|New description. Your place on ' || :'day' || ' is kept.|/gyms/' || :'gym',
            'but the app tells Xo of the change, with the gym''s page');
select t.eq((select string_agg(distinct concat_ws('|', body, link), ',') from public.notifications
             where title = 'New class booking' and body like '%Spin%'),
            'Xo Out booked Spin on ' || :'day' || ' at 9:00 AM. They aren''t a member here yet.|/gyms/' || :'gym' || '/manage/classes',
            'Xo booking a class tells the gym who, which class, when, and links to Classes');
select t.eq((select string_agg(user_id::text, ',' order by user_id) from public.notifications
             where title = 'New class booking' and body like '%Spin%'),
            '00000000-0000-0000-0000-0000000f3001,00000000-0000-0000-0000-0000000f3002,00000000-0000-0000-0000-0000000f3008',
            'everyone whose role has Classes: the owner, the front desk and the class host; not Xo');
set role authenticated;
select t.fails($$select public.email_configure('https://abc.supabase.co/functions/v1/send-email')$$, 'permission denied');
reset role;
select t.fails($$select public.email_configure('https://evil.example/steal')$$, 'send-email function''s address');
select public.email_configure('https://abc.supabase.co/functions/v1/send-email');

-- Booking: Xo (not a member) and Mindu (her account's email); Sonam has no email.
set role authenticated;
select t.as_user('00000000-0000-0000-0000-0000000f3005');
select public.gym_cancel_class_booking(:'xo_booking');
select public.gym_book_class(:'spin', :'tomorrow') as xo_booking \gset
select t.as_user('00000000-0000-0000-0000-0000000f3004');
select public.gym_book_class(:'spin', :'tomorrow') as mindu_booking \gset
select t.as_user('00000000-0000-0000-0000-0000000f3002');
select public.gym_book_class(:'spin', :'tomorrow', :'sonam');
reset role;
select t.eq((select string_agg(to_email || ':' || kind, ',' order by to_email) from private.email_outbox),
            'coach.mindu@x.bt:class_booked,coach.outsider@x.bt:class_booked',
            'booking emails Xo, and Mindu at her account''s email; not Sonam (none); cancelling one''s own sends nothing');
select t.eq((select count(*) from public.notifications
             where user_id = '00000000-0000-0000-0000-0000000f3001' and title = 'New class booking' and body like '%Spin%')::int, 3,
            'the owner is told of each booking members make themselves (Xo twice, Mindu)');
select t.eq((select count(*) from public.notifications where title = 'New class booking' and body like 'Sonam%')::int, 0,
            'not of the desk booking Sonam in');
select t.eq((select concat_ws('|', data ->> 'class', data ->> 'date', data ->> 'starts_at', data ->> 'minutes', data ->> 'trainer',
                              data ->> 'gym', data ->> 'address', data ->> 'phone', data ->> 'name')
             from private.email_outbox where to_email = 'coach.outsider@x.bt'),
            'Spin|' || :'tomorrow' || '|09:00|45|Tashi|Coach Gym|Norzin Lam, Thimphu|+97517000701|Xo Out',
            'with the class, day, time, length, trainer, the gym, where it is and its phone');

-- send-email claims each once; one that failed is tried again.
set role authenticated;
select t.fails($$select public.email_claim_pending(10)$$, 'permission denied');
select t.fails($$select count(*) from private.email_outbox$$, 'permission denied');
set role service_role;
select public.email_claim_pending(10) as claimed \gset
select t.eq(jsonb_array_length(:'claimed'::jsonb), 2, 'send-email claims what''s waiting');
select t.eq(jsonb_array_length(public.email_claim_pending(10)), 0, 'each once');
select public.email_finish(array[(:'claimed'::jsonb -> 0 ->> 'id')::uuid],
                           jsonb_build_array(jsonb_build_object('id', :'claimed'::jsonb -> 1 ->> 'id', 'error', '421 Try later')));
select public.email_claim_pending(10) as again \gset
select t.eq((select string_agg(e ->> 'to', ',') from jsonb_array_elements(:'again'::jsonb) e), :'claimed'::jsonb -> 1 ->> 'to',
            'the one that failed is tried again; the one sent isn''t');
select public.email_finish(null, jsonb_build_array(jsonb_build_object('id', :'again'::jsonb -> 0 ->> 'id', 'error', '421 Try later')));
select public.email_finish(null, jsonb_build_array(jsonb_build_object('id', (public.email_claim_pending(10) -> 0 ->> 'id'), 'error', 'x')));
select t.eq(jsonb_array_length(public.email_claim_pending(10)), 0, 'three tries at most');
reset role;
select t.eq((select count(*) from private.email_outbox where sent_at is not null)::int, 1, 'and the one sent is marked so');

-- Any change reaches everyone booked, by email and in the app: more places, members only.
set role authenticated;
select t.as_user('00000000-0000-0000-0000-0000000f3001');
select public.gym_save_class(:'gym', :'spin', jsonb_build_object('name', 'Spin', 'description', 'Bring water', 'trainer_name', 'Tashi',
                             'weekday', :dow, 'starts_at', '09:00', 'duration_minutes', 45, 'capacity', 8,
                             'open_to_all', false));
reset role;
select t.eq((select string_agg(concat_ws(':', to_email, data -> 'before' ->> 'capacity', data ->> 'capacity',
                                         data -> 'before' ->> 'open_to_all', data ->> 'open_to_all'), ',' order by to_email)
             from private.email_outbox where kind = 'class_changed'),
            'coach.mindu@x.bt:5:8:true:false,coach.outsider@x.bt:5:8:true:false',
            'more places, members only: each one booked is emailed');
select t.eq((select string_agg(concat_ws('|', n.user_id, n.body, n.link), ',' order by n.user_id) from public.notifications n
             where n.title = 'Spin has changed' and n.body like 'Places%'),
            concat_ws('|', '00000000-0000-0000-0000-0000000f3004',
                      'Places: 8 (was 5). Now for the gym''s members only. Your place on ' || :'day' || ' is kept.',
                      '/gyms/my?gym=' || :'gym') || ','
            || concat_ws('|', '00000000-0000-0000-0000-0000000f3005',
                         'Places: 8 (was 5). Now for the gym''s members only. Your place on ' || :'day' || ' is kept.',
                         '/gyms/' || :'gym'),
            'and told in the app: Mindu to My gym, Xo to the gym''s page; not Sonam (no account)');

-- A new time and trainer: everyone booked, once each.
delete from private.email_outbox where kind = 'class_changed';
set role authenticated;
select public.gym_save_class(:'gym', :'spin', jsonb_build_object('name', 'Spin', 'description', 'Bring water', 'trainer_name', 'Kinley',
                             'weekday', :dow, 'starts_at', '10:00', 'duration_minutes', 45, 'capacity', 8,
                             'open_to_all', false));
reset role;
select t.eq((select body from public.notifications
             where user_id = '00000000-0000-0000-0000-0000000f3004' and title = 'Spin has changed' and body like 'Now%'),
            'Now 10:00 AM to 10:45 AM (was 9:00 AM to 9:45 AM). Trainer: Kinley (was Tashi). Your place on ' || :'day' || ' is kept.',
            'the app says what changed');
select t.eq((select string_agg(concat_ws(':', to_email, data ->> 'starts_at', data ->> 'trainer', data -> 'before' ->> 'starts_at',
                                         data -> 'before' ->> 'trainer', data -> 'dates' ->> 0), ',' order by to_email)
             from private.email_outbox where kind = 'class_changed'),
            'coach.mindu@x.bt:10:00:Kinley:09:00:Tashi:' || :'tomorrow' || ',coach.outsider@x.bt:10:00:Kinley:09:00:Tashi:' || :'tomorrow',
            'a new time and trainer: each one booked is emailed what changed');

-- The desk cancels Mindu's place; then the class moves to another day.
set role authenticated;
select t.as_user('00000000-0000-0000-0000-0000000f3002');
select public.gym_cancel_class_booking(:'mindu_booking');
reset role;
select t.eq((select concat_ws('|', title, body, link) from public.notifications
             where user_id = '00000000-0000-0000-0000-0000000f3004' and title like 'Spin on %was cancelled'),
            'Spin on ' || :'day' || ' was cancelled|The gym cancelled your place. See its classes on My gym to book another.|/gyms/my?gym='
            || :'gym',
            'the desk cancelling Mindu''s place tells her in the app too');
set role authenticated;
select t.as_user('00000000-0000-0000-0000-0000000f3001');
select public.gym_save_class(:'gym', :'spin', jsonb_build_object('name', 'Spin', 'description', 'Bring water', 'trainer_name', 'Kinley',
                             'weekday', :dow % 7 + 1, 'starts_at', '10:00', 'duration_minutes', 45, 'capacity', 8,
                             'open_to_all', false));
reset role;
select t.eq((select string_agg(to_email || ':' || (data ->> 'reason'), ',' order by to_email)
             from private.email_outbox where kind = 'class_cancelled'),
            'coach.mindu@x.bt:gym,coach.outsider@x.bt:moved',
            'the gym cancelling a place emails them why: the desk did, or the class moved to another day');
select t.eq((select count(*) from private.email_outbox where kind = 'class_changed')::int, 2, 'moving it isn''t also a change');

select public.email_configure(null);
select t.eq(private.emails_on(), false, 'send-email without SMTP: nothing more is queued');
do $$ begin raise notice 'ALL CLASS EMAIL CHECKS PASSED'; end $$;
