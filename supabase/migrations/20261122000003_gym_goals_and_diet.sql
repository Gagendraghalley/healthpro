-- Goals, and diet plans in meals.
--
-- Goals (gym_member_goals): one per member. What they're after (lose fat,
-- build muscle, gain weight, keep fit), a target weight and day, and what
-- the app needs to work out their daily calories and protein: their sex and
-- how active they are (their age comes from gym_members.date_of_birth). Set
-- by the member, their trainer or the gym's staff who see members.
--
-- Diet plans in meals (gym_member_plans.meals): meals, each with foods, an
-- amount, calories and protein, and the day's targets (kcal_target,
-- protein_target_g). The words (content) become notes, and may be left out
-- when there are meals.
--
-- Foods (diet_foods): a shared list of common and Bhutanese foods with
-- approximate calories and protein for a serving, to fill a meal from.
-- Anyone signed in reads it; it changes only through migrations.
--
-- Plan templates (gym_plan_templates): a gym's workout and diet plans to
-- start a member's plan from, kept by its staff who see members and its
-- verified trainers.
--
-- Safe to re-run.

-- The signed-in person coaches at [venue]: its staff who see members, or one
-- of its verified trainers.
create or replace function public.gym_can_coach_at(venue uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.has_venue_permission(venue, 'gym.members') or public.gym_trainer_verified(venue, (select auth.uid()));
$$;
revoke execute on function public.gym_can_coach_at(uuid) from public, anon;
grant execute on function public.gym_can_coach_at(uuid) to authenticated;


-- ---------------------------------------------------------------------
-- Goals
-- ---------------------------------------------------------------------

create table if not exists public.gym_member_goals (
  gym_member_id    uuid primary key references public.gym_members (id) on delete cascade,
  venue_id         uuid not null references public.venues (id) on delete cascade,
  goal             text check (goal in ('lose_fat', 'build_muscle', 'gain_weight', 'keep_fit')),
  target_weight_kg numeric(5, 1) check (target_weight_kg between 20 and 300),
  target_date      date,
  sex              text check (sex in ('female', 'male')),
  activity         text not null default 'moderate' check (activity in ('light', 'moderate', 'active', 'very_active')),
  started_on       date not null default public.bhutan_today(), -- the goal or target weight was last set: progress counts from here
  set_by           uuid constraint gym_member_goals_set_by_fkey references public.profiles (id) on delete set null,
  set_by_name      text, -- as they were called then
  updated_at       timestamptz not null default now()
);

drop trigger if exists gym_member_goals_updated_at on public.gym_member_goals;
create trigger gym_member_goals_updated_at before update on public.gym_member_goals
  for each row execute function public.set_updated_at();

alter table public.gym_member_goals enable row level security;
revoke all on public.gym_member_goals from anon, authenticated;
grant select on public.gym_member_goals to authenticated;
drop policy if exists "gym_member_goals: staff, trainer and the member" on public.gym_member_goals;
create policy "gym_member_goals: staff, trainer and the member" on public.gym_member_goals for select to authenticated
  using (public.has_venue_permission(venue_id, 'gym.members') or public.gym_member_is_me(gym_member_id)
         or public.gym_member_is_my_trainee(gym_member_id));

-- [details]: goal, target_weight_kg, target_date, sex, activity (each may be
-- left out). The member, their trainer or the gym's staff.
create or replace function public.gym_save_member_goal(gym_member_id uuid, details jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  d jsonb := coalesce(gym_save_member_goal.details, '{}');
  v_member public.gym_members;
  v_me uuid := (select auth.uid());
  v_goal text := nullif(d ->> 'goal', '');
  v_target numeric := round(nullif(d ->> 'target_weight_kg', '')::numeric, 1);
  v_by date := nullif(d ->> 'target_date', '')::date;
  v_sex text := nullif(d ->> 'sex', '');
  v_activity text := coalesce(nullif(d ->> 'activity', ''), 'moderate');
begin
  select * into v_member from public.gym_members g where g.id = gym_save_member_goal.gym_member_id;
  if not found then
    raise exception 'This member is no longer registered.';
  end if;
  if not public.gym_member_can_coach(v_member.id) and not public.gym_member_is_me(v_member.id) then
    raise exception 'Only the member, their trainer and the gym''s staff can set their goal.';
  end if;
  if v_goal is not null and v_goal not in ('lose_fat', 'build_muscle', 'gain_weight', 'keep_fit') then
    raise exception 'Choose a goal.';
  end if;
  if v_target not between 20 and 300 then
    raise exception 'The target weight is 20 to 300 kg.';
  end if;
  if v_by is not null and (v_by <= public.bhutan_today() or v_by > public.bhutan_today() + 730) then
    raise exception 'Choose a target day within the next two years.';
  end if;
  if v_sex is not null and v_sex not in ('female', 'male') then
    raise exception 'Choose female or male.';
  end if;
  if v_activity not in ('light', 'moderate', 'active', 'very_active') then
    raise exception 'Choose how active they are.';
  end if;

  insert into public.gym_member_goals as g (gym_member_id, venue_id, goal, target_weight_kg, target_date, sex, activity, set_by,
                                            set_by_name)
  values (v_member.id, v_member.venue_id, v_goal, v_target, v_by, v_sex, v_activity, v_me,
          (select nullif(trim(p.full_name), '') from public.profiles p where p.id = v_me))
  on conflict on constraint gym_member_goals_pkey do update
     set goal = excluded.goal, target_weight_kg = excluded.target_weight_kg, target_date = excluded.target_date,
         sex = excluded.sex, activity = excluded.activity, set_by = excluded.set_by, set_by_name = excluded.set_by_name,
         started_on = case when g.goal is distinct from excluded.goal or g.target_weight_kg is distinct from excluded.target_weight_kg
                           then public.bhutan_today() else g.started_on end;
end;
$$;

-- What the app needs to work out [gym_member_id]'s daily calories: their
-- age in years (null when the desk has no date of birth). Null for anyone
-- who can't see their progress.
create or replace function public.gym_member_age(gym_member_id uuid)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select extract(year from age(public.bhutan_today(), g.date_of_birth))::int
    from public.gym_members g
   where g.id = gym_member_age.gym_member_id
     and (public.gym_member_can_coach(g.id) or public.gym_member_is_me(g.id));
$$;

revoke execute on function public.gym_save_member_goal(uuid, jsonb), public.gym_member_age(uuid) from public, anon;
grant execute on function public.gym_save_member_goal(uuid, jsonb), public.gym_member_age(uuid) to authenticated;


-- ---------------------------------------------------------------------
-- Diet plans in meals
-- ---------------------------------------------------------------------

alter table public.gym_member_plans add column if not exists meals jsonb not null default '[]';
alter table public.gym_member_plans add column if not exists kcal_target int;
alter table public.gym_member_plans add column if not exists protein_target_g int;

alter table public.gym_member_plans drop constraint if exists gym_member_plans_content_check;
alter table public.gym_member_plans add constraint gym_member_plans_content_check check (char_length(content) <= 8000);
alter table public.gym_member_plans drop constraint if exists gym_member_plans_meals_check;
alter table public.gym_member_plans add constraint gym_member_plans_meals_check check (jsonb_typeof(meals) = 'array');
alter table public.gym_member_plans drop constraint if exists gym_member_plans_something;
alter table public.gym_member_plans add constraint gym_member_plans_something
  check (char_length(content) > 0 or jsonb_array_length(meals) > 0);
alter table public.gym_member_plans drop constraint if exists gym_member_plans_targets;
alter table public.gym_member_plans add constraint gym_member_plans_targets
  check (kcal_target between 800 and 6000 and protein_target_g between 20 and 400);

-- [meals] as it's kept: up to 8 meals ({name, items}), each with up to 20
-- foods ({food, amount, kcal, protein_g}); names trimmed, numbers rounded.
-- Raises what's wrong.
create or replace function public.gym_clean_meals(meals jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_meals jsonb := coalesce(gym_clean_meals.meals, '[]');
  v_out jsonb := '[]';
  v_meal jsonb;
  v_item jsonb;
  v_items jsonb;
  v_name text;
  v_food text;
  v_amount text;
  v_kcal numeric;
  v_protein numeric;
begin
  if jsonb_typeof(v_meals) <> 'array' then
    raise exception 'The meals aren''t readable.';
  end if;
  if jsonb_array_length(v_meals) > 8 then
    raise exception 'Keep to 8 meals a day.';
  end if;
  for v_meal in select value from jsonb_array_elements(v_meals) loop
    v_name := trim(coalesce(v_meal ->> 'name', ''));
    if char_length(v_name) not between 1 and 40 then
      raise exception 'Name each meal, e.g. Breakfast.';
    end if;
    if jsonb_typeof(coalesce(v_meal -> 'items', '[]')) <> 'array' or jsonb_array_length(coalesce(v_meal -> 'items', '[]')) > 20 then
      raise exception 'Keep to 20 foods in a meal.';
    end if;
    v_items := '[]';
    for v_item in select value from jsonb_array_elements(coalesce(v_meal -> 'items', '[]')) loop
      v_food := trim(coalesce(v_item ->> 'food', ''));
      v_amount := nullif(trim(coalesce(v_item ->> 'amount', '')), '');
      v_kcal := round(nullif(v_item ->> 'kcal', '')::numeric);
      v_protein := round(nullif(v_item ->> 'protein_g', '')::numeric, 1);
      if char_length(v_food) not between 1 and 80 then
        raise exception 'Name each food in %.', v_name;
      end if;
      if char_length(v_amount) > 40 then
        raise exception 'Keep the amount of % short.', v_food;
      end if;
      if v_kcal not between 0 and 3000 or v_protein not between 0 and 300 then
        raise exception 'Check the calories and protein of %.', v_food;
      end if;
      v_items := v_items || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'food', v_food, 'amount', v_amount, 'kcal', v_kcal, 'protein_g', v_protein)));
    end loop;
    if jsonb_array_length(v_items) = 0 then
      raise exception 'Add a food to %, or take the meal out.', v_name;
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('name', v_name, 'items', v_items));
  end loop;
  return v_out;
end;
$$;

-- [details]: kind ('workout' or 'diet'), title, content, is_active, and for
-- a diet plan meals, kcal_target and protein_target_g. A new plan for
-- [gym_member_id] ([plan_id] null) or changes to one. The member is told of
-- a new plan, or new words or meals in one. Its id.
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
  v_meals jsonb;
  v_kcal int := nullif(d ->> 'kcal_target', '')::int;
  v_protein int := nullif(d ->> 'protein_target_g', '')::int;
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
  v_meals := case when v_kind = 'diet' then public.gym_clean_meals(d -> 'meals') else '[]' end;
  if v_kind <> 'diet' then
    v_kcal := null;
    v_protein := null;
  end if;
  if char_length(v_content) = 0 and jsonb_array_length(v_meals) = 0 then
    raise exception 'Write the plan.';
  end if;
  if char_length(v_content) > 8000 then
    raise exception 'Keep the plan under 8000 characters.';
  end if;
  if v_kcal not between 800 and 6000 then
    raise exception 'Daily calories are 800 to 6000.';
  end if;
  if v_protein not between 20 and 400 then
    raise exception 'Daily protein is 20 to 400 g.';
  end if;

  if gym_save_member_plan.plan_id is null then
    insert into public.gym_member_plans (venue_id, gym_member_id, kind, title, content, meals, kcal_target, protein_target_g,
                                         is_active, author_id, author_name)
    values (v_member.venue_id, v_member.id, v_kind, v_title, v_content, v_meals, v_kcal, v_protein, v_active, v_me,
            (select nullif(trim(p.full_name), '') from public.profiles p where p.id = v_me))
    returning id into v_id;
  else
    update public.gym_member_plans x
       set kind = v_kind, title = v_title, content = v_content, meals = v_meals, kcal_target = v_kcal,
           protein_target_g = v_protein, is_active = v_active
     where x.id = v_old.id;
    v_id := v_old.id;
  end if;

  -- They're told, if they have an account: a new plan, or new words or meals.
  if v_active and (v_old.id is null or v_old.content is distinct from v_content or v_old.title is distinct from v_title
                   or v_old.meals is distinct from v_meals or v_old.kcal_target is distinct from v_kcal
                   or v_old.protein_target_g is distinct from v_protein) then
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

revoke execute on function public.gym_clean_meals(jsonb) from public, anon, authenticated;
revoke execute on function public.gym_save_member_plan(uuid, uuid, jsonb) from public, anon;
grant execute on function public.gym_save_member_plan(uuid, uuid, jsonb) to authenticated;


-- ---------------------------------------------------------------------
-- Foods
-- ---------------------------------------------------------------------

create table if not exists public.diet_foods (
  id        uuid primary key default gen_random_uuid(),
  name      text not null unique check (char_length(name) between 2 and 80),
  serving   text not null check (char_length(serving) between 1 and 40),
  kcal      int not null check (kcal between 0 and 3000),
  protein_g numeric(4, 1) not null check (protein_g between 0 and 300),
  sort      int not null default 100
);

alter table public.diet_foods enable row level security;
revoke all on public.diet_foods from anon, authenticated;
grant select on public.diet_foods to authenticated;
drop policy if exists "diet_foods: anyone signed in" on public.diet_foods;
create policy "diet_foods: anyone signed in" on public.diet_foods for select to authenticated using (true);

-- Approximate, for a usual serving: cooked weights; dishes as usually made
-- at home, with some oil or butter.
insert into public.diet_foods (name, serving, kcal, protein_g, sort) values
  ('Red rice, cooked', '1 cup', 215, 4.5, 10),
  ('White rice, cooked', '1 cup', 205, 4.3, 11),
  ('Ema datshi', '1 bowl', 220, 9, 20),
  ('Kewa datshi', '1 bowl', 250, 8, 21),
  ('Shamu datshi', '1 bowl', 180, 8, 22),
  ('Jasha maru', '1 bowl', 220, 22, 23),
  ('Phaksha paa', '1 bowl', 350, 18, 24),
  ('Momo, meat', '5 pieces', 300, 14, 25),
  ('Momo, cheese or vegetable', '5 pieces', 250, 9, 26),
  ('Thukpa', '1 bowl', 300, 12, 27),
  ('Suja (butter tea)', '1 cup', 120, 2, 28),
  ('Sweet milk tea (ngaja)', '1 cup', 90, 2.5, 29),
  ('Dal', '1 bowl', 180, 9, 30),
  ('Chickpeas, cooked', '1 cup', 270, 14.5, 31),
  ('Kidney beans, cooked', '1 cup', 225, 15, 32),
  ('Vegetable curry', '1 bowl', 150, 4, 33),
  ('Green salad', '1 bowl', 20, 1.5, 34),
  ('Egg, boiled', '1 egg', 78, 6.3, 40),
  ('Egg, fried', '1 egg', 90, 6.3, 41),
  ('Chicken breast, cooked', '100 g', 165, 31, 42),
  ('Chicken curry', '1 bowl', 280, 25, 43),
  ('Beef, cooked', '100 g', 250, 26, 44),
  ('Pork, cooked', '100 g', 242, 27, 45),
  ('Fish, cooked', '100 g', 130, 24, 46),
  ('Paneer', '100 g', 265, 18, 47),
  ('Milk', '1 glass (250 ml)', 150, 8, 50),
  ('Curd (plain yoghurt)', '1 cup', 150, 8.5, 51),
  ('Whey protein', '1 scoop (30 g)', 120, 24, 52),
  ('Roti', '1 roti', 120, 3, 60),
  ('Bread', '1 slice', 75, 2.6, 61),
  ('Oats', '40 g dry', 150, 5, 62),
  ('Potato, boiled', '1 medium', 150, 3, 63),
  ('Instant noodles', '1 pack', 380, 8, 64),
  ('Banana', '1 medium', 105, 1.3, 70),
  ('Apple', '1 medium', 95, 0.5, 71),
  ('Orange', '1 medium', 62, 1.2, 72),
  ('Peanuts', '30 g', 170, 7, 73),
  ('Almonds', '30 g', 164, 6, 74),
  ('Peanut butter', '1 tablespoon', 95, 3.5, 75),
  ('Butter', '1 tablespoon', 100, 0.1, 80),
  ('Cooking oil', '1 tablespoon', 120, 0, 81),
  ('Sugar', '1 teaspoon', 16, 0, 82),
  ('Soft drink', '1 can (330 ml)', 140, 0, 83)
on conflict (name) do update
   set serving = excluded.serving, kcal = excluded.kcal, protein_g = excluded.protein_g, sort = excluded.sort;


-- ---------------------------------------------------------------------
-- Plan templates
-- ---------------------------------------------------------------------

create table if not exists public.gym_plan_templates (
  id          uuid primary key default gen_random_uuid(),
  venue_id    uuid not null references public.venues (id) on delete cascade,
  kind        text not null check (kind in ('workout', 'diet')),
  title       text not null check (char_length(trim(title)) between 2 and 100),
  content     text not null default '' check (char_length(content) <= 8000),
  meals       jsonb not null default '[]' check (jsonb_typeof(meals) = 'array'),
  author_name text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint gym_plan_templates_something check (char_length(content) > 0 or jsonb_array_length(meals) > 0)
);
create unique index if not exists gym_plan_templates_title on public.gym_plan_templates (venue_id, kind, lower(trim(title)));

drop trigger if exists gym_plan_templates_updated_at on public.gym_plan_templates;
create trigger gym_plan_templates_updated_at before update on public.gym_plan_templates
  for each row execute function public.set_updated_at();

alter table public.gym_plan_templates enable row level security;
revoke all on public.gym_plan_templates from anon, authenticated;
grant select on public.gym_plan_templates to authenticated;
drop policy if exists "gym_plan_templates: the gym's coaches" on public.gym_plan_templates;
create policy "gym_plan_templates: the gym's coaches" on public.gym_plan_templates for select to authenticated
  using (public.gym_can_coach_at(venue_id));

-- [details]: kind, title, content, meals. Saves a template at [venue_id]; one
-- with the same kind and title is replaced. Its id.
create or replace function public.gym_save_plan_template(venue_id uuid, details jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  d jsonb := coalesce(gym_save_plan_template.details, '{}');
  v_kind text := coalesce(nullif(d ->> 'kind', ''), 'workout');
  v_title text := trim(coalesce(d ->> 'title', ''));
  v_content text := trim(coalesce(d ->> 'content', ''));
  v_meals jsonb;
  v_me uuid := (select auth.uid());
  v_id uuid;
begin
  if not public.gym_can_coach_at(gym_save_plan_template.venue_id) then
    raise exception 'Only the gym''s staff and its trainers keep plan templates.';
  end if;
  if v_kind not in ('workout', 'diet') then
    raise exception 'Choose a workout or a diet plan.';
  end if;
  if char_length(v_title) not between 2 and 100 then
    raise exception 'Give the template a title.';
  end if;
  v_meals := case when v_kind = 'diet' then public.gym_clean_meals(d -> 'meals') else '[]' end;
  if char_length(v_content) = 0 and jsonb_array_length(v_meals) = 0 then
    raise exception 'Write the plan.';
  end if;
  if char_length(v_content) > 8000 then
    raise exception 'Keep the plan under 8000 characters.';
  end if;

  select t.id into v_id from public.gym_plan_templates t
   where t.venue_id = gym_save_plan_template.venue_id and t.kind = v_kind and lower(trim(t.title)) = lower(v_title);
  if v_id is null then
    insert into public.gym_plan_templates (venue_id, kind, title, content, meals, author_name)
    values (gym_save_plan_template.venue_id, v_kind, v_title, v_content, v_meals,
            (select nullif(trim(p.full_name), '') from public.profiles p where p.id = v_me))
    returning id into v_id;
  else
    update public.gym_plan_templates t
       set title = v_title, content = v_content, meals = v_meals,
           author_name = (select nullif(trim(p.full_name), '') from public.profiles p where p.id = v_me)
     where t.id = v_id;
  end if;
  return v_id;
end;
$$;

create or replace function public.gym_delete_plan_template(template_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venue uuid;
begin
  select t.venue_id into v_venue from public.gym_plan_templates t where t.id = gym_delete_plan_template.template_id;
  if v_venue is null then
    raise exception 'This template isn''t there any more.';
  end if;
  if not public.gym_can_coach_at(v_venue) then
    raise exception 'Only the gym''s staff and its trainers keep plan templates.';
  end if;
  delete from public.gym_plan_templates t where t.id = gym_delete_plan_template.template_id;
end;
$$;

revoke execute on function public.gym_save_plan_template(uuid, jsonb), public.gym_delete_plan_template(uuid) from public, anon;
grant execute on function public.gym_save_plan_template(uuid, jsonb), public.gym_delete_plan_template(uuid) to authenticated;
