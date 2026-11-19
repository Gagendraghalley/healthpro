-- Emails about classes. Whoever has a place in a class is emailed:
--
-- - when they book it, or the desk books it for them: the class, the day
--   and time, how long it runs, the trainer, the gym, where it is (with a
--   map link) and its phone;
-- - when the gym changes the class's time, length, trainer or name: what
--   changed, for their places to come (one email a person);
-- - when the gym cancels their place: the class taken off the timetable or
--   moved to another day, or the desk cancelling it. Cancelling one's own
--   place sends nothing.
--
-- To the email of their Health Pro account, or else the one the desk keeps
-- for the member; nobody without one is emailed.
--
-- How, as push is (20261115000005): triggers put each email in
-- private.email_outbox, out of the app's reach, and ask the send-email Edge
-- Function (pg_net, after the commit) to send what's waiting. It takes
-- nothing from its caller: it claims waiting emails (email_claim_pending),
-- sends them over SMTP and says how each went (email_finish). One that
-- fails is tried again with the next ones, three times at most, for two
-- days. send-email writes its own address (email_configure) when it's
-- deployed with SMTP set up; until then nothing is queued and the app works
-- as before.
--
-- Safe to re-run.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table if not exists private.settings (
  key   text primary key,
  value text not null
);
revoke all on private.settings from public, anon, authenticated;

create table if not exists private.email_outbox (
  id         uuid primary key default gen_random_uuid(),
  to_email   text not null,
  kind       text not null check (kind in ('class_booked', 'class_changed', 'class_cancelled')),
  data       jsonb not null default '{}',
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  sent_at    timestamptz,
  attempts   int not null default 0,
  last_error text
);
create index if not exists email_outbox_waiting on private.email_outbox (created_at) where sent_at is null;
revoke all on private.email_outbox from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- 1. What goes in an email
-- ---------------------------------------------------------------------

-- Emails are queued only once send-email has said where it is.
create or replace function private.emails_on()
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (select 1 from private.settings s where s.key = 'email_function_url')
$$;

-- Who has place [b], and where to email them: their account's email, else
-- the one the desk keeps for the member (null when there's none), their
-- name, and their account.
create or replace function private.class_booking_recipient(b public.gym_class_bookings)
returns table (email text, full_name text, user_id uuid)
language sql
stable
set search_path = ''
as $$
  select case when x.e ~ '^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$' then x.e end, x.n, x.u
  from (select lower(trim(coalesce(pr.email, gpr.email, g.email))) as e,
               coalesce(g.full_name, nullif(trim(pr.full_name), ''), nullif(trim(gpr.full_name), '')) as n,
               coalesce(b.user_id, gp.user_id) as u
        from (select 1) one
        left join public.gym_members g on g.id = b.gym_member_id
        left join public.people gp on gp.id = g.person_id
        left join public.profiles gpr on gpr.id = gp.user_id
        left join public.profiles pr on pr.id = b.user_id) x
$$;

-- Class [c] on [day], as its emails show it: the class and its time, the
-- trainer, and the gym, where it is and its phone.
create or replace function private.class_email_details(c public.gym_classes, day date)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'class', c.name, 'date', day, 'weekday', c.weekday, 'starts_at', to_char(c.starts_at, 'HH24:MI'),
    'minutes', c.duration_minutes, 'trainer', c.trainer_name,
    'venue_id', v.id, 'gym', v.name,
    'address', nullif(concat_ws(', ', nullif(trim(v.address), ''), nullif(trim(v.town), ''),
                                case when v.dzongkhag is distinct from nullif(trim(v.town), '') then v.dzongkhag end), ''),
    'phone', v.phone, 'latitude', v.latitude, 'longitude', v.longitude)
  from public.venues v
  where v.id = c.venue_id
$$;


-- ---------------------------------------------------------------------
-- 2. Booked, or cancelled by the gym
-- ---------------------------------------------------------------------

create or replace function private.gym_class_booking_emails()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.gym_classes;
  r record;
  v_kind text;
  v_reason text;
begin
  if not private.emails_on() or new.class_date < public.bhutan_today() then
    return null;
  end if;
  if tg_op = 'INSERT' and new.status = 'booked' then
    v_kind := 'class_booked';
  elsif tg_op = 'UPDATE' and old.status = 'booked' and new.status = 'cancelled' then
    v_kind := 'class_cancelled';
  else
    return null;
  end if;
  select * into r from private.class_booking_recipient(new);
  if r.email is null then
    return null;
  end if;
  -- They cancelled it themselves: nothing to tell them.
  if v_kind = 'class_cancelled' and new.cancelled_by is not null and new.cancelled_by = r.user_id then
    return null;
  end if;
  select * into c from public.gym_classes x where x.id = new.class_id;
  if v_kind = 'class_cancelled' then
    v_reason := case when not c.is_active then 'off'
                     when c.weekday <> extract(isodow from new.class_date) then 'moved'
                     else 'gym' end;
  end if;
  insert into private.email_outbox (to_email, kind, data)
  values (r.email, v_kind, private.class_email_details(c, new.class_date) || jsonb_build_object('name', r.full_name, 'reason', v_reason));
  return null;
end;
$$;
drop trigger if exists gym_class_booking_emails on public.gym_class_bookings;
create trigger gym_class_booking_emails after insert or update of status on public.gym_class_bookings
  for each row execute function private.gym_class_booking_emails();


-- ---------------------------------------------------------------------
-- 3. The class changed: its time, length, trainer or name
-- ---------------------------------------------------------------------

-- Taken off the timetable or moved to another day, its places to come are
-- cancelled (gym_save_class), and each is emailed as such (section 2).
create or replace function private.gym_class_change_emails()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.emails_on() or not old.is_active or not new.is_active or new.weekday <> old.weekday
     or (new.name, new.starts_at, new.duration_minutes, new.trainer_name)
        is not distinct from (old.name, old.starts_at, old.duration_minutes, old.trainer_name) then
    return null;
  end if;
  insert into private.email_outbox (to_email, kind, data)
  select r.email, 'class_changed',
         private.class_email_details(new, min(b.class_date))
           || jsonb_build_object(
                'name', min(r.full_name),
                'dates', jsonb_agg(b.class_date order by b.class_date),
                'before', jsonb_build_object('class', old.name, 'starts_at', to_char(old.starts_at, 'HH24:MI'),
                                             'minutes', old.duration_minutes, 'trainer', old.trainer_name))
  from public.gym_class_bookings b
  cross join lateral private.class_booking_recipient(b) r
  where b.class_id = new.id and b.status = 'booked' and b.class_date >= public.bhutan_today()
    and public.gym_class_start(old, b.class_date) > now() and r.email is not null
  group by r.email;
  return null;
end;
$$;
drop trigger if exists gym_class_change_emails on public.gym_classes;
create trigger gym_class_change_emails after update on public.gym_classes
  for each row execute function private.gym_class_change_emails();


-- ---------------------------------------------------------------------
-- 4. Sending: send-email is asked; it claims, sends, and says how it went
-- ---------------------------------------------------------------------

create or replace function private.email_outbox_send()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
begin
  select s.value into v_url from private.settings s where s.key = 'email_function_url';
  if v_url is null or not exists (select 1 from added) then
    return null;
  end if;
  -- pg_net calls it after this commits; whatever goes wrong there, the
  -- booking or the change itself stands.
  begin
    perform net.http_post(
      url := v_url,
      body := '{"send": true}'::jsonb,
      headers := '{"Content-Type": "application/json"}'::jsonb
    );
  exception when others then
    raise warning 'Emails not sent yet: %', sqlerrm;
  end;
  return null;
end;
$$;
drop trigger if exists email_outbox_send on private.email_outbox;
create trigger email_outbox_send after insert on private.email_outbox
  referencing new table as added
  for each statement execute function private.email_outbox_send();

-- Up to [max_count] emails waiting, oldest first, for send-email to send
-- now: each claimed by one call only, tried three times at most, for two
-- days. Emails over a month old are cleared away.
create or replace function public.email_claim_pending(max_count int default 25)
returns jsonb
language sql
volatile
security definer
set search_path = ''
as $$
  with cleared as (
    delete from private.email_outbox o where o.created_at < now() - interval '30 days'
  ), picked as (
    select o.id from private.email_outbox o
    where o.sent_at is null and o.attempts < 3 and o.created_at > now() - interval '2 days'
      and (o.claimed_at is null or o.claimed_at < now() - interval '10 minutes')
    order by o.created_at
    limit greatest(1, least(coalesce(max_count, 25), 100))
    for update skip locked
  ), claimed as (
    update private.email_outbox o set claimed_at = now(), attempts = o.attempts + 1
    from picked
    where o.id = picked.id
    returning o.id, o.to_email, o.kind, o.data, o.created_at
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'to', c.to_email, 'kind', c.kind, 'data', c.data) order by c.created_at),
                  '[]'::jsonb)
  from claimed c
$$;

-- How sending went: [sent_ids] went out; [failures] ([{id, error}]) are
-- tried again with the next ones.
create or replace function public.email_finish(sent_ids uuid[], failures jsonb default '[]')
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  update private.email_outbox o set sent_at = now(), last_error = null
  where o.id = any (coalesce(sent_ids, '{}'));
  update private.email_outbox o set claimed_at = null, last_error = left(f ->> 'error', 500)
  from jsonb_array_elements(coalesce(failures, '[]'::jsonb)) f
  where o.id = (f ->> 'id')::uuid and o.sent_at is null;
$$;

-- Where send-email is: it says so itself, from its own address, when SMTP
-- is set up; null when it isn't (nothing is queued then).
create or replace function public.email_configure(function_url text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if function_url is null then
    delete from private.settings s where s.key = 'email_function_url';
    return;
  end if;
  if function_url !~ '^https://[A-Za-z0-9.-]+/functions/v1/send-email$' then
    raise exception 'That isn''t the send-email function''s address.';
  end if;
  insert into private.settings (key, value) values ('email_function_url', function_url)
  on conflict (key) do update set value = excluded.value;
end;
$$;

revoke execute on function public.email_claim_pending(int), public.email_finish(uuid[], jsonb), public.email_configure(text)
  from public, anon, authenticated;
grant execute on function public.email_claim_pending(int), public.email_finish(uuid[], jsonb), public.email_configure(text)
  to service_role;
