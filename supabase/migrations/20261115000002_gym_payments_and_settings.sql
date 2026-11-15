-- Health Pro, phase 2 of the QR code flow: paying online, and the gym's
-- settings for it.
--
-- - gym_settings, one row a gym (defaults while there's none): its payment
--   QR code (the bank's, an image in the public gym-payment-qr bucket), how
--   many days before a package ends members are reminded (one or more), and
--   who answers requests to join (the front desk, or managers only).
-- - gym_payment_claims: a member pays online (scans the gym's payment QR in
--   their bank app) and enters the journal number (JRN). The gym's staff who
--   take payments are told; they check it against the bank and confirm it,
--   which renews the package (from the day the current one ends, or today),
--   or reject it, with why. Cash is still sold at the desk as before. Either
--   way the desk confirms the payment before the package starts.
-- - The daily job reminds members (now people with an account, wherever the
--   desk registered them) on the gym's days, and on the package's last day
--   tells them it ends, and how to renew.
--
-- Safe to run again.


-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

create table if not exists public.gym_settings (
  venue_id        uuid primary key references public.venues (id) on delete cascade,
  -- The bank's payment QR code: '<venue id>/<file>' in gym-payment-qr.
  payment_qr_path text check (payment_qr_path ~ '^[0-9a-f-]{36}/[0-9A-Za-z._-]{1,100}$'),
  -- Days before the end a member is reminded, most first: {7, 3}.
  reminder_days   int[] not null default '{3}'
                  check (cardinality(reminder_days) <= 5 and 1 <= all (reminder_days) and 60 >= all (reminder_days)),
  -- Who adds or declines requests to join: 'desk' (whoever registers
  -- members) or 'managers' (the owner and managers only).
  join_approval   text not null default 'desk' check (join_approval in ('desk', 'managers')),
  updated_by      uuid constraint gym_settings_updated_by_fkey references public.profiles (id) on delete set null,
  updated_at      timestamptz not null default now()
);

drop trigger if exists gym_settings_updated_at on public.gym_settings;
create trigger gym_settings_updated_at before update on public.gym_settings
  for each row execute function public.set_updated_at();

-- A member's online payment, waiting for the gym to check it.
create table if not exists public.gym_payment_claims (
  id              uuid primary key default gen_random_uuid(),
  venue_id        uuid not null references public.venues (id) on delete cascade,
  gym_member_id   uuid not null references public.gym_members (id) on delete cascade,
  user_id         uuid constraint gym_payment_claims_user_id_fkey references public.profiles (id) on delete set null,
  plan_id         uuid references public.gym_plans (id) on delete set null,
  plan_name       text not null,
  months          int not null check (months between 1 and 24),
  amount          int not null check (amount between 1 and 1000000), -- Ngultrum, as they say they paid
  -- The bank's journal number, tidied: capitals, no spaces.
  jrn             text not null check (jrn ~ '^[0-9A-Z/-]{4,40}$'),
  status          text not null default 'pending' check (status in ('pending', 'confirmed', 'rejected', 'cancelled')),
  decision_note   text check (char_length(decision_note) <= 500),
  decided_by      uuid constraint gym_payment_claims_decided_by_fkey references public.profiles (id) on delete set null,
  decided_at      timestamptz,
  subscription_id uuid references public.gym_subscriptions (id) on delete set null,
  payment_id      uuid references public.payments (id) on delete set null,
  created_at      timestamptz not null default now()
);
-- One payment waiting per member per gym; a journal number pays once.
create unique index if not exists gym_payment_claims_one_pending
  on public.gym_payment_claims (gym_member_id) where status = 'pending';
create unique index if not exists gym_payment_claims_jrn_once
  on public.gym_payment_claims (venue_id, jrn) where status in ('pending', 'confirmed');
create index if not exists gym_payment_claims_venue_idx on public.gym_payment_claims (venue_id, status, created_at desc);
create index if not exists gym_payment_claims_user_idx on public.gym_payment_claims (user_id);

-- Which reminders a package has had (days before its end; 0: its last day).
create table if not exists public.gym_reminders_sent (
  subscription_id uuid not null references public.gym_subscriptions (id) on delete cascade,
  days_before     int not null,
  sent_at         timestamptz not null default now(),
  primary key (subscription_id, days_before)
);


-- ---------------------------------------------------------------------
-- 2. Who can read what (changes go through the functions below)
-- ---------------------------------------------------------------------

alter table public.gym_settings enable row level security;
revoke all on public.gym_settings from anon, authenticated;
grant select on public.gym_settings to authenticated;
-- Nothing secret: the payment QR is the one at the gym's desk.
drop policy if exists "gym_settings: anyone signed in" on public.gym_settings;
create policy "gym_settings: anyone signed in" on public.gym_settings for select to authenticated using (true);

alter table public.gym_payment_claims enable row level security;
revoke all on public.gym_payment_claims from anon, authenticated;
grant select on public.gym_payment_claims to authenticated;
drop policy if exists "gym_payment_claims: the payer and the gym" on public.gym_payment_claims;
create policy "gym_payment_claims: the payer and the gym" on public.gym_payment_claims for select to authenticated
  using (user_id = (select auth.uid())
         or public.has_venue_permission(venue_id, 'gym.payments')
         or public.has_venue_permission(venue_id, 'gym.members'));

alter table public.gym_reminders_sent enable row level security;
revoke all on public.gym_reminders_sent from anon, authenticated;

-- The payment QR codes: public (they're printed at the desk); changed by
-- whoever edits the gym.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('gym-payment-qr', 'gym-payment-qr', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;
drop policy if exists "gym-payment-qr: gym editors upload" on storage.objects;
create policy "gym-payment-qr: gym editors upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'gym-payment-qr' and public.can_edit_venue_folder(name));
drop policy if exists "gym-payment-qr: gym editors replace" on storage.objects;
create policy "gym-payment-qr: gym editors replace" on storage.objects for update to authenticated
  using (bucket_id = 'gym-payment-qr' and public.can_edit_venue_folder(name))
  with check (bucket_id = 'gym-payment-qr' and public.can_edit_venue_folder(name));
drop policy if exists "gym-payment-qr: gym editors remove" on storage.objects;
create policy "gym-payment-qr: gym editors remove" on storage.objects for delete to authenticated
  using (bucket_id = 'gym-payment-qr' and public.can_edit_venue_folder(name));


-- ---------------------------------------------------------------------
-- 3. Helpers (not callable by the app)
-- ---------------------------------------------------------------------

-- Person [u] may do [perm] at [venue], by their role there: has_venue_permission
-- for someone other than the caller (whom to tell).
create or replace function public.user_has_venue_permission(u uuid, venue uuid, perm text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.venue_staff s
    join public.venues v on v.id = s.venue_id
    join public.roles r on r.key = s.role and r.is_active
                       and (r.organisation_id is null or r.organisation_id = v.organisation_id)
    join public.profiles p on p.id = s.user_id and p.is_active
    left join public.organisation_role_settings o on o.organisation_id = v.organisation_id and o.role_id = r.id
    where s.venue_id = venue and s.user_id = u
      and coalesce(o.is_active, true)
      and (r.key = 'owner'
           or (coalesce(o.custom_permissions, false) and exists (
                 select 1 from public.organisation_role_permissions op
                 where op.organisation_id = o.organisation_id and op.role_id = r.id and op.permission_key = perm))
           or (not coalesce(o.custom_permissions, false) and exists (
                 select 1 from public.role_permissions rp where rp.role_id = r.id and rp.permission_key = perm)))
  );
$$;

-- Tells [venue]'s staff whose role allows [perm] (and, with [roles], has
-- one of those roles); not the caller.
create or replace function public.notify_venue_permission(p_venue uuid, p_perm text, p_module text, p_title text,
                                                          p_body text default null, p_link text default null,
                                                          p_roles text[] default null)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notifications (user_id, module_key, title, body, link)
  select s.user_id, p_module, p_title, p_body, p_link
  from public.venue_staff s
  where s.venue_id = p_venue and s.user_id is distinct from (select auth.uid())
    and (p_roles is null or s.role = any (p_roles))
    and public.user_has_venue_permission(s.user_id, p_venue, p_perm);
$$;

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
  end if;
  return v;
end;
$$;

-- The caller may add or decline requests to join [venue]: they register
-- members there, and the gym lets the front desk answer, or they're its
-- owner or a manager.
create or replace function public.gym_can_answer_joins(venue uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.has_venue_permission(venue, 'gym.register')
     and ((public.gym_settings_of(venue)).join_approval = 'desk'
          or public.is_admin()
          or public.venue_role(venue) in ('owner', 'manager'));
$$;

-- Answering a request to join (adding them, or declining) follows the
-- gym's setting, whichever function does it.
create or replace function public.gym_join_requests_answer_check()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'pending' and new.status in ('approved', 'declined')
     and not public.gym_can_answer_joins(new.venue_id) then
    raise exception 'At this gym, the owner and managers answer requests to join.';
  end if;
  return new;
end;
$$;
drop trigger if exists gym_join_requests_answer on public.gym_join_requests;
create trigger gym_join_requests_answer before update of status on public.gym_join_requests
  for each row execute function public.gym_join_requests_answer_check();

-- ---------------------------------------------------------------------
-- 4. Functions the app calls
-- ---------------------------------------------------------------------

-- The gym's settings: whoever edits the gym (venue.edit).
create or replace function public.gym_save_settings(venue_id uuid, payment_qr_path text, reminder_days int[],
                                                    join_approval text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_save_settings.venue_id;
  p_path text := nullif(trim(coalesce(gym_save_settings.payment_qr_path, '')), '');
  v_days int[];
begin
  perform public.gym_require_gym(p_venue);
  if not public.has_venue_permission(p_venue, 'venue.edit') then
    raise exception 'Only those who edit the gym can change its settings.';
  end if;
  if p_path is not null and p_path not like p_venue::text || '/%' then
    raise exception 'The payment QR code must be uploaded to this gym''s folder.';
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
  insert into public.gym_settings (venue_id, payment_qr_path, reminder_days, join_approval, updated_by)
  values (p_venue, p_path, v_days, gym_save_settings.join_approval, (select auth.uid()))
  on conflict (venue_id) do update
    set payment_qr_path = excluded.payment_qr_path, reminder_days = excluded.reminder_days,
        join_approval = excluded.join_approval, updated_by = excluded.updated_by;
end;
$$;

-- Asking to join, as before; who is told follows the gym's setting: the
-- staff who register members, or only its owner and managers.
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
  perform public.notify_venue_permission(
    v_venue.id, 'gym.register', 'gym_membership', 'New request to join',
    public.person_name(v) || ' asked to join ' || v_venue.name || '.',
    '/gyms/' || v_venue.id || '/manage/requests',
    case when (public.gym_settings_of(v_venue.id)).join_approval = 'managers' then array['owner', 'manager'] end
  );
  return v_id;
end;
$$;

-- A member says they paid online: [months] of [plan_id] at [venue_id], Nu.
-- [amount], with the bank's journal number [jrn]. The staff who take
-- payments are told. Returns the claim.
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

  insert into public.gym_payment_claims (venue_id, gym_member_id, user_id, plan_id, plan_name, months, amount, jrn)
  values (v_venue.id, v_member.id, uid, v_plan.id, v_plan.name, gym_claim_payment.months, gym_claim_payment.amount, v_jrn)
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

-- The payer takes their payment back (sent by mistake).
create or replace function public.gym_cancel_payment_claim(claim_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  update public.gym_payment_claims c set status = 'cancelled', decided_at = now()
  where c.id = gym_cancel_payment_claim.claim_id and c.user_id = (select auth.uid()) and c.status = 'pending';
  if not found then
    raise exception 'That payment isn''t waiting any more.';
  end if;
end;
$$;

-- The gym found the payment: the package starts (from the day the current
-- one ends, or today), the payment is recorded with its journal number, and
-- the member is told.
create or replace function public.gym_confirm_payment_claim(claim_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  c public.gym_payment_claims;
  v_membership jsonb;
  v_gym text;
begin
  select * into c from public.gym_payment_claims x where x.id = gym_confirm_payment_claim.claim_id for update;
  if not found or not public.has_venue_permission(c.venue_id, 'gym.payments') then
    raise exception 'Only the gym''s staff who take payments can confirm them.';
  end if;
  if c.status <> 'pending' then
    raise exception 'That payment has been answered already.';
  end if;
  v_membership := public.gym_renew_member(c.gym_member_id, c.plan_id, c.months, c.amount, 'bank', c.jrn);
  update public.gym_payment_claims x set status = 'confirmed', decided_by = (select auth.uid()), decided_at = now(),
    subscription_id = (v_membership ->> 'subscription_id')::uuid, payment_id = (v_membership ->> 'payment_id')::uuid
  where x.id = c.id;
  select v.name into v_gym from public.venues v where v.id = c.venue_id;
  perform public.notify(c.user_id, 'gym_membership', 'Payment confirmed',
    v_gym || ' confirmed your payment (JRN ' || c.jrn || '). ' || c.plan_name || ' runs until '
      || to_char((v_membership ->> 'end_date')::date, 'FMDD Mon YYYY') || '.',
    '/gyms/my');
  return v_membership;
end;
$$;

-- The gym couldn't find the payment: the member is told, with [note].
create or replace function public.gym_reject_payment_claim(claim_id uuid, note text default null)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  c public.gym_payment_claims;
  v_note text := nullif(left(trim(coalesce(gym_reject_payment_claim.note, '')), 500), '');
  v_gym text;
begin
  select * into c from public.gym_payment_claims x where x.id = gym_reject_payment_claim.claim_id for update;
  if not found or not public.has_venue_permission(c.venue_id, 'gym.payments') then
    raise exception 'Only the gym''s staff who take payments can answer them.';
  end if;
  if c.status <> 'pending' then
    raise exception 'That payment has been answered already.';
  end if;
  update public.gym_payment_claims x set status = 'rejected', decision_note = v_note,
    decided_by = (select auth.uid()), decided_at = now()
  where x.id = c.id;
  select v.name into v_gym from public.venues v where v.id = c.venue_id;
  perform public.notify(c.user_id, 'gym_membership', 'We couldn''t confirm your payment',
    v_gym || ' couldn''t find your payment (JRN ' || c.jrn || ').' || coalesce(' ' || v_note, '')
      || ' Check the number, or ask at the front desk.',
    '/gyms/my');
end;
$$;

-- The signed-in person's gyms, as before, and for each: how to pay it
-- online (its payment QR code and note), their payment waiting, and the
-- last one answered.
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
                           limit 1)
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

-- Every day (00:05 Bhutan time, pg_cron): packages past their last day end;
-- members are reminded on each of the gym's reminder days, and told on the
-- last day that it ends and how to renew (unless they have renewed); and
-- requests nobody answered in 30 days close.
create or replace function public.gym_daily_maintenance()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := public.bhutan_today();
  v_expired int := 0;
  v_reminded int := 0;
  v_ending int := 0;
  v_cancelled int := 0;
  r record;
  v_user uuid;
  v_days int;
begin
  update public.gym_subscriptions s set status = 'expired'
  where s.status = 'active' and s.end_date < v_today;
  get diagnostics v_expired = row_count;

  -- Active packages ending on a reminder day, or today, not renewed.
  for r in
    select s.*, ven.name as gym_name, (public.gym_settings_of(s.venue_id)).reminder_days as reminder_days
    from public.gym_subscriptions s
    join public.venues ven on ven.id = s.venue_id
    where s.status = 'active' and s.end_date between v_today and v_today + 60
      and not exists (select 1 from public.gym_subscriptions n
                      where n.status = 'active' and n.start_date >= s.end_date and n.id <> s.id
                        and ((s.gym_member_id is not null and n.gym_member_id = s.gym_member_id)
                             or (s.member_id is not null and n.member_id = s.member_id and n.venue_id = s.venue_id)))
  loop
    v_days := r.end_date - v_today;
    continue when v_days <> 0 and not (v_days = any (r.reminder_days));
    continue when exists (select 1 from public.gym_reminders_sent x where x.subscription_id = r.id and x.days_before = v_days);
    insert into public.gym_reminders_sent (subscription_id, days_before) values (r.id, v_days);
    v_user := coalesce(r.member_id, (select p.user_id from public.gym_members g join public.people p on p.id = g.person_id
                                     where g.id = r.gym_member_id));
    continue when v_user is null;
    if v_days = 0 then
      v_ending := v_ending + 1;
      perform public.notify(v_user, 'gym_membership', 'Your package at ' || r.gym_name || ' ends today',
        r.plan_name || ' ends today. Pay to renew it: online with your bank app (then enter the journal number in '
          || 'Health Pro), or cash at the front desk.',
        '/gyms/my');
    else
      v_reminded := v_reminded + 1;
      perform public.notify(v_user, 'gym_membership',
        'Your package ends in ' || v_days || case when v_days = 1 then ' day' else ' days' end,
        r.gym_name || ': ' || r.plan_name || ' ends on ' || to_char(r.end_date, 'FMDD Mon YYYY') || '. Renew it to keep going.',
        '/gyms/my');
    end if;
  end loop;

  -- Account requests (from before) nobody confirmed in 30 days.
  for r in
    update public.gym_subscriptions s set status = 'cancelled', cancelled_at = now()
    where s.status = 'pending' and s.requested_at < now() - interval '30 days'
    returning s.venue_id, s.member_id, s.plan_name
  loop
    v_cancelled := v_cancelled + 1;
    perform public.notify(r.member_id, 'gym_membership', 'Your request was closed',
      'Your request for ' || r.plan_name || ' waited 30 days without a payment. Ask again any time.',
      '/gyms/' || r.venue_id);
  end loop;

  -- Requests to join nobody answered in 30 days.
  for r in
    update public.gym_join_requests j set status = 'cancelled', decided_at = now()
    where j.status = 'pending' and j.created_at < now() - interval '30 days'
    returning j.venue_id, j.user_id
  loop
    v_cancelled := v_cancelled + 1;
    perform public.notify(r.user_id, 'gym_membership', 'Your request to join was closed',
      (select v.name from public.venues v where v.id = r.venue_id)
        || ' didn''t answer in 30 days. Ask again, or visit the front desk.',
      '/gyms/' || r.venue_id);
  end loop;

  return jsonb_build_object('expired', v_expired, 'reminded', v_reminded, 'ending_today', v_ending,
                            'cancelled', v_cancelled);
end;
$$;


-- ---------------------------------------------------------------------
-- 5. Who can call which function
-- ---------------------------------------------------------------------

revoke execute on function public.user_has_venue_permission(uuid, uuid, text),
  public.notify_venue_permission(uuid, text, text, text, text, text, text[]), public.gym_settings_of(uuid),
  public.gym_join_requests_answer_check(),
  public.gym_daily_maintenance()
  from public, anon, authenticated;

revoke execute on function public.gym_can_answer_joins(uuid), public.gym_save_settings(uuid, text, int[], text),
  public.gym_request_to_join(uuid, uuid, text), public.gym_claim_payment(uuid, uuid, int, int, text),
  public.gym_cancel_payment_claim(uuid), public.gym_confirm_payment_claim(uuid),
  public.gym_reject_payment_claim(uuid, text), public.my_gyms()
  from public, anon;
grant execute on function public.gym_can_answer_joins(uuid), public.gym_save_settings(uuid, text, int[], text),
  public.gym_request_to_join(uuid, uuid, text), public.gym_claim_payment(uuid, uuid, int, int, text),
  public.gym_cancel_payment_claim(uuid), public.gym_confirm_payment_claim(uuid),
  public.gym_reject_payment_claim(uuid, text), public.my_gyms()
  to authenticated;
