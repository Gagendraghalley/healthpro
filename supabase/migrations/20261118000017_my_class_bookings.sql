-- A person's classes (gym_classes, booked in gym_class_bookings) on
-- My dashboard: what they're booked into from today, at every gym, whether
-- on their registration there or on their account (a non-member, or an
-- account member).
-- Safe to re-run.

-- The signed-in person's places from today, soonest first: the booking, the
-- workout (name, trainer, start, length), the gym (id, name).
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
  join public.gym_classes c on c.id = b.class_id
  join public.venues v on v.id = b.venue_id
  where b.status = 'booked' and b.class_date >= public.bhutan_today()
    and (b.user_id = (select auth.uid())
         or b.gym_member_id in (select g.id from public.gym_members g join public.people p on p.id = g.person_id
                                where p.user_id = (select auth.uid())));
$$;

revoke execute on function public.my_class_bookings() from public, anon;
grant execute on function public.my_class_bookings() to authenticated;

-- As in 20261118000014; the gym's side is who has 'gym.classes'
-- (20261118000018).
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
  if not public.has_venue_permission(b.venue_id, 'gym.classes') then
    if not public.gym_class_booking_is_mine(b) then
      raise exception 'Only the member and the gym''s staff can cancel this booking.';
    end if;
    if public.gym_class_start(c, b.class_date) <= now() then
      raise exception '% has started. Ask the front desk.', c.name;
    end if;
  end if;
  update public.gym_class_bookings x set status = 'cancelled', cancelled_by = (select auth.uid()), cancelled_at = now()
  where x.id = b.id;
end;
$$;
