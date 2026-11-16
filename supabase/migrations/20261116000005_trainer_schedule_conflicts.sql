-- Keep a trainer's weekly schedule conflict-free even when two gyms save at
-- nearly the same time. The advisory lock serializes edits for this trainer.
create or replace function public.trainer_set_slots(
  p_trainer uuid,
  p_venue uuid,
  slots jsonb,
  own boolean
)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  s jsonb;
  v_days int[] := '{}';
  v_from time[] := '{}';
  v_to time[] := '{}';
  v_day int;
  v_start time;
  v_end time;
  v_clash record;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('trainer-slots:' || p_trainer::text, 0)
  );

  if jsonb_typeof(coalesce(slots, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(slots, '[]'::jsonb)) > 50 then
    raise exception 'Up to 50 times a week.';
  end if;

  for s in select * from jsonb_array_elements(coalesce(slots, '[]'::jsonb)) loop
    begin
      v_day := (s ->> 'weekday')::int;
      v_start := (s ->> 'starts')::time;
      v_end := (s ->> 'ends')::time;
    exception when others then
      raise exception 'Enter each time as a day and HH:MM to HH:MM.';
    end;
    if v_day is null or v_day not between 1 and 7 or v_start is null or v_end is null then
      raise exception 'Enter each time as a day and HH:MM to HH:MM.';
    end if;
    if v_end <= v_start then
      raise exception 'Each time must end after it starts.';
    end if;
    v_days := v_days || v_day;
    v_from := v_from || v_start;
    v_to := v_to || v_end;
  end loop;

  if exists (
    select 1
    from unnest(v_days, v_from, v_to) with ordinality a(d, f, t, i)
    join unnest(v_days, v_from, v_to) with ordinality b(d, f, t, i)
      on a.i < b.i and a.d = b.d and a.f < b.t and b.f < a.t
  ) then
    raise exception 'Two of the times here overlap.';
  end if;

  select n.d, n.f, n.t into v_clash
  from unnest(v_days, v_from, v_to) n(d, f, t)
  where exists (
    select 1
    from public.trainer_slots o
    where o.user_id = p_trainer
      and o.venue_id <> p_venue
      and o.weekday = n.d
      and o.starts_at < n.t
      and n.f < o.ends_at
  )
  limit 1;

  if found then
    raise exception '%',
      case when own then 'That overlaps your time at another gym'
           else 'They''re not available at that time' end
      || ' ('
      || (array['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])[v_clash.d]
      || ' ' || to_char(v_clash.f, 'HH12:MI AM')
      || '–' || to_char(v_clash.t, 'HH12:MI AM') || ').';
  end if;

  delete from public.trainer_slots t
  where t.venue_id = p_venue and t.user_id = p_trainer;

  insert into public.trainer_slots (user_id, venue_id, weekday, starts_at, ends_at)
  select p_trainer, p_venue, n.d, n.f, n.t
  from unnest(v_days, v_from, v_to) n(d, f, t);
end;
$$;
