-- Coaching nudges, and AI drafts of plans.
--
-- Nudges (gym_coaching_nudges(), daily with pg_cron): a member with the app
-- and a package today, last measured 30 days ago or more, is reminded to log
-- their weight (at most once in 30 days). A member's trainer is told when
-- their weight hasn't moved toward their goal for 3 weeks (at most once in
-- 21 days). Both arrive as notifications, so as push too. The app shows the
-- same suggestions on the member's progress.
--
-- AI drafts (ai_plan_drafts): a member's trainer, or the gym's staff who see
-- members, asks the draft-plan Edge Function to draft a workout or diet plan
-- from the member's numbers (never their name, phone or medical notes). It's
-- counted here first, 10 a Bhutan day each; the table keeps who, at which
-- gym and when (not what), for 90 days. The draft is only filled into the
-- plan form: the coach checks it and gives it, or not.
--
-- Safe to re-run.

-- ---------------------------------------------------------------------
-- Nudges
-- ---------------------------------------------------------------------

create table if not exists public.gym_coaching_nudges (
  gym_member_id uuid not null references public.gym_members (id) on delete cascade,
  kind          text not null check (kind in ('measure', 'plateau')),
  sent_on       date not null, -- Bhutan date, the last one sent
  primary key (gym_member_id, kind)
);

-- Only gym_coaching_nudges() reads or writes it.
alter table public.gym_coaching_nudges enable row level security;
revoke all on public.gym_coaching_nudges from anon, authenticated;

-- Sends today's nudges; how many.
create or replace function public.gym_coaching_nudges()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := public.bhutan_today();
  v_sent int := 0;
  r record;
begin
  -- Time for a new measurement.
  for r in
    select g.id, g.venue_id, p.user_id, v_today - last.measured_on as days
      from public.gym_members g
      join public.people p on p.id = g.person_id and p.user_id is not null
      join lateral (select max(m.measured_on) as measured_on from public.gym_body_measurements m
                     where m.gym_member_id = g.id) last on last.measured_on is not null
     where last.measured_on <= v_today - 30
       and exists (select 1 from public.gym_subscriptions s
                    where s.gym_member_id = g.id and s.status = 'active' and s.start_date <= v_today and s.end_date >= v_today)
       and not exists (select 1 from public.gym_coaching_nudges n
                        where n.gym_member_id = g.id and n.kind = 'measure' and n.sent_on > v_today - 30)
  loop
    perform public.notify(r.user_id, 'gym_membership', 'Time for a new measurement',
      'Your last one was ' || r.days || ' days ago. Log your weight on My gym, or ask your trainer or the desk.',
      '/gyms/my?gym=' || r.venue_id);
    insert into public.gym_coaching_nudges as n (gym_member_id, kind, sent_on) values (r.id, 'measure', v_today)
      on conflict (gym_member_id, kind) do update set sent_on = excluded.sent_on;
    v_sent := v_sent + 1;
  end loop;

  -- Weight that hasn't moved toward the goal for 3 weeks: the latest weighing
  -- (in the last 14 days) against one 21 to 35 days before it.
  for r in
    select g.id, g.full_name, l.trainer_id, goal.goal
      from public.gym_member_goals goal
      join public.gym_members g on g.id = goal.gym_member_id
      join public.trainer_links l on l.gym_member_id = g.id and l.ended_at is null
      join lateral (select m.measured_on, m.weight_kg from public.gym_body_measurements m
                     where m.gym_member_id = g.id and m.weight_kg is not null
                     order by m.measured_on desc, m.created_at desc limit 1) w_now on true
      join lateral (select m.weight_kg from public.gym_body_measurements m
                     where m.gym_member_id = g.id and m.weight_kg is not null
                       and m.measured_on between w_now.measured_on - 35 and w_now.measured_on - 21
                     order by m.measured_on desc, m.created_at desc limit 1) w_then on true
     where goal.goal in ('lose_fat', 'build_muscle', 'gain_weight')
       and w_now.measured_on >= v_today - 14
       and case when goal.goal = 'lose_fat'
                then w_now.weight_kg - w_then.weight_kg > -0.3 and w_now.weight_kg > coalesce(goal.target_weight_kg, 0)
                else w_now.weight_kg - w_then.weight_kg < 0.3 and w_now.weight_kg < coalesce(goal.target_weight_kg, 1000) end
       and not exists (select 1 from public.gym_coaching_nudges n
                        where n.gym_member_id = g.id and n.kind = 'plateau' and n.sent_on > v_today - 21)
  loop
    perform public.notify(r.trainer_id, 'gym_membership', r.full_name || '''s weight hasn''t moved in 3 weeks',
      'Their goal is to ' || replace(r.goal, '_', ' ') || '. Have a look at their diet plan.',
      '/gyms/trainer/members/' || r.id);
    insert into public.gym_coaching_nudges as n (gym_member_id, kind, sent_on) values (r.id, 'plateau', v_today)
      on conflict (gym_member_id, kind) do update set sent_on = excluded.sent_on;
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end;
$$;

revoke execute on function public.gym_coaching_nudges() from public, anon, authenticated;

-- Daily at 08:15 Bhutan time (02:15 UTC) with pg_cron, as the daily gym jobs.
-- Without it, run "select public.gym_coaching_nudges()" once a day.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
    perform cron.schedule('gym-coaching-nudges', '15 2 * * *', 'select public.gym_coaching_nudges()');
  else
    raise notice 'pg_cron is not available: run "select public.gym_coaching_nudges()" once a day.';
  end if;
exception when others then
  raise warning 'The coaching nudges job was not scheduled (%). See the README, "Daily job".', sqlerrm;
end;
$$;


-- ---------------------------------------------------------------------
-- AI drafts of plans
-- ---------------------------------------------------------------------

create table if not exists public.ai_plan_drafts (
  id       bigint generated always as identity primary key,
  user_id  uuid not null references auth.users (id) on delete cascade,
  venue_id uuid not null references public.venues (id) on delete cascade,
  asked_at timestamptz not null default now()
);
create index if not exists ai_plan_drafts_user_asked on public.ai_plan_drafts (user_id, asked_at);

-- Only ai_take_plan_draft reads or writes it.
alter table public.ai_plan_drafts enable row level security;
revoke all on public.ai_plan_drafts from anon, authenticated;

-- Counts a draft the caller asks for [gym_member_id]: their trainer or the
-- gym's staff who see members, up to 10 a Bhutan day. How many are left
-- today after this one.
create or replace function public.ai_take_plan_draft(gym_member_id uuid)
returns int
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_daily constant int := 10;
  v_day_start timestamptz := public.bhutan_today()::timestamp at time zone 'Asia/Thimphu';
  v_me uuid := (select auth.uid());
  v_venue uuid;
  v_used int;
begin
  if v_me is null then
    raise exception 'Please sign in again.';
  end if;
  select g.venue_id into v_venue from public.gym_members g where g.id = ai_take_plan_draft.gym_member_id;
  if v_venue is null then
    raise exception 'This member is no longer registered.';
  end if;
  if not public.gym_member_can_coach(ai_take_plan_draft.gym_member_id) then
    raise exception 'Only the member''s trainer and the gym''s staff can draft their plans.';
  end if;

  select count(*) into v_used from public.ai_plan_drafts d where d.user_id = v_me and d.asked_at >= v_day_start;
  if v_used >= v_daily then
    raise exception 'You''ve drafted % plans with AI today. Draft more tomorrow, or write this one yourself.', v_daily;
  end if;

  insert into public.ai_plan_drafts (user_id, venue_id) values (v_me, v_venue);
  delete from public.ai_plan_drafts d where d.user_id = v_me and d.asked_at < now() - interval '90 days';
  return v_daily - v_used - 1;
end;
$$;

revoke execute on function public.ai_take_plan_draft(uuid) from public, anon, authenticated;
grant execute on function public.ai_take_plan_draft(uuid) to authenticated;
