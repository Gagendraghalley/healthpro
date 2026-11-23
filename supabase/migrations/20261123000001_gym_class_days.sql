-- One date of a weekly class, changed or cancelled on its own ("Yoga on
-- Sat 28 Nov only"): its time, length, trainer or places, or not held at
-- all, with a note for who's booked. Every other week runs as the timetable
-- says. Changing the class itself (gym_save_class) still changes every
-- week, but no longer a date's own time, length, trainer or places.
--
-- Kept by who has Classes ('gym.classes'), seen by anyone (the gym's public
-- page shows it). A date is changed before it starts, up to two weeks ahead,
-- and its places never below those booked. Who's booked is told in the app
-- and by email: a new time, trainer or places keeps their place; cancelled,
-- their places are cancelled. Back to the timetable puts the date as the
-- timetable has it (places cancelled stay cancelled). Moved to another day
-- or taken off the timetable, its dates to come go too.
--
-- Booking, cancelling and the emails now read a class as it runs on the day
-- (gym_class_on): gym_class_start, gym_book_class, my_class_bookings, the
-- booking emails and the gym's notice of a booking.
--
-- Safe to re-run.

create table if not exists public.gym_class_days (
  class_id         uuid not null references public.gym_classes (id) on delete cascade,
  class_date       date not null,
  venue_id         uuid not null references public.venues (id) on delete cascade,
  starts_at        time not null,
  duration_minutes int not null check (duration_minutes between 15 and 240),
  trainer_name     text check (char_length(trainer_name) <= 100),
  capacity         int not null check (capacity between 1 and 500),
  is_cancelled     boolean not null default false,
  note             text check (char_length(note) <= 200),
  changed_by       uuid constraint gym_class_days_changed_by_fkey references public.profiles (id) on delete set null,
  updated_at       timestamptz not null default now(),
  constraint gym_class_days_pkey primary key (class_id, class_date)
);
create index if not exists gym_class_days_venue on public.gym_class_days (venue_id, class_date);

drop trigger if exists gym_class_days_updated_at on public.gym_class_days;
create trigger gym_class_days_updated_at before update on public.gym_class_days
  for each row execute function public.set_updated_at();

-- Public, as the timetable: written only through gym_save_class_day.
alter table public.gym_class_days enable row level security;
revoke all on public.gym_class_days from anon, authenticated;
grant select on public.gym_class_days to anon, authenticated;
drop policy if exists "gym_class_days: anyone" on public.gym_class_days;
create policy "gym_class_days: anyone" on public.gym_class_days for select to anon, authenticated using (true);


-- ---------------------------------------------------------------------
-- 1. A class as it runs on a day
-- ---------------------------------------------------------------------

-- Class [c] on [on_day]: the date's own time, length, trainer and places
-- when it was changed on its own; the timetable's otherwise.
create or replace function public.gym_class_on(c public.gym_classes, on_day date)
returns public.gym_classes
language plpgsql
stable
set search_path = ''
as $$
declare
  x public.gym_class_days;
begin
  select * into x from public.gym_class_days d where d.class_id = c.id and d.class_date = on_day;
  if found then
    c.starts_at := x.starts_at;
    c.duration_minutes := x.duration_minutes;
    c.trainer_name := x.trainer_name;
    c.capacity := x.capacity;
  end if;
  return c;
end;
$$;
revoke execute on function public.gym_class_on(public.gym_classes, date) from public, anon, authenticated;

-- As in 20261118000013, at the date's own time when it has one.
create or replace function public.gym_class_start(c public.gym_classes, day date)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select (day + coalesce((select d.starts_at from public.gym_class_days d where d.class_id = c.id and d.class_date = day), c.starts_at))
         at time zone 'Asia/Thimphu'
$$;
revoke execute on function public.gym_class_start(public.gym_classes, date) from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- 2. Changing a date, cancelling it, back to the timetable
-- ---------------------------------------------------------------------

-- Tells who's booked into class [c] on [on_day] that it changed from [o] to
-- [n] that day, their place kept: in the app, and by email.
create or replace function private.gym_class_day_notices(c public.gym_classes, on_day date, o public.gym_classes,
                                                         n public.gym_classes, note text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  if (n.starts_at, n.duration_minutes, n.trainer_name, n.capacity)
     is not distinct from (o.starts_at, o.duration_minutes, o.trainer_name, o.capacity) then
    return;
  end if;
  if private.emails_on() then
    insert into private.email_outbox (to_email, kind, data)
    select rc.email, 'class_changed',
           private.class_email_details(n, on_day)
             || jsonb_build_object(
                  'name', rc.full_name,
                  'dates', jsonb_build_array(on_day),
                  'before', jsonb_build_object('class', o.name, 'starts_at', to_char(o.starts_at, 'HH24:MI'),
                                               'minutes', o.duration_minutes, 'trainer', o.trainer_name,
                                               'description', o.description, 'capacity', o.capacity,
                                               'open_to_all', o.open_to_all))
    from public.gym_class_bookings b
    cross join lateral private.class_booking_recipient(b) rc
    where b.class_id = c.id and b.class_date = on_day and b.status = 'booked' and rc.email is not null;
  end if;
  for r in
    select rc.user_id, b.user_id is null as registered
    from public.gym_class_bookings b
    cross join lateral private.class_booking_recipient(b) rc
    where b.class_id = c.id and b.class_date = on_day and b.status = 'booked' and rc.user_id is not null
  loop
    perform public.notify(r.user_id, 'gym_membership', c.name || ' on ' || to_char(on_day, 'FMDy FMDD Mon') || ' has changed',
      concat_ws(' ', private.class_change_summary(o, n), note, 'Your place is kept.'),
      case when r.registered then '/gyms/my?gym=' || c.venue_id else '/gyms/' || c.venue_id end);
  end loop;
end;
$$;
revoke execute on function private.gym_class_day_notices(public.gym_classes, date, public.gym_classes, public.gym_classes, text)
  from public, anon, authenticated;

-- [details]: starts_at ('09:00'), duration_minutes, trainer_name, capacity,
-- is_cancelled, note. Class [class_id] on [class_date] only; what's left out
-- stays as the date has it.
create or replace function public.gym_save_class_day(class_id uuid, class_date date, details jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  d jsonb := coalesce(gym_save_class_day.details, '{}');
  v_day date := gym_save_class_day.class_date;
  c public.gym_classes;
  v_was public.gym_classes;
  v_cancel boolean := coalesce((d ->> 'is_cancelled')::boolean, false);
  v_note text := nullif(trim(coalesce(d ->> 'note', '')), '');
  v_starts time;
  v_minutes int;
  v_trainer text;
  v_capacity int;
  v_taken int;
begin
  select * into c from public.gym_classes x where x.id = gym_save_class_day.class_id;
  if not found or not c.is_active then
    raise exception 'This class isn''t on the timetable any more.';
  end if;
  if not public.has_venue_permission(c.venue_id, 'gym.classes') then
    raise exception 'Only the gym''s staff with Classes can change a class.';
  end if;
  if v_day is null or extract(isodow from v_day) <> c.weekday then
    raise exception '% isn''t on that day.', c.name;
  end if;
  if v_day > public.bhutan_today() + 13 then
    raise exception 'Change a class up to two weeks ahead.';
  end if;
  if public.gym_class_start(c, v_day) <= now() then
    raise exception '% on % has started already.', c.name, to_char(v_day, 'FMDD Mon');
  end if;
  v_was := public.gym_class_on(c, v_day);
  v_starts := coalesce(nullif(d ->> 'starts_at', '')::time, v_was.starts_at);
  v_minutes := coalesce(nullif(d ->> 'duration_minutes', '')::int, v_was.duration_minutes);
  v_trainer := case when d ? 'trainer_name' then nullif(trim(coalesce(d ->> 'trainer_name', '')), '') else v_was.trainer_name end;
  v_capacity := coalesce(nullif(d ->> 'capacity', '')::int, v_was.capacity);
  if v_minutes not between 15 and 240 then
    raise exception 'A class runs 15 minutes to 4 hours.';
  end if;
  if v_capacity not between 1 and 500 then
    raise exception 'Places: 1 to 500.';
  end if;
  if char_length(v_trainer) > 100 or char_length(v_note) > 200 then
    raise exception 'Keep the trainer under 100 characters and the note under 200.';
  end if;
  if not v_cancel and (v_day + v_starts) at time zone 'Asia/Thimphu' <= now() then
    raise exception 'Choose a time still to come.';
  end if;

  -- Under the lock booking takes, so the places counted stay counted.
  perform 1 from public.gym_classes x where x.id = c.id for update;
  select count(*) into v_taken from public.gym_class_bookings b
  where b.class_id = c.id and b.class_date = v_day and b.status = 'booked';
  if not v_cancel and v_capacity < v_taken then
    raise exception 'Booked in already: %. Keep that many places at least, or take some out first.', v_taken;
  end if;

  insert into public.gym_class_days (class_id, class_date, venue_id, starts_at, duration_minutes, trainer_name, capacity,
                                     is_cancelled, note, changed_by)
  values (c.id, v_day, c.venue_id, v_starts, v_minutes, v_trainer, v_capacity, v_cancel, v_note, (select auth.uid()))
  on conflict on constraint gym_class_days_pkey do update
     set starts_at = excluded.starts_at, duration_minutes = excluded.duration_minutes, trainer_name = excluded.trainer_name,
         capacity = excluded.capacity, is_cancelled = excluded.is_cancelled, note = excluded.note, changed_by = excluded.changed_by;

  if v_cancel then
    -- Each one is told why (gym_class_booking_emails: reason 'day', with the note).
    update public.gym_class_bookings b
       set status = 'cancelled', cancelled_by = (select auth.uid()), cancelled_at = now()
     where b.class_id = c.id and b.class_date = v_day and b.status = 'booked';
  else
    perform private.gym_class_day_notices(c, v_day, v_was, public.gym_class_on(c, v_day), v_note);
  end if;
end;
$$;
revoke execute on function public.gym_save_class_day(uuid, date, jsonb) from public, anon;
grant execute on function public.gym_save_class_day(uuid, date, jsonb) to authenticated;

-- Class [class_id] on [class_date] as the timetable has it again. Places
-- cancelled with the date stay cancelled.
create or replace function public.gym_clear_class_day(class_id uuid, class_date date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_day date := gym_clear_class_day.class_date;
  c public.gym_classes;
  x public.gym_class_days;
  v_was public.gym_classes;
  v_taken int;
begin
  select * into c from public.gym_classes g where g.id = gym_clear_class_day.class_id;
  if not found or not c.is_active then
    raise exception 'This class isn''t on the timetable any more.';
  end if;
  if not public.has_venue_permission(c.venue_id, 'gym.classes') then
    raise exception 'Only the gym''s staff with Classes can change a class.';
  end if;
  select * into x from public.gym_class_days d where d.class_id = c.id and d.class_date = v_day;
  if not found then
    return;
  end if;
  if least(public.gym_class_start(c, v_day), (v_day + c.starts_at) at time zone 'Asia/Thimphu') <= now() then
    raise exception '% on % has started already.', c.name, to_char(v_day, 'FMDD Mon');
  end if;
  v_was := public.gym_class_on(c, v_day);
  perform 1 from public.gym_classes g where g.id = c.id for update;
  if not x.is_cancelled then
    select count(*) into v_taken from public.gym_class_bookings b
    where b.class_id = c.id and b.class_date = v_day and b.status = 'booked';
    if c.capacity < v_taken then
      raise exception 'Booked in already: %, and the timetable has % places. Take some out first, or keep this date''s places.',
        v_taken, c.capacity;
    end if;
  end if;
  delete from public.gym_class_days d where d.class_id = c.id and d.class_date = v_day;
  if not x.is_cancelled then
    perform private.gym_class_day_notices(c, v_day, v_was, c, null);
  end if;
end;
$$;
revoke execute on function public.gym_clear_class_day(uuid, date) from public, anon;
grant execute on function public.gym_clear_class_day(uuid, date) to authenticated;

-- Moved to another day or off the timetable: its dates to come go with it
-- (gym_save_class cancels their places).
create or replace function private.gym_class_days_follow_class()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not new.is_active or new.weekday <> old.weekday then
    delete from public.gym_class_days d where d.class_id = new.id and d.class_date >= public.bhutan_today();
  end if;
  return null;
end;
$$;
revoke execute on function private.gym_class_days_follow_class() from public, anon, authenticated;
drop trigger if exists gym_class_days_follow_class on public.gym_classes;
create trigger gym_class_days_follow_class after update on public.gym_classes
  for each row execute function private.gym_class_days_follow_class();


-- ---------------------------------------------------------------------
-- 3. Booking, and what's said about it, on the day as it runs
-- ---------------------------------------------------------------------

-- As in 20261118000016: a cancelled date can't be booked, and a date's own
-- places count.
create or replace function public.gym_book_class(class_id uuid, class_date date, gym_member_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  c public.gym_classes;
  v_member public.gym_members;
  v_account uuid; -- the account booked in, when they have no registration here
  v_name text;
  v_self boolean := gym_book_class.gym_member_id is null;
  v_me uuid := (select auth.uid());
  v_today date := public.bhutan_today();
  v_day date := gym_book_class.class_date;
  v_person public.people;
  v_taken int;
  v_id uuid;
begin
  select * into c from public.gym_classes x where x.id = gym_book_class.class_id;
  if not found or not c.is_active then
    raise exception 'This class isn''t on the timetable any more.';
  end if;
  if v_self then
    if v_me is null then
      raise exception 'Sign in to Health Pro to book a class.';
    end if;
    v_person := public.person_for_user(v_me);
    select * into v_member from public.gym_members g where g.person_id = v_person.id and g.venue_id = c.venue_id limit 1;
    if v_member.id is null then
      if c.open_to_all or exists (select 1 from public.gym_subscriptions s
                                  where s.member_id = v_me and s.venue_id = c.venue_id and s.status in ('active', 'expired')) then
        v_account := v_me;
      else
        raise exception 'Only members of this gym can book %.', c.name;
      end if;
    end if;
  else
    select * into v_member from public.gym_members g where g.id = gym_book_class.gym_member_id and g.venue_id = c.venue_id;
    if not found then
      raise exception 'That member isn''t registered at this gym.';
    end if;
    if not public.has_venue_permission(c.venue_id, 'gym.classes') and not public.gym_member_is_me(v_member.id) then
      raise exception 'Only the gym''s staff can book a class for a member.';
    end if;
  end if;
  v_name := coalesce(v_member.full_name, 'They');
  if v_day is null or extract(isodow from v_day) <> c.weekday then
    raise exception '% isn''t on that day.', c.name;
  end if;
  if v_day < v_today or v_day > v_today + 13 then
    raise exception 'Book a class up to two weeks ahead.';
  end if;
  if exists (select 1 from public.gym_class_days x where x.class_id = c.id and x.class_date = v_day and x.is_cancelled) then
    raise exception '% on % is cancelled.', c.name, to_char(v_day, 'FMDD Mon');
  end if;
  c := public.gym_class_on(c, v_day);
  if public.gym_class_start(c, v_day) <= now() then
    raise exception '% on % has started already.', c.name, to_char(v_day, 'FMDD Mon');
  end if;
  if not c.open_to_all then
    if not exists (select 1 from public.gym_subscriptions s
                   where s.status = 'active' and s.start_date <= v_day and s.end_date >= v_day
                     and ((v_account is null and s.gym_member_id = v_member.id)
                          or (v_account is not null and s.member_id = v_account and s.venue_id = c.venue_id))) then
      raise exception '%', case when v_self then 'Your package doesn''t cover ' || to_char(v_day, 'FMDD Mon') || '. Renew it first.'
                                else v_name || ' has no package on ' || to_char(v_day, 'FMDD Mon') || '.' end;
    end if;
    if v_account is null and exists (select 1 from public.gym_membership_pauses p
                                     where p.gym_member_id = v_member.id and v_day between p.start_date and p.end_date) then
      raise exception '%', case when v_self then 'Your membership is paused on ' || to_char(v_day, 'FMDD Mon') || '.'
                                else v_name || '''s membership is paused on ' || to_char(v_day, 'FMDD Mon') || '.' end;
    end if;
  end if;

  -- One booking at a time per class: the places are counted under the lock.
  -- Once a person: by their registration, or their account (booked as a
  -- guest before the desk registered them).
  perform 1 from public.gym_classes x where x.id = c.id for update;
  if exists (select 1 from public.gym_class_bookings b
             where b.class_id = c.id and b.class_date = v_day and b.status = 'booked'
               and (b.gym_member_id = v_member.id or b.user_id = v_account
                    or b.user_id = (select p.user_id from public.people p where p.id = v_member.person_id))) then
    raise exception '%', case when v_self then 'You''re booked in already.' else v_name || ' is booked in already.' end;
  end if;
  -- The date's places as they are now, read again under the lock.
  c := public.gym_class_on(c, v_day);
  select count(*) into v_taken from public.gym_class_bookings b
  where b.class_id = c.id and b.class_date = v_day and b.status = 'booked';
  if v_taken >= c.capacity then
    raise exception '% on % is full.', c.name, to_char(v_day, 'FMDD Mon');
  end if;

  insert into public.gym_class_bookings (class_id, venue_id, class_date, gym_member_id, user_id, booked_by)
  values (c.id, c.venue_id, v_day, v_member.id, v_account, v_me)
  returning id into v_id;
  return v_id;
end;
$$;

-- As in 20261118000017, at the date's own time and with its trainer.
create or replace function public.my_class_bookings()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', b.id,
    'class_id', c.id,
    'venue_id', b.venue_id,
    'venue_name', v.name,
    'class_date', b.class_date,
    'name', c.name,
    'trainer_name', c.trainer_name,
    'starts_at', c.starts_at,
    'duration_minutes', c.duration_minutes
  ) order by b.class_date, c.starts_at), '[]'::jsonb)
  from public.gym_class_bookings b
  join public.gym_classes w on w.id = b.class_id
  cross join lateral public.gym_class_on(w, b.class_date) c
  join public.venues v on v.id = b.venue_id
  where b.status = 'booked' and b.class_date >= public.bhutan_today()
    and (b.user_id = (select auth.uid())
         or b.gym_member_id in (select g.id from public.gym_members g join public.people p on p.id = g.person_id
                                where p.user_id = (select auth.uid())));
$$;

-- As in 20261119000002, with the class as it runs that day; a cancelled date
-- says so (reason 'day', with the gym's note).
create or replace function private.gym_class_booking_emails()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.gym_classes;
  x public.gym_class_days;
  r record;
  v_kind text;
  v_reason text;
begin
  if new.class_date < public.bhutan_today() then
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
  -- They cancelled it themselves: nothing to tell them.
  if v_kind = 'class_cancelled' and new.cancelled_by is not null and new.cancelled_by = r.user_id then
    return null;
  end if;
  select * into c from public.gym_classes g where g.id = new.class_id;
  select * into x from public.gym_class_days d where d.class_id = new.class_id and d.class_date = new.class_date;
  c := public.gym_class_on(c, new.class_date);
  if v_kind = 'class_cancelled' then
    v_reason := case when not c.is_active then 'off'
                     when c.weekday <> extract(isodow from new.class_date) then 'moved'
                     when x.is_cancelled then 'day'
                     else 'gym' end;
  end if;
  if v_reason in ('gym', 'day') then
    perform public.notify(r.user_id, 'gym_membership',
      c.name || ' on ' || to_char(new.class_date, 'FMDy FMDD Mon') || case when v_reason = 'day' then ' is cancelled' else ' was cancelled' end,
      case when v_reason = 'day' then concat_ws(' ', 'The gym isn''t holding it that day, so your place was cancelled.', x.note)
           else 'The gym cancelled your place.' end
      || case when new.user_id is null then ' See its classes on My gym to book another.'
              else ' See its classes on its page to book another.' end,
      case when new.user_id is null then '/gyms/my?gym=' || new.venue_id else '/gyms/' || new.venue_id end);
  end if;
  if r.email is null or not private.emails_on() then
    return null;
  end if;
  insert into private.email_outbox (to_email, kind, data)
  values (r.email, v_kind, private.class_email_details(c, new.class_date)
                           || jsonb_build_object('name', r.full_name, 'reason', v_reason, 'note', x.note));
  return null;
end;
$$;

-- As in 20261122000002, at the date's own time.
create or replace function private.gym_class_booking_tells_desk()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.gym_classes;
  r record;
begin
  if new.status <> 'booked' then
    return null;
  end if;
  select * into r from private.class_booking_recipient(new);
  if r.user_id is null or new.booked_by is distinct from r.user_id then
    return null;
  end if;
  select * into c from public.gym_classes x where x.id = new.class_id;
  c := public.gym_class_on(c, new.class_date);
  perform public.notify_venue_permission(
    new.venue_id, 'gym.classes', 'gym_membership', 'New class booking',
    coalesce(r.full_name, 'Someone') || ' booked ' || c.name || ' on ' || to_char(new.class_date, 'FMDy FMDD Mon')
      || ' at ' || to_char(c.starts_at, 'FMHH12:MI AM') || '.'
      || case when new.gym_member_id is null then ' They aren''t a member here yet.' else '' end,
    '/gyms/' || new.venue_id || '/manage/classes'
  );
  return null;
end;
$$;

-- As in 20261119000002, leaving out the dates changed on their own: the
-- class's new time, trainer or places don't reach them (they keep their own).
create or replace function private.gym_class_change_notices()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_what text;
  r record;
begin
  if not old.is_active or not new.is_active or new.weekday <> old.weekday
     or (new.name, new.description, new.starts_at, new.duration_minutes, new.trainer_name, new.capacity, new.open_to_all)
        is not distinct from
        (old.name, old.description, old.starts_at, old.duration_minutes, old.trainer_name, old.capacity, old.open_to_all) then
    return null;
  end if;

  -- Their places to come that haven't started (at the old time).
  if private.emails_on() then
    insert into private.email_outbox (to_email, kind, data)
    select x.email, 'class_changed',
           private.class_email_details(new, min(x.class_date))
             || jsonb_build_object(
                  'name', min(x.full_name),
                  'dates', jsonb_agg(x.class_date order by x.class_date),
                  'before', jsonb_build_object('class', old.name, 'starts_at', to_char(old.starts_at, 'HH24:MI'),
                                               'minutes', old.duration_minutes, 'trainer', old.trainer_name,
                                               'description', old.description, 'capacity', old.capacity,
                                               'open_to_all', old.open_to_all))
    from (select rc.email, rc.full_name, b.class_date
          from public.gym_class_bookings b
          cross join lateral private.class_booking_recipient(b) rc
          where b.class_id = new.id and b.status = 'booked' and b.class_date >= public.bhutan_today()
            and public.gym_class_start(old, b.class_date) > now()
            and not exists (select 1 from public.gym_class_days d where d.class_id = new.id and d.class_date = b.class_date)) x
    where x.email is not null
    group by x.email;
  end if;

  v_what := private.class_change_summary(old, new);
  for r in
    select x.user_id, bool_or(x.registered) as registered, array_agg(x.class_date order by x.class_date) as dates
    from (select rc.user_id, b.user_id is null as registered, b.class_date
          from public.gym_class_bookings b
          cross join lateral private.class_booking_recipient(b) rc
          where b.class_id = new.id and b.status = 'booked' and b.class_date >= public.bhutan_today()
            and public.gym_class_start(old, b.class_date) > now()
            and not exists (select 1 from public.gym_class_days d where d.class_id = new.id and d.class_date = b.class_date)) x
    where x.user_id is not null
    group by x.user_id
  loop
    perform public.notify(r.user_id, 'gym_membership', old.name || ' has changed',
      v_what || ' ' || case when cardinality(r.dates) = 1
                            then 'Your place on ' || to_char(r.dates[1], 'FMDy FMDD Mon') || ' is kept.'
                            else 'Your ' || cardinality(r.dates) || ' places from ' || to_char(r.dates[1], 'FMDy FMDD Mon')
                                 || ' are kept.' end,
      case when r.registered then '/gyms/my?gym=' || new.venue_id else '/gyms/' || new.venue_id end);
  end loop;
  return null;
end;
$$;
