-- Pausing memberships and numbered receipts: runs after scenario_test.sql
-- (it uses its t.* helpers and super admin A). Owner Olo runs Pause Gym with
-- front desk Dawa (takes payments) and registrar Rinzin (sees members, no
-- payments); Xo is an outsider; Mindu has an account and paid once.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000f0001', 'pause.owner@gym.bt', '{"full_name":"Olo Owner"}'),
  ('00000000-0000-0000-0000-0000000f0002', 'pause.desk@gym.bt', '{"full_name":"Dawa Desk"}'),
  ('00000000-0000-0000-0000-0000000f0003', 'pause.registrar@gym.bt', '{"full_name":"Rinzin Registrar"}'),
  ('00000000-0000-0000-0000-0000000f0004', 'pause.outsider@x.bt', '{"full_name":"Xo Out"}'),
  ('00000000-0000-0000-0000-0000000f0005', 'pause.mindu@x.bt', '{"full_name":"Mindu Member"}');
set role authenticated;

select t.as_user('00000000-0000-0000-0000-0000000f0001');
select public.register_venue('{"type":"gym","name":"Pause Gym","dzongkhag":"Thimphu","phone":"+97517000401"}') as gym \gset
select public.register_venue('{"type":"gym","name":"Second Gym","dzongkhag":"Thimphu","phone":"+97517000402"}') as gym2 \gset
select t.as_user('00000000-0000-0000-0000-00000000000a');
select public.review_venue(:'gym', true);
select public.review_venue(:'gym2', true);
select public.save_role(null, 'venue', 'Pause registrar', null, true, array['gym.register', 'gym.members']) as registrar \gset
select t.as_user('00000000-0000-0000-0000-0000000f0001');
select public.gym_save_plan(:'gym', null, 'Monthly', null, 30, 1500, true) as plan \gset
select public.gym_save_plan(:'gym2', null, 'Monthly', null, 30, 1200, true) as plan2 \gset
select public.add_venue_staff(:'gym', 'pause.desk@gym.bt', 'staff');
select public.add_venue_staff(:'gym', 'pause.registrar@gym.bt', 'pause_registrar');

select t.as_user('00000000-0000-0000-0000-0000000f0002');
select (public.gym_register_member(:'gym', jsonb_build_object('full_name', 'Sonam Pause', 'phone', '17400001',
          'joined_on', public.bhutan_today()), :'plan', 3, 4500, 'cash', null) ->> 'gym_member_id') as sonam \gset
select code as sonam_code from public.gym_members where id = :'sonam' \gset
select public.gym_renew_member(:'sonam', :'plan', 1, 1500, 'mbob', '123456789');
select (public.bhutan_today() + interval '3 months')::date as e1 \gset
select (date :'e1' + interval '1 month')::date as e2 \gset
-- The packages' dates, oldest first: '<start>..<end>, <start>..<end>'.
create function pg_temp.dates(m uuid) returns text language sql as $$
  select string_agg(start_date || '..' || end_date, ', ' order by start_date, end_date)
  from public.gym_subscriptions where gym_member_id = m and status = 'active'
$$;
select t.eq(pg_temp.dates(:'sonam'), public.bhutan_today() || '..' || :'e1' || ', ' || :'e1' || '..' || :'e2',
            'three months, then a renewal from the day it expires');

-- ---- Who may pause, and what ---------------------------------------------
select t.as_user('00000000-0000-0000-0000-0000000f0003');
select t.fails(format($$select public.gym_pause_member(%L, null, 7)$$, :'sonam'), 'can''t pause');
select t.as_user('00000000-0000-0000-0000-0000000f0004');
select t.fails(format($$select public.gym_pause_member(%L, null, 7)$$, :'sonam'), 'can''t pause');
select t.as_user('00000000-0000-0000-0000-0000000f0002');
select t.fails(format($$select public.gym_pause_member(%L, null, 0)$$, :'sonam'), '1 to 180 days');
select t.fails(format($$select public.gym_pause_member(%L, null, 181)$$, :'sonam'), '1 to 180 days');
select t.fails(format($$select public.gym_pause_member(%L, public.bhutan_today() - 1, 7)$$, :'sonam'), 'before today');
select t.fails(format($$select public.gym_pause_member(%L, %L::date + 40, 7)$$, :'sonam', :'e2'), 'no package running');

-- ---- A pause later on, then taken back -------------------------------------
select public.gym_pause_member(:'sonam', public.bhutan_today() + 10, 14, 'Travelling') as later \gset
select t.eq(pg_temp.dates(:'sonam'),
            public.bhutan_today() || '..' || (date :'e1' + 14) || ', ' || (date :'e1' + 14) || '..' || (date :'e2' + 14),
            'a 14-day pause moves the running package''s end and the renewal 14 days later');
select t.eq((:'later'::jsonb ->> 'runs_until')::date, date :'e2' + 14, 'and says until when they''re covered');
select t.fails(format($$select public.gym_pause_member(%L, null, 3)$$, :'sonam'), 'already');
select t.eq((public.gym_check_in_by_code(:'gym', :'sonam_code') ->> 'member_name'), 'Sonam Pause',
            'before the pause they still check in');
select id as later_id from public.gym_membership_pauses where gym_member_id = :'sonam' \gset
select public.gym_resume_member(:'later_id');
select t.eq(pg_temp.dates(:'sonam'), public.bhutan_today() || '..' || :'e1' || ', ' || :'e1' || '..' || :'e2',
            'taken back before it began: the dates are as they were');
select t.eq((select count(*) from public.gym_membership_pauses where gym_member_id = :'sonam')::int, 0,
            'and the pause is gone');

-- ---- Paused today: no check-in; back early ----------------------------------
select public.gym_pause_member(:'sonam', null, 10);
select t.fails(format($$select public.gym_check_in_by_code(%L, %L)$$, :'gym', :'sonam_code'), 'paused until');
-- Three days on: as if their package had ended on e1 - 3 and the pause began
-- three days ago (so it ends on e1 + 7 now).
reset role;
update public.gym_membership_pauses set start_date = start_date - 3, end_date = end_date - 3 where gym_member_id = :'sonam';
update public.gym_subscriptions set start_date = case when start_date > public.bhutan_today() then start_date - 3 else start_date end,
                                    end_date = end_date - 3
where gym_member_id = :'sonam' and status = 'active';
set role authenticated;
select t.as_user('00000000-0000-0000-0000-0000000f0002');
select id as now_id from public.gym_membership_pauses where gym_member_id = :'sonam' \gset
select t.eq((public.gym_resume_member(:'now_id') ->> 'days_returned')::int, 7, 'back on day 4 of 10: 7 days come back');
select t.eq(pg_temp.dates(:'sonam'), public.bhutan_today() || '..' || :'e1' || ', ' || :'e1' || '..' || :'e2',
            'so the 3 days they were away are added to e1 - 3, and the renewal follows');
select t.eq((select (end_date = public.bhutan_today() - 1 and ended_at is not null and ended_by is not null)::text
             from public.gym_membership_pauses where id = :'now_id'), 'true', 'the pause ends yesterday, resumed by the desk');
select t.eq((public.gym_check_in_by_code(:'gym', :'sonam_code') ->> 'member_name'), 'Sonam Pause', 'and they check in again');
select t.fails(format($$select public.gym_resume_member(%L)$$, :'now_id'), 'over already');

-- Staff who see members see pauses; others don't.
select t.as_user('00000000-0000-0000-0000-0000000f0003');
select t.eq((select count(*) from public.gym_membership_pauses where gym_member_id = :'sonam')::int, 1, 'the registrar sees it');
select t.as_user('00000000-0000-0000-0000-0000000f0004');
select t.eq((select count(*) from public.gym_membership_pauses)::int, 0, 'an outsider sees none');
select t.fails($$insert into public.gym_membership_pauses (venue_id, gym_member_id, start_date, end_date)
                select venue_id, id, current_date, current_date from public.gym_members limit 1$$, 'permission denied');

-- ---- Receipts -------------------------------------------------------------
reset role;
select t.eq((select string_agg(receipt_no::text, ',' order by created_at, receipt_no) from public.payments where venue_id = :'gym'),
            '1,2', 'each payment gets the gym''s next receipt number');
insert into public.payments (user_id, venue_id, module_key, amount, method)
values ('00000000-0000-0000-0000-0000000f0005', :'gym', 'gym_membership', 300, 'cash') returning id as mindu_pay \gset
insert into public.payments (venue_id, module_key, amount, method, payer_name)
values (:'gym2', 'gym_membership', 1200, 'cash', 'Walk In') returning receipt_no as other_no \gset
select t.eq((select receipt_no from public.payments where id = :'mindu_pay'), 3, 'and the next');
select t.eq(:other_no, 1, 'another gym counts from 1');
select t.fails(format($$update public.payments set receipt_no = 1 where id = %L$$, :'mindu_pay'), 'payments_venue_receipt');
select id as renewal_pay from public.payments where venue_id = :'gym' and receipt_no = 2 \gset

set role authenticated;
select t.as_user('00000000-0000-0000-0000-0000000f0002');
select t.eq((select r ->> 'receipt_no' || '|' || (r ->> 'member_name') || '|' || (r ->> 'member_code') || '|' || (r ->> 'plan_name')
                    || '|' || (r ->> 'amount') || '|' || (r ->> 'method') || '|' || (r ->> 'reference') || '|' || (r ->> 'gym_name')
                    || '|' || (r ->> 'received_by')
             from public.gym_payment_receipt(:'renewal_pay') r),
            '2|Sonam Pause|' || :'sonam_code' || '|Monthly|1500|mbob|123456789|Pause Gym|Dawa Desk',
            'the desk opens a receipt: number, member, package, amount, how, JRN, gym and who took it');
select t.as_user('00000000-0000-0000-0000-0000000f0003');
select t.eq((public.gym_payment_receipt(:'renewal_pay') ->> 'receipt_no')::int, 2, 'so does staff who see members');
select t.as_user('00000000-0000-0000-0000-0000000f0004');
select t.fails(format($$select public.gym_payment_receipt(%L)$$, :'renewal_pay'), 'member who paid');
select t.as_user('00000000-0000-0000-0000-0000000f0005');
select t.eq((public.gym_payment_receipt(:'mindu_pay') ->> 'member_name'), 'Mindu Member', 'the member sees their own');
select t.fails(format($$select public.gym_payment_receipt(%L)$$, :'renewal_pay'), 'member who paid');
set role anon;
select t.fails(format($$select public.gym_payment_receipt(%L)$$, :'renewal_pay'), 'permission denied');

-- ---- The member's own page (my_gyms) --------------------------------------
-- Sonam signs up as Mindu's account: the desk's registration becomes theirs.
reset role;
update public.people set user_id = '00000000-0000-0000-0000-0000000f0005'
where id = (select person_id from public.gym_members where id = :'sonam');
set role authenticated;
select t.as_user('00000000-0000-0000-0000-0000000f0002');
select public.gym_pause_member(:'sonam', public.bhutan_today() + 5, 7, 'Holiday');
select t.as_user('00000000-0000-0000-0000-0000000f0005');
select g as mine from jsonb_array_elements(public.my_gyms() -> 'gyms') g where g ->> 'venue_id' = :'gym' \gset
select t.eq((:'mine'::jsonb -> 'pause' ->> 'reason') || '|' || (:'mine'::jsonb -> 'pause' ->> 'start_date'),
            'Holiday|' || (public.bhutan_today() + 5), 'they see the pause planned, not the one that''s over');
select t.eq((select string_agg(r.value ->> 'receipt_no', ',' order by r.n)
             from jsonb_array_elements(:'mine'::jsonb -> 'receipts') with ordinality as r(value, n)),
            '2,1', 'and their receipts, latest first');
select t.eq((:'mine'::jsonb -> 'receipts' -> 0 ->> 'plan_name') || '|' || (:'mine'::jsonb -> 'receipts' -> 0 ->> 'amount'),
            'Monthly|1500', 'each with its package and amount');
select t.eq((public.gym_payment_receipt(:'renewal_pay') ->> 'member_name'), 'Sonam Pause', 'which they can open');
select t.eq((select (g -> 'receipts')::text from jsonb_array_elements(public.my_gyms() -> 'gyms') g
             where g ->> 'venue_id' = :'gym2'), null, 'nothing from a gym they''re not at');

reset role;
do $$ begin raise notice 'ALL PAUSE AND RECEIPT CHECKS PASSED'; end $$;
