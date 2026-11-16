-- Scanned and staff-recorded trainer arrivals share this function. Serialize
-- by gym and trainer, then record at most one arrival per Bhutan calendar day.
create or replace function public.gym_trainer_arrived(venue uuid, trainer uuid, token text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_today date := public.bhutan_today();
  v_earlier int;
  v_marked_at timestamptz;
  v_member boolean;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('trainer-attendance:' || venue::text || ':' || trainer::text, 0)
  );

  select count(*), min(c.checked_in_at)
    into v_earlier, v_marked_at
  from public.trainer_check_ins c
  where c.venue_id = venue
    and c.user_id = trainer
    and (c.checked_in_at at time zone 'Asia/Thimphu')::date = v_today;

  if v_earlier = 0 then
    insert into public.trainer_check_ins (venue_id, user_id, recorded_by)
    values (venue, trainer, (select auth.uid()))
    returning checked_in_at into v_marked_at;
  end if;

  select exists (
    select 1
    from public.gym_members g
    join public.people p on p.id = g.person_id
    where g.venue_id = venue and p.user_id = trainer
  ) into v_member;

  return jsonb_build_object(
    'trainer', true,
    'member_name', public.trainer_name(trainer),
    'trainer_id', trainer,
    'photo_url', (select t.photo_url from public.trainer_profiles t where t.user_id = trainer),
    'earlier_today', v_earlier,
    'already_marked', v_earlier > 0,
    'marked_at', v_marked_at,
    'slots_today', coalesce((
      select jsonb_agg(jsonb_build_array(to_char(s.starts_at, 'HH24:MI'), to_char(s.ends_at, 'HH24:MI')) order by s.starts_at)
      from public.trainer_slots s
      where s.venue_id = venue and s.user_id = trainer
        and s.weekday = extract(isodow from v_today)::int
    ), '[]'::jsonb),
    'also_member', v_member,
    'person_token', token
  );
end;
$$;
