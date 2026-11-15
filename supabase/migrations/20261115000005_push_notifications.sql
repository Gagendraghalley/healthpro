-- Health Pro, phase 5: push notifications.
--
-- Every notification (public.notifications: join requests, payments,
-- expiry, trainers, reviews...) also goes to its person's phones and
-- browsers as a push, when they turned notifications on there:
--
-- - push_subscriptions: each device that turned them on (the app sends its
--   push address and keys after the person allows it).
-- - A trigger on notifications asks the send-push Edge Function to send the
--   new one (pg_net, after the insert commits). The function sends each
--   notification once, to its own person only (push_claim_notification),
--   so anyone calling it can't send anything else.
-- - private.settings holds the function's address; send-push writes it
--   itself when it's first called (scripts/deploy_supabase.sh calls it).
--   Until then, and where pg_net isn't installed (the local tests), nothing
--   is sent and notifications work as before, inside the app.
--
-- Safe to run again.


-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

do $$
begin
  create extension if not exists pg_net;
exception when others then
  raise notice 'pg_net is not available here: push notifications stay off (%).', sqlerrm;
end;
$$;

-- Settings the app never reads (not in an exposed schema).
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table if not exists private.settings (
  key   text primary key,
  value text not null
);
revoke all on private.settings from public, anon, authenticated;

create table if not exists public.push_subscriptions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null constraint push_subscriptions_user_id_fkey references public.profiles (id) on delete cascade,
  -- Where the device's push service takes messages for it.
  endpoint     text not null unique check (endpoint ~ '^https://' and char_length(endpoint) <= 1000),
  -- Its keys (base64url): the public key and the auth secret.
  p256dh       text not null check (p256dh ~ '^[A-Za-z0-9_-]{80,100}$'),
  auth         text not null check (auth ~ '^[A-Za-z0-9_-]{16,32}$'),
  user_agent   text check (char_length(user_agent) <= 300),
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index if not exists push_subscriptions_user_idx on public.push_subscriptions (user_id);

-- When a notification went out as a push (once).
alter table public.notifications add column if not exists pushed_at timestamptz;


-- ---------------------------------------------------------------------
-- 2. Who can read what
-- ---------------------------------------------------------------------

alter table public.push_subscriptions enable row level security;
revoke all on public.push_subscriptions from anon, authenticated;
grant select on public.push_subscriptions to authenticated;
drop policy if exists "push_subscriptions: their own" on public.push_subscriptions;
create policy "push_subscriptions: their own" on public.push_subscriptions for select to authenticated
  using (user_id = (select auth.uid()));


-- ---------------------------------------------------------------------
-- 3. The app: turning push on and off on a device
-- ---------------------------------------------------------------------

-- This device ([endpoint], [p256dh], [auth]) gets the signed-in person's
-- notifications. A device that was someone else's (they signed out, this
-- person signed in) becomes this person's.
create or replace function public.save_push_subscription(endpoint text, p256dh text, auth text,
                                                         user_agent text default null)
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
  if coalesce(save_push_subscription.endpoint, '') !~ '^https://' or char_length(save_push_subscription.endpoint) > 1000
     or coalesce(save_push_subscription.p256dh, '') !~ '^[A-Za-z0-9_-]{80,100}$'
     or coalesce(save_push_subscription.auth, '') !~ '^[A-Za-z0-9_-]{16,32}$' then
    raise exception 'That isn''t a push subscription.';
  end if;
  if (select count(*) from public.push_subscriptions p where p.user_id = uid) >= 20 then
    -- The oldest device makes room.
    delete from public.push_subscriptions p
    where p.id = (select x.id from public.push_subscriptions x where x.user_id = uid order by x.last_seen_at limit 1);
  end if;
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, user_agent)
  values (uid, save_push_subscription.endpoint, save_push_subscription.p256dh, save_push_subscription.auth,
          left(save_push_subscription.user_agent, 300))
  on conflict (endpoint) do update
    set user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth,
        user_agent = excluded.user_agent, last_seen_at = now();
end;
$$;

-- This device stops getting them (turned off, or signing out).
create or replace function public.remove_push_subscription(endpoint text)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  delete from public.push_subscriptions p
  where p.endpoint = remove_push_subscription.endpoint and p.user_id = (select auth.uid());
$$;


-- ---------------------------------------------------------------------
-- 4. send-push (the service role only)
-- ---------------------------------------------------------------------

-- Notification [notification_id], to send now: once (it's marked sent),
-- only if made in the last 15 minutes, and only to its own person's
-- devices. Null when there's nothing to send.
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
                               from public.push_subscriptions p where p.user_id = n.user_id), '[]'::jsonb)
  );
end;
$$;

-- Devices their push service says are gone (unsubscribed, or the app
-- removed).
create or replace function public.push_forget_subscriptions(endpoints text[])
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  delete from public.push_subscriptions p where p.endpoint = any (endpoints);
$$;

-- Where send-push is: it says so itself, from its own address.
create or replace function public.push_configure(function_url text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if coalesce(function_url, '') !~ '^https://[A-Za-z0-9.-]+/functions/v1/send-push$' then
    raise exception 'That isn''t the send-push function''s address.';
  end if;
  insert into private.settings (key, value) values ('push_function_url', function_url)
  on conflict (key) do update set value = excluded.value;
end;
$$;


-- ---------------------------------------------------------------------
-- 5. Each new notification goes out as a push
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
  if v_url is null or not exists (select 1 from public.push_subscriptions p where p.user_id = new.user_id) then
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
drop trigger if exists notifications_push on public.notifications;
create trigger notifications_push after insert on public.notifications
  for each row execute function public.notifications_push();


-- ---------------------------------------------------------------------
-- 6. Who can call which function
-- ---------------------------------------------------------------------

revoke execute on function public.notifications_push() from public, anon, authenticated;
revoke execute on function public.push_claim_notification(uuid), public.push_forget_subscriptions(text[]),
  public.push_configure(text)
  from public, anon, authenticated;
grant execute on function public.push_claim_notification(uuid), public.push_forget_subscriptions(text[]),
  public.push_configure(text)
  to service_role;
revoke execute on function public.save_push_subscription(text, text, text, text), public.remove_push_subscription(text)
  from public, anon;
grant execute on function public.save_push_subscription(text, text, text, text), public.remove_push_subscription(text)
  to authenticated;
