-- Body progress, and workout and diet plans.
--
-- Progress (gym_body_measurements): weight, height, body fat and tape
-- measurements (chest, waist, hips, arm, thigh), on a day. BMI is worked out
-- by the app from weight and the latest height. The gym's staff who see
-- members, the member's trainer (trainer_links) and the member themselves
-- (their account) record them. A member changes or removes only their own.
--
-- Plans (gym_member_plans): a workout or diet plan written for one member,
-- a title and the plan itself in words (days, exercises, sets, meals), by
-- their trainer or the gym's staff who see members. The member reads them on
-- My gym and is told when one is given or changed. Old ones are kept,
-- marked no longer active.
--
-- A trainer sees their own members (trainer_my_members()). Safe to re-run.

-- The signed-in person is [gym_member]: the desk registered them and their
-- account is linked.
create or replace function public.gym_member_is_me(gym_member uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.gym_members g join public.people p on p.id = g.person_id
                 where g.id = gym_member and p.user_id = (select auth.uid()));
$$;

-- The signed-in trainer trains [gym_member] now.
create or replace function public.gym_member_is_my_trainee(gym_member uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.trainer_links l
                 where l.gym_member_id = gym_member and l.trainer_id = (select auth.uid()) and l.ended_at is null);
$$;

-- Coaches [gym_member]: the gym's staff who see members, or their trainer.
create or replace function public.gym_member_can_coach(gym_member uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.gym_member_is_my_trainee(gym_member)
      or coalesce((select public.has_venue_permission(g.venue_id, 'gym.members') from public.gym_members g where g.id = gym_member),
                  false);
$$;

revoke execute on function public.gym_member_is_me(uuid), public.gym_member_is_my_trainee(uuid),
  public.gym_member_can_coach(uuid) from public, anon;
grant execute on function public.gym_member_is_me(uuid), public.gym_member_is_my_trainee(uuid),
  public.gym_member_can_coach(uuid) to authenticated;


-- ---------------------------------------------------------------------
-- Progress
-- ---------------------------------------------------------------------

create table if not exists public.gym_body_measurements (
  id               uuid primary key default gen_random_uuid(),
  venue_id         uuid not null references public.venues (id) on delete cascade,
  gym_member_id    uuid not null references public.gym_members (id) on delete cascade,
  measured_on      date not null, -- Bhutan date
  weight_kg        numeric(5, 1) check (weight_kg between 10 and 400),
  height_cm        numeric(4, 1) check (height_cm between 50 and 260),
  body_fat_pct     numeric(4, 1) check (body_fat_pct between 2 and 75),
  chest_cm         numeric(4, 1) check (chest_cm between 30 and 250),
  waist_cm         numeric(4, 1) check (waist_cm between 30 and 250),
  hips_cm          numeric(4, 1) check (hips_cm between 30 and 250),
  arm_cm           numeric(4, 1) check (arm_cm between 10 and 100),
  thigh_cm         numeric(4, 1) check (thigh_cm between 20 and 150),
  note             text check (char_length(note) <= 300),
  recorded_by      uuid constraint gym_body_measurements_recorded_by_fkey references public.profiles (id) on delete set null,
  recorded_by_name text, -- as they were called then
  created_at       timestamptz not null default now(),
  constraint gym_body_measurements_something check (
    coalesce(weight_kg, height_cm, body_fat_pct, chest_cm, waist_cm, hips_cm, arm_cm, thigh_cm) is not null)
);
create index if not exists gym_body_measurements_member on public.gym_body_measurements (gym_member_id, measured_on desc);

alter table public.gym_body_measurements enable row level security;
revoke all on public.gym_body_measurements from anon, authenticated;
grant select on public.gym_body_measurements to authenticated;
drop policy if exists "gym_body_measurements: staff, trainer and the member" on public.gym_body_measurements;
create policy "gym_body_measurements: staff, trainer and the member" on public.gym_body_measurements for select to authenticated
  using (public.has_venue_permission(venue_id, 'gym.members') or public.gym_member_is_me(gym_member_id)
         or public.gym_member_is_my_trainee(gym_member_id));

-- [details]: measured_on, weight_kg, height_cm, body_fat_pct, chest_cm,
-- waist_cm, hips_cm, arm_cm, thigh_cm, note. A new one ([measurement_id]
-- null) or changes to one. Its id.
create or replace function public.gym_save_measurement(gym_member_id uuid, measurement_id uuid, details jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  d jsonb := coalesce(gym_save_measurement.details, '{}');
  v_member public.gym_members;
  v_old public.gym_body_measurements;
  v_me uuid := (select auth.uid());
  v_coach boolean;
  v_on date := coalesce(nullif(d ->> 'measured_on', '')::date, public.bhutan_today());
  m public.gym_body_measurements;
  v_id uuid;
begin
  select * into v_member from public.gym_members g where g.id = gym_save_measurement.gym_member_id;
  if not found then
    raise exception 'This member is no longer registered.';
  end if;
  v_coach := public.gym_member_can_coach(v_member.id);
  if not v_coach and not public.gym_member_is_me(v_member.id) then
    raise exception 'Only the member, their trainer and the gym''s staff can record their progress.';
  end if;
  if gym_save_measurement.measurement_id is not null then
    select * into v_old from public.gym_body_measurements x where x.id = gym_save_measurement.measurement_id;
    if not found or v_old.gym_member_id <> v_member.id then
      raise exception 'This measurement isn''t there any more.';
    end if;
    if not v_coach and v_old.recorded_by is distinct from v_me then
      raise exception 'Only your trainer or the gym can change what they recorded.';
    end if;
  end if;
  if v_on > public.bhutan_today() or v_on < v_member.joined_on - 365 then
    raise exception 'Choose the day it was measured (today or before).';
  end if;

  m.weight_kg := nullif(d ->> 'weight_kg', '')::numeric;
  m.height_cm := nullif(d ->> 'height_cm', '')::numeric;
  m.body_fat_pct := nullif(d ->> 'body_fat_pct', '')::numeric;
  m.chest_cm := nullif(d ->> 'chest_cm', '')::numeric;
  m.waist_cm := nullif(d ->> 'waist_cm', '')::numeric;
  m.hips_cm := nullif(d ->> 'hips_cm', '')::numeric;
  m.arm_cm := nullif(d ->> 'arm_cm', '')::numeric;
  m.thigh_cm := nullif(d ->> 'thigh_cm', '')::numeric;
  m.note := nullif(trim(coalesce(d ->> 'note', '')), '');
  if coalesce(m.weight_kg, m.height_cm, m.body_fat_pct, m.chest_cm, m.waist_cm, m.hips_cm, m.arm_cm, m.thigh_cm) is null then
    raise exception 'Enter at least one measurement.';
  end if;
  if m.weight_kg not between 10 and 400 then raise exception 'Weight is 10 to 400 kg.'; end if;
  if m.height_cm not between 50 and 260 then raise exception 'Height is 50 to 260 cm.'; end if;
  if m.body_fat_pct not between 2 and 75 then raise exception 'Body fat is 2 to 75%%.'; end if;
  if m.chest_cm not between 30 and 250 or m.waist_cm not between 30 and 250 or m.hips_cm not between 30 and 250 then
    raise exception 'Chest, waist and hips are 30 to 250 cm.';
  end if;
  if m.arm_cm not between 10 and 100 or m.thigh_cm not between 20 and 150 then
    raise exception 'Arm is 10 to 100 cm, and thigh 20 to 150 cm.';
  end if;
  if char_length(m.note) > 300 then
    raise exception 'Keep the note under 300 characters.';
  end if;

  if gym_save_measurement.measurement_id is null then
    insert into public.gym_body_measurements (venue_id, gym_member_id, measured_on, weight_kg, height_cm, body_fat_pct, chest_cm,
                                              waist_cm, hips_cm, arm_cm, thigh_cm, note, recorded_by, recorded_by_name)
    values (v_member.venue_id, v_member.id, v_on, round(m.weight_kg, 1), round(m.height_cm, 1), round(m.body_fat_pct, 1),
            round(m.chest_cm, 1), round(m.waist_cm, 1), round(m.hips_cm, 1), round(m.arm_cm, 1), round(m.thigh_cm, 1), m.note, v_me,
            (select nullif(trim(p.full_name), '') from public.profiles p where p.id = v_me))
    returning id into v_id;
    return v_id;
  end if;
  update public.gym_body_measurements x
     set measured_on = v_on, weight_kg = round(m.weight_kg, 1), height_cm = round(m.height_cm, 1),
         body_fat_pct = round(m.body_fat_pct, 1), chest_cm = round(m.chest_cm, 1), waist_cm = round(m.waist_cm, 1),
         hips_cm = round(m.hips_cm, 1), arm_cm = round(m.arm_cm, 1), thigh_cm = round(m.thigh_cm, 1), note = m.note
   where x.id = v_old.id;
  return v_old.id;
end;
$$;

create or replace function public.gym_delete_measurement(measurement_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.gym_body_measurements;
begin
  select * into v_old from public.gym_body_measurements x where x.id = gym_delete_measurement.measurement_id;
  if not found then
    raise exception 'This measurement isn''t there any more.';
  end if;
  if not public.gym_member_can_coach(v_old.gym_member_id)
     and not (public.gym_member_is_me(v_old.gym_member_id) and v_old.recorded_by = (select auth.uid())) then
    raise exception 'Only your trainer or the gym can remove what they recorded.';
  end if;
  delete from public.gym_body_measurements x where x.id = v_old.id;
end;
$$;

revoke execute on function public.gym_save_measurement(uuid, uuid, jsonb), public.gym_delete_measurement(uuid) from public, anon;
grant execute on function public.gym_save_measurement(uuid, uuid, jsonb), public.gym_delete_measurement(uuid) to authenticated;


-- ---------------------------------------------------------------------
-- Workout and diet plans
-- ---------------------------------------------------------------------

create table if not exists public.gym_member_plans (
  id            uuid primary key default gen_random_uuid(),
  venue_id      uuid not null references public.venues (id) on delete cascade,
  gym_member_id uuid not null references public.gym_members (id) on delete cascade,
  kind          text not null check (kind in ('workout', 'diet')),
  title         text not null check (char_length(trim(title)) between 2 and 100),
  content       text not null check (char_length(content) between 1 and 8000),
  is_active     boolean not null default true,
  author_id     uuid constraint gym_member_plans_author_id_fkey references public.profiles (id) on delete set null,
  author_name   text, -- as they were called then
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists gym_member_plans_member on public.gym_member_plans (gym_member_id, is_active, updated_at desc);

drop trigger if exists gym_member_plans_updated_at on public.gym_member_plans;
create trigger gym_member_plans_updated_at before update on public.gym_member_plans
  for each row execute function public.set_updated_at();

alter table public.gym_member_plans enable row level security;
revoke all on public.gym_member_plans from anon, authenticated;
grant select on public.gym_member_plans to authenticated;
drop policy if exists "gym_member_plans: staff, trainer and the member" on public.gym_member_plans;
create policy "gym_member_plans: staff, trainer and the member" on public.gym_member_plans for select to authenticated
  using (public.has_venue_permission(venue_id, 'gym.members') or public.gym_member_is_me(gym_member_id)
         or public.gym_member_is_my_trainee(gym_member_id));

-- [details]: kind ('workout' or 'diet'), title, content, is_active. A new
-- plan for [gym_member_id] ([plan_id] null) or changes to one. The member
-- is told of a new plan, or new words in one. Its id.
create or replace function public.gym_save_member_plan(gym_member_id uuid, plan_id uuid, details jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  d jsonb := coalesce(gym_save_member_plan.details, '{}');
  v_member public.gym_members;
  v_old public.gym_member_plans;
  v_kind text := coalesce(nullif(d ->> 'kind', ''), 'workout');
  v_title text := trim(coalesce(d ->> 'title', ''));
  v_content text := trim(coalesce(d ->> 'content', ''));
  v_active boolean := coalesce((d ->> 'is_active')::boolean, true);
  v_me uuid := (select auth.uid());
  v_user uuid;
  v_id uuid;
begin
  select * into v_member from public.gym_members g where g.id = gym_save_member_plan.gym_member_id;
  if not found then
    raise exception 'This member is no longer registered.';
  end if;
  if not public.gym_member_can_coach(v_member.id) then
    raise exception 'Only the member''s trainer and the gym''s staff can give them plans.';
  end if;
  if gym_save_member_plan.plan_id is not null then
    select * into v_old from public.gym_member_plans x where x.id = gym_save_member_plan.plan_id;
    if not found or v_old.gym_member_id <> v_member.id then
      raise exception 'This plan isn''t there any more.';
    end if;
  end if;
  if v_kind not in ('workout', 'diet') then
    raise exception 'Choose a workout or a diet plan.';
  end if;
  if char_length(v_title) not between 2 and 100 then
    raise exception 'Give the plan a title, e.g. Strength, 3 days a week.';
  end if;
  if char_length(v_content) = 0 then
    raise exception 'Write the plan.';
  end if;
  if char_length(v_content) > 8000 then
    raise exception 'Keep the plan under 8000 characters.';
  end if;

  if gym_save_member_plan.plan_id is null then
    insert into public.gym_member_plans (venue_id, gym_member_id, kind, title, content, is_active, author_id, author_name)
    values (v_member.venue_id, v_member.id, v_kind, v_title, v_content, v_active, v_me,
            (select nullif(trim(p.full_name), '') from public.profiles p where p.id = v_me))
    returning id into v_id;
  else
    update public.gym_member_plans x
       set kind = v_kind, title = v_title, content = v_content, is_active = v_active
     where x.id = v_old.id;
    v_id := v_old.id;
  end if;

  -- They're told, if they have an account: a new plan, or new words.
  if v_active and (v_old.id is null or v_old.content is distinct from v_content or v_old.title is distinct from v_title) then
    select p.user_id into v_user from public.people p where p.id = v_member.person_id;
    perform public.notify(v_user, 'gym_membership',
      case when v_old.id is null then 'A new ' || v_kind || ' plan for you' else 'Your ' || v_kind || ' plan was updated' end,
      v_title || ', from ' || coalesce((select nullif(trim(p.full_name), '') from public.profiles p where p.id = v_me), 'your gym')
        || '. Open My gym to read it.',
      '/gyms/my?gym=' || v_member.venue_id);
  end if;
  return v_id;
end;
$$;

create or replace function public.gym_delete_member_plan(plan_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.gym_member_plans;
begin
  select * into v_old from public.gym_member_plans x where x.id = gym_delete_member_plan.plan_id;
  if not found then
    raise exception 'This plan isn''t there any more.';
  end if;
  if not public.gym_member_can_coach(v_old.gym_member_id) then
    raise exception 'Only the member''s trainer and the gym''s staff can remove their plans.';
  end if;
  delete from public.gym_member_plans x where x.id = v_old.id;
end;
$$;

revoke execute on function public.gym_save_member_plan(uuid, uuid, jsonb), public.gym_delete_member_plan(uuid) from public, anon;
grant execute on function public.gym_save_member_plan(uuid, uuid, jsonb), public.gym_delete_member_plan(uuid) to authenticated;


-- ---------------------------------------------------------------------
-- A trainer's members
-- ---------------------------------------------------------------------

-- The signed-in trainer's members now, gym by gym: who, since when, until
-- when their package runs, their latest weight and active plans.
create or replace function public.trainer_my_members()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'gym_member_id', g.id,
    'venue_id', g.venue_id,
    'venue_name', v.name,
    'full_name', g.full_name,
    'code', g.code,
    'phone', g.phone,
    'since', l.started_at,
    'paid_until', (select max(s.end_date) from public.gym_subscriptions s
                   where s.gym_member_id = g.id and s.status = 'active' and s.end_date >= public.bhutan_today()),
    'latest_weight', (select m.weight_kg from public.gym_body_measurements m
                      where m.gym_member_id = g.id and m.weight_kg is not null
                      order by m.measured_on desc, m.created_at desc limit 1),
    'active_plans', (select count(*) from public.gym_member_plans p where p.gym_member_id = g.id and p.is_active)
  ) order by v.name, g.full_name), '[]'::jsonb)
  from public.trainer_links l
  join public.gym_members g on g.id = l.gym_member_id
  join public.venues v on v.id = g.venue_id
  where l.trainer_id = (select auth.uid()) and l.ended_at is null;
$$;

revoke execute on function public.trainer_my_members() from public, anon;
grant execute on function public.trainer_my_members() to authenticated;
