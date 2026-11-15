-- Health Pro, phase 1 of the QR code flow: one QR code per person that works
-- at every gym, and joining a gym by scanning its QR code.
--
-- - people: everyone Health Pro knows, with an account or not (the front
--   desk registers walk-ins without one). Each has one personal QR code,
--   'healthpro:member:<qr_token>'. A gym's registered member (gym_members)
--   is a person at that gym; one person can be at several gyms.
-- - An account's person is made the first time it's needed (my_person). It
--   takes in the people the desk registered with the account's email, once
--   that email is confirmed: never by phone, which nobody has proved is
--   theirs.
-- - At the desk, any QR code (the personal one, a gym's old card, an
--   account's) checks the person in where they're registered, or says
--   they're not a member here yet; then the desk adds them with the details
--   they gave before (gym_person_details), without typing them again.
-- - gym_join_requests: a person with an account scans a gym's QR code and
--   asks to join; the front desk is told, and adds them (approves) or
--   declines.
--
-- Safe to run again.


-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

create table if not exists public.people (
  id          uuid primary key default gen_random_uuid(),
  -- Their account, once they have one.
  user_id     uuid unique constraint people_user_id_fkey references public.profiles (id) on delete set null,
  -- What their QR code holds; a new one makes the old one useless.
  qr_token    text not null unique check (qr_token ~ '^[0-9a-f]{32}$'),
  full_name   text not null default '' check (char_length(full_name) <= 100),
  email       text check (char_length(email) <= 320),
  phone       text check (phone ~ '^\+[0-9]{8,15}$'),
  -- Joined into another person (theirs, once they had an account): its QR
  -- code still finds them.
  merged_into uuid constraint people_merged_into_fkey references public.people (id) on delete set null,
  created_by  uuid constraint people_created_by_fkey references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists people_unclaimed_email_idx on public.people (lower(email))
  where user_id is null and merged_into is null;

drop trigger if exists people_updated_at on public.people;
create trigger people_updated_at before update on public.people
  for each row execute function public.set_updated_at();

-- Each registered member is a person. Members registered before this get a
-- person each, whose QR code is their card's, so printed cards keep working.
alter table public.gym_members add column if not exists person_id uuid;
do $$
declare
  r public.gym_members;
  v_person uuid;
begin
  if not exists (select 1 from pg_constraint where conname = 'gym_members_person_id_fkey') then
    alter table public.gym_members add constraint gym_members_person_id_fkey
      foreign key (person_id) references public.people (id) on delete restrict;
  end if;
  for r in select * from public.gym_members g where g.person_id is null loop
    insert into public.people (qr_token, full_name, email, phone, created_by, created_at)
    values (case when exists (select 1 from public.people p where p.qr_token = r.qr_token)
                 then replace(gen_random_uuid()::text, '-', '') else r.qr_token end,
            r.full_name, r.email, r.phone, r.created_by, r.created_at)
    returning id into v_person;
    update public.gym_members g set person_id = v_person where g.id = r.id;
  end loop;
end;
$$;
alter table public.gym_members alter column person_id set not null;
-- A person is registered once at a gym.
create unique index if not exists gym_members_one_per_person on public.gym_members (venue_id, person_id);
create index if not exists gym_members_person_idx on public.gym_members (person_id);

-- Asking to join a gym, from its QR code.
create table if not exists public.gym_join_requests (
  id            uuid primary key default gen_random_uuid(),
  venue_id      uuid not null references public.venues (id) on delete cascade,
  person_id     uuid not null references public.people (id) on delete cascade,
  -- The account that asked.
  user_id       uuid constraint gym_join_requests_user_id_fkey references public.profiles (id) on delete set null,
  -- The package they'd like, if they chose one.
  plan_id       uuid references public.gym_plans (id) on delete set null,
  message       text check (char_length(message) <= 500),
  status        text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'cancelled')),
  decision_note text check (char_length(decision_note) <= 500),
  decided_by    uuid constraint gym_join_requests_decided_by_fkey references public.profiles (id) on delete set null,
  decided_at    timestamptz,
  -- Approved: their registration at the gym.
  gym_member_id uuid references public.gym_members (id) on delete set null,
  created_at    timestamptz not null default now()
);
-- One request waiting per person per gym.
create unique index if not exists gym_join_requests_one_pending
  on public.gym_join_requests (venue_id, person_id) where status = 'pending';
create index if not exists gym_join_requests_venue_idx on public.gym_join_requests (venue_id, status, created_at desc);
create index if not exists gym_join_requests_user_idx on public.gym_join_requests (user_id);


-- ---------------------------------------------------------------------
-- 2. Who can read what (changes go through the functions below)
-- ---------------------------------------------------------------------

alter table public.people enable row level security;
revoke all on public.people from anon, authenticated;
grant select on public.people to authenticated;

-- Themselves; the gyms they're registered at; a gym they asked to join.
drop policy if exists "people: themselves and their gyms" on public.people;
create policy "people: themselves and their gyms" on public.people for select to authenticated
  using (
    user_id = (select auth.uid())
    or exists (select 1 from public.gym_members g
               where g.person_id = people.id and public.has_venue_permission(g.venue_id, 'gym.members'))
    or exists (select 1 from public.gym_join_requests j
               where j.person_id = people.id and j.status = 'pending'
                 and public.has_venue_permission(j.venue_id, 'gym.register'))
  );

alter table public.gym_join_requests enable row level security;
revoke all on public.gym_join_requests from anon, authenticated;
grant select on public.gym_join_requests to authenticated;

drop policy if exists "gym_join_requests: the asker and the desk" on public.gym_join_requests;
create policy "gym_join_requests: the asker and the desk" on public.gym_join_requests for select to authenticated
  using (user_id = (select auth.uid()) or public.has_venue_permission(venue_id, 'gym.register'));


-- ---------------------------------------------------------------------
-- 3. Helpers (not callable by the app)
-- ---------------------------------------------------------------------

-- The person in use: [p], or whoever they were joined into.
create or replace function public.person_current(p public.people)
returns public.people
language plpgsql
stable
set search_path = ''
as $$
declare
  v public.people := p;
begin
  for i in 1..5 loop
    exit when v.id is null or v.merged_into is null;
    select * into v from public.people x where x.id = v.merged_into;
  end loop;
  return v;
end;
$$;

-- Whoever's QR code holds [token]: a personal QR code, or a gym's card
-- (made before personal ones). Null fields when nobody's.
create or replace function public.person_by_token(token text)
returns public.people
language plpgsql
stable
set search_path = ''
as $$
declare
  t text := lower(trim(coalesce(token, '')));
  v public.people;
begin
  select * into v from public.people p where p.qr_token = t;
  if not found then
    select p.* into v from public.gym_members g join public.people p on p.id = g.person_id where g.qr_token = t;
  end if;
  return public.person_current(v);
end;
$$;

-- The person of account [uid]: theirs, or made now. Either way, the people
-- the desk registered with the account's email join it, once the account
-- has confirmed that email (one registration per gym: one at a gym where
-- they're registered already stays apart).
create or replace function public.person_for_user(uid uuid)
returns public.people
language plpgsql
volatile
set search_path = ''
as $$
declare
  v public.people;
  o public.people;
  v_profile public.profiles;
  v_email text;
begin
  select * into v_profile from public.profiles p where p.id = uid;
  if not found then
    raise exception 'Sign in first.';
  end if;
  select lower(u.email) into v_email from auth.users u where u.id = uid and u.email_confirmed_at is not null;

  select * into v from public.people p where p.user_id = uid for update;
  if not found and v_email is not null then
    select * into v from public.people p
    where p.user_id is null and p.merged_into is null and lower(p.email) = v_email
    order by p.created_at desc
    limit 1
    for update;
  end if;
  if v.id is null then
    insert into public.people (user_id, qr_token, full_name, email, phone, created_by)
    values (uid, replace(gen_random_uuid()::text, '-', ''), left(coalesce(v_profile.full_name, ''), 100),
            v_profile.email, v_profile.phone, uid)
    returning * into v;
  else
    update public.people p set
      user_id = uid,
      full_name = coalesce(nullif(trim(v_profile.full_name), ''), p.full_name),
      email = coalesce(v_profile.email, p.email),
      phone = coalesce(v_profile.phone, p.phone)
    where p.id = v.id
    returning * into v;
  end if;

  if v_email is not null then
    for o in select * from public.people p
             where p.user_id is null and p.merged_into is null and lower(p.email) = v_email and p.id <> v.id
             for update loop
      update public.gym_members g set person_id = v.id
      where g.person_id = o.id
        and not exists (select 1 from public.gym_members x where x.person_id = v.id and x.venue_id = g.venue_id);
      update public.gym_join_requests j set person_id = v.id
      where j.person_id = o.id and j.status <> 'pending';
      if not exists (select 1 from public.gym_members g where g.person_id = o.id) then
        update public.people p set merged_into = v.id where p.id = o.id;
      end if;
    end loop;
  end if;
  return v;
end;
$$;

-- What a person is called: their account's name, or what the desk wrote.
create or replace function public.person_name(p public.people)
returns text
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (select nullif(trim(pr.full_name), '') from public.profiles pr where pr.id = p.user_id),
    nullif(trim(p.full_name), ''),
    'Member'
  );
$$;

-- Checks [person] in at [venue] where they're registered (or have an
-- account membership); otherwise says they're not a member here yet, with
-- [token] for the desk to add them by.
create or replace function public.gym_check_in_person_at(venue uuid, person public.people, token text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_member uuid;
begin
  if person.id is null then
    raise exception 'This QR code isn''t valid any more. Ask for their member code, or give them a new card.';
  end if;
  select g.id into v_member from public.gym_members g where g.person_id = person.id and g.venue_id = venue;
  if v_member is not null then
    return public.gym_check_in_registered(venue, v_member);
  end if;
  if person.user_id is not null and exists (
    select 1 from public.gym_subscriptions s where s.venue_id = venue and s.member_id = person.user_id
  ) then
    return public.gym_check_in(venue, person.user_id);
  end if;
  return jsonb_build_object('not_member', true, 'member_name', public.person_name(person), 'person_token', token);
end;
$$;

-- A gym_members row's details, as the registration form sends them.
create or replace function public.gym_member_details_json(m public.gym_members)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'full_name', m.full_name, 'phone', m.phone, 'email', m.email, 'date_of_birth', m.date_of_birth,
    'blood_group', m.blood_group, 'occupation', m.occupation, 'dzongkhag_id', m.dzongkhag_id,
    'gewog_id', m.gewog_id, 'village_id', m.village_id, 'emergency_contact_name', m.emergency_contact_name,
    'emergency_contact_phone', m.emergency_contact_phone, 'medical_notes', m.medical_notes
  );
$$;


-- ---------------------------------------------------------------------
-- 4. Functions the app calls
-- ---------------------------------------------------------------------

-- The signed-in person's own QR code.
create or replace function public.my_person()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v public.people := public.person_for_user((select auth.uid()));
begin
  return jsonb_build_object('person_id', v.id, 'qr_token', v.qr_token, 'full_name', public.person_name(v));
end;
$$;

-- A new QR code for the signed-in person (a screenshot of it got out): the
-- old one stops working at every gym.
create or replace function public.my_person_new_qr()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v public.people := public.person_for_user((select auth.uid()));
  v_token text := public.gym_new_qr_token();
begin
  update public.people p set qr_token = v_token where p.id = v.id;
  return v_token;
end;
$$;

-- The signed-in person's gyms: each one they're registered at (or have an
-- account membership at), with their latest package and last visit; their
-- requests to join; and their recent visits.
create or replace function public.my_gyms()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  v public.people := public.person_for_user(uid);
  v_today date := public.bhutan_today();
begin
  return jsonb_build_object(
    'gyms', coalesce((
      select jsonb_agg(x.gym order by x.sort_end desc nulls last, x.name)
      from (
        select jsonb_build_object(
                 'venue_id', ven.id, 'venue_name', ven.name, 'dzongkhag', ven.dzongkhag, 'town', ven.town,
                 'phone', ven.phone, 'member_code', g.code, 'joined_on', g.joined_on,
                 'plan_name', s.plan_name, 'start_date', s.start_date, 'end_date', s.end_date,
                 'last_visit', (select max(c.checked_in_at) from public.gym_check_ins c where c.gym_member_id = g.id)
               ) as gym,
               s.end_date as sort_end, ven.name
        from public.gym_members g
        join public.venues ven on ven.id = g.venue_id
        left join lateral (
          select * from public.gym_subscriptions s
          where s.gym_member_id = g.id and s.status in ('active', 'expired')
          order by s.end_date desc
          limit 1
        ) s on true
        where g.person_id = v.id
        union all
        select jsonb_build_object(
                 'venue_id', ven.id, 'venue_name', ven.name, 'dzongkhag', ven.dzongkhag, 'town', ven.town,
                 'phone', ven.phone, 'member_code', null, 'joined_on', null,
                 'plan_name', s.plan_name, 'start_date', s.start_date, 'end_date', s.end_date,
                 'last_visit', (select max(c.checked_in_at) from public.gym_check_ins c
                                where c.member_id = uid and c.venue_id = ven.id)
               ),
               s.end_date, ven.name
        from public.venues ven
        join lateral (
          select * from public.gym_subscriptions s
          where s.member_id = uid and s.venue_id = ven.id and s.status in ('active', 'expired')
          order by s.end_date desc
          limit 1
        ) s on true
        where not exists (select 1 from public.gym_members g where g.person_id = v.id and g.venue_id = ven.id)
      ) x
    ), '[]'::jsonb),
    'requests', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', j.id, 'venue_id', j.venue_id, 'venue_name', ven.name, 'status', j.status,
               'plan_name', pl.name, 'message', j.message, 'decision_note', j.decision_note,
               'created_at', j.created_at, 'decided_at', j.decided_at
             ) order by j.created_at desc)
      from public.gym_join_requests j
      join public.venues ven on ven.id = j.venue_id
      left join public.gym_plans pl on pl.id = j.plan_id
      where (j.person_id = v.id or j.user_id = uid) and j.created_at > now() - interval '90 days'
    ), '[]'::jsonb),
    'visits', coalesce((
      select jsonb_agg(jsonb_build_object('venue_name', y.name, 'checked_in_at', y.checked_in_at)
                       order by y.checked_in_at desc)
      from (
        select ven.name, c.checked_in_at
        from public.gym_check_ins c
        join public.venues ven on ven.id = c.venue_id
        where c.gym_member_id in (select g.id from public.gym_members g where g.person_id = v.id)
           or c.member_id = uid
        order by c.checked_in_at desc
        limit 30
      ) y
    ), '[]'::jsonb),
    'today', v_today
  );
end;
$$;

-- Asks to join gym [venue_id], with the package they'd like if they chose
-- one. Its front desk, managers and owner are told. Returns the request.
create or replace function public.gym_request_to_join(venue_id uuid, plan_id uuid default null, message text default null)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  uid uuid := (select auth.uid());
  v_venue public.venues;
  v public.people;
  v_id uuid;
  v_message text := nullif(left(trim(coalesce(gym_request_to_join.message, '')), 500), '');
begin
  if uid is null then
    raise exception 'Sign in to ask to join.';
  end if;
  v_venue := public.gym_require_gym(gym_request_to_join.venue_id);
  if not v_venue.is_verified then
    raise exception '% isn''t taking members on Health Pro yet.', v_venue.name;
  end if;
  v := public.person_for_user(uid);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_venue.id::text || ':' || v.id::text, 0));
  if exists (select 1 from public.gym_members g where g.person_id = v.id and g.venue_id = v_venue.id) then
    raise exception 'You''re already a member of %. Ask the front desk there to renew your package.', v_venue.name;
  end if;
  if exists (select 1 from public.gym_join_requests j
             where j.person_id = v.id and j.venue_id = v_venue.id and j.status = 'pending') then
    raise exception 'You''ve already asked to join %. The front desk will answer soon.', v_venue.name;
  end if;
  if gym_request_to_join.plan_id is not null and not exists (
    select 1 from public.gym_plans p
    where p.id = gym_request_to_join.plan_id and p.venue_id = v_venue.id and p.is_active
  ) then
    raise exception 'Choose one of the gym''s packages.';
  end if;

  insert into public.gym_join_requests (venue_id, person_id, user_id, plan_id, message)
  values (v_venue.id, v.id, uid, gym_request_to_join.plan_id, v_message)
  returning id into v_id;
  perform public.notify_venue_staff(
    v_venue.id, 'gym_membership', 'New request to join',
    public.person_name(v) || ' asked to join ' || v_venue.name || '.',
    '/gyms/' || v_venue.id || '/manage/requests'
  );
  return v_id;
end;
$$;

-- The asker takes their request back.
create or replace function public.gym_cancel_join_request(request_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  update public.gym_join_requests j set status = 'cancelled', decided_at = now()
  where j.id = gym_cancel_join_request.request_id and j.user_id = (select auth.uid()) and j.status = 'pending';
  if not found then
    raise exception 'That request isn''t waiting any more.';
  end if;
end;
$$;

-- The desk says no, with a [note] for them if it likes.
create or replace function public.gym_decline_join_request(request_id uuid, note text default null)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  j public.gym_join_requests;
  v_gym text;
  v_note text := nullif(left(trim(coalesce(gym_decline_join_request.note, '')), 500), '');
begin
  select * into j from public.gym_join_requests r where r.id = gym_decline_join_request.request_id for update;
  if not found or not public.has_venue_permission(j.venue_id, 'gym.register') then
    raise exception 'Only the gym''s staff who register members can answer requests.';
  end if;
  if j.status <> 'pending' then
    raise exception 'That request has been answered already.';
  end if;
  update public.gym_join_requests r set status = 'declined', decision_note = v_note, decided_by = (select auth.uid()),
    decided_at = now()
  where r.id = j.id;
  select v.name into v_gym from public.venues v where v.id = j.venue_id;
  perform public.notify(j.user_id, 'gym_membership', 'Your request to join ' || v_gym,
                        'It wasn''t accepted.' || coalesce(' ' || v_note, ''), '/gyms/my');
end;
$$;

-- What the desk needs to add a person to [venue_id] without typing their
-- details again: from their QR code ([qr_token]) or their request to join
-- ([join_request_id]). The details are those they gave the gym they joined
-- most recently, else their account's. Says so if they're registered here
-- already.
create or replace function public.gym_person_details(venue_id uuid, qr_token text default null,
                                                     join_request_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_person_details.venue_id;
  v public.people;
  j public.gym_join_requests;
  v_last public.gym_members;
  v_here uuid;
  v_profile public.profiles;
  v_details jsonb;
begin
  perform public.gym_require_gym(p_venue);
  if not public.has_venue_permission(p_venue, 'gym.register') then
    raise exception 'Only the gym''s staff who register members can do this.';
  end if;
  if gym_person_details.join_request_id is not null then
    select * into j from public.gym_join_requests r
    where r.id = gym_person_details.join_request_id and r.venue_id = p_venue;
    if not found or j.status <> 'pending' then
      raise exception 'That request isn''t waiting any more.';
    end if;
    select * into v from public.people p where p.id = j.person_id;
    v := public.person_current(v);
  else
    v := public.person_by_token(gym_person_details.qr_token);
  end if;
  if v.id is null then
    raise exception 'This QR code isn''t valid any more.';
  end if;

  select g.id into v_here from public.gym_members g where g.person_id = v.id and g.venue_id = p_venue;
  select * into v_last from public.gym_members g where g.person_id = v.id order by g.updated_at desc limit 1;
  if v_last.id is not null then
    v_details := public.gym_member_details_json(v_last);
  else
    select * into v_profile from public.profiles p where p.id = v.user_id;
    v_details := jsonb_build_object(
      'full_name', public.person_name(v), 'phone', coalesce(v_profile.phone, v.phone),
      'email', coalesce(v_profile.email, v.email)
    );
  end if;
  return jsonb_build_object(
    'person_id', v.id, 'full_name', public.person_name(v), 'details', v_details,
    'gym_member_id', v_here, 'plan_id', j.plan_id, 'message', j.message
  );
end;
$$;

-- Registers a member at [venue_id], as before; and with [person_qr] (the QR
-- code they showed) or [join_request_id] (their request, which this
-- approves), it's that person, already on Health Pro, so their QR code works
-- here too. Otherwise a new person, with a new QR code.
drop function if exists public.gym_register_member(uuid, jsonb, uuid, int, int, text, text);
create or replace function public.gym_register_member(venue_id uuid, details jsonb, plan_id uuid default null,
                                                      months int default null, amount int default 0,
                                                      method text default null, reference text default null,
                                                      person_qr text default null, join_request_id uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_register_member.venue_id;
  v_venue public.venues;
  m public.gym_members;
  v public.people;
  j public.gym_join_requests;
  v_existing_name text;
  v_existing_code text;
  v_existing_until date;
  v_membership jsonb;
begin
  v_venue := public.gym_require_gym(p_venue);
  if not public.has_venue_permission(p_venue, 'gym.register') then
    raise exception 'Only the gym''s staff who register members can do this.';
  end if;

  m := public.gym_member_from_details(details);

  -- Who: the person who asked to join, or whose QR code was shown, or someone new.
  if gym_register_member.join_request_id is not null then
    select * into j from public.gym_join_requests r
    where r.id = gym_register_member.join_request_id and r.venue_id = p_venue
    for update;
    if not found or j.status <> 'pending' then
      raise exception 'That request isn''t waiting any more.';
    end if;
    select * into v from public.people p where p.id = j.person_id;
    v := public.person_current(v);
  elsif nullif(trim(coalesce(gym_register_member.person_qr, '')), '') is not null then
    v := public.person_by_token(gym_register_member.person_qr);
    if v.id is null then
      raise exception 'This QR code isn''t valid any more.';
    end if;
  end if;
  if v.id is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_venue::text || ':' || v.id::text, 0));
    if exists (select 1 from public.gym_members g where g.person_id = v.id and g.venue_id = p_venue) then
      raise exception '% is registered here already. Open their page to renew their package.', public.person_name(v);
    end if;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_venue::text || ':' || m.phone, 0));
  select c.full_name, c.member_code, c.expires_on
    into v_existing_name, v_existing_code, v_existing_until
  from (
    select g.full_name, g.code as member_code, max(s.end_date) as expires_on
    from public.gym_members g
    join public.gym_subscriptions s on s.gym_member_id = g.id
    where g.venue_id = p_venue and g.phone = m.phone
      and s.status = 'active' and s.end_date >= public.bhutan_today()
    group by g.id, g.full_name, g.code
    union all
    select coalesce(nullif(trim(p.full_name), ''), 'Member'), null::text, max(s.end_date)
    from public.profiles p
    join public.gym_subscriptions s on s.member_id = p.id
    where s.venue_id = p_venue and p.phone = m.phone and p.id is distinct from v.user_id
      and s.status = 'active' and s.end_date >= public.bhutan_today()
    group by p.id, p.full_name
  ) c
  order by c.expires_on desc
  limit 1;
  if v_existing_until is not null then
    raise exception 'This phone number belongs to % (%) until %. Register it again after the package expires.',
      v_existing_name, coalesce(v_existing_code, 'account member'), to_char(v_existing_until, 'FMDD Mon YYYY');
  end if;

  if v.id is null then
    insert into public.people (qr_token, full_name, email, phone, created_by)
    values (public.gym_new_qr_token(), m.full_name, m.email, m.phone, (select auth.uid()))
    returning * into v;
  elsif v.user_id is null then
    -- Someone without an account: what the desk writes is all they have.
    update public.people p set full_name = m.full_name, email = coalesce(m.email, p.email), phone = m.phone
    where p.id = v.id
    returning * into v;
  end if;

  m.id := gen_random_uuid();
  m.venue_id := p_venue;
  m.person_id := v.id;
  m.code := public.gym_new_member_code();
  m.qr_token := public.gym_new_qr_token();
  m.created_by := (select auth.uid());
  m.created_at := now();
  m.updated_at := now();
  insert into public.gym_members select m.*;

  if gym_register_member.plan_id is not null then
    v_membership := public.gym_add_membership(m, gym_register_member.plan_id, gym_register_member.months, m.joined_on,
                                              coalesce(gym_register_member.amount, 0), gym_register_member.method,
                                              gym_register_member.reference);
  end if;

  if j.id is not null then
    update public.gym_join_requests r set status = 'approved', gym_member_id = m.id, decided_by = (select auth.uid()),
      decided_at = now()
    where r.id = j.id;
  end if;
  -- Someone with an account sees the gym in their app.
  perform public.notify(v.user_id, 'gym_membership', 'Welcome to ' || v_venue.name,
                        case when j.id is not null then 'Your request to join was approved.'
                             else 'You''re now a member. Show your Health Pro QR code at the front desk.' end,
                        '/gyms/my');

  return jsonb_build_object('gym_member_id', m.id, 'code', m.code, 'qr_token', v.qr_token, 'person_id', v.id,
                            'membership', v_membership);
end;
$$;

-- Changing a member's details: as before, and for a person without an
-- account, their name, phone and email on Health Pro too.
create or replace function public.gym_update_member_person()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.people p set full_name = new.full_name, email = coalesce(new.email, p.email), phone = new.phone
  where p.id = new.person_id and p.user_id is null
    and (p.full_name, p.email, p.phone) is distinct from (new.full_name, coalesce(new.email, p.email), new.phone);
  return new;
end;
$$;
drop trigger if exists gym_members_person_details on public.gym_members;
create trigger gym_members_person_details after update of full_name, email, phone on public.gym_members
  for each row execute function public.gym_update_member_person();

-- A new card: their QR code changes everywhere (it's one code for every
-- gym), and so does this gym's old card. Returns the new QR code.
create or replace function public.gym_reissue_member_qr(gym_member_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_member public.gym_members;
  v_token text := public.gym_new_qr_token();
begin
  select * into v_member from public.gym_members g where g.id = gym_reissue_member_qr.gym_member_id for update;
  if not found then
    raise exception 'This member is no longer registered.';
  end if;
  if not public.has_venue_permission(v_member.venue_id, 'gym.register') then
    raise exception 'Only the gym''s staff who register members can issue cards.';
  end if;
  update public.gym_members g set qr_token = public.gym_new_qr_token() where g.id = v_member.id;
  update public.people p set qr_token = v_token where p.id = v_member.person_id;
  return v_token;
end;
$$;

-- Checks in whoever's QR code this is (their personal one, or a gym's
-- card): where they're registered here, or 'not_member' with what the desk
-- needs to add them.
create or replace function public.gym_check_in_member(venue_id uuid, qr_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_check_in_member.venue_id;
  v public.people;
begin
  perform public.gym_require_gym(p_venue);
  if not public.has_venue_permission(p_venue, 'gym.check_in') then
    raise exception 'Only the gym''s staff can check members in.';
  end if;
  v := public.person_by_token(gym_check_in_member.qr_token);
  return public.gym_check_in_person_at(p_venue, v, v.qr_token);
end;
$$;

-- An account's QR code (from before personal QR codes): checks in its person
-- where they're registered, or by their account membership here.
create or replace function public.gym_check_in_account(venue_id uuid, member_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_check_in_account.venue_id;
  v public.people;
begin
  perform public.gym_require_gym(p_venue);
  if not public.has_venue_permission(p_venue, 'gym.check_in') then
    raise exception 'Only the gym''s staff can check members in.';
  end if;
  select * into v from public.people p where p.user_id = gym_check_in_account.member_id;
  if v.id is null then
    return public.gym_check_in(p_venue, gym_check_in_account.member_id);
  end if;
  return public.gym_check_in_person_at(p_venue, v, v.qr_token);
end;
$$;

-- By the member code typed at the desk: this gym's registered members, then
-- account members (where they're registered, or by account membership).
create or replace function public.gym_check_in_by_code(venue_id uuid, code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_check_in_by_code.venue_id;
  p_code text := upper(regexp_replace(coalesce(gym_check_in_by_code.code, ''), '[\s-]', '', 'g'));
  v_registered public.gym_members;
  v_member uuid;
  v public.people;
  v_here uuid;
begin
  if not public.has_venue_permission(p_venue, 'gym.check_in') then
    raise exception 'Only the gym''s staff can check members in.';
  end if;
  select * into v_registered from public.gym_members g where g.code = p_code;
  if found then
    if v_registered.venue_id <> p_venue then
      raise exception 'Member % is registered at another gym. Scan their Health Pro QR code to add them here.', p_code;
    end if;
    return public.gym_check_in_registered(p_venue, v_registered.id);
  end if;
  select p.id into v_member from public.profiles p where p.member_code = p_code;
  if v_member is null then
    raise exception 'No member has the code %.', p_code;
  end if;
  select * into v from public.people p where p.user_id = v_member;
  select g.id into v_here from public.gym_members g where g.person_id = v.id and g.venue_id = p_venue;
  if v_here is not null then
    return public.gym_check_in_registered(p_venue, v_here);
  end if;
  return public.gym_check_in(p_venue, v_member);
end;
$$;


-- ---------------------------------------------------------------------
-- 5. Who can call which function
-- ---------------------------------------------------------------------

revoke execute on function public.person_current(public.people), public.person_by_token(text),
  public.person_for_user(uuid), public.person_name(public.people),
  public.gym_check_in_person_at(uuid, public.people, text), public.gym_member_details_json(public.gym_members),
  public.gym_update_member_person()
  from public, anon, authenticated;

revoke execute on function public.my_person(), public.my_person_new_qr(), public.my_gyms(),
  public.gym_request_to_join(uuid, uuid, text), public.gym_cancel_join_request(uuid),
  public.gym_decline_join_request(uuid, text), public.gym_person_details(uuid, text, uuid),
  public.gym_register_member(uuid, jsonb, uuid, int, int, text, text, text, uuid),
  public.gym_reissue_member_qr(uuid), public.gym_check_in_member(uuid, text), public.gym_check_in_account(uuid, uuid),
  public.gym_check_in_by_code(uuid, text)
  from public, anon;
grant execute on function public.my_person(), public.my_person_new_qr(), public.my_gyms(),
  public.gym_request_to_join(uuid, uuid, text), public.gym_cancel_join_request(uuid),
  public.gym_decline_join_request(uuid, text), public.gym_person_details(uuid, text, uuid),
  public.gym_register_member(uuid, jsonb, uuid, int, int, text, text, text, uuid),
  public.gym_reissue_member_qr(uuid), public.gym_check_in_member(uuid, text), public.gym_check_in_account(uuid, uuid),
  public.gym_check_in_by_code(uuid, text)
  to authenticated;
