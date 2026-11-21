-- The Classes screen right ('gym.classes', 20261118000018) now covers the
-- whole page: whoever the owner gives it to (front desk, trainer, manager,
-- the gym's own roles) adds classes, changes them and takes them off the
-- timetable, and sees the classes no longer on it. Until now that was
-- 'gym.plans' (who sets the packages), so only the owner and manager could.
--
-- Safe to re-run.

update public.permissions
   set description = 'See the classes, who''s booked into each and who has registered to date; book members in; '
                     'add and change the classes on the timetable'
 where key = 'gym.classes';

drop policy if exists "gym_classes: who keeps it" on public.gym_classes;
create policy "gym_classes: who keeps it" on public.gym_classes for select to authenticated
  using (public.has_venue_permission(venue_id, 'gym.classes'));

-- As in 20261118000016, for who has 'gym.classes'.
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
  if not public.has_venue_permission(v_venue, 'gym.classes') then
    raise exception 'Only the gym''s staff with Classes can change its timetable.';
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
