-- Classes open to everyone on Health Pro. A class (gym_classes.open_to_all,
-- on unless the gym turns it off) can be booked by anyone signed in to
-- Health Pro, member of the gym or not, and by its members whatever their
-- package; the gym's page shows its classes to the public, with places left.
-- A class turned off is for members only, as before (20261118000014): a
-- package that covers the day, not paused.
--
-- Someone who isn't registered at the gym books on their account
-- (gym_class_bookings.user_id), as an account member does. The desk's list
-- of who's booked (gym_class_bookings_on, for 'gym.classes': 20261118000018) says who is registered at the gym
-- and who isn't, with their member code, phone and email, and whether the
-- desk booked them or they booked themselves.
--
-- Safe to re-run.

alter table public.gym_classes add column if not exists open_to_all boolean not null default true;

-- As in 20261118000014, with who may book; telling a guest whose class
-- goes to look at the gym's page.
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
  v_open boolean;
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
  v_open := coalesce((d ->> 'open_to_all')::boolean, v_old.open_to_all, true);
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
                                    is_active, open_to_all)
    values (v_venue, v_name, v_description, v_trainer, v_weekday, v_starts, v_minutes, v_capacity, v_active, v_open)
    returning id into v_id;
    return v_id;
  end if;

  update public.gym_classes c
     set name = v_name, description = v_description, trainer_name = v_trainer, weekday = v_weekday, starts_at = v_starts,
         duration_minutes = v_minutes, capacity = v_capacity, is_active = v_active, open_to_all = v_open
   where c.id = v_old.id;

  -- Off the timetable, or on another day: its bookings to come are cancelled.
  -- (Made members only, the places booked already stay.)
  if v_old.is_active and (not v_active or v_weekday <> v_old.weekday) then
    for r in
      update public.gym_class_bookings b
         set status = 'cancelled', cancelled_by = (select auth.uid()), cancelled_at = now()
       where b.class_id = v_old.id and b.status = 'booked' and b.class_date >= public.bhutan_today()
      returning b.gym_member_id, b.user_id, b.class_date
    loop
      perform public.notify(coalesce(r.user_id, (select p.user_id from public.gym_members g join public.people p on p.id = g.person_id
                                                  where g.id = r.gym_member_id)),
        'gym_membership', v_old.name || ' on ' || to_char(r.class_date, 'FMDy FMDD Mon') || ' was cancelled',
        case when r.user_id is null then 'The gym changed its timetable. See its classes on My gym to book another.'
             else 'The gym changed its timetable. See its classes on its page to book another.' end,
        case when r.user_id is null then '/gyms/my?gym=' || v_venue else '/gyms/' || v_venue end);
    end loop;
  end if;
  return v_old.id;
end;
$$;

-- As in 20261118000014. An open class: anyone signed in books themselves
-- (on their registration here if they have one, else on their account), and
-- the desk books any member, with no package needed. A members-only class:
-- as before.
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

-- Who's booked into the gym's classes on a day, for the desk: each one's
-- name, whether they're registered at the gym (a member) or not (a guest on
-- Health Pro), member code, phone, email, and who booked.
create or replace function public.gym_class_bookings_on(venue_id uuid, class_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not public.has_venue_permission(gym_class_bookings_on.venue_id, 'gym.classes') then
    raise exception 'Only the gym''s staff can see who''s booked.';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', b.id,
      'class_id', b.class_id,
      'class_date', b.class_date,
      'gym_member_id', coalesce(g.id, reg.id),
      'user_id', b.user_id,
      'full_name', coalesce(g.full_name, reg.full_name, nullif(trim(pr.full_name), ''), pr.email, 'Member'),
      'member_code', coalesce(g.code, reg.code),
      'phone', coalesce(g.phone, reg.phone, pr.phone),
      'email', coalesce(g.email, reg.email, pr.email),
      'is_member', g.id is not null or reg.id is not null
                   or exists (select 1 from public.gym_subscriptions s
                              where s.member_id = b.user_id and s.venue_id = b.venue_id and s.status in ('active', 'expired')),
      'booked_by_desk', b.booked_by is distinct from coalesce(b.user_id, gp.user_id),
      'booked_at', b.booked_at
    ) order by b.booked_at), '[]'::jsonb)
    from public.gym_class_bookings b
    left join public.gym_members g on g.id = b.gym_member_id
    left join public.people gp on gp.id = g.person_id
    left join public.profiles pr on pr.id = b.user_id
    -- A guest the desk has registered since.
    left join lateral (select m.id, m.full_name, m.code, m.phone, m.email
                       from public.gym_members m join public.people p on p.id = m.person_id
                       where b.user_id is not null and p.user_id = b.user_id and m.venue_id = b.venue_id
                       limit 1) reg on true
    where b.venue_id = gym_class_bookings_on.venue_id and b.class_date = gym_class_bookings_on.class_date
      and b.status = 'booked'
  );
end;
$$;

revoke execute on function public.gym_class_bookings_on(uuid, date) from public, anon;
grant execute on function public.gym_class_bookings_on(uuid, date) to authenticated;

-- Places left, on the gym's public page too (nobody's booking is anyone's
-- but their own).
grant execute on function public.gym_class_places(uuid, date, int) to anon;
