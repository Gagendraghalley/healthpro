-- A member booking a class tells the gym: everyone whose role there has
-- Classes ('gym.classes': the owner, and the managers and front desk it's
-- given to) is notified in the app (and by push, where they turned it on),
-- with who booked, the class, the day and time, and a link to Classes.
-- Booked at the desk for a member: nothing, the desk did it.
--
-- (Asking to join a gym already tells them: gym_request_to_join.)
--
-- Safe to re-run.

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
revoke execute on function private.gym_class_booking_tells_desk() from public, anon, authenticated;

drop trigger if exists gym_class_booking_tells_desk on public.gym_class_bookings;
create trigger gym_class_booking_tells_desk after insert on public.gym_class_bookings
  for each row execute function private.gym_class_booking_tells_desk();
