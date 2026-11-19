-- Every change to a class reaches whoever has a place in it to come, by
-- email (20261119000001) and in the app (the bell, and a push to their
-- phone). 20261119000001 emailed its time, length, trainer or name; now
-- also its description, its places, and who may book it (open to everyone
-- or members only). One email and one notification a person, for all their
-- places in it.
--
-- Taken off the timetable or moved to another day, its places to come are
-- cancelled: gym_save_class tells the app, 20261119000001 emails. The desk
-- cancelling one place is now told in the app too, not only by email.
--
-- Safe to re-run.

-- As in 20261119000001, with the class's description, places and who may book it.
create or replace function private.class_email_details(c public.gym_classes, day date)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'class', c.name, 'date', day, 'weekday', c.weekday, 'starts_at', to_char(c.starts_at, 'HH24:MI'),
    'minutes', c.duration_minutes, 'trainer', c.trainer_name,
    'description', c.description, 'capacity', c.capacity, 'open_to_all', c.open_to_all,
    'venue_id', v.id, 'gym', v.name,
    'address', nullif(concat_ws(', ', nullif(trim(v.address), ''), nullif(trim(v.town), ''),
                                case when v.dzongkhag is distinct from nullif(trim(v.town), '') then v.dzongkhag end), ''),
    'phone', v.phone, 'latitude', v.latitude, 'longitude', v.longitude)
  from public.venues v
  where v.id = c.venue_id
$$;

-- '9:00 AM to 9:45 AM'.
create or replace function private.class_time_span(c public.gym_classes)
returns text
language sql
immutable
set search_path = ''
as $$
  select to_char(date '2000-01-01' + c.starts_at, 'FMHH12:MI AM') || ' to '
         || to_char(date '2000-01-01' + c.starts_at + make_interval(mins => c.duration_minutes), 'FMHH12:MI AM')
$$;

-- What changed from class [o] to [n], as the app says it:
-- 'Now 10:00 AM to 10:45 AM (was 9:00 AM to 9:45 AM). Trainer: Kinley (was Tashi).'
create or replace function private.class_change_summary(o public.gym_classes, n public.gym_classes)
returns text
language sql
immutable
set search_path = ''
as $$
  select concat_ws(' ',
    case when n.name is distinct from o.name then 'Now called ' || n.name || '.' end,
    case when (n.starts_at, n.duration_minutes) is distinct from (o.starts_at, o.duration_minutes)
         then 'Now ' || private.class_time_span(n) || ' (was ' || private.class_time_span(o) || ').' end,
    case when n.trainer_name is distinct from o.trainer_name then
      case when n.trainer_name is null then 'No trainer named now (was ' || o.trainer_name || ').'
           when o.trainer_name is null then 'Trainer: ' || n.trainer_name || '.'
           else 'Trainer: ' || n.trainer_name || ' (was ' || o.trainer_name || ').' end end,
    case when n.capacity <> o.capacity then 'Places: ' || n.capacity || ' (was ' || o.capacity || ').' end,
    case when n.open_to_all and not o.open_to_all then 'Now open to everyone on Health Pro.'
         when o.open_to_all and not n.open_to_all then 'Now for the gym''s members only.' end,
    case when n.description is distinct from o.description then 'New description.' end)
$$;


-- ---------------------------------------------------------------------
-- 1. The class changed: anything but its day, or taken off
-- ---------------------------------------------------------------------

drop trigger if exists gym_class_change_emails on public.gym_classes;
drop function if exists private.gym_class_change_emails();

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
            and public.gym_class_start(old, b.class_date) > now()) x
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
            and public.gym_class_start(old, b.class_date) > now()) x
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
drop trigger if exists gym_class_change_notices on public.gym_classes;
create trigger gym_class_change_notices after update on public.gym_classes
  for each row execute function private.gym_class_change_notices();


-- ---------------------------------------------------------------------
-- 2. Booked, or cancelled by the gym
-- ---------------------------------------------------------------------

-- As in 20261119000001; the desk cancelling one place is told in the app as
-- well (gym_save_class tells it when the class moves or comes off).
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
  select * into c from public.gym_classes x where x.id = new.class_id;
  if v_kind = 'class_cancelled' then
    v_reason := case when not c.is_active then 'off'
                     when c.weekday <> extract(isodow from new.class_date) then 'moved'
                     else 'gym' end;
  end if;
  if v_reason = 'gym' then
    perform public.notify(r.user_id, 'gym_membership',
      c.name || ' on ' || to_char(new.class_date, 'FMDy FMDD Mon') || ' was cancelled',
      case when new.user_id is null then 'The gym cancelled your place. See its classes on My gym to book another.'
           else 'The gym cancelled your place. See its classes on its page to book another.' end,
      case when new.user_id is null then '/gyms/my?gym=' || new.venue_id else '/gyms/' || new.venue_id end);
  end if;
  if r.email is null or not private.emails_on() then
    return null;
  end if;
  insert into private.email_outbox (to_email, kind, data)
  values (r.email, v_kind, private.class_email_details(c, new.class_date) || jsonb_build_object('name', r.full_name, 'reason', v_reason));
  return null;
end;
$$;
