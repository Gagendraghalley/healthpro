-- A venue's public profile, prices for the list of gyms, and reviews by
-- registered members: runs after payments_test.sql (it uses the t.* helpers
-- and super admin A from scenario_test.sql). Owner O9 registers Epsilon Gym;
-- Dawa, a member the desk registered, reviews it; X9 is a stranger.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000901', 'owner9@gym.bt', now(), '{"full_name":"Oza Owner"}'),
  ('00000000-0000-0000-0000-000000000902', 'dawa9@x.bt', now(), '{"full_name":"Dawa Zangmo"}'),
  ('00000000-0000-0000-0000-000000000903', 'x9@x.bt', now(), '{"full_name":"Xen Stranger"}');
set role authenticated;

-- ---- The profile ------------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-000000000901');
select public.register_venue(jsonb_build_object(
  'type', 'gym', 'name', 'Epsilon Gym', 'dzongkhag', 'Thimphu', 'phone', '+97517900901',
  'email', ' Hello@Epsilon.BT ', 'contact_person', '  Oza   Owner ',
  'latitude', 27.4728, 'longitude', 89.6390,
  'opening_hours', '{"mon": [["06:00", "10:00"], ["16:00", "21:00"]], "sun": []}'::jsonb,
  'facilities', '["Shower", "Massage", " shower ", "Steam   room"]'::jsonb,
  'videos', '["https://www.youtube.com/watch?v=abc123", "https://fb.watch/xyz/"]'::jsonb)) as gym \gset
select t.eq((select email || '|' || contact_person || '|' || latitude || ',' || longitude from public.venues where id = :'gym'),
            'hello@epsilon.bt|Oza Owner|27.4728,89.639', 'email, contact person and the place on the map');
select t.eq((select facilities from public.venues where id = :'gym'), '{Shower,Massage,"Steam room"}'::text[],
            'facilities, tidied, no repeats');
select t.eq((select opening_hours -> 'mon' -> 1 ->> 0 from public.venues where id = :'gym'), '16:00',
            'opening hours: two periods on Monday');
select t.eq((select opening_hours -> 'sun' from public.venues where id = :'gym'), '[]'::jsonb, '...closed on Sunday');
select t.eq((select cardinality(videos) from public.venues where id = :'gym'), 2, 'video links');

select t.fails(format($$select public.update_venue(%L, '{"opening_hours": {"mon": [["10:00", "06:00"]]}}')$$, :'gym'), 'close after it opens');
select t.fails(format($$select public.update_venue(%L, '{"opening_hours": {"mon": [["06:00", "12:00"], ["11:00", "20:00"]]}}')$$, :'gym'),
               'second opening time');
select t.fails(format($$select public.update_venue(%L, '{"opening_hours": {"mon": [["6am", "9pm"]]}}')$$, :'gym'), 'HH:MM');
select t.fails(format($$select public.update_venue(%L, '{"opening_hours": {"funday": []}}')$$, :'gym'), 'day by day');
select t.fails(format($$select public.update_venue(%L, '{"videos": ["https://evil.example/v"]}')$$, :'gym'), 'YouTube or Facebook');
select t.fails(format($$select public.update_venue(%L, '{"facilities": ["x"]}')$$, :'gym'), 'between 2 and 40');
select t.fails(format($$select public.update_venue(%L, '{"latitude": 51.5, "longitude": -0.12}')$$, :'gym'), 'isn''t in Bhutan');
select t.fails(format($$select public.update_venue(%L, '{"latitude": 27.4, "longitude": null}')$$, :'gym'), 'on the map');
select t.fails(format($$select public.update_venue(%L, jsonb_build_object('photos',
                        (select jsonb_agg('https://x.bt/' || i) from generate_series(1, 31) i)))$$, :'gym'), 'Up to 30 photos');
select public.update_venue(:'gym', jsonb_build_object('photos', (select jsonb_agg('https://x.bt/' || i) from generate_series(1, 30) i)));
select t.eq((select cardinality(photos) from public.venues where id = :'gym'), 30, 'up to 30 photos');
select public.update_venue(:'gym', '{"opening_hours": null, "facilities": [], "contact_person": ""}');
select t.eq((select (opening_hours is null, cardinality(facilities), contact_person is null)::text from public.venues where id = :'gym'),
            '(t,0,t)', 'and cleared');

-- ---- The promotional video: one clip, in the gym's folder ---------------------
select t.as_user('00000000-0000-0000-0000-000000000901');
select t.fails(format($$select public.set_venue_promo_video(%L, %L)$$, :'gym', :'gym' || '/promo.mp4'), 'Upload the video');
insert into storage.objects (bucket_id, name) values ('venue-videos', :'gym' || '/promo.mp4');
select public.set_venue_promo_video(:'gym', :'gym' || '/promo.mp4');
select t.eq((select promo_video from public.venues where id = :'gym'), :'gym' || '/promo.mp4', 'the owner sets the promotional video');
select t.fails(format($$select public.set_venue_promo_video(%L, 'https://evil.example/v.mp4')$$, :'gym'), 'Upload the video');
select t.fails(format($$select public.set_venue_promo_video(%L, %L)$$, :'gym', :'gym' || '/promo.exe'), 'Upload the video');
insert into storage.objects (bucket_id, name) values ('venue-videos', :'gym' || '/next.mp4');
select t.fails(format($$insert into storage.objects (bucket_id, name) values ('venue-videos', %L)$$, :'gym' || '/third.mp4'),
               'row-level security');
select t.as_user('00000000-0000-0000-0000-000000000903');
select t.fails(format($$select public.set_venue_promo_video(%L, null)$$, :'gym'), 'can edit this venue');
select t.fails($$insert into storage.objects (bucket_id, name) values ('venue-videos', 'not-a-venue/a.mp4')$$, 'row-level security');
select t.as_user('00000000-0000-0000-0000-000000000901');
select public.set_venue_promo_video(:'gym', null);
select t.eq((select promo_video from public.venues where id = :'gym'), null, '...and removes it');

-- ---- Prices, for the list of gyms -------------------------------------------
select public.gym_save_plan(:'gym', null, 'Monthly', null, 30, 2000, true) as plan \gset
select public.gym_save_plan(:'gym', null, 'Yearly', null, 365, 10000, true);
select public.gym_save_plan(:'gym', null, 'Old', null, 30, 500, false);
reset role;
select t.eq((select count(*) from public.gym_price_ranges() where venue_id = :'gym')::int, 0, 'not on the list until verified');
set role authenticated;
select t.as_user('00000000-0000-0000-0000-00000000000a');
select public.review_venue(:'gym', true);
set role anon;
select t.as_user(null);
select t.eq((select lowest || '-' || highest from public.gym_price_ranges() where venue_id = :'gym'), '2000-10000',
            'visitors see the lowest and highest price on sale');
set role authenticated;

-- ---- Reviews by registered members -------------------------------------------
select t.as_user('00000000-0000-0000-0000-000000000902');
select public.my_person() ->> 'qr_token' as dawa_qr \gset
select t.fails(format($$select public.save_review(%L, 5, 'Great')$$, :'gym'), '');
select t.as_user('00000000-0000-0000-0000-000000000901');
select public.gym_register_member(:'gym', '{"full_name":"Dawa Zangmo","phone":"17900902"}', :'plan', 1, 2000, 'cash', null, :'dawa_qr');
select t.as_user('00000000-0000-0000-0000-000000000902');
select public.save_review(:'gym', 5, 'Clean, and the trainers know their stuff');
select t.eq((select rating_count from public.venues where id = :'gym'), 1, 'a member the desk registered reviews the gym');
select t.as_user('00000000-0000-0000-0000-000000000903');
select t.fails(format($$select public.save_review(%L, 1, 'Never been')$$, :'gym'), '');

reset role;
do $$ begin raise notice 'ALL PROFILE CHECKS PASSED'; end $$;
