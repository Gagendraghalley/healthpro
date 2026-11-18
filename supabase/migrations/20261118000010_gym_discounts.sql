-- Discounts and offers. A gym keeps its offers ('Student', 10% off;
-- 'Couple', Nu. 500 off) under Offers & discounts ('gym.plans'). Selling a
-- package at the desk, staff pick one, or take less with a reason
-- ('Referred by Sonam'). Every package now keeps its full price
-- (list_price: the plan's price for those months, as the form suggests it),
-- so what was taken off, why and by whom shows in the activity log, the
-- receipt and the gym's discount totals, whether or not an offer was picked.
-- The amount received stays the staff's to enter.
--
-- The desk's functions take the discount as {offer_id, reason}:
-- gym_register_member in its details ('discount'), gym_renew_member as a new
-- last argument. Packages sold before keep list_price null (no discount
-- known). Safe to re-run.

create table if not exists public.gym_offers (
  id         uuid primary key default gen_random_uuid(),
  venue_id   uuid not null references public.venues (id) on delete cascade,
  name       text not null check (char_length(trim(name)) between 2 and 60),
  kind       text not null check (kind in ('percent', 'amount')),
  value      int not null check (value between 1 and 1000000 and (kind <> 'percent' or value <= 100)),
  is_active  boolean not null default true, -- false: no longer offered
  created_by uuid constraint gym_offers_created_by_fkey references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists gym_offers_venue_name on public.gym_offers (venue_id, lower(name));

drop trigger if exists gym_offers_updated_at on public.gym_offers;
create trigger gym_offers_updated_at before update on public.gym_offers
  for each row execute function public.set_updated_at();

-- The desk (who sells packages) and who sets prices see them.
alter table public.gym_offers enable row level security;
revoke all on public.gym_offers from anon, authenticated;
grant select on public.gym_offers to authenticated;
drop policy if exists "gym_offers: who sells or prices packages" on public.gym_offers;
create policy "gym_offers: who sells or prices packages" on public.gym_offers for select to authenticated
  using (public.has_venue_permission(venue_id, 'gym.payments') or public.has_venue_permission(venue_id, 'gym.plans'));

alter table public.gym_subscriptions add column if not exists list_price int check (list_price between 0 and 100000000);
alter table public.gym_subscriptions add column if not exists offer_id uuid
  constraint gym_subscriptions_offer_id_fkey references public.gym_offers (id) on delete set null;
alter table public.gym_subscriptions add column if not exists offer_name text; -- as it was called then
alter table public.gym_subscriptions add column if not exists discount_reason text check (char_length(discount_reason) <= 200);

-- A new offer ([offer_id] null) or changes to one. Its id.
create or replace function public.gym_save_offer(venue_id uuid, offer_id uuid, name text, kind text, value int,
                                                 is_active boolean default true)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_venue uuid := gym_save_offer.venue_id;
  v_name text := trim(coalesce(gym_save_offer.name, ''));
  v_id uuid;
begin
  if not public.has_venue_permission(v_venue, 'gym.plans') then
    raise exception 'Only those who set the gym''s prices can change its offers.';
  end if;
  if gym_save_offer.offer_id is not null
     and not exists (select 1 from public.gym_offers o where o.id = gym_save_offer.offer_id and o.venue_id = v_venue) then
    raise exception 'This offer isn''t there any more.';
  end if;
  if char_length(v_name) not between 2 and 60 then
    raise exception 'Give the offer a name, e.g. Student.';
  end if;
  if gym_save_offer.kind is null or gym_save_offer.kind not in ('percent', 'amount') then
    raise exception 'Choose a percentage or an amount off.';
  end if;
  if gym_save_offer.kind = 'percent' and (gym_save_offer.value is null or gym_save_offer.value not between 1 and 100) then
    raise exception 'A percentage off is 1 to 100.';
  end if;
  if gym_save_offer.kind = 'amount' and (gym_save_offer.value is null or gym_save_offer.value not between 1 and 1000000) then
    raise exception 'Enter the amount off in Ngultrum.';
  end if;
  if exists (select 1 from public.gym_offers o
             where o.venue_id = v_venue and lower(o.name) = lower(v_name) and o.id is distinct from gym_save_offer.offer_id) then
    raise exception 'The gym has an offer called % already.', v_name;
  end if;

  if gym_save_offer.offer_id is null then
    insert into public.gym_offers (venue_id, name, kind, value, is_active, created_by)
    values (v_venue, v_name, gym_save_offer.kind, gym_save_offer.value, coalesce(gym_save_offer.is_active, true),
            (select auth.uid()))
    returning id into v_id;
    return v_id;
  end if;
  update public.gym_offers o
     set name = v_name, kind = gym_save_offer.kind, value = gym_save_offer.value,
         is_active = coalesce(gym_save_offer.is_active, true)
   where o.id = gym_save_offer.offer_id;
  return gym_save_offer.offer_id;
end;
$$;

revoke execute on function public.gym_save_offer(uuid, uuid, text, text, int, boolean) from public, anon;
grant execute on function public.gym_save_offer(uuid, uuid, text, text, int, boolean) to authenticated;

-- What [months] months of [plan] cost at its price (as the app's
-- packagePrice): its price per month, a 30-day plan being a month.
create or replace function public.gym_package_price(plan public.gym_plans, months int)
returns int
language sql
immutable
set search_path = ''
as $$
  select round(plan.price::numeric * months / greatest(1, round(plan.duration_days / 30.44)))::int
$$;


-- ---------------------------------------------------------------------
-- Selling with a discount
-- ---------------------------------------------------------------------

-- As in 20261108000005, with [discount] ({offer_id, reason}) and the full
-- price kept. The offer and reason are kept only when they paid less.
drop function if exists public.gym_add_membership(public.gym_members, uuid, int, date, int, text, text);
create or replace function public.gym_add_membership(member public.gym_members, plan_id uuid, months int, start date,
                                                     amount int, method text, reference text, discount jsonb default null)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_member public.gym_members := gym_add_membership.member;
  p_months int := gym_add_membership.months;
  p_start date := gym_add_membership.start;
  p_amount int := gym_add_membership.amount;
  p_method text := gym_add_membership.method;
  p_reference text := nullif(trim(gym_add_membership.reference), '');
  v_reason text := nullif(trim(coalesce(gym_add_membership.discount ->> 'reason', '')), '');
  v_offer public.gym_offers;
  v_plan public.gym_plans;
  v_list int;
  v_end date;
  v_status text;
  v_sub uuid;
  v_payment uuid;
begin
  if not public.has_venue_permission(p_member.venue_id, 'gym.payments') then
    raise exception 'Your role here can register members but not sell them a package.';
  end if;
  select * into v_plan from public.gym_plans pl where pl.id = gym_add_membership.plan_id and pl.venue_id = p_member.venue_id;
  if not found or not v_plan.is_active then
    raise exception 'Choose one of the gym''s packages.';
  end if;
  if p_months is null or p_months not between 1 and 24 then
    raise exception 'Choose how many months (1 to 24).';
  end if;
  if p_amount is null or p_amount < 0 or p_amount > 1000000 then
    raise exception 'Enter the amount received.';
  end if;
  if p_amount > 0 and (p_method is null or p_method not in ('mbob', 'cash', 'bank', 'other')) then
    raise exception 'Choose how they paid.';
  end if;
  if nullif(gym_add_membership.discount ->> 'offer_id', '') is not null then
    select * into v_offer from public.gym_offers o
    where o.id = (gym_add_membership.discount ->> 'offer_id')::uuid and o.venue_id = p_member.venue_id;
    if not found or not v_offer.is_active then
      raise exception 'That offer isn''t available any more. Choose another, or none.';
    end if;
  end if;
  if char_length(v_reason) > 200 then
    raise exception 'Keep the reason for the discount under 200 characters.';
  end if;
  v_list := public.gym_package_price(v_plan, p_months);
  if p_amount >= v_list then
    v_offer := null;
    v_reason := null;
  end if;
  v_end := (p_start + make_interval(months => p_months))::date;
  v_status := case when v_end < public.bhutan_today() then 'expired' else 'active' end;

  insert into public.gym_subscriptions (venue_id, gym_member_id, plan_id, plan_name, duration_days, price, status,
                                        start_date, end_date, activated_at, activated_by, list_price, offer_id, offer_name,
                                        discount_reason)
  values (p_member.venue_id, p_member.id, v_plan.id, v_plan.name, v_end - p_start + 1, p_amount, v_status,
          p_start, v_end, now(), (select auth.uid()), v_list, v_offer.id, v_offer.name, v_reason)
  returning gym_subscriptions.id into v_sub;

  if p_amount > 0 then
    insert into public.payments (venue_id, module_key, reference_id, amount, method, reference, recorded_by, payer_name)
    values (p_member.venue_id, 'gym_membership', v_sub, p_amount, p_method, p_reference, (select auth.uid()),
            p_member.full_name)
    returning payments.id into v_payment;
    update public.gym_subscriptions s set payment_id = v_payment where s.id = v_sub;
  end if;

  return jsonb_build_object('subscription_id', v_sub, 'start_date', p_start, 'end_date', v_end, 'status', v_status,
                            'payment_id', v_payment);
end;
$$;
revoke execute on function public.gym_add_membership(public.gym_members, uuid, int, date, int, text, text, jsonb)
  from public, anon, authenticated;

-- As in 20261115000001, passing on details' 'discount'.
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
                                              gym_register_member.reference, gym_register_member.details -> 'discount');
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

-- As in 20261115000006, with [discount] last.
drop function if exists public.gym_renew_member(uuid, uuid, int, int, text, text);
create or replace function public.gym_renew_member(gym_member_id uuid, plan_id uuid, months int, amount int,
                                                   method text default null, reference text default null,
                                                   discount jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_member public.gym_members;
  v_last_end date;
  v_today date := public.bhutan_today();
  v_membership jsonb;
  v_user uuid;
  v_gym text;
  v_plan text;
  v_start date;
  v_runs text;
  v_reference text := nullif(trim(coalesce(gym_renew_member.reference, '')), '');
begin
  select * into v_member from public.gym_members g where g.id = gym_renew_member.gym_member_id;
  if not found then
    raise exception 'This member is no longer registered.';
  end if;
  -- Serialises renewals of the same member.
  perform 1 from public.gym_members g where g.id = v_member.id for update;
  select max(s.end_date) into v_last_end from public.gym_subscriptions s
  where s.gym_member_id = v_member.id and s.status = 'active';
  v_membership := public.gym_add_membership(v_member, gym_renew_member.plan_id, gym_renew_member.months,
                                            greatest(v_today, coalesce(v_last_end, v_today)), gym_renew_member.amount,
                                            gym_renew_member.method, gym_renew_member.reference,
                                            gym_renew_member.discount);

  -- They're told, if they have an account.
  select p.user_id into v_user from public.people p where p.id = v_member.person_id;
  if v_user is not null then
    select v.name into v_gym from public.venues v where v.id = v_member.venue_id;
    select s.plan_name into v_plan from public.gym_subscriptions s
    where s.id = (v_membership ->> 'subscription_id')::uuid;
    v_start := (v_membership ->> 'start_date')::date;
    v_runs := v_plan
              || case when v_start > v_today then ' runs from ' || to_char(v_start, 'FMDD Mon YYYY') || ' until '
                      else ' runs until ' end
              || to_char((v_membership ->> 'end_date')::date, 'FMDD Mon YYYY') || '.';
    if coalesce(gym_renew_member.amount, 0) > 0 then
      perform public.notify(v_user, 'gym_membership', 'Payment confirmed',
        v_gym || ' confirmed your ' || case when gym_renew_member.method = 'cash' then 'cash payment' else 'payment' end
          || ' of Nu. ' || gym_renew_member.amount
          || case when v_reference is null then ''
                  when gym_renew_member.method in ('mbob', 'bank') then ' (JRN ' || v_reference || ')'
                  else ' (ref ' || v_reference || ')' end
          || '. ' || v_runs,
        '/gyms/my');
    else
      perform public.notify(v_user, 'gym_membership', 'Your package was renewed', v_gym || ' renewed your package. ' || v_runs,
                            '/gyms/my');
    end if;
  end if;
  return v_membership;
end;
$$;
revoke execute on function public.gym_renew_member(uuid, uuid, int, int, text, text, jsonb) from public, anon;
grant execute on function public.gym_renew_member(uuid, uuid, int, int, text, text, jsonb) to authenticated;


-- ---------------------------------------------------------------------
-- The discount on the receipt and in the activity log
-- ---------------------------------------------------------------------

-- As in 20261118000004, with the full price, offer and reason.
create or replace function public.gym_payment_receipt(payment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_pay public.payments;
  v_sub public.gym_subscriptions;
  v_member public.gym_members;
  v_profile public.profiles;
  v_venue public.venues;
  v_me uuid := (select auth.uid());
begin
  select * into v_pay from public.payments p where p.id = gym_payment_receipt.payment_id;
  if not found then
    raise exception 'There''s no such payment.';
  end if;
  if v_pay.reference_id is not null then
    select * into v_sub from public.gym_subscriptions s where s.id = v_pay.reference_id;
  end if;
  if v_sub.gym_member_id is not null then
    select * into v_member from public.gym_members g where g.id = v_sub.gym_member_id;
  end if;
  -- coalesce: a payment without an account (user_id null) is nobody's own.
  if not coalesce(public.has_venue_permission(v_pay.venue_id, 'gym.members')
                  or public.has_venue_permission(v_pay.venue_id, 'gym.payments')
                  or public.has_venue_permission(v_pay.venue_id, 'venue.income')
                  or v_pay.user_id = v_me
                  or exists (select 1 from public.people p where p.id = v_member.person_id and p.user_id = v_me),
                  false) then
    raise exception 'Only the gym''s staff and the member who paid can see this receipt.';
  end if;
  select * into v_venue from public.venues v where v.id = v_pay.venue_id;
  select * into v_profile from public.profiles pr where pr.id = coalesce(v_pay.user_id, v_sub.member_id);

  return jsonb_build_object(
    'payment_id', v_pay.id,
    'receipt_no', v_pay.receipt_no,
    'paid_at', v_pay.created_at,
    'amount', v_pay.amount,
    'method', v_pay.method,
    'reference', v_pay.reference,
    'status', v_pay.status,
    'gym_name', v_venue.name,
    'gym_phone', v_venue.phone,
    'gym_email', v_venue.email,
    'gym_address', concat_ws(', ', nullif(trim(v_venue.address), ''), nullif(trim(v_venue.town), ''), v_venue.dzongkhag),
    'member_name', coalesce(v_member.full_name, nullif(trim(v_profile.full_name), ''), v_pay.payer_name, 'Member'),
    'member_code', coalesce(v_member.code, v_profile.member_code),
    'member_phone', coalesce(v_member.phone, v_profile.phone),
    'plan_name', v_sub.plan_name,
    'start_date', v_sub.start_date,
    'end_date', v_sub.end_date,
    'received_by', (select nullif(trim(pr.full_name), '') from public.profiles pr where pr.id = v_pay.recorded_by),
    'list_price', case when v_sub.list_price > v_sub.price then v_sub.list_price end,
    'offer_name', v_sub.offer_name,
    'discount_reason', v_sub.discount_reason
  );
end;
$$;
revoke execute on function public.gym_payment_receipt(uuid) from public, anon;
grant execute on function public.gym_payment_receipt(uuid) to authenticated;

-- As in 20261118000006, with the discount after the dates:
-- 'Monthly, 18 Nov 2026 to 18 Feb 2027 · discount Nu. 450 (Student)'.
create or replace function public.gym_audit_subscriptions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_dates text;
  v_renewal boolean;
  v_why text;
begin
  v_name := coalesce((select g.full_name from public.gym_members g where g.id = new.gym_member_id),
                     (select p.full_name from public.profiles p where p.id = new.member_id), 'a member');
  v_dates := new.plan_name || case when new.start_date is null then ''
                                   else ', ' || public.gym_audit_day(new.start_date) || ' to ' || public.gym_audit_day(new.end_date) end;
  if new.list_price > new.price then
    v_why := nullif(concat_ws(': ', new.offer_name, new.discount_reason), '');
    v_dates := v_dates || ' · discount ' || public.gym_audit_nu(new.list_price - new.price)
               || coalesce(' (' || v_why || ')', ', no reason given');
  end if;
  if tg_op = 'INSERT' then
    if new.status in ('active', 'expired') then
      v_renewal := exists (
        select 1 from public.gym_subscriptions s
        where s.id <> new.id and s.status in ('active', 'expired') and s.venue_id = new.venue_id
          and ((new.gym_member_id is not null and s.gym_member_id = new.gym_member_id)
               or (new.gym_member_id is null and s.member_id = new.member_id)));
      perform public.gym_audit(new.venue_id, 'membership.sold',
                               case when v_renewal then 'Renewed ' || v_name || '''s membership'
                                    else 'Sold ' || v_name || ' a package' end,
                               v_dates, new.gym_member_id, v_name);
    elsif new.status = 'pending' then
      perform public.gym_audit(new.venue_id, 'membership.requested', v_name || ' asked for ' || new.plan_name, null,
                               new.gym_member_id, v_name);
    end if;
  elsif old.status = 'pending' and new.status = 'active' then
    perform public.gym_audit(new.venue_id, 'membership.confirmed', 'Started ' || v_name || '''s ' || new.plan_name, v_dates,
                             new.gym_member_id, v_name);
  elsif new.status = 'cancelled' and old.status <> 'cancelled' then
    perform public.gym_audit(new.venue_id, 'membership.cancelled',
                             case when new.member_id = (select auth.uid()) then v_name || ' took back their request for ' || new.plan_name
                                  else 'Cancelled ' || v_name || '''s ' || new.plan_name end,
                             null, new.gym_member_id, v_name);
  end if;
  return null;
end;
$$;

-- Offers: added, changed (name, how much, on or off).
create or replace function public.gym_audit_offers()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changes text[];
begin
  if tg_op = 'INSERT' then
    perform public.gym_audit(new.venue_id, 'offer.added', 'Added the offer ' || new.name,
                             case new.kind when 'percent' then new.value || '% off' else public.gym_audit_nu(new.value) || ' off' end);
  else
    v_changes := array_remove(array[
      case when new.name <> old.name then 'renamed from ' || old.name end,
      case when (new.kind, new.value) is distinct from (old.kind, old.value)
           then case old.kind when 'percent' then old.value || '%' else public.gym_audit_nu(old.value) end || ' off to '
                || case new.kind when 'percent' then new.value || '%' else public.gym_audit_nu(new.value) end || ' off' end,
      case when old.is_active and not new.is_active then 'no longer offered' end,
      case when new.is_active and not old.is_active then 'offered again' end
    ], null);
    if cardinality(v_changes) > 0 then
      perform public.gym_audit(new.venue_id, 'offer.changed', 'Changed the offer ' || new.name, array_to_string(v_changes, ' · '));
    end if;
  end if;
  return null;
end;
$$;
drop trigger if exists gym_offers_audit on public.gym_offers;
create trigger gym_offers_audit after insert or update on public.gym_offers
  for each row execute function public.gym_audit_offers();
revoke execute on function public.gym_audit_offers() from public, anon, authenticated;
