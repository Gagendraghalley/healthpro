-- Organisation types (20261127000001): runs after scenario_test.sql (its t.*
-- helpers and super admin A), last. Owner Pema runs a yoga studio, a type the
-- team adds; Xo keeps no master data.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000f7001', 'types.owner@x.bt', '{"full_name":"Pema Owner"}'),
  ('00000000-0000-0000-0000-0000000f7002', 'types.outsider@x.bt', '{"full_name":"Xo Types"}');

-- The master comes with the kinds of health business, in order; the gym's filled in.
select t.eq((select string_agg(name, ', ' order by sort_order, name) from public.venue_types where key in
              ('gym', 'fitness_centre', 'swimming', 'cycling', 'sports_facility', 'wellness_centre')),
            'Gym, Fitness Centre, Swimming Pool, Cycling, Sports Facility, Wellness Centre', 'six types to start with');
select t.eq((select bool_and(module_key = 'gym_membership' and is_active) from public.venue_types), true,
            'all run by gym membership, all in use');
select t.eq((select 'Sauna' = any (facilities) and description is not null from public.venue_types where key = 'gym'), true,
            'the gym has its description and facilities');
select t.eq((select count(*) from public.venues where module_key is null)::int, 0, 'every venue knows its module');

-- Only who keeps the master data adds or changes a type.
set role authenticated;
select t.as_user('00000000-0000-0000-0000-0000000f7002');
select t.fails($$select public.save_venue_type(null, '{"name": "Yoga Studio"}')$$, 'Only people who keep the master data');
select t.as_user('00000000-0000-0000-0000-00000000000a');
select public.save_venue_type(null, jsonb_build_object(
  'name', '  Yoga   Studio ', 'description', 'Yoga and meditation classes', 'icon', 'yoga', 'sort_order', 70,
  'facilities', jsonb_build_array(' Mats ', 'Meditation room', 'mats', ''))) as yoga \gset
select t.eq(:'yoga'::text, 'yoga_studio', 'its key is made from its name');
select t.eq((select concat_ws('|', name, icon, sort_order, array_to_string(facilities, ',')) from public.venue_types where key = 'yoga_studio'),
            'Yoga Studio|yoga|70|Mats,Meditation room', 'name tidied, facilities trimmed and kept once');
select t.fails($$select public.save_venue_type(null, '{"name": "yoga studio"}')$$, 'already a type called');
select t.fails($$select public.save_venue_type('gym', '{"name": "Swimming Pool"}')$$, 'already a type called');
select t.fails($$select public.save_venue_type(null, '{"name": "Y"}')$$, '2 to 60 letters');
select t.fails($$select public.save_venue_type('nope', '{"name": "Nope"}')$$, 'no longer exists');

-- A yoga studio registers and runs on the same packages, members and check-in as a gym.
select t.as_user('00000000-0000-0000-0000-0000000f7001');
select public.register_venue('{"type":"yoga_studio","name":"Lotus Yoga","dzongkhag":"Paro","phone":"+97517007001"}') as studio \gset
reset role;
select t.eq((select module_key from public.venues where id = :'studio'), 'gym_membership', 'the studio is run by gym membership');
set role authenticated;
select t.as_user('00000000-0000-0000-0000-00000000000a');
select public.review_venue(:'studio', true);
select t.as_user('00000000-0000-0000-0000-0000000f7001');
select public.gym_save_plan(:'studio', null, '10 yoga sessions', null, 30, 1200, true);
select public.gym_save_class(:'studio', null, jsonb_build_object('name', 'Morning Flow', 'trainer_name', 'Tashi', 'weekday', 1,
                             'starts_at', '07:00', 'duration_minutes', 60, 'capacity', 12));
reset role;
select t.eq((select count(*) from public.gym_audit_log where venue_id = :'studio')::int > 0, true,
            'its activity log keeps what happens there');

-- Visitors find its services by name.
set role anon;
select t.as_user(null);
select t.eq((select array_to_string(services, ', ') from public.gym_venue_services() where venue_id = :'studio'),
            '10 yoga sessions, Morning Flow', 'its packages and classes, for searching');
set role authenticated;

-- Turned off: no new ones; those registered keep it. Deleting one in use is refused.
select t.as_user('00000000-0000-0000-0000-00000000000a');
select public.save_venue_type('yoga_studio', '{"name": "Yoga Studio", "icon": "yoga", "sort_order": 70, "active": false}');
select t.as_user('00000000-0000-0000-0000-0000000f7001');
select t.fails($$select public.register_venue('{"type":"yoga_studio","name":"Lotus Two","dzongkhag":"Paro","phone":"+97517007002"}')$$,
               'can''t be registered right now');
select t.eq((select type from public.venues where id = :'studio'), 'yoga_studio', 'the studio keeps its type');
select t.as_user('00000000-0000-0000-0000-00000000000a');
select t.fails($$select public.delete_venue_type('yoga_studio')$$, '1 organisation is of this type');
select public.save_venue_type(null, '{"name": "Climbing Wall", "icon": "climb"}');
select public.delete_venue_type('climbing_wall');
select t.eq((select count(*) from public.venue_types where key = 'climbing_wall')::int, 0, 'one nobody has is deleted');

-- Each card's look (20261127000002): a colour each to start; colour, cover photo and Coming soon saved.
reset role;
select t.eq((select string_agg(key || ':' || color, ',' order by sort_order) from public.venue_types
             where key in ('gym', 'swimming', 'wellness_centre')), 'gym:orange,swimming:blue,wellness_centre:teal',
            'the types start with a colour each');
select t.eq((select public from storage.buckets where id = 'service-type-photos'), true, 'cover photos are public');
set role authenticated;
select t.as_user('00000000-0000-0000-0000-00000000000a');
select public.save_venue_type('yoga_studio', jsonb_build_object(
  'name', 'Yoga Studio', 'icon', 'yoga', 'sort_order', 70, 'color', 'pink', 'show_when_empty', false,
  'photo', 'https://abc.supabase.co/storage/v1/object/public/service-type-photos/yoga_studio/1.jpg'));
reset role;
select t.eq((select concat_ws('|', color, show_when_empty, photo like '%/service-type-photos/yoga_studio/1.jpg')
             from public.venue_types where key = 'yoga_studio'), 'pink|f|t', 'colour, Coming soon off, photo');
set role authenticated;
select t.as_user('00000000-0000-0000-0000-00000000000a');
select t.fails($$select public.save_venue_type('yoga_studio', '{"name": "Yoga Studio", "photo": "javascript:alert(1)"}')$$,
               'Upload the cover photo again');
select t.fails($$select public.save_venue_type('yoga_studio', '{"name": "Yoga Studio", "color": "#FF0000"}')$$, 'Choose a colour');
select public.save_venue_type('yoga_studio', '{"name": "Yoga Studio", "icon": "yoga", "sort_order": 70}');
reset role;
select t.eq((select concat_ws('|', coalesce(color, '-'), coalesce(photo, '-'), show_when_empty) from public.venue_types
             where key = 'yoga_studio'), '-|-|t', 'none given: no colour, no photo, shown while empty');

-- Inventory is out of the app; its permission is now Suppliers, still the owner's and manager's.
reset role;
select t.eq((select name from public.permissions where key = 'gym.inventory'), 'Suppliers', 'the permission reads Suppliers');
select t.eq((select count(*) from public.role_permissions rp join public.roles r on r.id = rp.role_id
             where rp.permission_key = 'gym.inventory' and r.key in ('owner', 'manager'))::int > 0, true,
            'owners and managers keep it');

do $$ begin raise notice 'ALL ORGANISATION TYPE CHECKS PASSED'; end $$;
