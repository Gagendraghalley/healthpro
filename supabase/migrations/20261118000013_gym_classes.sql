-- Group classes: a gym's weekly timetable (Yoga on Monday at 7:00, an hour,
-- 20 places) and booking a place in a class on a day.
--
-- The timetable (gym_classes) is kept by who sets prices ('gym.plans') and
-- seen by anyone. Members book themselves in My gym, up to two weeks ahead,
-- before the class starts, when a package of theirs covers that day and
-- they're not paused; the desk ('gym.members') books anyone, and sees who's
-- booked. Never more than the class's places. A member cancels their own
-- before it starts; the desk any time. Taking a class off the timetable
-- cancels its bookings to come, and members with the app are told.
--
-- Days are ISO weekdays, Monday 1 to Sunday 7 (as trainer_slots); times are
-- Bhutan times. Safe to re-run.

create table if not exists public.gym_classes (
  id               uuid primary key default gen_random_uuid(),
  venue_id         uuid not null references public.venues (id) on delete cascade,
  name             text not null check (char_length(trim(name)) between 2 and 60),
  description      text check (char_length(description) <= 300),
  trainer_name     text check (char_length(trainer_name) <= 100),
  weekday          smallint not null check (weekday between 1 and 7),
  starts_at        time not null,
  duration_minutes int not null check (duration_minutes between 15 and 240),
  capacity         int not null check (capacity between 1 and 500),
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists gym_classes_venue on public.gym_classes (venue_id, weekday, starts_at);

drop trigger if exists gym_classes_updated_at on public.gym_classes;
create trigger gym_classes_updated_at before update on public.gym_classes
  for each row execute function public.set_updated_at();

create table if not exists public.gym_class_bookings (
  id            uuid primary key default gen_random_uuid(),
  class_id      uuid not null references public.gym_classes (id) on delete cascade,
  venue_id      uuid not null references public.venues (id) on delete cascade,
  class_date    date not null,
  gym_member_id uuid not null references public.gym_members (id) on delete cascade,
  status        text not null default 'booked' check (status in ('booked', 'cancelled')),
  booked_by     uuid constraint gym_class_bookings_booked_by_fkey references public.profiles (id) on delete set null,
  booked_at     timestamptz not null default now(),
  cancelled_by  uuid constraint gym_class_bookings_cancelled_by_fkey references public.profiles (id) on delete set null,
  cancelled_at  timestamptz
);
create unique index if not exists gym_class_bookings_once on public.gym_class_bookings (class_id, class_date, gym_member_id)
  where status = 'booked';
create index if not exists gym_class_bookings_day on public.gym_class_bookings (venue_id, class_date);
create index if not exists gym_class_bookings_member on public.gym_class_bookings (gym_member_id, class_date);

-- The timetable is public; classes no longer on it, only to who keeps it.
alter table public.gym_classes enable row level security;
revoke all on public.gym_classes from anon, authenticated;
grant select on public.gym_classes to anon, authenticated;
drop policy if exists "gym_classes: on the timetable" on public.gym_classes;
create policy "gym_classes: on the timetable" on public.gym_classes for select to anon, authenticated using (is_active);
drop policy if exists "gym_classes: who keeps it" on public.gym_classes;
create policy "gym_classes: who keeps it" on public.gym_classes for select to authenticated
  using (public.has_venue_permission(venue_id, 'gym.plans'));

alter table public.gym_class_bookings enable row level security;
revoke all on public.gym_class_bookings from anon, authenticated;
grant select on public.gym_class_bookings to authenticated;
drop policy if exists "gym_class_bookings: the desk and the member" on public.gym_class_bookings;
create policy "gym_class_bookings: the desk and the member" on public.gym_class_bookings for select to authenticated
  using (public.has_venue_permission(venue_id, 'gym.members') or public.gym_member_is_me(gym_member_id));

-- When a class on [day] starts, as a moment.
create or replace function public.gym_class_start(c public.gym_classes, day date)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select (day + c.starts_at) at time zone 'Asia/Thimphu'
$$;

-- [details]: name, description, trainer_name, weekday (1 Monday to 7
-- Sunday), starts_at ('07:00'), duration_minutes, capacity, is_active. A new
-- class ([class_id] null) or changes to one. Its id.
create or replace function public.gym_save_class(venue_id uuid, class_id uuid, details jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  d jsonb := coalesce(gym_save_class.details, '{}');
  v_venue uuid := gym_save_class.venue_id;
  v_old public.gym_classes;
  v_name text := trim(coalesce(d ->> 'name', ''));
  v_description text := nullif(trim(coalesce(d ->> 'description', '')), '');
  v_trainer text := nullif(trim(coalesce(d ->> 'trainer_name', '')), '');
  v_weekday int := nullif(d ->> 'weekday', '')::int;
  v_starts time := nullif(d ->> 'starts_at', '')::time;
  v_minutes int := coalesce(nullif(d ->> 'duration_minutes', '')::int, 60);
  v_capacity int := nullif(d ->> 'capacity', '')::int;
  v_active boolean := coalesce((d ->> 'is_active')::boolean, true);
  v_id uuid;
  r record;
begin
  if not public.has_venue_permission(v_venue, 'gym.plans') then
    raise exception 'Only those who set the gym''s packages can change its timetable.';
  end if;
  if gym_save_class.class_id is not null then
    select * into v_old from public.gym_classes c where c.id = gym_save_class.class_id;
    if not found or v_old.venue_id <> v_venue then
      raise exception 'This class isn''t there any more.';
    end if;
  end if;
  if char_length(v_name) not between 2 and 60 then
    raise exception 'Give the class a name, e.g. Yoga.';
  end if;
  if char_length(v_description) > 300 or char_length(v_trainer) > 100 then
    raise exception 'Keep the description under 300 characters and the trainer under 100.';
  end if;
  if v_weekday is null or v_weekday not between 1 and 7 then
    raise exception 'Choose the day of the week.';
  end if;
  if v_starts is null then
    raise exception 'Choose when it starts.';
  end if;
  if v_minutes not between 15 and 240 then
    raise exception 'A class runs 15 minutes to 4 hours.';
  end if;
  if v_capacity is null or v_capacity not between 1 and 500 then
    raise exception 'Places: 1 to 500.';
  end if;

  if gym_save_class.class_id is null then
    insert into public.gym_classes (venue_id, name, description, trainer_name, weekday, starts_at, duration_minutes, capacity,
                                    is_active)
    values (v_venue, v_name, v_description, v_trainer, v_weekday, v_starts, v_minutes, v_capacity, v_active)
    returning id into v_id;
    return v_id;
  end if;

  update public.gym_classes c
     set name = v_name, description = v_description, trainer_name = v_trainer, weekday = v_weekday, starts_at = v_starts,
         duration_minutes = v_minutes, capacity = v_capacity, is_active = v_active
   where c.id = v_old.id;

  -- Off the timetable, or on another day: its bookings to come are cancelled.
  if v_old.is_active and (not v_active or v_weekday <> v_old.weekday) then
    for r in
      update public.gym_class_bookings b
         set status = 'cancelled', cancelled_by = (select auth.uid()), cancelled_at = now()
       where b.class_id = v_old.id and b.status = 'booked' and b.class_date >= public.bhutan_today()
      returning b.gym_member_id, b.class_date
    loop
      perform public.notify((select p.user_id from public.gym_members g join public.people p on p.id = g.person_id
                             where g.id = r.gym_member_id),
        'gym_membership', v_old.name || ' on ' || to_char(r.class_date, 'FMDy FMDD Mon') || ' was cancelled',
        'The gym changed its timetable. See the classes on My gym to book another.',
        '/gyms/my?gym=' || v_venue);
    end loop;
  end if;
  return v_old.id;
end;
$$;

-- Books [gym_member_id] (or, when null, the signed-in member) into
-- [class_id] on [class_date]. The booking's id.
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
  v_self boolean := gym_book_class.gym_member_id is null;
  v_today date := public.bhutan_today();
  v_day date := gym_book_class.class_date;
  v_taken int;
  v_id uuid;
begin
  select * into c from public.gym_classes x where x.id = gym_book_class.class_id;
  if not found or not c.is_active then
    raise exception 'This class isn''t on the timetable any more.';
  end if;
  if v_self then
    select g.* into v_member from public.gym_members g join public.people p on p.id = g.person_id
    where g.venue_id = c.venue_id and p.user_id = (select auth.uid())
    limit 1;
    if v_member.id is null then
      raise exception 'Only members of this gym can book its classes.';
    end if;
  else
    select * into v_member from public.gym_members g where g.id = gym_book_class.gym_member_id and g.venue_id = c.venue_id;
    if not found then
      raise exception 'That member isn''t registered at this gym.';
    end if;
    if not public.has_venue_permission(c.venue_id, 'gym.members') and not public.gym_member_is_me(v_member.id) then
      raise exception 'Only the gym''s staff can book a class for a member.';
    end if;
  end if;
  if v_day is null or extract(isodow from v_day) <> c.weekday then
    raise exception '% isn''t on that day.', c.name;
  end if;
  if v_day < v_today or v_day > v_today + 13 then
    raise exception 'Book a class up to two weeks ahead.';
  end if;
  if public.gym_class_start(c, v_day) <= now() then
    raise exception '% on % has started already.', c.name, to_char(v_day, 'FMDD Mon');
  end if;
  if not exists (select 1 from public.gym_subscriptions s
                 where s.gym_member_id = v_member.id and s.status = 'active' and s.start_date <= v_day and s.end_date >= v_day) then
    raise exception '%', case when v_self then 'Your package doesn''t cover ' || to_char(v_day, 'FMDD Mon') || '. Renew it first.'
                              else v_member.full_name || ' has no package on ' || to_char(v_day, 'FMDD Mon') || '.' end;
  end if;
  if exists (select 1 from public.gym_membership_pauses p
             where p.gym_member_id = v_member.id and v_day between p.start_date and p.end_date) then
    raise exception '%', case when v_self then 'Your membership is paused on ' || to_char(v_day, 'FMDD Mon') || '.'
                              else v_member.full_name || '''s membership is paused on ' || to_char(v_day, 'FMDD Mon') || '.' end;
  end if;

  -- One booking at a time per class: the places are counted under the lock.
  perform 1 from public.gym_classes x where x.id = c.id for update;
  if exists (select 1 from public.gym_class_bookings b
             where b.class_id = c.id and b.class_date = v_day and b.gym_member_id = v_member.id and b.status = 'booked') then
    raise exception '%', case when v_self then 'You''re booked in already.' else v_member.full_name || ' is booked in already.' end;
  end if;
  select count(*) into v_taken from public.gym_class_bookings b
  where b.class_id = c.id and b.class_date = v_day and b.status = 'booked';
  if v_taken >= c.capacity then
    raise exception '% on % is full.', c.name, to_char(v_day, 'FMDD Mon');
  end if;

  insert into public.gym_class_bookings (class_id, venue_id, class_date, gym_member_id, booked_by)
  values (c.id, c.venue_id, v_day, v_member.id, (select auth.uid()))
  returning id into v_id;
  return v_id;
end;
$$;

-- A member takes back their own booking before the class starts; the desk
-- any time.
create or replace function public.gym_cancel_class_booking(booking_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  b public.gym_class_bookings;
  c public.gym_classes;
begin
  select * into b from public.gym_class_bookings x where x.id = gym_cancel_class_booking.booking_id;
  if not found or b.status <> 'booked' then
    raise exception 'This booking isn''t there any more.';
  end if;
  select * into c from public.gym_classes x where x.id = b.class_id;
  if not public.has_venue_permission(b.venue_id, 'gym.members') then
    if not public.gym_member_is_me(b.gym_member_id) then
      raise exception 'Only the member and the gym''s staff can cancel this booking.';
    end if;
    if public.gym_class_start(c, b.class_date) <= now() then
      raise exception 'The class has started. Ask the front desk.';
    end if;
  end if;
  update public.gym_class_bookings x set status = 'cancelled', cancelled_by = (select auth.uid()), cancelled_at = now()
  where x.id = b.id;
end;
$$;

-- How many places are booked in each class of [venue_id] on the [days] days
-- from [from_date], and the signed-in member's own bookings: for the
-- timetable's 'places left' and Book / Cancel.
create or replace function public.gym_class_places(venue_id uuid, from_date date, days int default 14)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'class_id', b.class_id,
    'class_date', b.class_date,
    'booked', b.booked,
    'my_booking_id', b.mine
  )), '[]'::jsonb)
  from (
    select x.class_id, x.class_date, count(*) as booked,
           (array_agg(x.id) filter (where public.gym_member_is_me(x.gym_member_id)))[1] as mine
    from public.gym_class_bookings x
    where x.venue_id = gym_class_places.venue_id and x.status = 'booked'
      and x.class_date between gym_class_places.from_date and gym_class_places.from_date + least(greatest(days, 1), 31) - 1
    group by x.class_id, x.class_date
  ) b;
$$;

revoke execute on function public.gym_class_start(public.gym_classes, date) from public, anon, authenticated;
revoke execute on function public.gym_save_class(uuid, uuid, jsonb), public.gym_book_class(uuid, date, uuid),
  public.gym_cancel_class_booking(uuid), public.gym_class_places(uuid, date, int) from public, anon;
grant execute on function public.gym_save_class(uuid, uuid, jsonb), public.gym_book_class(uuid, date, uuid),
  public.gym_cancel_class_booking(uuid), public.gym_class_places(uuid, date, int) to authenticated;
