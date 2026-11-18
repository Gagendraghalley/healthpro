-- Pausing a membership (travel, illness, an injury): the desk pauses a
-- member's running package from a day for some days, and every package of
-- theirs still to come moves later by those days, so nothing they paid for
-- is lost. While paused they can't check in. Back early, the desk resumes
-- it, and the days not used come back off the dates.
--
-- One pause at a time per member (running or planned); 1 to 180 days,
-- starting today or later, on a day a package of theirs runs. Members
-- registered at the desk (gym_members) only. Needs 'gym.payments': it
-- changes what a payment covers. A member with an account is told.
--
-- Packages keep their own dates (start_date, end_date), which the pause
-- moves: the expiry rule (same date N months later, renewals from the last
-- expiry) and everything that reads end_date (check-in, reminders, the
-- daily job, the dashboard) carry on as before. Safe to re-run.

create table if not exists public.gym_membership_pauses (
  id            uuid primary key default gen_random_uuid(),
  venue_id      uuid not null references public.venues (id) on delete cascade,
  gym_member_id uuid not null references public.gym_members (id) on delete cascade,
  start_date    date not null, -- Bhutan dates, both paused
  end_date      date not null,
  reason        text check (char_length(reason) <= 200),
  created_by    uuid constraint gym_membership_pauses_created_by_fkey references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  -- Resumed early: end_date became the day before.
  ended_by      uuid constraint gym_membership_pauses_ended_by_fkey references public.profiles (id) on delete set null,
  ended_at      timestamptz,
  constraint gym_membership_pauses_dates check (end_date >= start_date and end_date - start_date < 180)
);
create index if not exists gym_membership_pauses_member on public.gym_membership_pauses (gym_member_id, end_date desc);
create index if not exists gym_membership_pauses_venue on public.gym_membership_pauses (venue_id, end_date desc);

-- Staff who see members see their pauses; only the functions below write.
alter table public.gym_membership_pauses enable row level security;
revoke all on public.gym_membership_pauses from anon, authenticated;
grant select on public.gym_membership_pauses to authenticated;
drop policy if exists "gym_membership_pauses: who sees members" on public.gym_membership_pauses;
create policy "gym_membership_pauses: who sees members" on public.gym_membership_pauses for select to authenticated
  using (public.has_venue_permission(venue_id, 'gym.members'));

-- Pauses [gym_member_id]'s membership for [days] days from [start_on]
-- (today when null).
create or replace function public.gym_pause_member(gym_member_id uuid, start_on date, days int, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_member public.gym_members;
  v_today date := public.bhutan_today();
  v_start date := coalesce(gym_pause_member.start_on, public.bhutan_today());
  v_days int := gym_pause_member.days;
  v_end date;
  v_current public.gym_subscriptions;
  v_open public.gym_membership_pauses;
  v_pause uuid;
  v_until date;
  v_user uuid;
  v_gym text;
begin
  select * into v_member from public.gym_members g where g.id = gym_pause_member.gym_member_id;
  if not found then
    raise exception 'This member is no longer registered.';
  end if;
  if not public.has_venue_permission(v_member.venue_id, 'gym.payments') then
    raise exception 'Your role here can''t pause memberships.';
  end if;
  -- Serialises pauses and renewals of the same member.
  perform 1 from public.gym_members g where g.id = v_member.id for update;
  if v_days is null or v_days not between 1 and 180 then
    raise exception 'Pause for 1 to 180 days.';
  end if;
  if v_start < v_today then
    raise exception 'A pause can''t start before today.';
  end if;
  select * into v_open from public.gym_membership_pauses p
  where p.gym_member_id = v_member.id and p.end_date >= v_today
  order by p.start_date limit 1;
  if v_open.id is not null then
    raise exception '% is paused from % to % already. Resume that pause first.', v_member.full_name,
      to_char(v_open.start_date, 'FMDD Mon YYYY'), to_char(v_open.end_date, 'FMDD Mon YYYY');
  end if;
  -- The package running on the first paused day (the earliest, if two do).
  select * into v_current from public.gym_subscriptions s
  where s.gym_member_id = v_member.id and s.status = 'active' and s.start_date <= v_start and s.end_date >= v_start
  order by s.start_date, s.end_date limit 1;
  if v_current.id is null then
    raise exception '% has no package running on %. Only a running package can be paused.', v_member.full_name,
      to_char(v_start, 'FMDD Mon YYYY');
  end if;
  v_end := v_start + v_days - 1;

  -- It ends [days] later; the ones after it start and end [days] later.
  update public.gym_subscriptions s
     set start_date = case when s.id = v_current.id then s.start_date else s.start_date + v_days end,
         end_date = s.end_date + v_days
   where s.gym_member_id = v_member.id and s.status = 'active' and s.end_date >= v_start;

  insert into public.gym_membership_pauses (venue_id, gym_member_id, start_date, end_date, reason, created_by)
  values (v_member.venue_id, v_member.id, v_start, v_end, nullif(trim(coalesce(gym_pause_member.reason, '')), ''),
          (select auth.uid()))
  returning id into v_pause;

  select max(s.end_date) into v_until from public.gym_subscriptions s
  where s.gym_member_id = v_member.id and s.status = 'active';

  select p.user_id into v_user from public.people p where p.id = v_member.person_id;
  if v_user is not null then
    select v.name into v_gym from public.venues v where v.id = v_member.venue_id;
    perform public.notify(v_user, 'gym_membership', 'Membership paused',
      v_gym || ' paused your membership from ' || to_char(v_start, 'FMDD Mon YYYY') || ' to '
        || to_char(v_end, 'FMDD Mon YYYY') || '. It now runs until ' || to_char(v_until, 'FMDD Mon YYYY') || '.',
      '/gyms/my');
  end if;

  return jsonb_build_object('pause_id', v_pause, 'start_date', v_start, 'end_date', v_end, 'runs_until', v_until);
end;
$$;

-- Back early (or not going after all): the pause ends yesterday, or is
-- taken back if it hasn't begun, and the days not used come off the dates
-- it moved.
create or replace function public.gym_resume_member(pause_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_pause public.gym_membership_pauses;
  v_member public.gym_members;
  v_today date := public.bhutan_today();
  v_from date;
  v_unused int;
  v_until date;
  v_user uuid;
  v_gym text;
begin
  select * into v_pause from public.gym_membership_pauses p where p.id = gym_resume_member.pause_id;
  if not found then
    raise exception 'This pause isn''t there any more.';
  end if;
  if not public.has_venue_permission(v_pause.venue_id, 'gym.payments') then
    raise exception 'Your role here can''t resume memberships.';
  end if;
  select * into v_member from public.gym_members g where g.id = v_pause.gym_member_id;
  perform 1 from public.gym_members g where g.id = v_member.id for update;
  select * into v_pause from public.gym_membership_pauses p where p.id = gym_resume_member.pause_id;
  if v_pause.end_date < v_today then
    raise exception 'This pause is over already.';
  end if;
  v_from := greatest(v_today, v_pause.start_date);
  v_unused := v_pause.end_date - v_from + 1;

  -- Everything the pause moved ends after it.
  update public.gym_subscriptions s
     set start_date = case when s.start_date > v_pause.end_date then s.start_date - v_unused else s.start_date end,
         end_date = s.end_date - v_unused
   where s.gym_member_id = v_member.id and s.status = 'active' and s.end_date > v_pause.end_date;

  if v_from = v_pause.start_date then
    delete from public.gym_membership_pauses p where p.id = v_pause.id;
  else
    update public.gym_membership_pauses p
       set end_date = v_from - 1, ended_by = (select auth.uid()), ended_at = now()
     where p.id = v_pause.id;
  end if;

  select max(s.end_date) into v_until from public.gym_subscriptions s
  where s.gym_member_id = v_member.id and s.status = 'active';

  select p.user_id into v_user from public.people p where p.id = v_member.person_id;
  if v_user is not null then
    select v.name into v_gym from public.venues v where v.id = v_member.venue_id;
    perform public.notify(v_user, 'gym_membership', 'Membership resumed',
      v_gym || ' resumed your membership. It runs until ' || to_char(v_until, 'FMDD Mon YYYY') || '.', '/gyms/my');
  end if;

  return jsonb_build_object('runs_until', v_until, 'days_returned', v_unused);
end;
$$;

revoke execute on function public.gym_pause_member(uuid, date, int, text), public.gym_resume_member(uuid)
  from public, anon;
grant execute on function public.gym_pause_member(uuid, date, int, text), public.gym_resume_member(uuid)
  to authenticated;

-- The desk can't check in a paused member. As in 20261108000004, with the
-- pause first.
create or replace function public.gym_check_in_registered(venue uuid, gym_member uuid)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_today date := public.bhutan_today();
  v_member public.gym_members;
  v_sub public.gym_subscriptions;
  v_other public.gym_subscriptions;
  v_pause public.gym_membership_pauses;
  v_earlier int;
begin
  select * into v_member from public.gym_members m where m.id = gym_member and m.venue_id = venue;
  if not found then
    raise exception 'That member isn''t registered at this gym.';
  end if;
  select * into v_pause from public.gym_membership_pauses p
  where p.gym_member_id = v_member.id and v_today between p.start_date and p.end_date
  limit 1;
  if v_pause.id is not null then
    raise exception '%''s membership is paused until %. Resume it on their page to let them in.', v_member.full_name,
      to_char(v_pause.end_date, 'FMDD Mon YYYY');
  end if;
  select * into v_sub from public.gym_subscriptions s
  where s.gym_member_id = v_member.id and s.status = 'active' and s.start_date <= v_today and s.end_date >= v_today
  order by s.end_date desc
  limit 1;
  if v_sub.id is null then
    select * into v_other from public.gym_subscriptions s
    where s.gym_member_id = v_member.id and s.status in ('active', 'expired')
    order by case when s.status = 'active' then 0 else 1 end, s.end_date desc
    limit 1;
    if v_other.id is null then
      raise exception '% has no package yet. Sell them one on their page.', v_member.full_name;
    elsif v_other.status = 'active' then
      raise exception '%''s package starts on %.', v_member.full_name, to_char(v_other.start_date, 'FMDD Mon YYYY');
    else
      raise exception '%''s package ended on %. Renew it on their page.', v_member.full_name,
        to_char(v_other.end_date, 'FMDD Mon YYYY');
    end if;
  end if;

  select count(*) into v_earlier from public.gym_check_ins c
  where c.gym_member_id = v_member.id and (c.checked_in_at at time zone 'Asia/Thimphu')::date = v_today;
  insert into public.gym_check_ins (venue_id, gym_member_id, subscription_id, recorded_by)
  values (venue, v_member.id, v_sub.id, (select auth.uid()));

  return jsonb_build_object(
    'member_name', v_member.full_name,
    'member_code', v_member.code,
    'gym_member_id', v_member.id,
    'photo_path', v_member.photo_path,
    'medical_notes', v_member.medical_notes,
    'plan_name', v_sub.plan_name,
    'end_date', v_sub.end_date,
    'days_left', v_sub.end_date - v_today + 1,
    'earlier_today', v_earlier
  );
end;
$$;
