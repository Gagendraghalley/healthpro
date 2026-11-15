-- Health Pro, phase 3: a venue's public profile, and finding a gym.
--
-- - venues: an email, a contact person, opening hours (each day: closed, or
--   one or two periods, e.g. 6-10 am and 4-9 pm), facilities (the module's
--   own, e.g. a gym's shower and massage, and any of the venue's), video
--   links (YouTube, Facebook) and up to 30 photos. Its place on the map
--   (latitude, longitude) can now be set.
-- - gym_price_ranges(): each verified gym's lowest and highest package
--   price, for the list of gyms (sort by price, a budget). Worked out from
--   the packages, so it's never out of date.
-- - Reviews: anyone a venue has registered (a gym's member, with their
--   account), not only those who paid with their account.
--
-- Safe to run again.


-- ---------------------------------------------------------------------
-- 1. Columns
-- ---------------------------------------------------------------------

alter table public.venues add column if not exists email text
  check (char_length(email) <= 320 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$');
alter table public.venues add column if not exists contact_person text check (char_length(contact_person) <= 100);
-- {"mon": [["06:00", "10:00"], ["16:00", "21:00"]], "sun": []}: a day not
-- there isn't known; an empty list is closed.
alter table public.venues add column if not exists opening_hours jsonb check (jsonb_typeof(opening_hours) = 'object');
alter table public.venues add column if not exists facilities text[] not null default '{}'
  check (cardinality(facilities) <= 40);
alter table public.venues add column if not exists videos text[] not null default '{}'
  check (cardinality(videos) <= 10);

-- More photos: up to 30.
alter table public.venues drop constraint if exists venues_photos_check;
alter table public.venues add constraint venues_photos_check check (cardinality(photos) <= 30);


-- ---------------------------------------------------------------------
-- 2. Helpers (not callable by the app)
-- ---------------------------------------------------------------------

-- [hours] checked and tidied: the days of the week only, each closed ([])
-- or one or two periods, opening before closing, the second after the first.
create or replace function public.venue_clean_hours(hours jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_out jsonb := '{}'::jsonb;
  v_day text;
  v_periods jsonb;
  v_period jsonb;
  v_last text;
begin
  if hours is null or jsonb_typeof(hours) = 'null' then
    return null;
  end if;
  if jsonb_typeof(hours) <> 'object' then
    raise exception 'Enter the opening hours day by day.';
  end if;
  for v_day, v_periods in select * from jsonb_each(hours) loop
    if v_day not in ('mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun') then
      raise exception 'Enter the opening hours day by day.';
    end if;
    if jsonb_typeof(v_periods) <> 'array' or jsonb_array_length(v_periods) > 2 then
      raise exception 'Each day can have up to two opening times.';
    end if;
    v_last := null;
    for v_period in select * from jsonb_array_elements(v_periods) loop
      if jsonb_typeof(v_period) <> 'array' or jsonb_array_length(v_period) <> 2
         or (v_period ->> 0) !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
         or (v_period ->> 1) !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$|^24:00$' then
        raise exception 'Enter the opening times as HH:MM.';
      end if;
      if (v_period ->> 0) >= (v_period ->> 1) then
        raise exception 'Each opening time must close after it opens.';
      end if;
      if v_last is not null and (v_period ->> 0) <= v_last then
        raise exception 'A day''s second opening time must start after the first ends.';
      end if;
      v_last := v_period ->> 1;
    end loop;
    v_out := v_out || jsonb_build_object(v_day, v_periods);
  end loop;
  return v_out;
end;
$$;

-- [list] tidied: trimmed, 2 to 40 letters each, no repeats.
create or replace function public.venue_clean_facilities(list jsonb)
returns text[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text[];
begin
  if list is null or jsonb_typeof(list) <> 'array' then
    return '{}';
  end if;
  select coalesce(array_agg(f order by n), '{}') into v
  from (
    select distinct on (lower(f)) f, n
    from (select regexp_replace(trim(e), '\s+', ' ', 'g') as f, n
          from jsonb_array_elements_text(list) with ordinality as t(e, n)) x
    where f <> ''
    order by lower(f), n
  ) y;
  if exists (select 1 from unnest(v) f where char_length(f) not between 2 and 40) then
    raise exception 'Keep each facility between 2 and 40 letters.';
  end if;
  if cardinality(v) > 40 then
    raise exception 'Up to 40 facilities.';
  end if;
  return v;
end;
$$;

-- [list] of video links: YouTube or Facebook, up to 10.
create or replace function public.venue_clean_videos(list jsonb)
returns text[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text[];
begin
  if list is null or jsonb_typeof(list) <> 'array' then
    return '{}';
  end if;
  select coalesce(array_agg(trim(e) order by n), '{}') into v
  from jsonb_array_elements_text(list) with ordinality as t(e, n)
  where trim(e) <> '';
  if exists (select 1 from unnest(v) u
             where char_length(u) > 300
                or u !~* '^https://([a-z0-9-]+\.)?(youtube\.com|youtu\.be|facebook\.com|fb\.watch)/') then
    raise exception 'Add videos as YouTube or Facebook links.';
  end if;
  if cardinality(v) > 10 then
    raise exception 'Up to 10 videos.';
  end if;
  return v;
end;
$$;

-- A place on the map, checked: both or neither, within Bhutan's reach.
create or replace function public.venue_check_location(lat double precision, lng double precision)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if (lat is null) <> (lng is null) then
    raise exception 'Choose the place on the map.';
  end if;
  if lat is not null and (lat not between 26 and 29 or lng not between 88 and 93) then
    raise exception 'That place isn''t in Bhutan. Choose it on the map.';
  end if;
end;
$$;


-- ---------------------------------------------------------------------
-- 3. Functions the app calls
-- ---------------------------------------------------------------------

-- Registers a venue, as before, with the rest of its profile if given.
create or replace function public.register_venue(details jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_details jsonb := register_venue.details;
  v_user uuid := (select auth.uid());
  v_type text := p_details ->> 'type';
  v_id uuid;
  v_name text;
  v_lat double precision := (p_details ->> 'latitude')::double precision;
  v_lng double precision := (p_details ->> 'longitude')::double precision;
begin
  if v_user is null then
    raise exception 'Please sign in first.';
  end if;
  if not exists (
    select 1 from public.venue_types t join public.app_modules m on m.key = t.module_key
    where t.key = v_type and (m.is_enabled or public.is_admin())
  ) then
    raise exception 'Venues of this kind can''t be registered yet.';
  end if;
  if (select count(*) from public.venue_staff s join public.venues v on v.id = s.venue_id
      where s.user_id = v_user and s.role = 'owner' and v.verification_status = 'pending') >= 3 then
    raise exception 'You already have 3 venues waiting for verification. Wait for the Health Pro team first.';
  end if;
  perform public.venue_check_location(v_lat, v_lng);

  insert into public.venues (type, name, description, dzongkhag, town, address, phone, whatsapp, payment_info,
                             cancellation_policy, email, contact_person, latitude, longitude, opening_hours,
                             facilities, videos, created_by)
  values (
    v_type,
    trim(p_details ->> 'name'),
    nullif(trim(p_details ->> 'description'), ''),
    p_details ->> 'dzongkhag',
    nullif(trim(p_details ->> 'town'), ''),
    nullif(trim(p_details ->> 'address'), ''),
    nullif(trim(p_details ->> 'phone'), ''),
    nullif(trim(p_details ->> 'whatsapp'), ''),
    nullif(trim(p_details ->> 'payment_info'), ''),
    nullif(trim(p_details ->> 'cancellation_policy'), ''),
    nullif(lower(trim(p_details ->> 'email')), ''),
    nullif(regexp_replace(trim(coalesce(p_details ->> 'contact_person', '')), '\s+', ' ', 'g'), ''),
    v_lat,
    v_lng,
    public.venue_clean_hours(p_details -> 'opening_hours'),
    public.venue_clean_facilities(p_details -> 'facilities'),
    public.venue_clean_videos(p_details -> 'videos'),
    v_user
  )
  returning venues.id, venues.name into v_id, v_name;

  insert into public.venue_staff (venue_id, user_id, role, added_by) values (v_id, v_user, 'owner', v_user);

  perform public.notify_admins('New venue to verify', v_name || ' (' || v_type || ') was sent for verification.',
                               '/admin/venues');
  return v_id;
end;
$$;

-- Changes a venue, as before, and the rest of its profile. Photos, videos,
-- facilities and opening hours don't send a venue that was sent back for
-- checking again; its details do.
create or replace function public.update_venue(venue_id uuid, details jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := update_venue.venue_id;
  p_details jsonb := update_venue.details;
  v_venue public.venues;
  v_photos text[];
  v_resubmit boolean;
  v_lat double precision;
  v_lng double precision;
begin
  if not public.has_venue_permission(p_venue, 'venue.edit') then
    raise exception 'Only people who can edit this venue can change it.';
  end if;
  select * into v_venue from public.venues v where v.id = p_venue for update;
  if not found then
    raise exception 'This venue no longer exists.';
  end if;
  v_resubmit := v_venue.verification_status = 'rejected'
                and exists (select 1 from jsonb_object_keys(p_details) k
                            where k not in ('photos', 'videos', 'facilities', 'opening_hours'));

  if p_details ? 'photos' then
    v_photos := array(select jsonb_array_elements_text(p_details -> 'photos'));
    if exists (select 1 from unnest(v_photos) u where u !~ '^https://') then
      raise exception 'Photos must be uploaded to Health Pro.';
    end if;
    if cardinality(v_photos) > 30 then
      raise exception 'Up to 30 photos.';
    end if;
  end if;
  v_lat := case when p_details ? 'latitude' then (p_details ->> 'latitude')::double precision else v_venue.latitude end;
  v_lng := case when p_details ? 'longitude' then (p_details ->> 'longitude')::double precision else v_venue.longitude end;
  perform public.venue_check_location(v_lat, v_lng);

  update public.venues v set
    name                = case when p_details ? 'name' then trim(p_details ->> 'name') else v.name end,
    description         = case when p_details ? 'description' then nullif(trim(p_details ->> 'description'), '') else v.description end,
    dzongkhag           = case when p_details ? 'dzongkhag' then p_details ->> 'dzongkhag' else v.dzongkhag end,
    town                = case when p_details ? 'town' then nullif(trim(p_details ->> 'town'), '') else v.town end,
    address             = case when p_details ? 'address' then nullif(trim(p_details ->> 'address'), '') else v.address end,
    phone               = case when p_details ? 'phone' then nullif(trim(p_details ->> 'phone'), '') else v.phone end,
    whatsapp            = case when p_details ? 'whatsapp' then nullif(trim(p_details ->> 'whatsapp'), '') else v.whatsapp end,
    latitude            = v_lat,
    longitude           = v_lng,
    photos              = case when p_details ? 'photos' then v_photos else v.photos end,
    payment_info        = case when p_details ? 'payment_info' then nullif(trim(p_details ->> 'payment_info'), '') else v.payment_info end,
    cancellation_policy = case when p_details ? 'cancellation_policy' then nullif(trim(p_details ->> 'cancellation_policy'), '') else v.cancellation_policy end,
    email               = case when p_details ? 'email' then nullif(lower(trim(p_details ->> 'email')), '') else v.email end,
    contact_person      = case when p_details ? 'contact_person'
                               then nullif(regexp_replace(trim(coalesce(p_details ->> 'contact_person', '')), '\s+', ' ', 'g'), '')
                               else v.contact_person end,
    opening_hours       = case when p_details ? 'opening_hours' then public.venue_clean_hours(p_details -> 'opening_hours') else v.opening_hours end,
    facilities          = case when p_details ? 'facilities' then public.venue_clean_facilities(p_details -> 'facilities') else v.facilities end,
    videos              = case when p_details ? 'videos' then public.venue_clean_videos(p_details -> 'videos') else v.videos end,
    verification_status = case when v_resubmit then 'pending' else v.verification_status end
  where v.id = p_venue;

  if v_resubmit then
    perform public.notify_admins('Venue sent again', v_venue.name || ' was changed and sent for verification again.',
                                 '/admin/venues');
  end if;
end;
$$;

-- Each verified gym's lowest and highest package price (packages on sale),
-- for everyone, signed in or not.
create or replace function public.gym_price_ranges()
returns table (venue_id uuid, lowest int, highest int)
language sql
stable
security definer
set search_path = ''
as $$
  select p.venue_id, min(p.price), max(p.price)
  from public.gym_plans p
  join public.venues v on v.id = p.venue_id
  where p.is_active and v.is_verified
  group by p.venue_id;
$$;

-- The signed-in person has used [venue]: paid there with their account, or
-- the venue registered them (a gym's member). They may review it.
create or replace function public.has_used_venue(venue uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.payments p
    where p.venue_id = venue and p.user_id = (select auth.uid()) and p.status = 'completed'
  ) or exists (
    select 1 from public.gym_members g join public.people x on x.id = g.person_id
    where g.venue_id = venue and x.user_id = (select auth.uid())
  );
$$;


-- ---------------------------------------------------------------------
-- 4. Who can call which function
-- ---------------------------------------------------------------------

revoke execute on function public.venue_clean_hours(jsonb), public.venue_clean_facilities(jsonb),
  public.venue_clean_videos(jsonb), public.venue_check_location(double precision, double precision)
  from public, anon, authenticated;
revoke execute on function public.gym_price_ranges() from public;
grant execute on function public.gym_price_ranges() to anon, authenticated;
