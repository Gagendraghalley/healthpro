-- =====================================================================
-- Service types: how each one's card looks on Services
-- =====================================================================
-- The Service types master (venue_types, 20261127000001) also keeps, for
-- its card on the Services page:
--   - color: one of the app's palette keys (orange, blue, green, teal,
--     violet, amber, pink, red) for its icon tile, arrow and count;
--   - photo: a cover photo, uploaded to the public service-type-photos
--     bucket by whoever keeps the master data;
--   - show_when_empty: off keeps the card hidden until the first
--     organisation of the type is verified (on: it says Coming soon).
-- save_venue_type takes them too. Safe to re-run; colours the team has
-- chosen are kept.
-- =====================================================================

alter table public.venue_types
  add column if not exists color text,
  add column if not exists photo text,
  add column if not exists show_when_empty boolean not null default true;

alter table public.venue_types drop constraint if exists venue_types_color_key;
alter table public.venue_types add constraint venue_types_color_key check (color ~ '^[a-z]{2,20}$');
alter table public.venue_types drop constraint if exists venue_types_photo_url;
alter table public.venue_types add constraint venue_types_photo_url
  check (char_length(photo) <= 500 and photo ~ '^https?://');

-- A colour each to start with, where none is chosen yet.
update public.venue_types t set color = c.color
from (values ('gym', 'orange'), ('fitness_centre', 'violet'), ('swimming', 'blue'), ('cycling', 'green'),
             ('sports_facility', 'amber'), ('wellness_centre', 'teal')) as c(key, color)
where t.key = c.key and t.color is null;


-- ---------------------------------------------------------------------
-- Cover photos: anyone sees them; whoever keeps the master data uploads,
-- replaces and removes them (a folder per type).
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('service-type-photos', 'service-type-photos', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

drop policy if exists "service-type-photos: master keepers upload" on storage.objects;
create policy "service-type-photos: master keepers upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'service-type-photos' and public.has_permission('masters.manage'));
drop policy if exists "service-type-photos: master keepers replace" on storage.objects;
create policy "service-type-photos: master keepers replace" on storage.objects for update to authenticated
  using (bucket_id = 'service-type-photos' and public.has_permission('masters.manage'))
  with check (bucket_id = 'service-type-photos' and public.has_permission('masters.manage'));
drop policy if exists "service-type-photos: master keepers remove" on storage.objects;
create policy "service-type-photos: master keepers remove" on storage.objects for delete to authenticated
  using (bucket_id = 'service-type-photos' and public.has_permission('masters.manage'));


-- ---------------------------------------------------------------------
-- Saving a type, with its card's colour, photo and Coming soon
-- ---------------------------------------------------------------------

-- From 20261127000001_organisation_types.sql, with details' color, photo
-- (null or '' for none) and show_when_empty (default true).
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
  v_color text := nullif(trim(coalesce(d ->> 'color', '')), '');
  v_photo text := nullif(trim(coalesce(d ->> 'photo', '')), '');
  v_show_empty boolean := coalesce((d ->> 'show_when_empty')::boolean, true);
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
  if v_color !~ '^[a-z]{2,20}$' then
    raise exception 'Choose a colour.';
  end if;
  if char_length(v_photo) > 500 or v_photo !~ '^https?://' then
    raise exception 'Upload the cover photo again.';
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
    insert into public.venue_types (key, module_key, name, description, icon, facilities, sort_order, is_active, color,
                                    photo, show_when_empty)
    values (p_key, 'gym_membership', v_name, v_description, v_icon, v_facilities, v_order, v_active, v_color, v_photo,
            v_show_empty);
  else
    if exists (select 1 from public.venue_types t where lower(t.name) = lower(v_name) and t.key <> p_key) then
      raise exception 'There is already a type called %.', v_name;
    end if;
    update public.venue_types t
    set name = v_name, description = v_description, icon = v_icon, facilities = v_facilities, sort_order = v_order,
        is_active = v_active, color = v_color, photo = v_photo, show_when_empty = v_show_empty
    where t.key = p_key;
    if not found then
      raise exception 'This type no longer exists.';
    end if;
  end if;
  return p_key;
end;
$$;

revoke execute on function public.save_venue_type(text, jsonb) from public, anon;
grant execute on function public.save_venue_type(text, jsonb) to authenticated;
