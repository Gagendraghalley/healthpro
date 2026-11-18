-- Enquiries and free trials: people who walked in, phoned or messaged and
-- haven't joined yet, for the desk to follow up and turn into members. Each
-- has how they heard of the gym, what they're after, a free trial (first
-- and last day) if they're on one, and the day to follow up. Registering
-- someone with the same phone number marks their enquiry joined.
--
-- Where one stands: 'open' (following up), 'trial', 'joined', 'lost'. One
-- open or trial enquiry per phone number per gym. Staff who register
-- members ('gym.register') see and keep them. Safe to re-run.

create table if not exists public.gym_enquiries (
  id              uuid primary key default gen_random_uuid(),
  venue_id        uuid not null references public.venues (id) on delete cascade,
  full_name       text not null check (char_length(trim(full_name)) between 2 and 100),
  phone           text not null check (phone ~ '^\+[0-9]{8,15}$'),
  source          text not null default 'walk_in' check (source in ('walk_in', 'phone', 'social', 'friend', 'other')),
  interest        text check (char_length(interest) <= 200), -- what they're after: weight loss, a trainer, evenings
  status          text not null default 'open' check (status in ('open', 'trial', 'joined', 'lost')),
  trial_starts_on date, -- Bhutan dates, both in the trial
  trial_ends_on   date,
  follow_up_on    date,
  notes           text check (char_length(notes) <= 1000),
  gym_member_id   uuid constraint gym_enquiries_gym_member_id_fkey references public.gym_members (id) on delete set null,
  created_by      uuid constraint gym_enquiries_created_by_fkey references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_by      uuid constraint gym_enquiries_updated_by_fkey references public.profiles (id) on delete set null,
  updated_at      timestamptz not null default now(),
  constraint gym_enquiries_trial check ((trial_starts_on is null) = (trial_ends_on is null)
                                        and (trial_ends_on is null or trial_ends_on - trial_starts_on between 0 and 29)),
  constraint gym_enquiries_trial_dates check (status <> 'trial' or trial_starts_on is not null)
);
create unique index if not exists gym_enquiries_one_open on public.gym_enquiries (venue_id, phone)
  where status in ('open', 'trial');
create index if not exists gym_enquiries_venue on public.gym_enquiries (venue_id, created_at desc);

drop trigger if exists gym_enquiries_updated_at on public.gym_enquiries;
create trigger gym_enquiries_updated_at before update on public.gym_enquiries
  for each row execute function public.set_updated_at();

alter table public.gym_enquiries enable row level security;
revoke all on public.gym_enquiries from anon, authenticated;
grant select on public.gym_enquiries to authenticated;
drop policy if exists "gym_enquiries: who registers members" on public.gym_enquiries;
create policy "gym_enquiries: who registers members" on public.gym_enquiries for select to authenticated
  using (public.has_venue_permission(venue_id, 'gym.register'));

-- A new enquiry at [venue_id] ([enquiry_id] null), or changes to one, from
-- [details]: full_name, phone, source, interest, status, trial_starts_on,
-- trial_ends_on, follow_up_on, notes. Returns its id.
create or replace function public.gym_save_enquiry(venue_id uuid, enquiry_id uuid, details jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  d jsonb := coalesce(gym_save_enquiry.details, '{}');
  v_venue uuid := gym_save_enquiry.venue_id;
  v_old public.gym_enquiries;
  v_name text := trim(coalesce(d ->> 'full_name', ''));
  v_phone text := regexp_replace(coalesce(d ->> 'phone', ''), '[\s()-]', '', 'g');
  v_source text := coalesce(nullif(d ->> 'source', ''), 'walk_in');
  v_status text := coalesce(nullif(d ->> 'status', ''), 'open');
  v_interest text := nullif(trim(coalesce(d ->> 'interest', '')), '');
  v_notes text := nullif(trim(coalesce(d ->> 'notes', '')), '');
  v_trial_from date := nullif(d ->> 'trial_starts_on', '')::date;
  v_trial_to date := nullif(d ->> 'trial_ends_on', '')::date;
  v_follow date := nullif(d ->> 'follow_up_on', '')::date;
  v_other public.gym_enquiries;
  v_member public.gym_members;
  v_id uuid;
begin
  if gym_save_enquiry.enquiry_id is not null then
    select * into v_old from public.gym_enquiries e where e.id = gym_save_enquiry.enquiry_id;
    if not found or v_old.venue_id <> v_venue then
      raise exception 'This enquiry isn''t there any more.';
    end if;
  end if;
  if not public.has_venue_permission(v_venue, 'gym.register') then
    raise exception 'Your role here can''t keep enquiries.';
  end if;
  if char_length(v_name) not between 2 and 100 then
    raise exception 'Enter their name.';
  end if;
  if v_phone ~ '^[0-9]{8}$' then
    v_phone := '+975' || v_phone;
  end if;
  if v_phone !~ '^\+[0-9]{8,15}$' then
    raise exception 'Enter their phone number, e.g. 17123456.';
  end if;
  if v_source not in ('walk_in', 'phone', 'social', 'friend', 'other') then
    raise exception 'Choose how they heard of the gym.';
  end if;
  if v_status not in ('open', 'trial', 'joined', 'lost') then
    raise exception 'Choose where it stands.';
  end if;
  if char_length(v_interest) > 200 then
    raise exception 'Keep what they''re after under 200 characters.';
  end if;
  if char_length(v_notes) > 1000 then
    raise exception 'Keep the notes under 1000 characters.';
  end if;
  if v_status = 'trial' and (v_trial_from is null or v_trial_to is null) then
    raise exception 'Give the free trial''s first and last day.';
  end if;
  if (v_trial_from is null) <> (v_trial_to is null) then
    raise exception 'Give the free trial''s first and last day.';
  end if;
  if v_trial_to is not null and v_trial_to - v_trial_from not between 0 and 29 then
    raise exception 'A free trial runs 1 to 30 days.';
  end if;

  if v_status in ('open', 'trial') then
    select * into v_other from public.gym_enquiries e
    where e.venue_id = v_venue and e.phone = v_phone and e.status in ('open', 'trial')
      and e.id is distinct from gym_save_enquiry.enquiry_id
    limit 1;
    if v_other.id is not null then
      raise exception '% is on the enquiries list already, since %. Open theirs instead.', v_other.full_name,
        to_char(v_other.created_at at time zone 'Asia/Thimphu', 'FMDD Mon YYYY');
    end if;
  end if;
  if gym_save_enquiry.enquiry_id is null then
    select * into v_member from public.gym_members g where g.venue_id = v_venue and g.phone = v_phone limit 1;
    if v_member.id is not null then
      raise exception '% (%) is registered here already. Open their page in Members to renew.', v_member.full_name,
        v_member.code;
    end if;
    insert into public.gym_enquiries (venue_id, full_name, phone, source, interest, status, trial_starts_on, trial_ends_on,
                                      follow_up_on, notes, created_by, updated_by)
    values (v_venue, v_name, v_phone, v_source, v_interest, v_status, v_trial_from, v_trial_to, v_follow, v_notes,
            (select auth.uid()), (select auth.uid()))
    returning id into v_id;
    return v_id;
  end if;

  update public.gym_enquiries e
     set full_name = v_name, phone = v_phone, source = v_source, interest = v_interest, status = v_status,
         trial_starts_on = v_trial_from, trial_ends_on = v_trial_to, follow_up_on = v_follow, notes = v_notes,
         updated_by = (select auth.uid())
   where e.id = v_old.id;
  return v_old.id;
end;
$$;

-- Taken off the list (a mistake, or a duplicate).
create or replace function public.gym_delete_enquiry(enquiry_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venue uuid;
begin
  select e.venue_id into v_venue from public.gym_enquiries e where e.id = gym_delete_enquiry.enquiry_id;
  if v_venue is null then
    raise exception 'This enquiry isn''t there any more.';
  end if;
  if not public.has_venue_permission(v_venue, 'gym.register') then
    raise exception 'Your role here can''t keep enquiries.';
  end if;
  delete from public.gym_enquiries e where e.id = gym_delete_enquiry.enquiry_id;
end;
$$;

-- Registered: their enquiry (same phone, same gym) has joined.
create or replace function public.gym_enquiries_joined()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.gym_enquiries e
     set status = 'joined', gym_member_id = new.id, updated_by = (select auth.uid())
   where e.venue_id = new.venue_id and e.phone = new.phone and e.status <> 'joined';
  return null;
end;
$$;

drop trigger if exists gym_members_enquiry_joined on public.gym_members;
create trigger gym_members_enquiry_joined after insert on public.gym_members
  for each row execute function public.gym_enquiries_joined();

revoke execute on function public.gym_enquiries_joined() from public, anon, authenticated;
revoke execute on function public.gym_save_enquiry(uuid, uuid, jsonb), public.gym_delete_enquiry(uuid) from public, anon;
grant execute on function public.gym_save_enquiry(uuid, uuid, jsonb), public.gym_delete_enquiry(uuid) to authenticated;
