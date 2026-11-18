-- Following members up on WhatsApp, and birthday wishes.
--
-- The desk sends a renewal reminder or a birthday wish from WhatsApp on its
-- own phone (free, and it reaches members registered without the app); the
-- app notes each one, so the desk sees who was reminded and when, and it's
-- in the activity log. Staff who see members ('gym.members') send them.
--
-- Members with the app and a package running get a birthday wish from
-- their gym each year, as a notification (and a push), at 08:05 Bhutan time.
-- Born on 29 February: on 28 February in other years. Safe to re-run.

create table if not exists public.gym_member_messages (
  id            uuid primary key default gen_random_uuid(),
  venue_id      uuid not null references public.venues (id) on delete cascade,
  gym_member_id uuid not null references public.gym_members (id) on delete cascade,
  kind          text not null check (kind in ('renewal', 'birthday')),
  sent_by       uuid constraint gym_member_messages_sent_by_fkey references public.profiles (id) on delete set null,
  sent_at       timestamptz not null default now()
);
create index if not exists gym_member_messages_venue on public.gym_member_messages (venue_id, sent_at desc);
create index if not exists gym_member_messages_member on public.gym_member_messages (gym_member_id, sent_at desc);

alter table public.gym_member_messages enable row level security;
revoke all on public.gym_member_messages from anon, authenticated;
grant select on public.gym_member_messages to authenticated;
drop policy if exists "gym_member_messages: who sees members" on public.gym_member_messages;
create policy "gym_member_messages: who sees members" on public.gym_member_messages for select to authenticated
  using (public.has_venue_permission(venue_id, 'gym.members'));

-- The desk sent [gym_member_id] a [kind] ('renewal' or 'birthday') message
-- on WhatsApp. When it was noted.
create or replace function public.gym_note_message(gym_member_id uuid, kind text)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.gym_members;
  v_at timestamptz;
begin
  select * into v_member from public.gym_members g where g.id = gym_note_message.gym_member_id;
  if not found then
    raise exception 'This member is no longer registered.';
  end if;
  if not public.has_venue_permission(v_member.venue_id, 'gym.members') then
    raise exception 'Your role here can''t message members.';
  end if;
  if gym_note_message.kind is null or gym_note_message.kind not in ('renewal', 'birthday') then
    raise exception 'Choose a renewal reminder or a birthday wish.';
  end if;
  insert into public.gym_member_messages (venue_id, gym_member_id, kind, sent_by)
  values (v_member.venue_id, v_member.id, gym_note_message.kind, (select auth.uid()))
  returning sent_at into v_at;
  perform public.gym_audit(v_member.venue_id,
    case gym_note_message.kind when 'renewal' then 'member.reminded' else 'member.wished' end,
    case gym_note_message.kind when 'renewal' then 'Reminded ' || v_member.full_name || ' on WhatsApp to renew'
         else 'Wished ' || v_member.full_name || ' a happy birthday on WhatsApp' end,
    null, v_member.id, v_member.full_name);
  return v_at;
end;
$$;

-- Whose birthday is [day]: born that day of the year, or on 29 February
-- when [day] is 28 February of a year without one.
create or replace function public.gym_is_birthday(born date, day date)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select born is not null and (
    (extract(month from born) = extract(month from day) and extract(day from born) = extract(day from day))
    or (extract(month from born) = 2 and extract(day from born) = 29 and extract(month from day) = 2
        and extract(day from day) = 28 and extract(day from (make_date(extract(year from day)::int, 3, 1) - 1)) = 28))
$$;

-- Which members had this year's wish.
create table if not exists public.gym_birthday_wishes_sent (
  gym_member_id uuid not null references public.gym_members (id) on delete cascade,
  year          int not null,
  sent_at       timestamptz not null default now(),
  primary key (gym_member_id, year)
);
alter table public.gym_birthday_wishes_sent enable row level security;
revoke all on public.gym_birthday_wishes_sent from anon, authenticated;

-- Every day: a wish from each gym to its members with the app, a package
-- running and their birthday today. How many were sent.
create or replace function public.gym_birthday_wishes()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := public.bhutan_today();
  v_sent int := 0;
  r record;
begin
  for r in
    select g.id, g.full_name, v.name as gym_name, p.user_id
    from public.gym_members g
    join public.people p on p.id = g.person_id and p.user_id is not null
    join public.venues v on v.id = g.venue_id
    where public.gym_is_birthday(g.date_of_birth, v_today)
      and exists (select 1 from public.gym_subscriptions s
                  where s.gym_member_id = g.id and s.status = 'active' and s.end_date >= v_today)
  loop
    insert into public.gym_birthday_wishes_sent (gym_member_id, year)
    values (r.id, extract(year from v_today)::int)
    on conflict do nothing;
    continue when not found;
    perform public.notify(r.user_id, 'gym_membership',
      'Happy birthday, ' || split_part(trim(r.full_name), ' ', 1) || '!',
      'Everyone at ' || r.gym_name || ' wishes you a healthy, happy year ahead. Enjoy your workout today!',
      '/gyms/my');
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end;
$$;

revoke execute on function public.gym_birthday_wishes() from public, anon, authenticated;
revoke execute on function public.gym_note_message(uuid, text) from public, anon;
grant execute on function public.gym_note_message(uuid, text) to authenticated;

-- Daily at 08:05 Bhutan time (02:05 UTC) with pg_cron, as the daily gym job
-- (20261107000003). Without it, run "select public.gym_birthday_wishes()"
-- once a day.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
    perform cron.schedule('gym-birthday-wishes', '5 2 * * *', 'select public.gym_birthday_wishes()');
  else
    raise notice 'pg_cron is not available: run "select public.gym_birthday_wishes()" once a day.';
  end if;
exception when others then
  raise warning 'The birthday wishes job was not scheduled (%). See the README, "Daily job".', sqlerrm;
end;
$$;
