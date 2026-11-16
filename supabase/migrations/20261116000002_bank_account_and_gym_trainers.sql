-- Health Pro: the gym's bank account for paying online, and trainers the
-- gym adds itself.
--
-- Paying online
-- - A gym uploads the bank-issued payment QR and sets up the matching bank
--   account (bank, account number, account name) in Membership settings.
--   Payment screens show that QR with the amount and account details.
-- - Until the account and QR are set up, members can't pay online: gym_claim_payment
--   refuses, and my_gyms() gives no 'payment_account'. Cash at the desk works
--   as before.
-- - Kept for the RMA payment gateway, which comes later: gym_settings says
--   how the gym is paid online (online_provider: 'bank_account' now,
--   'rma_gateway' then, with its merchant id), and each payment says how it
--   came (gym_payment_claims.channel, gateway_reference). A gateway payment
--   will be confirmed by the gateway's answer instead of by the desk; it
--   ends in the same gym_renew_member.
--
-- Trainers
-- - A trainer still joins from the public side: they make their profile and
--   ask a gym, which checks them (gym_trainers.source 'request').
-- - The gym can also add a trainer itself, with all their details (source
--   'gym'): gym_add_trainer makes their trainer profile if they have none
--   (name, what they do, about, specialties, experience, photo,
--   certificates), verifies them here straight away and sets their week.
--   Their account is made first by the admin-users Edge Function (by email;
--   an email that has an account already is that trainer). A trainer who has
--   a profile already keeps it as it is: the gym only adds them here.
-- - The gym's staff who check trainers can change a trainer's times here
--   (gym_save_trainer_slots), and record their arrival without their QR
--   code (gym_trainer_mark_arrived).
--
-- Safe to run again.


-- ---------------------------------------------------------------------
-- 1. Paying online: the gym's bank account
-- ---------------------------------------------------------------------

alter table public.gym_settings add column if not exists bank_name text check (char_length(bank_name) between 2 and 60);
alter table public.gym_settings add column if not exists account_number text check (account_number ~ '^[0-9]{6,20}$');
alter table public.gym_settings add column if not exists account_name text check (char_length(account_name) between 2 and 100);
-- How the gym is paid online. 'rma_gateway' isn't offered yet.
alter table public.gym_settings add column if not exists online_provider text not null default 'bank_account'
  check (online_provider in ('bank_account', 'rma_gateway'));
alter table public.gym_settings add column if not exists gateway_merchant_id text check (char_length(gateway_merchant_id) <= 100);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'gym_settings_account_whole') then
    alter table public.gym_settings add constraint gym_settings_account_whole
      check ((bank_name is null) = (account_number is null) and (bank_name is null) = (account_name is null));
  end if;
end;
$$;

-- How a payment came: the member paid into the gym's account and gave the
-- journal number (the desk confirms it), or, later, through the gateway
-- (its own reference; confirmed by the gateway).
alter table public.gym_payment_claims add column if not exists channel text not null default 'bank_account'
  check (channel in ('bank_account', 'rma_gateway'));
alter table public.gym_payment_claims add column if not exists gateway_reference text check (char_length(gateway_reference) <= 100);

-- A gym's settings, or the defaults.
create or replace function public.gym_settings_of(venue uuid)
returns public.gym_settings
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v public.gym_settings;
begin
  select * into v from public.gym_settings s where s.venue_id = venue;
  if not found then
    v.venue_id := venue;
    v.reminder_days := '{3}';
    v.join_approval := 'desk';
    v.online_provider := 'bank_account';
  end if;
  return v;
end;
$$;

-- The account a gym is paid into, for the QR code; null until it's set up.
create or replace function public.gym_payment_account(venue uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('bank_name', s.bank_name, 'account_number', s.account_number, 'account_name', s.account_name)
  from public.gym_settings s
  where s.venue_id = venue and s.account_number is not null and s.payment_qr_path is not null;
$$;

-- The gym's settings: whoever edits the gym (venue.edit). The bank account
-- is all three (bank, number, name) or none (payments at the desk only).
drop function if exists public.gym_save_settings(uuid, text, int[], text);
drop function if exists public.gym_save_settings(uuid, text, text, text, int[], text);
create or replace function public.gym_save_settings(venue_id uuid, bank_name text, account_number text, account_name text,
                                                    payment_qr_path text, reminder_days int[], join_approval text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_save_settings.venue_id;
  p_bank text := nullif(regexp_replace(trim(coalesce(gym_save_settings.bank_name, '')), '\s+', ' ', 'g'), '');
  p_number text := nullif(regexp_replace(coalesce(gym_save_settings.account_number, ''), '[\s-]', '', 'g'), '');
  p_name text := nullif(regexp_replace(trim(coalesce(gym_save_settings.account_name, '')), '\s+', ' ', 'g'), '');
  p_qr text := nullif(trim(coalesce(gym_save_settings.payment_qr_path, '')), '');
  v_days int[];
begin
  perform public.gym_require_gym(p_venue);
  if not public.has_venue_permission(p_venue, 'venue.edit') then
    raise exception 'Only those who edit the gym can change its settings.';
  end if;
  if p_bank is not null or p_number is not null or p_name is not null then
    if p_bank is null or p_number is null or p_name is null then
      raise exception 'Enter the bank, the account number and the account name.';
    end if;
    if char_length(p_bank) not between 2 and 60 then
      raise exception 'Choose the bank.';
    end if;
    if p_number !~ '^[0-9]{6,20}$' then
      raise exception 'Enter the account number: 6 to 20 digits.';
    end if;
    if char_length(p_name) not between 2 and 100 then
      raise exception 'Enter the account name, as the bank has it.';
    end if;
  end if;
  select coalesce(array_agg(distinct d order by d desc), '{}') into v_days
  from unnest(coalesce(gym_save_settings.reminder_days, '{}')) d;
  if exists (select 1 from unnest(v_days) d where d not between 1 and 60) then
    raise exception 'Reminders can be 1 to 60 days before a package ends.';
  end if;
  if cardinality(v_days) > 5 then
    raise exception 'Choose up to 5 reminders.';
  end if;
  if coalesce(gym_save_settings.join_approval, '') not in ('desk', 'managers') then
    raise exception 'Choose who answers requests to join.';
  end if;
  if p_qr is not null and (p_qr !~ ('^' || p_venue::text || '/[0-9A-Za-z._-]{1,100}$')) then
    raise exception 'Upload a QR image for this gym.';
  end if;
  insert into public.gym_settings (venue_id, bank_name, account_number, account_name, payment_qr_path, reminder_days, join_approval, updated_by)
  values (p_venue, p_bank, p_number, p_name, p_qr, v_days, gym_save_settings.join_approval, (select auth.uid()))
  on conflict (venue_id) do update
    set bank_name = excluded.bank_name, account_number = excluded.account_number, account_name = excluded.account_name,
        payment_qr_path = excluded.payment_qr_path,
        reminder_days = excluded.reminder_days, join_approval = excluded.join_approval, updated_by = excluded.updated_by;
end;
$$;

-- A member says they paid online, as before; only once the gym has set up
-- its bank account.
create or replace function public.gym_claim_payment(venue_id uuid, plan_id uuid, months int, amount int, jrn text)
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
  v_member public.gym_members;
  v_plan public.gym_plans;
  v_jrn text := upper(regexp_replace(coalesce(gym_claim_payment.jrn, ''), '\s', '', 'g'));
  v_id uuid;
begin
  if uid is null then
    raise exception 'Sign in to pay.';
  end if;
  v_venue := public.gym_require_gym(gym_claim_payment.venue_id);
  if public.gym_payment_account(v_venue.id) is null then
    raise exception '% hasn''t set up its bank account for online payments yet. Pay at the front desk.', v_venue.name;
  end if;
  v := public.person_for_user(uid);
  select * into v_member from public.gym_members g where g.person_id = v.id and g.venue_id = v_venue.id;
  if not found then
    raise exception 'You''re not a member of % yet. Ask to join first.', v_venue.name;
  end if;
  perform 1 from public.gym_members g where g.id = v_member.id for update;
  select * into v_plan from public.gym_plans p where p.id = gym_claim_payment.plan_id and p.venue_id = v_venue.id;
  if not found or not v_plan.is_active then
    raise exception 'Choose one of the gym''s packages.';
  end if;
  if gym_claim_payment.months is null or gym_claim_payment.months not between 1 and 24 then
    raise exception 'Choose how many months (1 to 24).';
  end if;
  if gym_claim_payment.amount is null or gym_claim_payment.amount not between 1 and 1000000 then
    raise exception 'Enter the amount you paid.';
  end if;
  if v_jrn !~ '^[0-9A-Z/-]{4,40}$' then
    raise exception 'Enter the journal number (JRN) from your bank''s receipt.';
  end if;
  if exists (select 1 from public.gym_payment_claims c where c.gym_member_id = v_member.id and c.status = 'pending') then
    raise exception 'You''ve sent a payment already. Wait for % to confirm it, or take it back.', v_venue.name;
  end if;
  if exists (select 1 from public.gym_payment_claims c
             where c.venue_id = v_venue.id and c.jrn = v_jrn and c.status in ('pending', 'confirmed'))
     or exists (select 1 from public.payments p
                where p.venue_id = v_venue.id and upper(replace(p.reference, ' ', '')) = v_jrn) then
    raise exception 'That journal number has been used at % already.', v_venue.name;
  end if;

  insert into public.gym_payment_claims (venue_id, gym_member_id, user_id, plan_id, plan_name, months, amount, jrn, channel)
  values (v_venue.id, v_member.id, uid, v_plan.id, v_plan.name, gym_claim_payment.months, gym_claim_payment.amount, v_jrn,
          'bank_account')
  returning id into v_id;
  perform public.notify_venue_permission(
    v_venue.id, 'gym.payments', 'gym_membership', 'Payment to confirm',
    v_member.full_name || ' paid Nu. ' || gym_claim_payment.amount || ' online for ' || v_plan.name || ' (JRN ' || v_jrn
      || '). Check it with the bank.',
    '/gyms/' || v_venue.id || '/manage/payments'
  );
  return v_id;
end;
$$;

-- A member's gyms, as before; each with the account to pay into
-- ('payment_account', null until the gym sets it up) instead of a QR image.
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
                 'payment_account', public.gym_payment_account(ven.id),
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
-- 2. Trainers the gym adds itself
-- ---------------------------------------------------------------------

-- How they came to train here: they asked ('request'), or the gym added
-- them ('gym').
alter table public.gym_trainers add column if not exists source text not null default 'request'
  check (source in ('request', 'gym'));
alter table public.gym_trainers add column if not exists added_by uuid
  constraint gym_trainers_added_by_fkey references public.profiles (id) on delete set null;

-- The personal Trainer profile belongs in the member menu only for someone
-- who applied from a gym's public page, not for someone a gym added itself.
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
    return jsonb_build_object('profile', null, 'joined_publicly', false);
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
                         from public.trainer_reviews r where r.trainer_id = uid), '[]'::jsonb),
    'joined_publicly', exists (
      select 1 from public.gym_trainers g where g.user_id = uid and g.source = 'request'
    )
  );
end;
$$;

-- The caller checks trainers at [venue], so may add one (and have their
-- account made: the admin-users Edge Function asks this first).
create or replace function public.can_add_gym_trainer(venue uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.has_venue_permission(venue, 'gym.trainers');
$$;

-- The photo and certificates of a trainer the gym adds go in the gym's own
-- folder of trainer-media: 'gym/<venue id>/<file>'.
create or replace function public.can_add_trainer_file(object_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_folders text[] := storage.foldername(object_name);
begin
  if coalesce(v_folders[1], '') <> 'gym'
     or coalesce(v_folders[2], '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  return public.has_venue_permission(v_folders[2]::uuid, 'gym.trainers');
end;
$$;
drop policy if exists "trainer-media: a gym adds its trainers' files" on storage.objects;
create policy "trainer-media: a gym adds its trainers' files" on storage.objects for insert to authenticated
  with check (bucket_id = 'trainer-media' and public.can_add_trainer_file(name));

-- Writes trainer [p_user]'s profile from [details] (made, or changed).
create or replace function public.trainer_put_profile(p_user uuid, details jsonb)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  d jsonb := coalesce(details, '{}'::jsonb);
  v_name text := regexp_replace(trim(coalesce(d ->> 'display_name', '')), '\s+', ' ', 'g');
  v_specialties text[];
  v_years int;
begin
  if char_length(v_name) not between 2 and 100 then
    raise exception 'Enter the name as members should see it.';
  end if;
  select coalesce(array_agg(distinct s), '{}') into v_specialties
  from (select regexp_replace(trim(e), '\s+', ' ', 'g') as s
        from jsonb_array_elements_text(case when jsonb_typeof(d -> 'specialties') = 'array' then d -> 'specialties'
                                            else '[]'::jsonb end) e) x
  where s <> '';
  if cardinality(v_specialties) > 15 or exists (select 1 from unnest(v_specialties) s where char_length(s) > 40) then
    raise exception 'Up to 15 specialties, each up to 40 letters.';
  end if;
  begin
    v_years := nullif(d ->> 'experience_years', '')::int;
  exception when others then
    raise exception 'Enter the years of experience as a number.';
  end;
  if v_years is not null and v_years not between 0 and 60 then
    raise exception 'Enter the years of experience (0 to 60).';
  end if;
  if nullif(d ->> 'photo_url', '') is not null and (d ->> 'photo_url') !~ '^https://' then
    raise exception 'Upload the photo to Health Pro.';
  end if;
  insert into public.trainer_profiles (user_id, display_name, headline, bio, specialties, experience_years, photo_url)
  values (p_user, v_name, nullif(left(trim(coalesce(d ->> 'headline', '')), 80), ''),
          nullif(left(trim(coalesce(d ->> 'bio', '')), 2000), ''), v_specialties, v_years, nullif(d ->> 'photo_url', ''))
  on conflict (user_id) do update
    set display_name = excluded.display_name, headline = excluded.headline, bio = excluded.bio,
        specialties = excluded.specialties, experience_years = excluded.experience_years, photo_url = excluded.photo_url;
end;
$$;

-- The signed-in person's trainer profile, made or changed (as before).
create or replace function public.trainer_save_profile(details jsonb)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
begin
  if uid is null then
    raise exception 'Sign in first.';
  end if;
  perform public.trainer_put_profile(uid, details);
end;
$$;

-- Trainer [p_trainer]'s week at [p_venue] becomes [slots] (weekday 1-7,
-- 'HH:MM' start and end). They can't overlap each other, nor the trainer's
-- times at other gyms. [own]: the trainer is saving them (how it's worded).
create or replace function public.trainer_set_slots(p_trainer uuid, p_venue uuid, slots jsonb, own boolean)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  s jsonb;
  v_days int[] := '{}';
  v_from time[] := '{}';
  v_to time[] := '{}';
  v_day int;
  v_start time;
  v_end time;
  v_clash record;
begin
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
    raise exception 'Two of the times here overlap.';
  end if;
  select n.d, n.f, n.t into v_clash
  from unnest(v_days, v_from, v_to) n(d, f, t)
  where exists (select 1 from public.trainer_slots o
                where o.user_id = p_trainer and o.venue_id <> p_venue and o.weekday = n.d
                  and o.starts_at < n.t and n.f < o.ends_at)
  limit 1;
  if found then
    raise exception '%', case when own then 'That overlaps your time at another gym' else 'They''re not available then' end
      || ' (' || (array['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])[v_clash.d] || ' '
      || to_char(v_clash.f, 'HH24:MI') || '–' || to_char(v_clash.t, 'HH24:MI') || ').';
  end if;

  delete from public.trainer_slots t where t.venue_id = p_venue and t.user_id = p_trainer;
  insert into public.trainer_slots (user_id, venue_id, weekday, starts_at, ends_at)
  select p_trainer, p_venue, n.d, n.f, n.t from unnest(v_days, v_from, v_to) n(d, f, t);
end;
$$;

-- The signed-in trainer's week at [venue_id] (as before).
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
begin
  if not exists (select 1 from public.gym_trainers g
                 where g.venue_id = p_venue and g.user_id = uid and g.status in ('pending', 'verified')) then
    raise exception 'Ask the gym to let you train there first.';
  end if;
  perform public.trainer_set_slots(uid, p_venue, trainer_save_slots.slots, true);
end;
$$;

-- The gym changes trainer [user_id]'s times here; they're told.
create or replace function public.gym_save_trainer_slots(venue_id uuid, user_id uuid, slots jsonb)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_save_trainer_slots.venue_id;
  p_user uuid := gym_save_trainer_slots.user_id;
begin
  if not public.has_venue_permission(p_venue, 'gym.trainers') then
    raise exception 'Only the gym''s staff who check trainers can do this.';
  end if;
  if not exists (select 1 from public.gym_trainers g
                 where g.venue_id = p_venue and g.user_id = p_user and g.status in ('pending', 'verified')) then
    raise exception 'That trainer doesn''t train here.';
  end if;
  perform public.trainer_set_slots(p_user, p_venue, gym_save_trainer_slots.slots, false);
  perform public.notify(p_user, 'gym_membership', 'Your times changed',
    (select v.name from public.venues v where v.id = p_venue) || ' changed your times there. Check them.', '/gyms/trainer');
end;
$$;

-- The gym adds trainer [user_id] (their account: admin-users makes it, or
-- finds it by email) with [details]: display_name, headline, bio,
-- specialties, experience_years, photo_url, certificates [{title, issuer,
-- issued_on, file_url}] and slots [{weekday, starts, ends}]. Someone with no
-- trainer profile gets one from them; someone who has one keeps theirs.
-- They're verified here straight away, and told.
create or replace function public.gym_add_trainer(venue_id uuid, user_id uuid, details jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_add_trainer.venue_id;
  p_user uuid := gym_add_trainer.user_id;
  d jsonb := coalesce(gym_add_trainer.details, '{}'::jsonb);
  v_venue public.venues;
  v_files text;
  v_new boolean;
  c jsonb;
  v_title text;
  v_issued date;
  v_file text;
begin
  v_venue := public.gym_require_gym(p_venue);
  if not public.has_venue_permission(p_venue, 'gym.trainers') then
    raise exception 'Only the gym''s staff who check trainers can add one.';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_user and p.is_active) then
    raise exception 'That person has no Health Pro account.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('trainer:' || p_venue::text || ':' || p_user::text, 0));
  if public.gym_trainer_verified(p_venue, p_user) then
    raise exception '% trains here already.', public.trainer_name(p_user);
  end if;

  v_files := '^https://.*/trainer-media/gym/' || p_venue::text || '/';
  v_new := not exists (select 1 from public.trainer_profiles t where t.user_id = p_user);
  if v_new then
    if nullif(d ->> 'photo_url', '') is not null and (d ->> 'photo_url') !~ v_files then
      raise exception 'Upload the photo to Health Pro.';
    end if;
    perform public.trainer_put_profile(p_user, d);
    if jsonb_typeof(d -> 'certificates') = 'array' then
      if jsonb_array_length(d -> 'certificates') > 20 then
        raise exception 'Up to 20 certificates.';
      end if;
      for c in select * from jsonb_array_elements(d -> 'certificates') loop
        v_title := regexp_replace(trim(coalesce(c ->> 'title', '')), '\s+', ' ', 'g');
        if char_length(v_title) not between 2 and 120 then
          raise exception 'Enter each certificate''s name.';
        end if;
        begin
          v_issued := nullif(c ->> 'issued_on', '')::date;
        exception when others then
          raise exception 'Check the date % was given.', v_title;
        end;
        if v_issued > public.bhutan_today() or v_issued < date '1950-01-01' then
          raise exception 'Check the date % was given.', v_title;
        end if;
        v_file := nullif(c ->> 'file_url', '');
        if v_file is not null and v_file !~ v_files then
          raise exception 'Upload the certificate to Health Pro.';
        end if;
        insert into public.trainer_certificates (user_id, title, issuer, issued_on, file_url)
        values (p_user, v_title, nullif(left(trim(coalesce(c ->> 'issuer', '')), 120), ''), v_issued, v_file);
      end loop;
    end if;
  end if;

  insert into public.gym_trainers (venue_id, user_id, status, source, added_by, decided_at, decided_by)
  values (p_venue, p_user, 'verified', 'gym', (select auth.uid()), now(), (select auth.uid()))
  on conflict (venue_id, user_id) do update
    set status = 'verified', source = 'gym', added_by = excluded.added_by, requested_at = now(),
        decided_at = excluded.decided_at, decided_by = excluded.decided_by, decision_note = null;
  if jsonb_typeof(d -> 'slots') = 'array' then
    perform public.trainer_set_slots(p_user, p_venue, d -> 'slots', false);
  end if;

  -- Their Health Pro QR code, for the desk to take their attendance with.
  perform public.person_for_user(p_user);
  perform public.notify(p_user, 'gym_membership', 'You''re a trainer at ' || v_venue.name,
    v_venue.name || ' added you as a trainer. Check your profile and your times there.', '/gyms/trainer');
  return jsonb_build_object('user_id', p_user, 'profile_made', v_new, 'name', public.trainer_name(p_user));
end;
$$;

-- The desk records trainer [user_id] arriving without scanning their QR
-- code (they forgot their phone, or haven't signed in yet).
create or replace function public.gym_trainer_mark_arrived(venue_id uuid, user_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_trainer_mark_arrived.venue_id;
  p_user uuid := gym_trainer_mark_arrived.user_id;
begin
  if not (public.has_venue_permission(p_venue, 'gym.check_in') or public.has_venue_permission(p_venue, 'gym.trainers')) then
    raise exception 'Only the gym''s staff can take attendance.';
  end if;
  if not public.gym_trainer_verified(p_venue, p_user) then
    raise exception 'That trainer isn''t verified here.';
  end if;
  return public.gym_trainer_arrived(p_venue, p_user, (select p.qr_token from public.people p where p.user_id = p_user));
end;
$$;

-- The gym's trainers, for its staff, as before; and how each came (asked,
-- or added by the gym) and how to reach them.
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
             'requested_at', g.requested_at, 'decided_at', g.decided_at, 'source', g.source,
             'email', pr.email, 'phone', pr.phone,
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
    from public.gym_trainers g
    join public.trainer_profiles t on t.user_id = g.user_id
    left join public.profiles pr on pr.id = g.user_id
    where g.venue_id = p_venue and g.status <> 'left'
  ), '[]'::jsonb);
end;
$$;


-- ---------------------------------------------------------------------
-- 3. Who can call which function
-- ---------------------------------------------------------------------

revoke execute on function public.gym_settings_of(uuid), public.gym_payment_account(uuid),
  public.trainer_put_profile(uuid, jsonb), public.trainer_set_slots(uuid, uuid, jsonb, boolean)
  from public, anon, authenticated;

revoke execute on function public.gym_save_settings(uuid, text, text, text, text, int[], text),
  public.gym_claim_payment(uuid, uuid, int, int, text), public.my_gyms(),
  public.can_add_gym_trainer(uuid), public.can_add_trainer_file(text),
  public.trainer_save_profile(jsonb), public.trainer_save_slots(uuid, jsonb),
  public.gym_save_trainer_slots(uuid, uuid, jsonb), public.gym_add_trainer(uuid, uuid, jsonb),
  public.gym_trainer_mark_arrived(uuid, uuid), public.gym_trainers_overview(uuid)
  from public, anon;
grant execute on function public.gym_save_settings(uuid, text, text, text, text, int[], text),
  public.gym_claim_payment(uuid, uuid, int, int, text), public.my_gyms(),
  public.can_add_gym_trainer(uuid), public.can_add_trainer_file(text),
  public.trainer_save_profile(jsonb), public.trainer_save_slots(uuid, jsonb),
  public.gym_save_trainer_slots(uuid, uuid, jsonb), public.gym_add_trainer(uuid, uuid, jsonb),
  public.gym_trainer_mark_arrived(uuid, uuid), public.gym_trainers_overview(uuid)
  to authenticated;
