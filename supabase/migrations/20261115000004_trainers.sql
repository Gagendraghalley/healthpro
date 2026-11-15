-- Health Pro, phase 4: trainers.
--
-- - trainer_profiles: a trainer's one profile on Health Pro (their account),
--   with their certificates (trainer_certificates; files in the public
--   trainer-media bucket). Public once a gym has verified them.
-- - gym_trainers: a trainer asks to train at a gym; that gym checks them
--   and verifies them, or not. Each gym on its own: one saying no doesn't
--   touch the others.
-- - trainer_slots: their week, gym by gym (days and times). A gym sees its
--   own times and the trainer's others only as 'Not available'
--   (trainer_timings), never the other gym's name.
-- - trainer_check_ins: each gym takes its trainers' attendance. The front
--   desk scans the trainer's Health Pro QR code when they arrive, as for
--   members; a trainer verified there is recorded as arriving, not checked
--   in as a member. Each gym sees only its own record; the trainer sees all
--   of them, gym by gym.
-- - trainer_links: which trainer a member has at a gym, over time. The
--   member chooses one, or the front desk assigns one (at check-in, or on
--   their page); the old and the new trainer are told.
-- - trainer_reviews: only members who have trained with a trainer review
--   them (stars and a comment), shown on their profile; no replies.
--
-- Safe to run again.


-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

create table if not exists public.trainer_profiles (
  user_id          uuid primary key constraint trainer_profiles_user_id_fkey references public.profiles (id) on delete cascade,
  display_name     text not null check (char_length(trim(display_name)) between 2 and 100),
  headline         text check (char_length(headline) <= 80), -- 'Strength and conditioning coach'
  bio              text check (char_length(bio) <= 2000),
  specialties      text[] not null default '{}' check (cardinality(specialties) <= 15),
  experience_years int check (experience_years between 0 and 60),
  photo_url        text check (photo_url ~ '^https://'),
  rating_average   numeric(3, 2),
  rating_count     int not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table if not exists public.trainer_certificates (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.trainer_profiles (user_id) on delete cascade,
  title      text not null check (char_length(trim(title)) between 2 and 120),
  issuer     text check (char_length(issuer) <= 120),
  issued_on  date check (issued_on >= '1950-01-01'),
  file_url   text check (file_url ~ '^https://'),
  created_at timestamptz not null default now()
);
create index if not exists trainer_certificates_user_idx on public.trainer_certificates (user_id);

create table if not exists public.gym_trainers (
  venue_id      uuid not null references public.venues (id) on delete cascade,
  user_id       uuid not null references public.trainer_profiles (user_id) on delete cascade,
  status        text not null default 'pending' check (status in ('pending', 'verified', 'rejected', 'left')),
  message       text check (char_length(message) <= 500),  -- the trainer's note to the gym
  decision_note text check (char_length(decision_note) <= 500),
  requested_at  timestamptz not null default now(),
  decided_at    timestamptz,
  decided_by    uuid constraint gym_trainers_decided_by_fkey references public.profiles (id) on delete set null,
  primary key (venue_id, user_id)
);
create index if not exists gym_trainers_user_idx on public.gym_trainers (user_id);

create table if not exists public.trainer_slots (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid not null,
  venue_id  uuid not null,
  weekday   smallint not null check (weekday between 1 and 7), -- Monday 1 to Sunday 7
  starts_at time not null,
  ends_at   time not null,
  constraint trainer_slots_order check (ends_at > starts_at),
  constraint trainer_slots_gym foreign key (venue_id, user_id) references public.gym_trainers (venue_id, user_id) on delete cascade
);
create index if not exists trainer_slots_user_idx on public.trainer_slots (user_id, weekday);

create table if not exists public.trainer_check_ins (
  id            uuid primary key default gen_random_uuid(),
  venue_id      uuid not null references public.venues (id) on delete cascade,
  user_id       uuid not null constraint trainer_check_ins_user_id_fkey references public.profiles (id) on delete cascade,
  checked_in_at timestamptz not null default now(),
  recorded_by   uuid constraint trainer_check_ins_recorded_by_fkey references public.profiles (id) on delete set null
);
create index if not exists trainer_check_ins_venue_idx on public.trainer_check_ins (venue_id, checked_in_at desc);
create index if not exists trainer_check_ins_user_idx on public.trainer_check_ins (user_id, checked_in_at desc);

create table if not exists public.trainer_links (
  id            uuid primary key default gen_random_uuid(),
  gym_member_id uuid not null references public.gym_members (id) on delete cascade,
  venue_id      uuid not null references public.venues (id) on delete cascade,
  trainer_id    uuid not null constraint trainer_links_trainer_id_fkey references public.profiles (id) on delete cascade,
  started_at    timestamptz not null default now(),
  ended_at      timestamptz,
  set_by        uuid constraint trainer_links_set_by_fkey references public.profiles (id) on delete set null
);
-- One trainer at a time per member per gym.
create unique index if not exists trainer_links_one_current on public.trainer_links (gym_member_id) where ended_at is null;
create index if not exists trainer_links_trainer_idx on public.trainer_links (trainer_id, venue_id);

create table if not exists public.trainer_reviews (
  id            uuid primary key default gen_random_uuid(),
  trainer_id    uuid not null references public.trainer_profiles (user_id) on delete cascade,
  user_id       uuid not null constraint trainer_reviews_user_id_fkey references public.profiles (id) on delete cascade,
  reviewer_name text not null default '',
  rating        int not null check (rating between 1 and 5),
  comment       text check (char_length(comment) <= 1000),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint trainer_reviews_one_per_user unique (trainer_id, user_id)
);

drop trigger if exists trainer_profiles_updated_at on public.trainer_profiles;
create trigger trainer_profiles_updated_at before update on public.trainer_profiles
  for each row execute function public.set_updated_at();
drop trigger if exists trainer_reviews_updated_at on public.trainer_reviews;
create trigger trainer_reviews_updated_at before update on public.trainer_reviews
  for each row execute function public.set_updated_at();

-- 'gym.trainers': checking trainers who ask to train here, and their
-- attendance. The roles that run the desk have it to start with.
do $$
declare
  v_new boolean;
begin
  with saved as (
    insert into public.permissions (key, scope, module_key, name, description, sort_order)
    values ('gym.trainers', 'venue', 'gym_membership', 'Trainers',
            'Verify trainers who ask to train here, see their timings and attendance', 106)
    on conflict (key) do update
      set name = excluded.name, description = excluded.description, sort_order = excluded.sort_order
    returning (xmax = 0) as inserted
  )
  select inserted into v_new from saved;
  if v_new then
    insert into public.role_permissions (role_id, permission_key)
    select r.id, 'gym.trainers' from public.roles r where r.key in ('owner', 'manager', 'staff')
    on conflict do nothing;
  end if;
end;
$$;


-- ---------------------------------------------------------------------
-- 2. Who can read what (changes go through the functions below)
-- ---------------------------------------------------------------------

-- Gym staff who check trainers ([perm] at a gym they asked to train at).
create or replace function public.trainer_asked_my_gym(trainer uuid, perm text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.gym_trainers g
                 where g.user_id = trainer and public.has_venue_permission(g.venue_id, perm));
$$;

-- Verified at a gym somewhere: their profile is public.
create or replace function public.trainer_is_public(trainer uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.gym_trainers g where g.user_id = trainer and g.status = 'verified');
$$;

alter table public.trainer_profiles enable row level security;
revoke all on public.trainer_profiles from anon, authenticated;
grant select on public.trainer_profiles to anon, authenticated;
drop policy if exists "trainer_profiles: public once verified" on public.trainer_profiles;
create policy "trainer_profiles: public once verified" on public.trainer_profiles for select to anon
  using (public.trainer_is_public(user_id));
drop policy if exists "trainer_profiles: theirs, and the gyms they asked" on public.trainer_profiles;
create policy "trainer_profiles: theirs, and the gyms they asked" on public.trainer_profiles for select to authenticated
  using (user_id = (select auth.uid()) or public.trainer_is_public(user_id)
         or public.trainer_asked_my_gym(user_id, 'gym.trainers'));

alter table public.trainer_certificates enable row level security;
revoke all on public.trainer_certificates from anon, authenticated;
grant select on public.trainer_certificates to anon, authenticated;
drop policy if exists "trainer_certificates: public once verified" on public.trainer_certificates;
create policy "trainer_certificates: public once verified" on public.trainer_certificates for select to anon
  using (public.trainer_is_public(user_id));
drop policy if exists "trainer_certificates: as the profile" on public.trainer_certificates;
create policy "trainer_certificates: as the profile" on public.trainer_certificates for select to authenticated
  using (user_id = (select auth.uid()) or public.trainer_is_public(user_id)
         or public.trainer_asked_my_gym(user_id, 'gym.trainers'));

alter table public.gym_trainers enable row level security;
revoke all on public.gym_trainers from anon, authenticated;
grant select on public.gym_trainers to anon, authenticated;
-- Verified ones are public (a gym's trainers, a trainer's gyms); the rest
-- for the trainer and the gym that checks them.
drop policy if exists "gym_trainers: verified for all" on public.gym_trainers;
create policy "gym_trainers: verified for all" on public.gym_trainers for select to anon using (status = 'verified');
drop policy if exists "gym_trainers: the trainer and the gym" on public.gym_trainers;
create policy "gym_trainers: the trainer and the gym" on public.gym_trainers for select to authenticated
  using (status = 'verified' or user_id = (select auth.uid()) or public.has_venue_permission(venue_id, 'gym.trainers'));

-- Times: the trainer's own, and each gym its own. Everyone else, and a
-- gym's view of the others, through trainer_timings().
alter table public.trainer_slots enable row level security;
revoke all on public.trainer_slots from anon, authenticated;
grant select on public.trainer_slots to authenticated;
drop policy if exists "trainer_slots: the trainer and the gym" on public.trainer_slots;
create policy "trainer_slots: the trainer and the gym" on public.trainer_slots for select to authenticated
  using (user_id = (select auth.uid()) or public.has_venue_permission(venue_id, 'gym.trainers'));

-- Attendance: each gym its own; the trainer all of theirs.
alter table public.trainer_check_ins enable row level security;
revoke all on public.trainer_check_ins from anon, authenticated;
grant select on public.trainer_check_ins to authenticated;
drop policy if exists "trainer_check_ins: the trainer and the gym" on public.trainer_check_ins;
create policy "trainer_check_ins: the trainer and the gym" on public.trainer_check_ins for select to authenticated
  using (user_id = (select auth.uid())
         or public.has_venue_permission(venue_id, 'gym.trainers')
         or public.has_venue_permission(venue_id, 'gym.check_in'));

alter table public.trainer_links enable row level security;
revoke all on public.trainer_links from anon, authenticated;
grant select on public.trainer_links to authenticated;
drop policy if exists "trainer_links: the trainer and the gym" on public.trainer_links;
create policy "trainer_links: the trainer and the gym" on public.trainer_links for select to authenticated
  using (trainer_id = (select auth.uid()) or public.has_venue_permission(venue_id, 'gym.members'));

alter table public.trainer_reviews enable row level security;
revoke all on public.trainer_reviews from anon, authenticated;
grant select on public.trainer_reviews to anon, authenticated;
drop policy if exists "trainer_reviews: everyone" on public.trainer_reviews;
create policy "trainer_reviews: everyone" on public.trainer_reviews for select to anon, authenticated using (true);

-- Trainers' photos and certificates: public (they're on their profile), in
-- a folder named after their account, which only they change.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('trainer-media', 'trainer-media', true, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do nothing;
drop policy if exists "trainer-media: their own folder" on storage.objects;
create policy "trainer-media: their own folder" on storage.objects for insert to authenticated
  with check (bucket_id = 'trainer-media' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "trainer-media: they replace their own" on storage.objects;
create policy "trainer-media: they replace their own" on storage.objects for update to authenticated
  using (bucket_id = 'trainer-media' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'trainer-media' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "trainer-media: they remove their own" on storage.objects;
create policy "trainer-media: they remove their own" on storage.objects for delete to authenticated
  using (bucket_id = 'trainer-media' and (storage.foldername(name))[1] = (select auth.uid())::text);


-- ---------------------------------------------------------------------
-- 3. Helpers (not callable by the app)
-- ---------------------------------------------------------------------

-- [trainer] is verified to train at [venue].
create or replace function public.gym_trainer_verified(venue uuid, trainer uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.gym_trainers g
                 where g.venue_id = venue and g.user_id = trainer and g.status = 'verified');
$$;

-- A trainer's name on Health Pro.
create or replace function public.trainer_name(trainer uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select t.display_name from public.trainer_profiles t where t.user_id = trainer),
                  (select nullif(trim(p.full_name), '') from public.profiles p where p.id = trainer), 'Trainer');
$$;

-- Records trainer [trainer] arriving at [venue], and says so for the desk:
-- their times there today, how many times they came today already, and
-- whether they're also a member here (to check them in as one instead).
create or replace function public.gym_trainer_arrived(venue uuid, trainer uuid, token text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_today date := public.bhutan_today();
  v_earlier int;
  v_member boolean;
begin
  select count(*) into v_earlier from public.trainer_check_ins c
  where c.venue_id = venue and c.user_id = trainer and (c.checked_in_at at time zone 'Asia/Thimphu')::date = v_today;
  insert into public.trainer_check_ins (venue_id, user_id, recorded_by) values (venue, trainer, (select auth.uid()));
  select exists (select 1 from public.gym_members g join public.people p on p.id = g.person_id
                 where g.venue_id = venue and p.user_id = trainer) into v_member;
  return jsonb_build_object(
    'trainer', true,
    'member_name', public.trainer_name(trainer),
    'trainer_id', trainer,
    'photo_url', (select t.photo_url from public.trainer_profiles t where t.user_id = trainer),
    'earlier_today', v_earlier,
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

-- Keeps a trainer's rating in step with their reviews.
create or replace function public.refresh_trainer_rating()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trainer uuid := coalesce(new.trainer_id, old.trainer_id);
begin
  update public.trainer_profiles t set
    rating_average = (select round(avg(r.rating)::numeric, 2) from public.trainer_reviews r where r.trainer_id = v_trainer),
    rating_count   = (select count(*) from public.trainer_reviews r where r.trainer_id = v_trainer)
  where t.user_id = v_trainer;
  return null;
end;
$$;
drop trigger if exists trainer_reviews_refresh_rating on public.trainer_reviews;
create trigger trainer_reviews_refresh_rating after insert or update or delete on public.trainer_reviews
  for each row execute function public.refresh_trainer_rating();


-- ---------------------------------------------------------------------
-- 4. Functions the app calls: the trainer
-- ---------------------------------------------------------------------

-- The signed-in person's trainer profile, made or changed.
create or replace function public.trainer_save_profile(details jsonb)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  d jsonb := coalesce(details, '{}'::jsonb);
  v_name text := regexp_replace(trim(coalesce(d ->> 'display_name', '')), '\s+', ' ', 'g');
  v_specialties text[];
  v_years int;
begin
  if uid is null then
    raise exception 'Sign in first.';
  end if;
  if char_length(v_name) not between 2 and 100 then
    raise exception 'Enter your name as members should see it.';
  end if;
  select coalesce(array_agg(distinct s), '{}') into v_specialties
  from (select regexp_replace(trim(e), '\s+', ' ', 'g') as s from jsonb_array_elements_text(coalesce(d -> 'specialties', '[]')) e) x
  where s <> '';
  if cardinality(v_specialties) > 15 or exists (select 1 from unnest(v_specialties) s where char_length(s) > 40) then
    raise exception 'Up to 15 specialties, each up to 40 letters.';
  end if;
  begin
    v_years := nullif(d ->> 'experience_years', '')::int;
  exception when others then
    raise exception 'Enter your years of experience as a number.';
  end;
  if v_years is not null and v_years not between 0 and 60 then
    raise exception 'Enter your years of experience (0 to 60).';
  end if;
  if nullif(d ->> 'photo_url', '') is not null and (d ->> 'photo_url') !~ '^https://' then
    raise exception 'Upload your photo to Health Pro.';
  end if;
  insert into public.trainer_profiles (user_id, display_name, headline, bio, specialties, experience_years, photo_url)
  values (uid, v_name, nullif(left(trim(coalesce(d ->> 'headline', '')), 80), ''),
          nullif(trim(coalesce(d ->> 'bio', '')), ''), v_specialties, v_years, nullif(d ->> 'photo_url', ''))
  on conflict (user_id) do update
    set display_name = excluded.display_name, headline = excluded.headline, bio = excluded.bio,
        specialties = excluded.specialties, experience_years = excluded.experience_years, photo_url = excluded.photo_url;
end;
$$;

-- A certificate on the signed-in trainer's profile. Returns it.
create or replace function public.trainer_add_certificate(title text, issuer text default null, issued_on date default null,
                                                          file_url text default null)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  uid uuid := (select auth.uid());
  v_id uuid;
begin
  if not exists (select 1 from public.trainer_profiles t where t.user_id = uid) then
    raise exception 'Make your trainer profile first.';
  end if;
  if char_length(trim(coalesce(trainer_add_certificate.title, ''))) not between 2 and 120 then
    raise exception 'Enter the certificate''s name.';
  end if;
  if trainer_add_certificate.issued_on > public.bhutan_today() then
    raise exception 'Check the date it was issued.';
  end if;
  if nullif(trainer_add_certificate.file_url, '') is not null
     and trainer_add_certificate.file_url !~ ('^https://.*/trainer-media/' || uid::text || '/') then
    raise exception 'Upload the certificate to Health Pro.';
  end if;
  if (select count(*) from public.trainer_certificates c where c.user_id = uid) >= 20 then
    raise exception 'Up to 20 certificates.';
  end if;
  insert into public.trainer_certificates (user_id, title, issuer, issued_on, file_url)
  values (uid, trim(trainer_add_certificate.title), nullif(left(trim(coalesce(trainer_add_certificate.issuer, '')), 120), ''),
          trainer_add_certificate.issued_on, nullif(trainer_add_certificate.file_url, ''))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.trainer_remove_certificate(certificate_id uuid)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  delete from public.trainer_certificates c where c.id = certificate_id and c.user_id = (select auth.uid());
$$;

-- Asks gym [venue_id] to let the signed-in trainer train there; its staff
-- who check trainers are told.
create or replace function public.trainer_request_gym(venue_id uuid, message text default null)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  uid uuid := (select auth.uid());
  v_venue public.venues;
  v_now public.gym_trainers;
begin
  if not exists (select 1 from public.trainer_profiles t where t.user_id = uid) then
    raise exception 'Make your trainer profile first.';
  end if;
  v_venue := public.gym_require_gym(trainer_request_gym.venue_id);
  if not v_venue.is_verified then
    raise exception '% isn''t on Health Pro yet.', v_venue.name;
  end if;
  select * into v_now from public.gym_trainers g where g.venue_id = v_venue.id and g.user_id = uid for update;
  if v_now.status = 'verified' then
    raise exception 'You''re a trainer at % already.', v_venue.name;
  elsif v_now.status = 'pending' then
    raise exception 'You''ve asked % already. They''ll let you know.', v_venue.name;
  end if;
  insert into public.gym_trainers (venue_id, user_id, status, message)
  values (v_venue.id, uid, 'pending', nullif(left(trim(coalesce(trainer_request_gym.message, '')), 500), ''))
  on conflict (venue_id, user_id) do update
    set status = 'pending', message = excluded.message, requested_at = now(), decided_at = null,
        decided_by = null, decision_note = null;
  perform public.notify_venue_permission(v_venue.id, 'gym.trainers', 'gym_membership', 'New trainer request',
    public.trainer_name(uid) || ' asked to train at ' || v_venue.name || '. Check their certificates.',
    '/gyms/' || v_venue.id || '/manage/trainers');
end;
$$;

-- The signed-in trainer stops training at [venue_id] (or takes their
-- request back): their times there go, and so do their members there.
create or replace function public.trainer_leave_gym(venue_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  uid uuid := (select auth.uid());
begin
  update public.gym_trainers g set status = 'left', decided_at = now()
  where g.venue_id = trainer_leave_gym.venue_id and g.user_id = uid and g.status in ('pending', 'verified');
  if not found then
    raise exception 'You don''t train there.';
  end if;
  delete from public.trainer_slots s where s.venue_id = trainer_leave_gym.venue_id and s.user_id = uid;
  update public.trainer_links l set ended_at = now()
  where l.venue_id = trainer_leave_gym.venue_id and l.trainer_id = uid and l.ended_at is null;
end;
$$;

-- The signed-in trainer's week at [venue_id] ([slots]: weekday 1-7,
-- 'HH:MM' start and end), replacing what was there. They can't overlap
-- each other, nor the trainer's times at other gyms.
create or replace function public.trainer_save_slots(venue_id uuid, slots jsonb)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  uid uuid := (select auth.uid());
  p_venue uuid := trainer_save_slots.venue_id;
  s jsonb;
  v_days int[] := '{}';
  v_from time[] := '{}';
  v_to time[] := '{}';
  v_day int;
  v_start time;
  v_end time;
  v_clash record;
begin
  if not exists (select 1 from public.gym_trainers g
                 where g.venue_id = p_venue and g.user_id = uid and g.status in ('pending', 'verified')) then
    raise exception 'Ask the gym to let you train there first.';
  end if;
  if jsonb_typeof(coalesce(slots, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(slots, '[]'::jsonb)) > 50 then
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

  if exists (select 1
             from unnest(v_days, v_from, v_to) with ordinality a(d, f, t, i)
             join unnest(v_days, v_from, v_to) with ordinality b(d, f, t, i)
               on a.i < b.i and a.d = b.d and a.f < b.t and b.f < a.t) then
    raise exception 'Two of your times here overlap.';
  end if;
  select n.d, n.f, n.t into v_clash
  from unnest(v_days, v_from, v_to) n(d, f, t)
  where exists (select 1 from public.trainer_slots o
                where o.user_id = uid and o.venue_id <> p_venue and o.weekday = n.d
                  and o.starts_at < n.t and n.f < o.ends_at)
  limit 1;
  if found then
    raise exception 'That overlaps your time at another gym (% %–%).',
      (array['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])[v_clash.d], to_char(v_clash.f, 'HH24:MI'), to_char(v_clash.t, 'HH24:MI');
  end if;

  delete from public.trainer_slots t where t.venue_id = p_venue and t.user_id = uid;
  insert into public.trainer_slots (user_id, venue_id, weekday, starts_at, ends_at)
  select uid, p_venue, n.d, n.f, n.t from unnest(v_days, v_from, v_to) n(d, f, t);
end;
$$;

-- A trainer's week at the gyms that verified them; seen from gym [venue]
-- (its page, its staff), the other gyms' times are only 'Not available',
-- without their names. Anyone, signed in or not.
create or replace function public.trainer_timings(trainer uuid, venue uuid default null)
returns table (weekday int, starts_at text, ends_at text, venue_id uuid, venue_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select s.weekday::int, to_char(s.starts_at, 'HH24:MI'), to_char(s.ends_at, 'HH24:MI'),
         case when venue is null or s.venue_id = venue then s.venue_id end,
         case when venue is null or s.venue_id = venue then v.name end
  from public.trainer_slots s
  join public.gym_trainers g on g.venue_id = s.venue_id and g.user_id = s.user_id and g.status = 'verified'
  join public.venues v on v.id = s.venue_id
  where s.user_id = trainer
  order by s.weekday, s.starts_at;
$$;

-- Everything the signed-in trainer has: their profile, certificates, each
-- gym (where they stand, their week there, their attendance there and
-- their members there), and their reviews.
create or replace function public.my_trainer_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
begin
  if not exists (select 1 from public.trainer_profiles t where t.user_id = uid) then
    return jsonb_build_object('profile', null);
  end if;
  return jsonb_build_object(
    'profile', (select to_jsonb(t) from public.trainer_profiles t where t.user_id = uid),
    'certificates', coalesce((select jsonb_agg(to_jsonb(c) order by c.issued_on desc nulls last, c.created_at desc)
                              from public.trainer_certificates c where c.user_id = uid), '[]'::jsonb),
    'gyms', coalesce((
      select jsonb_agg(jsonb_build_object(
               'venue_id', g.venue_id, 'venue_name', v.name, 'place', concat_ws(', ', v.town, v.dzongkhag),
               'status', g.status, 'decision_note', g.decision_note, 'requested_at', g.requested_at,
               'slots', coalesce((select jsonb_agg(jsonb_build_object('weekday', s.weekday,
                                                                      'starts', to_char(s.starts_at, 'HH24:MI'),
                                                                      'ends', to_char(s.ends_at, 'HH24:MI'))
                                                   order by s.weekday, s.starts_at)
                                  from public.trainer_slots s where s.venue_id = g.venue_id and s.user_id = uid), '[]'::jsonb),
               'attendance', coalesce((select jsonb_agg(c.checked_in_at order by c.checked_in_at desc)
                                       from (select c.checked_in_at from public.trainer_check_ins c
                                             where c.venue_id = g.venue_id and c.user_id = uid
                                             order by c.checked_in_at desc limit 60) c), '[]'::jsonb),
               'attendance_30_days', (select count(*) from public.trainer_check_ins c
                                      where c.venue_id = g.venue_id and c.user_id = uid
                                        and c.checked_in_at > now() - interval '30 days'),
               'members', coalesce((select jsonb_agg(jsonb_build_object('name', m.full_name, 'since', l.started_at)
                                                     order by l.started_at desc)
                                    from public.trainer_links l join public.gym_members m on m.id = l.gym_member_id
                                    where l.venue_id = g.venue_id and l.trainer_id = uid and l.ended_at is null), '[]'::jsonb)
             ) order by (g.status = 'verified') desc, v.name)
      from public.gym_trainers g join public.venues v on v.id = g.venue_id
      where g.user_id = uid and g.status <> 'left'
    ), '[]'::jsonb),
    'reviews', coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc)
                         from public.trainer_reviews r where r.trainer_id = uid), '[]'::jsonb)
  );
end;
$$;


-- ---------------------------------------------------------------------
-- 5. Functions the app calls: the gym
-- ---------------------------------------------------------------------

-- The gym verifies trainer [user_id] ([approve]), or doesn't, with [note]
-- for them. They're told. Not verified: their times there and their
-- members there go.
create or replace function public.gym_decide_trainer(venue_id uuid, user_id uuid, approve boolean, note text default null)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_decide_trainer.venue_id;
  p_user uuid := gym_decide_trainer.user_id;
  v_note text := nullif(left(trim(coalesce(gym_decide_trainer.note, '')), 500), '');
  v_gym text;
begin
  if not public.has_venue_permission(p_venue, 'gym.trainers') then
    raise exception 'Only the gym''s staff who check trainers can do this.';
  end if;
  update public.gym_trainers g
  set status = case when gym_decide_trainer.approve then 'verified' else 'rejected' end,
      decision_note = v_note, decided_at = now(), decided_by = (select auth.uid())
  where g.venue_id = p_venue and g.user_id = p_user and g.status in ('pending', 'verified');
  if not found then
    raise exception 'That trainer hasn''t asked to train here.';
  end if;
  if not gym_decide_trainer.approve then
    delete from public.trainer_slots s where s.venue_id = p_venue and s.user_id = p_user;
    update public.trainer_links l set ended_at = now()
    where l.venue_id = p_venue and l.trainer_id = p_user and l.ended_at is null;
  end if;
  select v.name into v_gym from public.venues v where v.id = p_venue;
  perform public.notify(p_user, 'gym_membership',
    case when gym_decide_trainer.approve then 'You''re verified at ' || v_gym else v_gym || ' didn''t verify you' end,
    case when gym_decide_trainer.approve then 'You can train there now. Add your times there.'
         else coalesce(v_note, 'Ask them why, or add more certificates.') end,
    '/gyms/trainer');
end;
$$;

-- The gym's trainers, for its staff: each one's profile, where they stand,
-- their week (here; elsewhere only as Not available), their attendance here
-- and their members here.
create or replace function public.gym_trainers_overview(venue_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_trainers_overview.venue_id;
begin
  if not public.has_venue_permission(p_venue, 'gym.trainers') then
    raise exception 'Only the gym''s staff who check trainers can see this.';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'user_id', g.user_id, 'status', g.status, 'message', g.message, 'decision_note', g.decision_note,
             'requested_at', g.requested_at, 'decided_at', g.decided_at,
             'profile', to_jsonb(t),
             'certificates', coalesce((select jsonb_agg(to_jsonb(c) order by c.issued_on desc nulls last)
                                       from public.trainer_certificates c where c.user_id = g.user_id), '[]'::jsonb),
             'slots', coalesce((select jsonb_agg(jsonb_build_object('weekday', s.weekday,
                                                                    'starts', to_char(s.starts_at, 'HH24:MI'),
                                                                    'ends', to_char(s.ends_at, 'HH24:MI'),
                                                                    'here', s.venue_id = p_venue)
                                                 order by s.weekday, s.starts_at)
                                from public.trainer_slots s
                                join public.gym_trainers o on o.venue_id = s.venue_id and o.user_id = s.user_id
                                where s.user_id = g.user_id and (s.venue_id = p_venue or o.status = 'verified')), '[]'::jsonb),
             'attendance', coalesce((select jsonb_agg(c.checked_in_at order by c.checked_in_at desc)
                                     from (select c.checked_in_at from public.trainer_check_ins c
                                           where c.venue_id = p_venue and c.user_id = g.user_id
                                           order by c.checked_in_at desc limit 60) c), '[]'::jsonb),
             'attendance_30_days', (select count(*) from public.trainer_check_ins c
                                    where c.venue_id = p_venue and c.user_id = g.user_id
                                      and c.checked_in_at > now() - interval '30 days'),
             'members', (select count(*) from public.trainer_links l
                         where l.venue_id = p_venue and l.trainer_id = g.user_id and l.ended_at is null)
           ) order by case g.status when 'pending' then 0 when 'verified' then 1 else 2 end, t.display_name)
    from public.gym_trainers g join public.trainer_profiles t on t.user_id = g.user_id
    where g.venue_id = p_venue and g.status <> 'left'
  ), '[]'::jsonb);
end;
$$;

-- [gym_member_id]'s trainer at their gym becomes [trainer_id] (null: none).
-- The member themselves chooses (with their account), or the desk assigns
-- one. The old and the new trainer are told, and the member if the desk
-- chose.
create or replace function public.gym_set_member_trainer(gym_member_id uuid, trainer_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  uid uuid := (select auth.uid());
  m public.gym_members;
  v_member_user uuid;
  v_old uuid;
  v_gym text;
  v_by_member boolean;
begin
  select * into m from public.gym_members g where g.id = gym_set_member_trainer.gym_member_id for update;
  if not found then
    raise exception 'This member is no longer registered.';
  end if;
  select p.user_id into v_member_user from public.people p where p.id = m.person_id;
  v_by_member := v_member_user is not null and v_member_user = uid;
  if not v_by_member and not public.has_venue_permission(m.venue_id, 'gym.check_in') then
    raise exception 'Only the member, or the gym''s front desk, can choose their trainer.';
  end if;
  if gym_set_member_trainer.trainer_id is not null then
    if not public.gym_trainer_verified(m.venue_id, gym_set_member_trainer.trainer_id) then
      raise exception 'Choose one of the gym''s verified trainers.';
    end if;
    if gym_set_member_trainer.trainer_id = v_member_user then
      raise exception 'A trainer can''t train themselves.';
    end if;
  end if;
  select l.trainer_id into v_old from public.trainer_links l where l.gym_member_id = m.id and l.ended_at is null;
  if v_old is not distinct from gym_set_member_trainer.trainer_id then
    return;
  end if;
  update public.trainer_links l set ended_at = now() where l.gym_member_id = m.id and l.ended_at is null;
  if gym_set_member_trainer.trainer_id is not null then
    insert into public.trainer_links (gym_member_id, venue_id, trainer_id, set_by)
    values (m.id, m.venue_id, gym_set_member_trainer.trainer_id, uid);
  end if;

  select v.name into v_gym from public.venues v where v.id = m.venue_id;
  perform public.notify(v_old, 'gym_membership', 'Trainer changed',
    m.full_name || ' at ' || v_gym || ' has another trainer now.', '/gyms/trainer');
  perform public.notify(gym_set_member_trainer.trainer_id, 'gym_membership',
    case when v_old is null then 'New member' else 'Trainer changed' end,
    m.full_name || ' at ' || v_gym || case when v_by_member then ' chose you as their trainer.' else ' was given to you as their trainer.' end,
    '/gyms/trainer');
  if not v_by_member and gym_set_member_trainer.trainer_id is not null then
    perform public.notify(v_member_user, 'gym_membership', 'Your trainer at ' || v_gym,
      public.trainer_name(gym_set_member_trainer.trainer_id) || ' is your trainer now. You can change it in My gyms.', '/gyms/my');
  end if;
end;
$$;

-- The signed-in member reviews trainer [trainer_id]: only if they've
-- trained with them (had them as their trainer at a gym). The trainer is
-- told.
create or replace function public.save_trainer_review(trainer_id uuid, rating int, comment text default null)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  uid uuid := (select auth.uid());
  p_trainer uuid := save_trainer_review.trainer_id;
  v_comment text := nullif(left(trim(coalesce(save_trainer_review.comment, '')), 1000), '');
  v_name text;
begin
  if uid is null then
    raise exception 'Please sign in first.';
  end if;
  if save_trainer_review.rating is null or save_trainer_review.rating not between 1 and 5 then
    raise exception 'Give 1 to 5 stars.';
  end if;
  if p_trainer = uid then
    raise exception 'You can''t review yourself.';
  end if;
  if not exists (select 1 from public.trainer_links l
                 join public.gym_members g on g.id = l.gym_member_id
                 join public.people p on p.id = g.person_id
                 where l.trainer_id = p_trainer and p.user_id = uid) then
    raise exception 'Only members who have trained with them can review a trainer.';
  end if;
  select coalesce(nullif(trim(p.full_name), ''), 'Member') into v_name from public.profiles p where p.id = uid;
  insert into public.trainer_reviews (trainer_id, user_id, reviewer_name, rating, comment)
  values (p_trainer, uid, v_name, save_trainer_review.rating, v_comment)
  on conflict on constraint trainer_reviews_one_per_user do update
    set rating = excluded.rating, comment = excluded.comment, reviewer_name = excluded.reviewer_name;
  perform public.notify(p_trainer, 'gym_membership', 'New review: ' || save_trainer_review.rating || ' stars',
                        v_comment, '/gyms/trainer');
end;
$$;

create or replace function public.delete_my_trainer_review(trainer_id uuid)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  delete from public.trainer_reviews r where r.trainer_id = delete_my_trainer_review.trainer_id and r.user_id = (select auth.uid());
$$;

-- Whether the signed-in person may review trainer [trainer]: they've had
-- them as their trainer.
create or replace function public.can_review_trainer(trainer uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select trainer <> (select auth.uid()) and exists (
    select 1 from public.trainer_links l
    join public.gym_members g on g.id = l.gym_member_id
    join public.people p on p.id = g.person_id
    where l.trainer_id = trainer and p.user_id = (select auth.uid()));
$$;


-- ---------------------------------------------------------------------
-- 6. The desk: a trainer's QR code records their arrival
-- ---------------------------------------------------------------------

-- Whoever's QR code this is: a trainer verified here arrives (attendance);
-- anyone else is checked in as before, or is 'not_member'. With
-- [as_member], a trainer who is also a member here is checked in as one.
drop function if exists public.gym_check_in_member(uuid, text);
create or replace function public.gym_check_in_member(venue_id uuid, qr_token text, as_member boolean default false)
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
  if v.user_id is not null and not coalesce(gym_check_in_member.as_member, false)
     and public.gym_trainer_verified(p_venue, v.user_id) then
    return public.gym_trainer_arrived(p_venue, v.user_id, v.qr_token);
  end if;
  return public.gym_check_in_person_at(p_venue, v, v.qr_token);
end;
$$;

-- An account's old QR code: a trainer verified here arrives; anyone else as
-- before.
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
  if public.gym_trainer_verified(p_venue, gym_check_in_account.member_id) then
    return public.gym_trainer_arrived(p_venue, gym_check_in_account.member_id, v.qr_token);
  end if;
  if v.id is null then
    return public.gym_check_in(p_venue, gym_check_in_account.member_id);
  end if;
  return public.gym_check_in_person_at(p_venue, v, v.qr_token);
end;
$$;

-- By a typed member code: as before, and a trainer's account code records
-- their arrival.
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
  if public.gym_trainer_verified(p_venue, v_member) then
    return public.gym_trainer_arrived(p_venue, v_member, v.qr_token);
  end if;
  select g.id into v_here from public.gym_members g where g.person_id = v.id and g.venue_id = p_venue;
  if v_here is not null then
    return public.gym_check_in_registered(p_venue, v_here);
  end if;
  return public.gym_check_in(p_venue, v_member);
end;
$$;


-- ---------------------------------------------------------------------
-- 7. A member's gyms, with their trainer at each
-- ---------------------------------------------------------------------

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
                 'phone', ven.phone, 'member_code', g.code, 'joined_on', g.joined_on, 'gym_member_id', g.id,
                 'plan_name', s.plan_name, 'start_date', s.start_date, 'end_date', s.end_date,
                 'last_visit', (select max(c.checked_in_at) from public.gym_check_ins c where c.gym_member_id = g.id),
                 'payment_qr_path', (select st.payment_qr_path from public.gym_settings st where st.venue_id = ven.id),
                 'payment_info', ven.payment_info,
                 'claim', (select jsonb_build_object('id', c.id, 'status', c.status, 'plan_name', c.plan_name,
                                                     'months', c.months, 'amount', c.amount, 'jrn', c.jrn,
                                                     'decision_note', c.decision_note, 'created_at', c.created_at,
                                                     'decided_at', c.decided_at)
                           from public.gym_payment_claims c
                           where c.gym_member_id = g.id and c.status <> 'cancelled'
                             and (c.status = 'pending' or c.decided_at > now() - interval '30 days')
                           order by (c.status = 'pending') desc, c.created_at desc
                           limit 1),
                 'trainer', (select jsonb_build_object('id', l.trainer_id, 'name', public.trainer_name(l.trainer_id),
                                                       'photo_url', t.photo_url)
                             from public.trainer_links l
                             left join public.trainer_profiles t on t.user_id = l.trainer_id
                             where l.gym_member_id = g.id and l.ended_at is null)
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
                                where c.member_id = uid and c.venue_id = ven.id),
                 'payment_info', ven.payment_info
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


-- ---------------------------------------------------------------------
-- 8. Who can call which function
-- ---------------------------------------------------------------------

revoke execute on function public.gym_trainer_verified(uuid, uuid), public.trainer_name(uuid),
  public.gym_trainer_arrived(uuid, uuid, text), public.refresh_trainer_rating()
  from public, anon, authenticated;
revoke execute on function public.trainer_asked_my_gym(uuid, text), public.trainer_is_public(uuid) from public;
grant execute on function public.trainer_asked_my_gym(uuid, text), public.trainer_is_public(uuid) to anon, authenticated;

revoke execute on function public.trainer_save_profile(jsonb), public.trainer_add_certificate(text, text, date, text),
  public.trainer_remove_certificate(uuid), public.trainer_request_gym(uuid, text), public.trainer_leave_gym(uuid),
  public.trainer_save_slots(uuid, jsonb), public.my_trainer_overview(), public.gym_decide_trainer(uuid, uuid, boolean, text),
  public.gym_trainers_overview(uuid), public.gym_set_member_trainer(uuid, uuid), public.save_trainer_review(uuid, int, text),
  public.delete_my_trainer_review(uuid), public.can_review_trainer(uuid),
  public.gym_check_in_member(uuid, text, boolean), public.gym_check_in_account(uuid, uuid),
  public.gym_check_in_by_code(uuid, text), public.my_gyms()
  from public, anon;
grant execute on function public.trainer_save_profile(jsonb), public.trainer_add_certificate(text, text, date, text),
  public.trainer_remove_certificate(uuid), public.trainer_request_gym(uuid, text), public.trainer_leave_gym(uuid),
  public.trainer_save_slots(uuid, jsonb), public.my_trainer_overview(), public.gym_decide_trainer(uuid, uuid, boolean, text),
  public.gym_trainers_overview(uuid), public.gym_set_member_trainer(uuid, uuid), public.save_trainer_review(uuid, int, text),
  public.delete_my_trainer_review(uuid), public.can_review_trainer(uuid),
  public.gym_check_in_member(uuid, text, boolean), public.gym_check_in_account(uuid, uuid),
  public.gym_check_in_by_code(uuid, text), public.my_gyms()
  to authenticated;
revoke execute on function public.trainer_timings(uuid, uuid) from public;
grant execute on function public.trainer_timings(uuid, uuid) to anon, authenticated;
