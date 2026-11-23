-- One date of a class changed or cancelled on its own (20261123000001):
-- runs after class_emails_test.sql (its Coach Gym, owner Wangmo, front desk
-- Dechen, Mindu with the app, Sonam without one, and Xo, who isn't a member).
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
select id as gym from public.venues where name = 'Coach Gym' \gset
select id as sonam from public.gym_members where venue_id = :'gym' and full_name = 'Sonam Coach' \gset
select public.bhutan_today() + 1 as tomorrow \gset
select public.bhutan_today() + 8 as next_week \gset
select extract(isodow from date :'tomorrow')::int as dow \gset
select to_char(date :'tomorrow', 'FMDy FMDD Mon') as day \gset
select public.email_configure('https://abc.supabase.co/functions/v1/send-email');
delete from private.email_outbox;
set role authenticated;

select t.as_user('00000000-0000-0000-0000-0000000f3001');
select public.gym_save_class(:'gym', null, jsonb_build_object('name', 'Pilates', 'trainer_name', 'Tashi', 'weekday', :dow,
                             'starts_at', '09:00', 'duration_minutes', 45, 'capacity', 3)) as pilates \gset
select t.as_user('00000000-0000-0000-0000-0000000f3005');
select public.gym_book_class(:'pilates', :'tomorrow') as xo_booking \gset
select t.as_user('00000000-0000-0000-0000-0000000f3004');
select public.gym_book_class(:'pilates', :'tomorrow') as mindu_booking \gset

-- Only who has Classes changes a date, on the class's day, up to two weeks ahead, never below those booked.
select t.as_user('00000000-0000-0000-0000-0000000f3005');
select t.fails(format($$select public.gym_save_class_day(%L, %L, '{"capacity": 5}')$$, :'pilates', :'tomorrow'),
               'Only the gym''s staff with Classes');
select t.as_user('00000000-0000-0000-0000-0000000f3002');
select t.fails(format($$select public.gym_save_class_day(%L, %L, '{"capacity": 5}')$$, :'pilates', date :'tomorrow' + 1),
               'isn''t on that day');
select t.fails(format($$select public.gym_save_class_day(%L, %L, '{"capacity": 5}')$$, :'pilates', date :'tomorrow' + 14),
               'up to two weeks ahead');
select t.fails(format($$select public.gym_save_class_day(%L, %L, '{"capacity": 1}')$$, :'pilates', :'tomorrow'),
               'Booked in already: 2');

-- The desk changes tomorrow only: a new time, trainer and places, with a note.
select public.gym_save_class_day(:'pilates', :'tomorrow', jsonb_build_object('starts_at', '10:00', 'duration_minutes', 60,
                                 'trainer_name', 'Kinley', 'capacity', 2, 'note', 'Tashi is away.'));
reset role;
select t.eq((select concat_ws('|', starts_at, duration_minutes, trainer_name, capacity) from public.gym_classes where id = :'pilates'),
            '09:00:00|45|Tashi|3', 'the timetable keeps its own: every other week as before');
select t.eq((select concat_ws('|', c.starts_at, c.trainer_name, c.capacity)
             from public.gym_classes w cross join lateral public.gym_class_on(w, :'tomorrow') c where w.id = :'pilates'),
            '10:00:00|Kinley|2', 'tomorrow runs as changed');
select t.eq((select public.gym_class_start(w, :'tomorrow') from public.gym_classes w where w.id = :'pilates'),
            (date :'tomorrow' + time '10:00') at time zone 'Asia/Thimphu', 'and starts at its own time');
select t.eq((select concat_ws('|', title, body, link) from public.notifications
             where user_id = '00000000-0000-0000-0000-0000000f3004' and title like 'Pilates on % has changed'),
            'Pilates on ' || :'day' || ' has changed|Now 10:00 AM to 11:00 AM (was 9:00 AM to 9:45 AM). Trainer: Kinley (was Tashi). '
            || 'Places: 2 (was 3). Tashi is away. Your place is kept.|/gyms/my?gym=' || :'gym',
            'Mindu is told what changed that day, with the note');
select t.eq((select string_agg(concat_ws(':', to_email, data ->> 'starts_at', data -> 'before' ->> 'starts_at', data -> 'dates' ->> 0),
                               ',' order by to_email)
             from private.email_outbox where kind = 'class_changed'),
            'coach.mindu@x.bt:10:00:09:00:' || :'tomorrow' || ',coach.outsider@x.bt:10:00:09:00:' || :'tomorrow',
            'and each one booked is emailed it');
set role authenticated;
select t.as_user('00000000-0000-0000-0000-0000000f3004');
select t.eq((select string_agg(concat_ws('|', e ->> 'starts_at', e ->> 'trainer_name', e ->> 'duration_minutes'), ',')
             from jsonb_array_elements(public.my_class_bookings()) e where e ->> 'name' = 'Pilates'),
            '10:00:00|Kinley|60', 'My dashboard shows the day''s time and trainer');

-- The date's places count, more than the timetable's too.
select t.as_user('00000000-0000-0000-0000-0000000f3002');
select t.fails(format($$select public.gym_book_class(%L, %L, %L)$$, :'pilates', :'tomorrow', :'sonam'), 'is full');
select public.gym_save_class_day(:'pilates', :'tomorrow', '{"capacity": 4}');
select public.gym_book_class(:'pilates', :'tomorrow', :'sonam');
select t.as_user('00000000-0000-0000-0000-0000000f3001');
select public.gym_book_class(:'pilates', :'tomorrow') as owner_booking \gset
select t.eq((select (e ->> 'booked')::int from jsonb_array_elements(public.gym_class_places(:'gym', :'tomorrow', 1)) e
             where e ->> 'class_id' = :'pilates'), 4, 'four booked: the date''s places, past the timetable''s three');
select t.eq((select concat_ws('|', starts_at, trainer_name, capacity, note) from public.gym_class_days
             where class_id = :'pilates' and class_date = :'tomorrow'),
            '10:00:00|Kinley|4', 'the time and trainer left out stay as the date has them; the note goes with its message');

-- Changing the class every week leaves the changed date as it is, and doesn't tell its people.
reset role;
delete from private.email_outbox;
set role authenticated;
select public.gym_save_class(:'gym', :'pilates', jsonb_build_object('name', 'Pilates', 'trainer_name', 'Tashi', 'weekday', :dow,
                             'starts_at', '08:00', 'duration_minutes', 45, 'capacity', 3));
reset role;
select t.eq((select count(*) from public.notifications where title = 'Pilates has changed')::int, 0,
            'nobody booked on the changed date is told of the weekly change');
select t.eq((select count(*) from private.email_outbox where kind = 'class_changed')::int, 0, 'nor emailed');
select t.eq((select public.gym_class_start(w, :'tomorrow') from public.gym_classes w where w.id = :'pilates'),
            (date :'tomorrow' + time '10:00') at time zone 'Asia/Thimphu', 'the date keeps its own time');

-- Anyone sees the date's change, signed in or not (the gym's page).
set role anon;
select t.eq((select count(*) from public.gym_class_days where class_id = :'pilates')::int, 1, 'the gym''s page sees it');
set role authenticated;
select t.as_user('00000000-0000-0000-0000-0000000f3005');
select t.fails(format($$insert into public.gym_class_days (class_id, class_date, venue_id, starts_at, duration_minutes, capacity)
                        values (%L, %L, %L, '06:00', 30, 50)$$, :'pilates', :'next_week', :'gym'), 'permission denied');

-- Back to the timetable: not with more booked than its places; then everyone is told.
select t.as_user('00000000-0000-0000-0000-0000000f3002');
select t.fails(format($$select public.gym_clear_class_day(%L, %L)$$, :'pilates', :'tomorrow'),
               'Booked in already: 4, and the timetable has 3 places');
select public.gym_cancel_class_booking(:'owner_booking');
select public.gym_clear_class_day(:'pilates', :'tomorrow');
reset role;
select t.eq((select count(*) from public.gym_class_days where class_id = :'pilates')::int, 0, 'the date is as the timetable has it');
select t.eq((select body from public.notifications
             where user_id = '00000000-0000-0000-0000-0000000f3004' and title like 'Pilates on % has changed' and body like 'Now 8%'),
            'Now 8:00 AM to 8:45 AM (was 10:00 AM to 11:00 AM). Trainer: Tashi (was Kinley). Places: 3 (was 4). Your place is kept.',
            'and Mindu is told it''s back');

-- Cancelling the date: everyone's place goes, each is told why, and it can't be booked.
delete from private.email_outbox;
set role authenticated;
select public.gym_save_class_day(:'pilates', :'tomorrow', '{"is_cancelled": true, "note": "Public holiday."}');
reset role;
select t.eq((select count(*) from public.gym_class_bookings
             where class_id = :'pilates' and class_date = :'tomorrow' and status = 'booked')::int, 0, 'every place is cancelled');
select t.eq((select concat_ws('|', title, body, link) from public.notifications
             where user_id = '00000000-0000-0000-0000-0000000f3004' and title like 'Pilates on % is cancelled'),
            'Pilates on ' || :'day' || ' is cancelled|The gym isn''t holding it that day, so your place was cancelled. Public holiday. '
            || 'See its classes on My gym to book another.|/gyms/my?gym=' || :'gym',
            'Mindu is told, with the gym''s note');
select t.eq((select string_agg(concat_ws(':', to_email, data ->> 'reason', data ->> 'note'), ',' order by to_email)
             from private.email_outbox where kind = 'class_cancelled'),
            'coach.mindu@x.bt:day:Public holiday.,coach.outsider@x.bt:day:Public holiday.', 'and emailed why');
set role authenticated;
select t.as_user('00000000-0000-0000-0000-0000000f3005');
select t.fails(format($$select public.gym_book_class(%L, %L)$$, :'pilates', :'tomorrow'), 'is cancelled');
select public.gym_book_class(:'pilates', :'next_week');

-- Moved to another day: its dates to come go with it.
select t.as_user('00000000-0000-0000-0000-0000000f3001');
select public.gym_save_class(:'gym', :'pilates', jsonb_build_object('name', 'Pilates', 'trainer_name', 'Tashi', 'weekday', :dow % 7 + 1,
                             'starts_at', '08:00', 'duration_minutes', 45, 'capacity', 3));
reset role;
select t.eq((select count(*) from public.gym_class_days where class_id = :'pilates')::int, 0, 'moved: its changed dates go');

select public.email_configure(null);
do $$ begin raise notice 'ALL CLASS DAY CHECKS PASSED'; end $$;
