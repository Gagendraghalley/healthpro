-- Ask AI's question allowance: runs after scenario_test.sql (it uses its t.*
-- helpers). Gym owner Q runs a gym; outsider R doesn't work there.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
-- The Edge Functions' role uses the helpers too.
grant usage on schema t to service_role;
grant execute on all functions in schema t to service_role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000a1001', 'ask.owner@gym.bt', '{"full_name":"Qi Owner"}'),
  ('00000000-0000-0000-0000-0000000a1002', 'ask.outsider@x.bt', '{"full_name":"Ro Outsider"}');

set role authenticated;
select t.as_user('00000000-0000-0000-0000-0000000a1001');
select public.register_venue('{"type":"gym","name":"Ask Gym","dzongkhag":"Paro","phone":"+97517000040"}') as gym \gset

select t.eq(public.ai_take_question(:'gym'), 24, 'staff ask a question: 24 left today');
select t.fails($$select count(*) from public.ai_questions$$, 'permission denied');
select t.fails($$insert into public.ai_questions (user_id, venue_id) values (auth.uid(), gen_random_uuid())$$,
               'permission denied');

select t.as_user('00000000-0000-0000-0000-0000000a1002');
select t.fails(format($$select public.ai_take_question(%L)$$, :'gym'), 'Only the gym''s staff');

select t.as_user('00000000-0000-0000-0000-0000000a1001');
select public.ai_take_question(:'gym') from generate_series(1, 23);
select t.eq(public.ai_take_question(:'gym'), 0, 'the 25th question is the last today');
select t.fails(format($$select public.ai_take_question(%L)$$, :'gym'), 'asked 25 questions today');

-- Yesterday's questions don't count today, and old ones are cleared.
reset role;
update public.ai_questions set asked_at = now() - interval '100 days'
where user_id = '00000000-0000-0000-0000-0000000a1001';
set role authenticated;
select t.as_user('00000000-0000-0000-0000-0000000a1001');
select t.eq(public.ai_take_question(:'gym'), 24, 'a new day, a new allowance');
reset role;
select t.eq((select count(*) from public.ai_questions where user_id = '00000000-0000-0000-0000-0000000a1001')::int, 1,
            'questions over 90 days old are cleared');

set role anon;
select t.fails(format($$select public.ai_take_question(%L)$$, :'gym'), 'permission denied');

-- ---- Health Pro's assistant, for anyone ---------------------------------
-- Only the Edge Function (the service role) counts visitors' questions.
select t.fails($$select public.ai_take_public_question('visitor-hash-0000000001')$$, 'permission denied');
reset role; set role authenticated;
select t.fails($$select public.ai_take_public_question('visitor-hash-0000000001')$$, 'permission denied');
select t.fails($$select count(*) from public.ai_public_questions$$, 'permission denied');

reset role; set role service_role;
select t.eq(public.ai_take_public_question('visitor-hash-0000000001'), 14, 'a visitor asks: 14 left today');
select t.fails($$select public.ai_take_public_question('short')$$, 'Who is asking');
select public.ai_take_public_question('visitor-hash-0000000001') from generate_series(1, 14);
select t.fails($$select public.ai_take_public_question('visitor-hash-0000000001')$$, 'asked 15 questions today');
select t.eq(public.ai_take_public_question('visitor-hash-0000000002'), 14, 'another visitor has their own 15');

-- Everyone together: 150 a day (16 asked above, 134 more from others).
reset role;
insert into public.ai_public_questions (client_hash) select 'crowd-' || g from generate_series(1, 133) g;
set role service_role;
select t.eq(public.ai_take_public_question('visitor-hash-0000000003'), 14, 'the 150th question of the day');
reset role;
set role service_role;
select t.fails($$select public.ai_take_public_question('visitor-hash-0000000003')$$, 'answered all it can for today');

-- Signed-in members are counted by their account, not their address, and the
-- visitors' 150 (used up just above) don't stop them.
reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000a1003', 'ask.member@x.bt', '{"full_name":"Sonam Member"}'),
  ('00000000-0000-0000-0000-0000000a1004', 'ask.member2@x.bt', '{"full_name":"Tashi Member"}');
set role service_role;
select t.eq(public.ai_take_public_question('visitor-hash-0000000003', '00000000-0000-0000-0000-0000000a1003'), 14,
            'a member asks after the visitors'' share is used up: 14 left');
select public.ai_take_public_question('visitor-hash-0000000003', '00000000-0000-0000-0000-0000000a1003')
from generate_series(1, 14);
select t.fails($$select public.ai_take_public_question('visitor-hash-0000000003', '00000000-0000-0000-0000-0000000a1003')$$,
               'asked 15 questions today');
select t.eq(public.ai_take_public_question('visitor-hash-0000000003', '00000000-0000-0000-0000-0000000a1004'), 14,
            'another member on the same address has their own 15');
select t.eq(public.ai_take_public_question(null, '00000000-0000-0000-0000-0000000a1004'), 13, 'a member needs no address');
select t.fails($$select public.ai_take_public_question('visitor-hash-0000000004')$$, 'answered all it can for today');
reset role;
select t.eq((select count(*) from public.ai_public_questions where user_id is not null and client_hash is not null)::int,
            0, 'members'' addresses aren''t kept');
delete from auth.users where id = '00000000-0000-0000-0000-0000000a1004';
select t.eq((select count(*) from public.ai_public_questions
             where user_id = '00000000-0000-0000-0000-0000000a1004')::int, 0, 'a deleted account''s questions go with it');

-- Old questions are cleared.
reset role;
update public.ai_public_questions set asked_at = now() - interval '40 days';
set role service_role;
select t.eq(public.ai_take_public_question('visitor-hash-0000000003'), 14, 'a new day');
reset role;
select t.eq((select count(*) from public.ai_public_questions)::int, 1, 'questions over 30 days old are cleared');

reset role;
do $$ begin raise notice 'ALL ASK AI CHECKS PASSED'; end $$;
