-- Health Pro: push notifications on the Android and iOS apps.
--
-- The website's push (push_subscriptions, 20261115000005) stays as it is.
-- The phone apps get every notification through Firebase Cloud Messaging
-- (FCM) instead, by the same road:
--
-- - push_devices: each phone app that turned them on (its address at FCM).
-- - push_claim_notification also gives send-push the person's phone apps.
-- - The notifications_push trigger asks send-push when the person has a
--   browser or a phone app turned on.
--
-- Safe to run again.


-- ---------------------------------------------------------------------
-- 1. Table
-- ---------------------------------------------------------------------

create table if not exists public.push_devices (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null constraint push_devices_user_id_fkey references public.profiles (id) on delete cascade,
  -- The app's address at FCM: its Firebase Installation ID (FCM's
  -- replacement for registration tokens; send-push sends to it as `fid`).
  token        text not null unique check (token ~ '^[A-Za-z0-9_:.-]+$' and char_length(token) between 20 and 4096),
  platform     text not null check (platform in ('android', 'ios')),
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index if not exists push_devices_user_idx on public.push_devices (user_id);

alter table public.push_devices enable row level security;
revoke all on public.push_devices from anon, authenticated;
grant select on public.push_devices to authenticated;
drop policy if exists "push_devices: their own" on public.push_devices;
create policy "push_devices: their own" on public.push_devices for select to authenticated
  using (user_id = (select auth.uid()));


-- ---------------------------------------------------------------------
-- 2. The app: turning push on and off on a phone
-- ---------------------------------------------------------------------

-- This phone app ([token], on [platform]) gets the signed-in person's
-- notifications. A phone that was someone else's (they signed out, this
-- person signed in) becomes this person's.
create or replace function public.save_push_device(token text, platform text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  uid uuid := (select auth.uid());
begin
  if uid is null then
    raise exception 'Sign in first.';
  end if;
  if coalesce(save_push_device.token, '') !~ '^[A-Za-z0-9_:.-]+$'
     or char_length(save_push_device.token) not between 20 and 4096 then
    raise exception 'That isn''t a push token.';
  end if;
  if coalesce(save_push_device.platform, '') not in ('android', 'ios') then
    raise exception 'Phone push is for Android and iOS.';
  end if;
  if (select count(*) from public.push_devices d where d.user_id = uid) >= 20
     and not exists (select 1 from public.push_devices d where d.user_id = uid and d.token = save_push_device.token) then
    -- The oldest phone makes room.
    delete from public.push_devices d
    where d.id = (select x.id from public.push_devices x where x.user_id = uid order by x.last_seen_at limit 1);
  end if;
  insert into public.push_devices (user_id, token, platform)
  values (uid, save_push_device.token, save_push_device.platform)
  on conflict (token) do update
    set user_id = excluded.user_id, platform = excluded.platform, last_seen_at = now();
end;
$$;

-- This phone stops getting them (turned off, or signing out).
create or replace function public.remove_push_device(token text)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  delete from public.push_devices d
  where d.token = remove_push_device.token and d.user_id = (select auth.uid());
$$;


-- ---------------------------------------------------------------------
-- 3. send-push (the service role only)
-- ---------------------------------------------------------------------

-- Notification [notification_id], to send now: once (it's marked sent),
-- only if made in the last 15 minutes, and only to its own person's
-- browsers and phone apps. Null when there's nothing to send.
create or replace function public.push_claim_notification(notification_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  n public.notifications;
begin
  update public.notifications x set pushed_at = now()
  where x.id = push_claim_notification.notification_id and x.pushed_at is null
    and x.created_at > now() - interval '15 minutes'
  returning * into n;
  if n.id is null then
    return null;
  end if;
  return jsonb_build_object(
    'title', n.title, 'body', n.body, 'link', n.link,
    'subscriptions', coalesce((select jsonb_agg(jsonb_build_object('endpoint', p.endpoint, 'p256dh', p.p256dh, 'auth', p.auth))
                               from public.push_subscriptions p where p.user_id = n.user_id), '[]'::jsonb),
    'devices', coalesce((select jsonb_agg(jsonb_build_object('token', d.token, 'platform', d.platform))
                         from public.push_devices d where d.user_id = n.user_id), '[]'::jsonb)
  );
end;
$$;

-- Phone apps FCM says are gone (the app removed, or its token replaced).
create or replace function public.push_forget_devices(tokens text[])
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  delete from public.push_devices d where d.token = any (tokens);
$$;


-- ---------------------------------------------------------------------
-- 4. Each new notification goes out as a push, to browsers and phones
-- ---------------------------------------------------------------------

create or replace function public.notifications_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
begin
  select s.value into v_url from private.settings s where s.key = 'push_function_url';
  if v_url is null
     or (not exists (select 1 from public.push_subscriptions p where p.user_id = new.user_id)
         and not exists (select 1 from public.push_devices d where d.user_id = new.user_id)) then
    return null;
  end if;
  -- pg_net sends it after this commits; whatever goes wrong with push, the
  -- notification itself stands.
  begin
    perform net.http_post(
      url := v_url,
      body := jsonb_build_object('notification_id', new.id),
      headers := '{"Content-Type": "application/json"}'::jsonb
    );
  exception when others then
    raise warning 'Push not sent for notification %: %', new.id, sqlerrm;
  end;
  return null;
end;
$$;


-- ---------------------------------------------------------------------
-- 5. Who can call which function
-- ---------------------------------------------------------------------

revoke execute on function public.notifications_push() from public, anon, authenticated;
revoke execute on function public.push_claim_notification(uuid), public.push_forget_devices(text[])
  from public, anon, authenticated;
grant execute on function public.push_claim_notification(uuid), public.push_forget_devices(text[])
  to service_role;
revoke execute on function public.save_push_device(text, text), public.remove_push_device(text)
  from public, anon;
grant execute on function public.save_push_device(text, text), public.remove_push_device(text)
  to authenticated;
