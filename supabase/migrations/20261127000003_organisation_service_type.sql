-- =====================================================================
-- Every organisation has a service type
-- =====================================================================
-- An organisation (the business behind its venues) says what kind of
-- service it is: one of the Service types (venue_types). The team chooses
-- it when making one (Admin -> Organisations -> New organisation); one made
-- for a newly registered venue takes the venue's type. Those already here
-- take the type most of their venues have (a gym without any).
-- save_organisation takes it, and needs it for a new organisation.
-- Safe to re-run.
-- =====================================================================

alter table public.organisations
  add column if not exists venue_type text references public.venue_types (key) on delete set null;

update public.organisations o
set venue_type = coalesce(
  (select v.type from public.venues v where v.organisation_id = o.id group by v.type order by count(*) desc, v.type limit 1),
  'gym')
where o.venue_type is null;

-- An organisation made for a new venue (venues_own_organisation) takes its
-- type.
create or replace function public.venues_type_to_organisation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.organisations o set venue_type = new.type
  where o.id = new.organisation_id and o.venue_type is null;
  return null;
end;
$$;
revoke execute on function public.venues_type_to_organisation() from public, anon, authenticated;

drop trigger if exists venues_type_to_organisation on public.venues;
create trigger venues_type_to_organisation after insert on public.venues
  for each row execute function public.venues_type_to_organisation();

-- From 20261111000001_organisations_and_roles.sql, with [service_type]: a
-- service type key, needed for a new organisation; null keeps an existing
-- one's.
drop function if exists public.save_organisation(uuid, text, text);
create or replace function public.save_organisation(organisation_id uuid, name text, description text default null,
                                                    service_type text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_id uuid := save_organisation.organisation_id;
  p_name text := regexp_replace(trim(coalesce(save_organisation.name, '')), '\s+', ' ', 'g');
  p_description text := nullif(trim(save_organisation.description), '');
  p_type text := nullif(trim(save_organisation.service_type), '');
  v_id uuid;
begin
  if not public.has_permission('organisations.manage') then
    raise exception 'Only people who manage organisations can change them.';
  end if;
  if char_length(p_name) not between 2 and 100 then
    raise exception 'Enter the organisation''s name (2 to 100 letters).';
  end if;
  if p_id is null and p_type is null then
    raise exception 'Choose its service type.';
  end if;
  if p_type is not null and not exists (
    select 1 from public.venue_types t
    where t.key = p_type
      and (t.is_active or exists (select 1 from public.organisations o where o.id = p_id and o.venue_type = p_type))
  ) then
    raise exception 'Choose one of the service types in use.';
  end if;
  if p_id is null then
    insert into public.organisations (name, description, venue_type, created_by)
    values (p_name, p_description, p_type, (select auth.uid()))
    returning organisations.id into v_id;
  else
    update public.organisations o
    set name = p_name, description = p_description, venue_type = coalesce(p_type, o.venue_type)
    where o.id = p_id returning o.id into v_id;
    if v_id is null then
      raise exception 'This organisation no longer exists.';
    end if;
  end if;
  return v_id;
end;
$$;

revoke execute on function public.save_organisation(uuid, text, text, text) from public, anon;
grant execute on function public.save_organisation(uuid, text, text, text) to authenticated;
