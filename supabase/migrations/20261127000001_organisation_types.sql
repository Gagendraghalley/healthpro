-- =====================================================================
-- Organisation types: Health Pro for every kind of health business
-- =====================================================================
-- The kinds of organisation on Health Pro (gym, swimming pool, cycling,
-- wellness centre...) become master data the Health Pro team keeps in
-- Admin -> Organisation types, not code. Each type is run by a module
-- (venue_types.module_key); today gym_membership runs them all, so a pool or
-- a cycling club has the same packages, members, check-in, classes and
-- trainers as a gym. One Health Pro account joins any number of them.
--
-- 1. venue_types grows into the master: what it is, its icon, the
--    facilities its form suggests, its place in lists, and on/off.
-- 2. venues.module_key: the module that runs the venue, kept from its type,
--    so the gym module's checks take every type it runs, not only 'gym'.
--    A new venue needs a type that's in use.
-- 3. save_venue_type / delete_venue_type, for whoever keeps the master data.
-- 4. gym_require_gym and gym_audit_staff: any venue the gym module runs.
-- 5. gym_venue_services: each verified venue's packages and classes by
--    name, so people can search for a service.
-- 6. Inventory (the gym's own stock) is taken out of the app; Suppliers
--    stays. Its permission, 'gym.inventory', now reads Suppliers. The stock
--    tables and their data stay.
--
-- Safe to re-run: types the team has changed keep their changes.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. The master
-- ---------------------------------------------------------------------

alter table public.venue_types
  add column if not exists description text,
  add column if not exists icon text not null default 'fitness',
  add column if not exists facilities text[] not null default '{}',
  add column if not exists sort_order int not null default 100,
  add column if not exists is_active boolean not null default true,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

alter table public.venue_types alter column module_key set default 'gym_membership';

alter table public.venue_types drop constraint if exists venue_types_name_length;
alter table public.venue_types add constraint venue_types_name_length check (char_length(trim(name)) between 2 and 60);
alter table public.venue_types drop constraint if exists venue_types_description_length;
alter table public.venue_types add constraint venue_types_description_length check (char_length(description) <= 300);
alter table public.venue_types drop constraint if exists venue_types_icon_key;
alter table public.venue_types add constraint venue_types_icon_key check (icon ~ '^[a-z][a-z_]{1,30}$');
alter table public.venue_types drop constraint if exists venue_types_facilities_count;
alter table public.venue_types add constraint venue_types_facilities_count check (cardinality(facilities) <= 40);

drop trigger if exists venue_types_updated_at on public.venue_types;
create trigger venue_types_updated_at before update on public.venue_types
  for each row execute function public.set_updated_at();

-- The gym, filled in once (no description yet).
update public.venue_types
set description = 'Membership packages, trainers, classes and check-in with a QR code',
    icon = 'fitness',
    sort_order = 10,
    facilities = array['Shower', 'Changing rooms', 'Lockers', 'Massage', 'Sauna', 'Steam room', 'Personal training',
                       'Group classes', 'Yoga', 'Cardio machines', 'Free weights', 'Air conditioning', 'Drinking water',
                       'Parking', 'Wi-Fi']
where key = 'gym' and description is null;

insert into public.venue_types (key, module_key, name, description, icon, sort_order, facilities) values
  ('fitness_centre', 'gym_membership', 'Fitness Centre', 'Group workouts, aerobics, Zumba and personal training', 'run', 20,
   array['Group classes', 'Aerobics', 'Zumba', 'Personal training', 'Changing rooms', 'Shower', 'Lockers', 'Drinking water',
         'Parking']),
  ('swimming', 'gym_membership', 'Swimming Pool', 'Pool sessions, swimming lessons and pool memberships', 'pool', 30,
   array['Changing rooms', 'Shower', 'Lockers', 'Lifeguard', 'Swimming lessons', 'Kids'' pool', 'Heated pool', 'Towels',
         'Drinking water', 'Parking']),
  ('cycling', 'gym_membership', 'Cycling', 'Cycling clubs, bike hire, group rides and spin classes', 'cycling', 40,
   array['Bike hire', 'Helmets', 'Repairs', 'Group rides', 'Guided trails', 'Spin classes', 'Lockers', 'Shower', 'Parking']),
  ('sports_facility', 'gym_membership', 'Sports Facility', 'Courts, halls and grounds to play and train', 'sports', 50,
   array['Indoor court', 'Outdoor court', 'Floodlights', 'Equipment hire', 'Coaching', 'Changing rooms', 'Shower',
         'Spectator seats', 'Parking']),
  ('wellness_centre', 'gym_membership', 'Wellness Centre', 'Spa, massage, yoga, meditation and therapy', 'wellness', 60,
   array['Massage', 'Sauna', 'Steam room', 'Hot stone bath', 'Yoga', 'Meditation', 'Physiotherapy', 'Nutrition advice',
         'Changing rooms', 'Parking'])
on conflict (key) do nothing;


-- ---------------------------------------------------------------------
-- 2. The module that runs each venue
-- ---------------------------------------------------------------------

alter table public.venues add column if not exists module_key text;
update public.venues v set module_key = t.module_key
from public.venue_types t
where t.key = v.type and v.module_key is distinct from t.module_key;
alter table public.venues alter column module_key set not null;
create index if not exists venues_module_idx on public.venues (module_key, verification_status);

-- Keeps venues.module_key from the venue's type; a new venue (or a new type
-- for one) needs a type that's in use, but for the Health Pro team.
create or replace function public.venues_keep_module()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  t public.venue_types;
begin
  select * into t from public.venue_types vt where vt.key = new.type;
  if not found then
    raise exception 'Choose what kind of organisation it is.';
  end if;
  if (tg_op = 'INSERT' or new.type is distinct from old.type) and not t.is_active and not public.is_admin() then
    raise exception 'Organisations of this type can''t be registered right now.';
  end if;
  new.module_key := t.module_key;
  return new;
end;
$$;

drop trigger if exists venues_keep_module on public.venues;
create trigger venues_keep_module before insert or update of type, module_key on public.venues
  for each row execute function public.venues_keep_module();


-- ---------------------------------------------------------------------
-- 3. Keeping the master
-- ---------------------------------------------------------------------

-- Adds an organisation type (type_key null: its key is made from its name)
-- or changes one. details: {name, description, icon, facilities[],
-- sort_order, active}. Returns its key. The module that runs it isn't
-- changed here.
create or replace function public.save_venue_type(type_key text, details jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  d jsonb := coalesce(save_venue_type.details, '{}'::jsonb);
  p_key text := nullif(lower(trim(coalesce(save_venue_type.type_key, ''))), '');
  v_name text := regexp_replace(trim(coalesce(d ->> 'name', '')), '\s+', ' ', 'g');
  v_description text := nullif(trim(coalesce(d ->> 'description', '')), '');
  v_icon text := coalesce(nullif(trim(d ->> 'icon'), ''), 'fitness');
  v_order int := coalesce((d ->> 'sort_order')::int, 100);
  v_active boolean := coalesce((d ->> 'active')::boolean, true);
  v_facilities text[];
begin
  if not public.has_permission('masters.manage') then
    raise exception 'Only people who keep the master data can change it.';
  end if;
  if char_length(v_name) not between 2 and 60 then
    raise exception 'Enter the type''s name (2 to 60 letters).';
  end if;
  if char_length(v_description) > 300 then
    raise exception 'Keep the description to 300 letters.';
  end if;
  if v_icon !~ '^[a-z][a-z_]{1,30}$' then
    raise exception 'Choose an icon.';
  end if;
  if v_order not between 0 and 10000 then
    raise exception 'The order is a number from 0 to 10000.';
  end if;
  select coalesce(array_agg(f order by n), '{}') into v_facilities
  from (
    select distinct on (lower(f)) f, n
    from (select regexp_replace(trim(x), '\s+', ' ', 'g') as f, n
          from jsonb_array_elements_text(coalesce(d -> 'facilities', '[]'::jsonb)) with ordinality as e (x, n)) s
    where f <> ''
    order by lower(f), n
  ) u;
  if cardinality(v_facilities) > 40 then
    raise exception 'Up to 40 facilities.';
  end if;
  if exists (select 1 from unnest(v_facilities) f where char_length(f) > 60) then
    raise exception 'Keep each facility to 60 letters.';
  end if;

  if p_key is null then
    p_key := left(trim(both '_' from regexp_replace(lower(v_name), '[^a-z0-9]+', '_', 'g')), 40);
    if p_key !~ '^[a-z]' then
      p_key := left('type_' || p_key, 40);
    end if;
    if p_key !~ '^[a-z][a-z0-9_]{1,40}$' then
      raise exception 'Give the type a name in English letters.';
    end if;
    if exists (select 1 from public.venue_types t where t.key = p_key)
       or exists (select 1 from public.venue_types t where lower(t.name) = lower(v_name)) then
      raise exception 'There is already a type called %.', v_name;
    end if;
    insert into public.venue_types (key, module_key, name, description, icon, facilities, sort_order, is_active)
    values (p_key, 'gym_membership', v_name, v_description, v_icon, v_facilities, v_order, v_active);
  else
    if exists (select 1 from public.venue_types t where lower(t.name) = lower(v_name) and t.key <> p_key) then
      raise exception 'There is already a type called %.', v_name;
    end if;
    update public.venue_types t
    set name = v_name, description = v_description, icon = v_icon, facilities = v_facilities, sort_order = v_order,
        is_active = v_active
    where t.key = p_key;
    if not found then
      raise exception 'This type no longer exists.';
    end if;
  end if;
  return p_key;
end;
$$;

-- Deletes an organisation type no venue has; one in use is turned off
-- instead, so its organisations keep it.
create or replace function public.delete_venue_type(type_key text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  if not public.has_permission('masters.manage') then
    raise exception 'Only people who keep the master data can change it.';
  end if;
  select count(*) into v_count from public.venues v where v.type = delete_venue_type.type_key;
  if v_count > 0 then
    raise exception '% % of this type. Turn it off instead: they keep it.', v_count,
      case when v_count = 1 then 'organisation is' else 'organisations are' end;
  end if;
  delete from public.venue_types t where t.key = delete_venue_type.type_key;
  if not found then
    raise exception 'This type no longer exists.';
  end if;
end;
$$;

revoke execute on function public.save_venue_type(text, jsonb), public.delete_venue_type(text) from public, anon;
grant execute on function public.save_venue_type(text, jsonb), public.delete_venue_type(text) to authenticated;
revoke execute on function public.venues_keep_module() from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- 4. The gym module runs every type it has
-- ---------------------------------------------------------------------

-- From 20261115000006_health_pro_names_and_desk_payments.sql: any venue the
-- module runs, not only gyms.
create or replace function public.gym_require_gym(venue uuid)
returns public.venues
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_venue public.venues;
begin
  select * into v_venue from public.venues v where v.id = venue;
  if not found or v_venue.module_key is distinct from 'gym_membership' then
    raise exception 'This gym isn''t on Health Pro.';
  end if;
  return v_venue;
end;
$$;

-- From 20261118000006_gym_audit_log.sql: staff at any venue the module runs.
create or replace function public.gym_audit_staff()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.venue_staff;
  v_name text;
  v_role text;
  v_old_role text;
begin
  if tg_op = 'DELETE' then s := old; else s := new; end if;
  if not exists (select 1 from public.venues v where v.id = s.venue_id and v.module_key = 'gym_membership') then
    return null;
  end if;
  select coalesce(nullif(trim(p.full_name), ''), p.email, 'someone') into v_name from public.profiles p where p.id = s.user_id;
  select coalesce((select r.name from public.roles r join public.venues v on v.id = s.venue_id
                   where r.key = s.role and (r.organisation_id is null or r.organisation_id = v.organisation_id)
                   order by r.organisation_id nulls last limit 1), s.role) into v_role;
  if tg_op = 'INSERT' then
    perform public.gym_audit(s.venue_id, 'staff.added', 'Added ' || coalesce(v_name, 'someone') || ' to the staff', 'As ' || v_role);
  elsif tg_op = 'DELETE' then
    perform public.gym_audit(s.venue_id, 'staff.removed', 'Removed ' || coalesce(v_name, 'someone') || ' from the staff',
                             'Was ' || v_role);
  elsif new.role is distinct from old.role then
    select coalesce((select r.name from public.roles r join public.venues v on v.id = old.venue_id
                     where r.key = old.role and (r.organisation_id is null or r.organisation_id = v.organisation_id)
                     order by r.organisation_id nulls last limit 1), old.role) into v_old_role;
    perform public.gym_audit(s.venue_id, 'staff.role_changed', 'Changed ' || coalesce(v_name, 'someone') || '''s role',
                             v_old_role || ' to ' || v_role);
  end if;
  return null;
end;
$$;


-- ---------------------------------------------------------------------
-- 5. The services each venue offers, for search
-- ---------------------------------------------------------------------

-- Each verified venue the gym module runs: its packages on sale and its
-- classes on the timetable, by name. For everyone, signed in or not.
create or replace function public.gym_venue_services()
returns table (venue_id uuid, services text[])
language sql
stable
security definer
set search_path = ''
as $$
  select v.id, array(
           select s.name from (
             select p.name from public.gym_plans p where p.venue_id = v.id and p.is_active
             union
             select c.name from public.gym_classes c where c.venue_id = v.id and c.is_active
           ) s order by lower(s.name))
  from public.venues v
  where v.is_verified and v.module_key = 'gym_membership';
$$;

revoke execute on function public.gym_venue_services() from public;
grant execute on function public.gym_venue_services() to anon, authenticated;


-- ---------------------------------------------------------------------
-- 6. Inventory leaves the app; Suppliers stays
-- ---------------------------------------------------------------------

-- The key stays (roles keep it, and supplier-catalog checks it); only what
-- Roles & permissions calls it changes.
update public.permissions
set name = 'Suppliers', description = 'See items, stock and prices from connected suppliers'
where key = 'gym.inventory';
