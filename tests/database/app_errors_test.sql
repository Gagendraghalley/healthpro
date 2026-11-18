-- App errors (Admin -> App errors): runs after scenario_test.sql (it uses its
-- t.* helpers). Ama is a super admin, Karma has a team role with only
-- 'errors.view', Pema is a member, and a visitor isn't signed in.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000e0001', 'errors.ama@x.bt', '{"full_name":"Ama Admin"}'),
  ('00000000-0000-0000-0000-0000000e0002', 'errors.karma@x.bt', '{"full_name":"Karma Team"}'),
  ('00000000-0000-0000-0000-0000000e0003', 'errors.pema@x.bt', '{"full_name":"Pema Member"}');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-0000000e0001';
delete from public.app_errors;

select t.eq((select count(*) from public.role_permissions rp join public.roles r on r.id = rp.role_id
             where r.key = 'platform_admin' and rp.permission_key = 'errors.view')::int, 1,
            'the platform admin role can see app errors');

-- ---- Sending ------------------------------------------------------------
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select public.report_app_error('Null check operator used on a null value', E'#0 main.dart.js 1:2\n#1 x\n#2 y\n#3 z',
                               '/gyms/abc/manage?next=/secret', 'web');
reset role;
select t.eq((select times || '/' || page || '/' || platform || '/' || coalesce(user_id::text, 'visitor')
             from public.app_errors), '1//gyms/abc/manage/web/visitor',
            'a visitor''s error is kept, its page without what follows ?');

set role authenticated;
select t.as_user('00000000-0000-0000-0000-0000000e0003');
-- The same error, the same top of the stack, a different line further down.
select public.report_app_error('Null check operator used on a null value', E'#0 main.dart.js 1:2\n#1 x\n#2 y\n#3 other',
                               '/my-qr', 'android');
reset role;
select t.eq((select count(*) from public.app_errors)::int, 1, 'the same error is one row');
select t.eq((select times || '/' || page || '/' || platform || '/' || user_id::text from public.app_errors),
            '2//my-qr/android/00000000-0000-0000-0000-0000000e0003', 'counted, with where and who it was last');

set role authenticated;
select public.report_app_error('Null check operator used on a null value', E'#0 elsewhere.dart 9:9', null, null);
select public.report_app_error('   ', null, null, null);
select public.report_app_error(repeat('x', 5000), repeat('y', 20000), repeat('/p', 400), repeat('w', 100));
reset role;
select t.eq((select count(*) from public.app_errors)::int, 3, 'another place is another row; an empty message none');
select t.eq((select char_length(message) || '/' || char_length(stack) || '/' || char_length(page) || '/' || char_length(platform)
             from public.app_errors where message like 'xxx%'), '1000/8000/300/40', 'everything is cut to size');

-- ---- Reading and clearing -----------------------------------------------
set role anon;
select t.fails($$select count(*) from public.app_errors$$, 'permission denied');

set role authenticated;
select t.as_user('00000000-0000-0000-0000-0000000e0003');
select t.eq((select count(*) from public.app_errors)::int, 0, 'a member sees none');
delete from public.app_errors;
select t.fails($$insert into public.app_errors (fingerprint, message) values (md5('a'), 'made up')$$, 'permission denied');
select t.fails($$update public.app_errors set times = 1$$, 'permission denied');

select t.as_user('00000000-0000-0000-0000-0000000e0001');
select t.eq((select count(*) from public.app_errors)::int, 3, 'nothing a member did changed them, and an admin sees all');
select public.save_role(null, 'platform', 'Errors desk', null, true, array['errors.view']) as errors_role \gset
select public.set_user_platform_roles('00000000-0000-0000-0000-0000000e0002', array[:'errors_role']::uuid[]);

select t.as_user('00000000-0000-0000-0000-0000000e0002');
select t.eq((select count(*) from public.app_errors)::int, 3, 'someone with errors.view sees them');
delete from public.app_errors where message like 'xxx%';
select t.eq((select count(*) from public.app_errors)::int, 2, 'and clears a fixed one');

-- ---- Keeping it small ---------------------------------------------------
reset role;
update public.app_errors set last_seen = now() - interval '91 days' where page is null;
insert into public.app_errors (fingerprint, message)
select md5('filler ' || i), 'filler ' || i from generate_series(1, 499) i;
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select public.report_app_error('Brand new error', null, null, 'web');
reset role;
select t.eq((select count(*) from public.app_errors where page is null and message not like 'filler%')::int, 0,
            'one not seen for 90 days is cleared');
select t.eq((select count(*) from public.app_errors where message = 'Brand new error')::int, 0,
            'past 500 kinds, a new one isn''t kept');
set role anon;
select public.report_app_error('Null check operator used on a null value', E'#0 main.dart.js 1:2\n#1 x\n#2 y', null, 'web');
reset role;
select t.eq((select times from public.app_errors where page = '/my-qr'), 3, 'but a known one still counts up');

delete from public.app_errors;
do $$ begin raise notice 'ALL APP ERROR CHECKS PASSED'; end $$;
