-- App errors: what went wrong in the app on people's phones and in their
-- browsers, for the Health Pro team to put right (Admin -> App errors, the
-- 'errors.view' permission). The app sends each error it didn't handle
-- through report_app_error(), signed in or not; the same error at the same
-- place is one row with a count, not a row each time. An error not seen for
-- 90 days is cleared. Safe to re-run.

create table if not exists public.app_errors (
  id          bigint generated always as identity primary key,
  -- The message and the top of the stack: the same error is counted, not repeated.
  fingerprint text not null unique check (char_length(fingerprint) = 32),
  message     text not null check (char_length(message) between 1 and 1000),
  stack       text check (char_length(stack) <= 8000),
  -- The page it happened on: its path, without what follows '?'.
  page        text check (char_length(page) <= 300),
  -- 'web', 'android', 'iOS'.
  platform    text check (char_length(platform) <= 40),
  -- The last signed-in person it happened to (none for visitors).
  user_id     uuid references public.profiles (id) on delete set null,
  times       integer not null default 1 check (times >= 1),
  first_seen  timestamptz not null default now(),
  last_seen   timestamptz not null default now()
);
create index if not exists app_errors_last_seen on public.app_errors (last_seen desc);

-- The team reads them and clears what they've fixed; only report_app_error
-- adds them.
alter table public.app_errors enable row level security;
revoke all on public.app_errors from anon, authenticated;
grant select, delete on public.app_errors to authenticated;
drop policy if exists "app_errors: the team reads" on public.app_errors;
create policy "app_errors: the team reads" on public.app_errors for select to authenticated
  using (public.has_permission('errors.view'));
drop policy if exists "app_errors: the team clears" on public.app_errors;
create policy "app_errors: the team clears" on public.app_errors for delete to authenticated
  using (public.has_permission('errors.view'));

-- The permission. As in 20261111000001: seen for the first time, the
-- platform_admin role gets it; after that, admins choose.
do $$
declare
  v_new_permissions text[];
begin
  with saved as (
    insert into public.permissions (key, scope, name, description, sort_order) values
      ('errors.view', 'platform', 'App errors',
       'See errors the app hit on people''s phones and browsers, and clear fixed ones', 70)
    on conflict (key) do update
      set scope = excluded.scope, name = excluded.name, description = excluded.description,
          sort_order = excluded.sort_order
    returning key, (xmax = 0) as inserted
  )
  select coalesce(array_agg(key) filter (where inserted), '{}') into v_new_permissions from saved;

  insert into public.role_permissions (role_id, permission_key)
  select r.id, 'errors.view'
  from public.roles r
  where r.key = 'platform_admin' and 'errors.view' = any (v_new_permissions)
  on conflict do nothing;
end;
$$;

-- One error from the app. Anyone may send one (a visitor's count too), so
-- everything is cut to size, and new kinds stop at 500 until the team
-- clears some; a known one only counts up.
create or replace function public.report_app_error(
  error_message text,
  error_stack text default null,
  at_page text default null,
  on_platform text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_message text := left(btrim(coalesce(error_message, '')), 1000);
  v_stack text := nullif(left(error_stack, 8000), '');
  v_page text := nullif(left(split_part(btrim(coalesce(at_page, '')), '?', 1), 300), '');
  v_platform text := nullif(left(btrim(coalesce(on_platform, '')), 40), '');
  v_user uuid := (select p.id from public.profiles p where p.id = (select auth.uid()));
  v_fingerprint text;
begin
  if v_message = '' then
    return;
  end if;
  v_fingerprint := md5(v_message || E'\n' ||
    coalesce(array_to_string((string_to_array(v_stack, E'\n'))[1:3], E'\n'), ''));

  delete from public.app_errors where last_seen < now() - interval '90 days';

  update public.app_errors e
     set times = least(e.times, 2147483646) + 1,
         last_seen = now(),
         stack = coalesce(v_stack, e.stack),
         page = coalesce(v_page, e.page),
         platform = coalesce(v_platform, e.platform),
         user_id = coalesce(v_user, e.user_id)
   where e.fingerprint = v_fingerprint;
  if found then
    return;
  end if;

  if (select count(*) from public.app_errors) >= 500 then
    return;
  end if;
  insert into public.app_errors (fingerprint, message, stack, page, platform, user_id)
  values (v_fingerprint, v_message, v_stack, v_page, v_platform, v_user)
  on conflict (fingerprint) do update
    set times = least(public.app_errors.times, 2147483646) + 1, last_seen = now();
end;
$$;

revoke all on function public.report_app_error(text, text, text, text) from public;
grant execute on function public.report_app_error(text, text, text, text) to anon, authenticated;
