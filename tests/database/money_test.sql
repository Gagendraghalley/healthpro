-- Discounts and offers, and expenses: runs after scenario_test.sql (it uses
-- its t.* helpers and super admin A). Owner Ugyen runs Offer Gym with front
-- desk Dorji (sells packages, doesn't see income); Xo is an outsider.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000f2001', 'money.owner@gym.bt', '{"full_name":"Ugyen Owner"}'),
  ('00000000-0000-0000-0000-0000000f2002', 'money.desk@gym.bt', '{"full_name":"Dorji Desk"}'),
  ('00000000-0000-0000-0000-0000000f2003', 'money.outsider@x.bt', '{"full_name":"Xo Out"}');
set role authenticated;

select t.as_user('00000000-0000-0000-0000-0000000f2001');
select public.register_venue('{"type":"gym","name":"Offer Gym","dzongkhag":"Thimphu","phone":"+97517000601"}') as gym \gset
select public.register_venue('{"type":"gym","name":"Other Gym","dzongkhag":"Paro","phone":"+97517000602"}') as gym2 \gset
select t.as_user('00000000-0000-0000-0000-00000000000a');
select public.review_venue(:'gym', true);
select public.review_venue(:'gym2', true);
select t.as_user('00000000-0000-0000-0000-0000000f2001');
select public.gym_save_plan(:'gym', null, 'Monthly', null, 30, 1500, true) as plan \gset
select public.gym_save_plan(:'gym', null, 'Yearly', null, 365, 12000, true) as yearly \gset
select public.add_venue_staff(:'gym', 'money.desk@gym.bt', 'staff');

-- The gym's latest entry: 'action|summary|details'.
create function pg_temp.last_entry(v uuid) returns text language sql as $$
  select action || '|' || summary || '|' || details from public.gym_audit_log where venue_id = v order by id desc limit 1
$$;
create function pg_temp.d(n int) returns text language sql as $$ select to_char(public.bhutan_today() + n, 'FMDD Mon YYYY') $$;

-- ---- Offers ------------------------------------------------------------------
select public.gym_save_offer(:'gym', null, ' Student ', 'percent', 10) as student \gset
select public.gym_save_offer(:'gym', null, 'Couple', 'amount', 500) as couple \gset
select public.gym_save_offer(:'gym2', null, 'Elsewhere', 'percent', 50) as elsewhere \gset
select t.eq((select string_agg(name || ' ' || kind || ' ' || value, ', ' order by name) from public.gym_offers where venue_id = :'gym'),
            'Couple amount 500, Student percent 10', 'the owner keeps two offers, tidied');
select t.eq(pg_temp.last_entry(:'gym'), 'offer.added|Added the offer Couple|Nu. 500 off', 'and they''re logged');
select t.fails(format($$select public.gym_save_offer(%L, null, 'Big', 'percent', 120)$$, :'gym'), '1 to 100');
select t.fails(format($$select public.gym_save_offer(%L, null, 'student', 'amount', 100)$$, :'gym'), 'called student already');
select t.fails(format($$select public.gym_save_offer(%L, null, 'Free', 'gift', 1)$$, :'gym'), 'percentage or an amount');
select t.as_user('00000000-0000-0000-0000-0000000f2002');
select t.fails(format($$select public.gym_save_offer(%L, null, 'Desk deal', 'percent', 50)$$, :'gym'), 'set the gym''s prices');
select t.eq((select count(*) from public.gym_offers)::int, 2, 'the desk, who sells packages, sees the offers');
select t.as_user('00000000-0000-0000-0000-0000000f2003');
select t.eq((select count(*) from public.gym_offers)::int, 0, 'an outsider doesn''t');

-- The price the form suggests, as the app works it out.
reset role;
select t.eq((select public.gym_package_price(p, 3) from public.gym_plans p where id = :'plan'), 4500, '3 months of a monthly plan');
select t.eq((select public.gym_package_price(p, 6) from public.gym_plans p where id = :'yearly'), 6000, 'half of a yearly one');
set role authenticated;

-- ---- Selling with a discount -------------------------------------------------
select t.as_user('00000000-0000-0000-0000-0000000f2002');
select (public.gym_register_member(:'gym', jsonb_build_object('full_name', 'Pema Disc', 'phone', '17600001',
          'joined_on', public.bhutan_today(), 'discount', jsonb_build_object('offer_id', :'student', 'reason', 'College ID seen')),
          :'plan', 3, 4050, 'cash', null) -> 'membership' ->> 'payment_id') as pay1 \gset
select gym_member_id as pema from public.gym_subscriptions where payment_id = :'pay1' \gset
select t.eq((select list_price || '|' || price || '|' || offer_name || '|' || discount_reason
             from public.gym_subscriptions where payment_id = :'pay1'),
            '4500|4050|Student|College ID seen', 'registering with the Student offer keeps the full price, offer and why');
select t.as_user('00000000-0000-0000-0000-0000000f2001');
select t.eq(pg_temp.last_entry(:'gym') like
              'member.registered|Registered Pema Disc (%)|Monthly, % · discount Nu. 450 (Student: College ID seen) · Nu. 4,050 cash · receipt 1',
            true, 'the activity log says what was taken off, and why');
select t.as_user('00000000-0000-0000-0000-0000000f2002');
select t.eq((select r ->> 'list_price' || '|' || (r ->> 'offer_name') || '|' || (r ->> 'amount')
             from public.gym_payment_receipt(:'pay1') r), '4500|Student|4050', 'so does the receipt');

select public.gym_renew_member(:'pema', :'plan', 1, 1200, 'cash', null) ->> 'subscription_id' as sub2 \gset
select t.eq((select list_price || '|' || price || '|' || coalesce(offer_name, '-') || '|' || coalesce(discount_reason, '-')
             from public.gym_subscriptions where id = :'sub2'),
            '1500|1200|-|-', 'less money without a reason (the desk''s old call) is still a discount on record');
select t.as_user('00000000-0000-0000-0000-0000000f2001');
select t.eq(pg_temp.last_entry(:'gym') like '%· discount Nu. 300, no reason given · Nu. 1,200 cash · receipt 2', true,
            'flagged in the log');
select t.as_user('00000000-0000-0000-0000-0000000f2002');
select public.gym_renew_member(:'pema', :'plan', 1, 1000, 'cash', null, '{"reason":" Referred by Sonam "}') ->> 'subscription_id' as sub3 \gset
select t.eq((select discount_reason from public.gym_subscriptions where id = :'sub3'), 'Referred by Sonam', 'a reason on its own');
select public.gym_renew_member(:'pema', :'plan', 1, 1500, 'cash', null, jsonb_build_object('offer_id', :'couple'))
  ->> 'subscription_id' as sub4 \gset
select t.eq((select list_price || '|' || coalesce(offer_id::text, '-') from public.gym_subscriptions where id = :'sub4'),
            '1500|-', 'an offer with the full price paid isn''t a discount');
select t.fails(format($$select public.gym_renew_member(%L, %L, 1, 1000, 'cash', null, jsonb_build_object('offer_id', %L))$$,
                      :'pema', :'plan', :'elsewhere'), 'isn''t available');

select t.as_user('00000000-0000-0000-0000-0000000f2001');
select public.gym_save_offer(:'gym', :'couple', 'Couple', 'amount', 600, false);
select t.eq(pg_temp.last_entry(:'gym'), 'offer.changed|Changed the offer Couple|Nu. 500 off to Nu. 600 off · no longer offered',
            'changing an offer is logged');
select t.as_user('00000000-0000-0000-0000-0000000f2002');
select t.fails(format($$select public.gym_renew_member(%L, %L, 1, 900, 'cash', null, jsonb_build_object('offer_id', %L))$$,
                      :'pema', :'plan', :'couple'), 'isn''t available');

-- ---- Expenses ------------------------------------------------------------------
select t.as_user('00000000-0000-0000-0000-0000000f2001');
select public.gym_save_expense(:'gym', null, jsonb_build_object('spent_on', public.bhutan_today(), 'category', 'rent',
          'amount', 15000, 'method', 'bank', 'paid_to', ' Landlord ')) as rent \gset
select t.eq((select category || '|' || amount || '|' || method || '|' || paid_to from public.gym_expenses where id = :'rent'),
            'rent|15000|bank|Landlord', 'the owner records the rent');
select t.eq(pg_temp.last_entry(:'gym'), 'expense.added|Spent Nu. 15,000 on rent|' || pg_temp.d(0) || ' · paid to Landlord · bank transfer',
            'and it''s logged');
select t.fails(format($$select public.gym_save_expense(%L, null, jsonb_build_object('spent_on', public.bhutan_today() + 1,
                        'category', 'rent', 'amount', 100))$$, :'gym'), 'today or before');
select t.fails(format($$select public.gym_save_expense(%L, null, jsonb_build_object('spent_on', public.bhutan_today(),
                        'category', 'food', 'amount', 100))$$, :'gym'), 'what it was for');
select t.fails(format($$select public.gym_save_expense(%L, null, jsonb_build_object('spent_on', public.bhutan_today(),
                        'category', 'rent', 'amount', 0))$$, :'gym'), 'amount spent');
select public.gym_save_expense(:'gym', :'rent', jsonb_build_object('spent_on', public.bhutan_today(), 'category', 'rent',
          'amount', 16000, 'method', 'bank', 'paid_to', 'Landlord'));
select t.eq(pg_temp.last_entry(:'gym'), 'expense.changed|Changed an expense of Nu. 16,000 (rent)|amount Nu. 15,000 to Nu. 16,000',
            'a change says from what to what');

select t.as_user('00000000-0000-0000-0000-0000000f2002');
select t.fails(format($$select public.gym_save_expense(%L, null, jsonb_build_object('spent_on', public.bhutan_today(),
                        'category', 'supplies', 'amount', 300))$$, :'gym'), 'see the gym''s income');
select t.eq((select count(*) from public.gym_expenses)::int, 0, 'the desk, who doesn''t see income, doesn''t see expenses');
select t.fails(format($$select public.gym_delete_expense(%L)$$, :'rent'), 'see the gym''s income');
select t.as_user('00000000-0000-0000-0000-0000000f2003');
select t.eq((select count(*) from public.gym_expenses)::int, 0, 'nor an outsider');
select t.fails(format($$update public.gym_expenses set amount = 1 where id = %L$$, :'rent'), 'permission denied');

select t.as_user('00000000-0000-0000-0000-0000000f2001');
select public.gym_delete_expense(:'rent');
select t.eq(pg_temp.last_entry(:'gym'), 'expense.removed|Removed an expense of Nu. 16,000|rent, ' || pg_temp.d(0),
            'removing one is logged too');
select t.eq((select count(*) from public.gym_expenses where venue_id = :'gym')::int, 0, 'and it''s gone');

reset role;
do $$ begin raise notice 'ALL DISCOUNT AND EXPENSE CHECKS PASSED'; end $$;
