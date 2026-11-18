-- Each person's own profile photo: runs after scenario_test.sql (it uses its
-- t.* helpers). Dawa adds a photo; Sonam is someone else.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset tuples_only on

reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000d0001', 'photo.dawa@x.bt', '{"full_name":"Dawa Photo"}'),
  ('00000000-0000-0000-0000-0000000d0002', 'photo.sonam@x.bt', '{"full_name":"Sonam Photo"}');

set role authenticated;
select t.as_user('00000000-0000-0000-0000-0000000d0001');
select t.eq((select count(*) from public.profiles where id = auth.uid() and avatar_url is null)::int, 1,
            'a new account has no photo (their initials show)');

-- The picture goes in their own folder, and only theirs.
insert into storage.objects (bucket_id, name) values ('profile-photos', '00000000-0000-0000-0000-0000000d0001/1.jpg');
select t.eq((select count(*) from storage.objects where bucket_id = 'profile-photos')::int, 1,
            'they upload a photo to their own folder and see it');
select t.fails($$insert into storage.objects (bucket_id, name)
                 values ('profile-photos', '00000000-0000-0000-0000-0000000d0002/1.jpg')$$, 'row-level security');
select t.fails($$insert into storage.objects (bucket_id, name) values ('profile-photos', 'loose.jpg')$$,
               'row-level security');

update public.profiles set avatar_url = 'https://x.supabase.co/storage/v1/object/public/profile-photos/d1/1.jpg'
  where id = auth.uid();
select t.eq((select count(*) from public.profiles where id = auth.uid() and avatar_url like 'https://%')::int, 1,
            'they set it on their account');
select t.fails($$update public.profiles set avatar_url = 'javascript:alert(1)' where id = auth.uid()$$,
               'profiles_avatar_url');
select t.fails(format($$update public.profiles set avatar_url = %L where id = auth.uid()$$,
                      'https://x/' || repeat('a', 600)), 'profiles_avatar_url');

-- Someone else's photo and folder stay theirs.
update public.profiles set avatar_url = 'https://x/p.jpg' where id = '00000000-0000-0000-0000-0000000d0002';
select t.as_user('00000000-0000-0000-0000-0000000d0002');
select t.eq((select count(*) from storage.objects where bucket_id = 'profile-photos')::int, 0,
            'no one lists someone else''s photos');
delete from storage.objects where bucket_id = 'profile-photos';
reset role;
select t.eq((select count(*) from public.profiles
             where id = '00000000-0000-0000-0000-0000000d0002' and avatar_url is null)::int, 1,
            'no one changes someone else''s photo');
select t.eq((select count(*) from storage.objects where bucket_id = 'profile-photos')::int, 1,
            'no one removes someone else''s photo');

-- They take it off again.
set role authenticated;
select t.as_user('00000000-0000-0000-0000-0000000d0001');
delete from storage.objects where bucket_id = 'profile-photos';
update public.profiles set avatar_url = null where id = auth.uid();
reset role;
select t.eq((select count(*) from storage.objects where bucket_id = 'profile-photos')::int, 0,
            'they remove their own photo');

set role anon;
select t.fails($$update public.profiles set avatar_url = 'https://x/p.jpg'$$, 'permission denied');
select t.fails($$insert into storage.objects (bucket_id, name) values ('profile-photos', 'x/1.jpg')$$,
               'permission denied');

reset role;
do $$ begin raise notice 'ALL PROFILE PHOTO CHECKS PASSED'; end $$;
