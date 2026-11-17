-- Each person's app colours on their account: runs after scenario_test.sql
-- (it uses its t.* helpers). Tashi picks colours; Yeshi is someone else.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000c0001', 'theme.tashi@x.bt', '{"full_name":"Tashi Theme"}'),
  ('00000000-0000-0000-0000-0000000c0002', 'theme.yeshi@x.bt', '{"full_name":"Yeshi Theme"}');

set role authenticated;
select t.as_user('00000000-0000-0000-0000-0000000c0001');
select t.eq((select coalesce(theme_primary, 'none') || '/' || coalesce(theme_accent, 'none') from public.profiles
             where id = auth.uid()), 'none/none', 'a new account has Health Pro''s own colours');

update public.profiles set theme_primary = 'blue', theme_accent = 'plum' where id = auth.uid();
select t.eq((select theme_primary || '/' || theme_accent from public.profiles where id = auth.uid()), 'blue/plum',
            'they pick their own colours');

update public.profiles set theme_primary = null, theme_accent = null where id = auth.uid();
select t.eq((select count(*) from public.profiles where id = auth.uid() and theme_primary is null)::int, 1,
            'and go back to Health Pro''s own');

select t.fails($$update public.profiles set theme_primary = 'Blue; drop' where id = auth.uid()$$, 'profiles_theme_ids');
select t.fails($$update public.profiles set theme_accent = repeat('a', 21) where id = auth.uid()$$, 'profiles_theme_ids');

-- Only their own, and nothing more than they could change before.
update public.profiles set theme_primary = 'red' where id = '00000000-0000-0000-0000-0000000c0002';
reset role;
select t.eq((select count(*) from public.profiles
             where id = '00000000-0000-0000-0000-0000000c0002' and theme_primary is null)::int, 1,
            'no one changes someone else''s colours');
set role authenticated;
select t.as_user('00000000-0000-0000-0000-0000000c0001');
select t.fails($$update public.profiles set role = 'super_admin' where id = auth.uid()$$, 'permission denied');

set role anon;
select t.fails($$update public.profiles set theme_primary = 'red'$$, 'permission denied');

reset role;
do $$ begin raise notice 'ALL THEME CHECKS PASSED'; end $$;
