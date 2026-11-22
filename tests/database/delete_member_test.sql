-- Deleting a member from a gym: runs after scenario_test.sql (it uses its t.*
-- helpers and super admin A). Owner Ola runs Delete Gym with front desk Deki
-- (registers and takes payments) and registrar Rabi (registers, no
-- payments); Xi is an outsider; Mila has an account and is Sonam at the gym.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000de0001', 'delete.owner@gym.bt', '{"full_name":"Ola Owner"}'),
  ('00000000-0000-0000-0000-000000de0002', 'delete.desk@gym.bt', '{"full_name":"Deki Desk"}'),
  ('00000000-0000-0000-0000-000000de0003', 'delete.registrar@gym.bt', '{"full_name":"Rabi Registrar"}'),
  ('00000000-0000-0000-0000-000000de0004', 'delete.outsider@x.bt', '{"full_name":"Xi Out"}'),
  ('00000000-0000-0000-0000-000000de0005', 'delete.mila@x.bt', '{"full_name":"Mila Member"}');
set role authenticated;

select t.as_user('00000000-0000-0000-0000-000000de0001');
select public.register_venue('{"type":"gym","name":"Delete Gym","dzongkhag":"Thimphu","phone":"+97517000501"}') as gym \gset
select t.as_user('00000000-0000-0000-0000-00000000000a');
select public.review_venue(:'gym', true);
select public.save_role(null, 'venue', 'Delete registrar', null, true, array['gym.register', 'gym.members']) as registrar \gset
select t.as_user('00000000-0000-0000-0000-000000de0001');
select public.gym_save_plan(:'gym', null, 'Monthly', null, 30, 1500, true) as plan \gset
select public.add_venue_staff(:'gym', 'delete.desk@gym.bt', 'staff');
select public.add_venue_staff(:'gym', 'delete.registrar@gym.bt', 'delete_registrar');

select t.as_user('00000000-0000-0000-0000-000000de0002');
select (public.gym_register_member(:'gym', jsonb_build_object('full_name', 'Sonam Delete', 'phone', '17500001',
          'joined_on', public.bhutan_today()), :'plan', 1, 1500, 'cash', null) ->> 'gym_member_id') as sonam \gset
select code as sonam_code from public.gym_members where id = :'sonam' \gset
select (public.gym_register_member(:'gym', jsonb_build_object('full_name', 'Pema Walkin', 'phone', '17500002',
          'joined_on', public.bhutan_today())) ->> 'gym_member_id') as pema \gset
select person_id as pema_person from public.gym_members where id = :'pema' \gset
select public.gym_check_in_by_code(:'gym', :'sonam_code');
select public.gym_pause_member(:'sonam', public.bhutan_today() + 5, 7, 'Travel');
reset role;
-- Sonam signs up as Mila's account: the desk's registration becomes theirs.
update public.people set user_id = '00000000-0000-0000-0000-000000de0005'
where id = (select person_id from public.gym_members where id = :'sonam');
select person_id as sonam_person from public.gym_members where id = :'sonam' \gset
select count(*) as payments_before from public.payments where venue_id = :'gym' \gset
set role authenticated;

-- ---- Who may delete, and when ----------------------------------------------
select t.as_user('00000000-0000-0000-0000-000000de0004');
select t.fails(format($$select public.gym_delete_member(%L, true)$$, :'sonam'), 'can''t delete members');
select t.as_user('00000000-0000-0000-0000-000000de0003');
select t.fails(format($$select public.gym_delete_member(%L, true)$$, :'sonam'), 'Only staff who take payments');
select t.as_user('00000000-0000-0000-0000-000000de0002');
select t.fails(format($$select public.gym_delete_member(%L)$$, :'sonam'), 'still active until');
reset role;
insert into public.gym_payment_claims (venue_id, gym_member_id, user_id, plan_id, plan_name, months, amount, jrn)
values (:'gym', :'sonam', '00000000-0000-0000-0000-000000de0005', :'plan', 'Monthly', 1, 1500, 'DEL12345')
returning id as claim \gset
set role authenticated;
select t.fails(format($$select public.gym_delete_member(%L, true)$$, :'sonam'), 'waiting to be checked');
reset role;
update public.gym_payment_claims set status = 'rejected' where id = :'claim';
set role authenticated;

-- ---- No package, no account: the registrar deletes them ---------------------
select t.as_user('00000000-0000-0000-0000-000000de0003');
select t.eq((public.gym_delete_member(:'pema') ->> 'told')::boolean, false, 'a walk-in with no package goes; nobody to tell');
reset role;
select t.eq((select count(*) from public.gym_members where id = :'pema')::int, 0, 'off the register');
select t.eq((select count(*) from public.people where id = :'pema_person')::int, 0,
            'and the person the desk made for them, at no other gym, is forgotten');
select t.eq((select count(*) from public.gym_audit_log where venue_id = :'gym' and action = 'member.removed'
               and summary like 'Removed Pema Walkin (%) from the register')::int, 1, 'the activity log says who went');
set role authenticated;

-- ---- Still paid for: deleted once confirmed ----------------------------------
select t.as_user('00000000-0000-0000-0000-000000de0002');
select public.gym_delete_member(:'sonam', true) as gone \gset
select t.eq((:'gone'::jsonb ->> 'active_until')::date, (public.bhutan_today() + interval '1 month')::date + 7,
            'it says until when they were paid for (the pause included)');
select t.eq((:'gone'::jsonb ->> 'told')::boolean, true, 'and that they were told');
reset role;
select t.eq((select count(*) from public.gym_members where id = :'sonam')::int, 0, 'off the register');
select t.eq((select count(*) from public.gym_subscriptions where gym_member_id = :'sonam')::int
            + (select count(*) from public.gym_check_ins where gym_member_id = :'sonam')::int
            + (select count(*) from public.gym_membership_pauses where gym_member_id = :'sonam')::int
            + (select count(*) from public.gym_payment_claims where gym_member_id = :'sonam')::int, 0,
            'with their packages, visits, pause and claims');
select t.eq((select count(*) from public.payments where venue_id = :'gym')::int, :payments_before,
            'the gym''s payments stay in its income');
select t.eq((select details from public.gym_audit_log where venue_id = :'gym' and action = 'member.removed'
               and summary like 'Removed Sonam Delete%'),
            'Their membership was active until ' || public.gym_audit_day((public.bhutan_today() + interval '1 month')::date + 7),
            'the activity log says who went, and that they were paid for');
select t.eq((select user_id::text from public.people where id = :'sonam_person'), '00000000-0000-0000-0000-000000de0005',
            'their Health Pro account keeps its person');
select t.eq((select count(*) from public.profiles where id = '00000000-0000-0000-0000-000000de0005')::int, 1,
            'and its profile');
select t.eq((select title from public.notifications where user_id = '00000000-0000-0000-0000-000000de0005'
               and title like 'Removed%'), 'Removed from Delete Gym', 'they are told');

set role authenticated;
select t.as_user('00000000-0000-0000-0000-000000de0005');
select t.eq((select count(*) from jsonb_array_elements(public.my_gyms() -> 'gyms') g where g ->> 'venue_id' = :'gym')::int, 0,
            'the gym is gone from their own page');
select t.eq((select count(*) from public.gym_members)::int, 0, 'and they see no registration there');
select t.fails(format($$select public.gym_delete_member(%L, true)$$, :'sonam'), 'no longer registered');
select public.gym_request_to_join(:'gym');
select t.eq((select count(*) from public.gym_join_requests where venue_id = :'gym' and status = 'pending')::int, 1,
            'they can ask to join again');

reset role;
do $$ begin raise notice 'ALL DELETE MEMBER CHECKS PASSED'; end $$;
