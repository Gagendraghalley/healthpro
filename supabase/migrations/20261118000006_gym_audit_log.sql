-- The activity log: who did what at a gym, and when. Every registration,
-- change to a member's details or card, package sold or renewed, payment
-- taken, online payment answered, pause, cancellation, change to a package
-- or its price, and change to the staff. Cash changes hands at the desk, so
-- the owner can see who took what.
--
-- Triggers on those tables write it, so whichever function makes a change,
-- it's in. Nobody can change or delete an entry, the owner included. Only
-- what people do in the app: the daily job's changes (packages ending, old
-- requests closing) are left out.
--
-- One action is one entry: what one call does (register a member, sell
-- them a package, take the payment) is joined into a line, with the parts
-- after it: 'Registered Sonam Dorji (ABC234)' · 'Monthly, 18 Nov 2026 to
-- 18 Feb 2027 · Nu. 4,500 cash · receipt 12'.
--
-- Seen by the new venue permission 'gym.activity': owners, and managers by
-- default. Safe to re-run.

do $$
declare
  v_new boolean;
begin
  with saved as (
    insert into public.permissions (key, scope, module_key, name, description, sort_order)
    values ('gym.activity', 'venue', 'gym_membership', 'Activity log',
            'See who registered, sold, took payments, paused or cancelled what, and when', 180)
    on conflict (key) do update
      set name = excluded.name, description = excluded.description, sort_order = excluded.sort_order
    returning (xmax = 0) as inserted
  )
  select inserted into v_new from saved;
  if v_new then
    insert into public.role_permissions (role_id, permission_key)
    select r.id, 'gym.activity' from public.roles r where r.key in ('owner', 'manager')
    on conflict do nothing;
  end if;
end;
$$;

create table if not exists public.gym_audit_log (
  id            bigint generated always as identity primary key,
  venue_id      uuid not null references public.venues (id) on delete cascade,
  actor_id      uuid constraint gym_audit_log_actor_id_fkey references public.profiles (id) on delete set null,
  actor_name    text not null default '', -- as they were called then
  action        text not null,            -- 'member.registered', 'payment.received', ...
  summary       text not null,            -- 'Registered Sonam Dorji (ABC234)'
  details       text not null default '', -- 'Monthly, 18 Nov 2026 to 18 Feb 2027 · Nu. 4,500 cash · receipt 12'
  gym_member_id uuid constraint gym_audit_log_gym_member_id_fkey references public.gym_members (id) on delete set null,
  member_name   text,
  amount        int,
  tx            bigint not null default txid_current(), -- the transaction, to join one action's entries
  created_at    timestamptz not null default now()
);
create index if not exists gym_audit_log_venue on public.gym_audit_log (venue_id, created_at desc);
create index if not exists gym_audit_log_member on public.gym_audit_log (gym_member_id, created_at desc);

-- Read by who may see it; written only by the functions below.
alter table public.gym_audit_log enable row level security;
revoke all on public.gym_audit_log from anon, authenticated;
grant select on public.gym_audit_log to authenticated;
drop policy if exists "gym_audit_log: who sees activity" on public.gym_audit_log;
create policy "gym_audit_log: who sees activity" on public.gym_audit_log for select to authenticated
  using (public.has_venue_permission(venue_id, 'gym.activity'));

-- 'Nu. 4,500' and '18 Nov 2026', as the app writes them.
create or replace function public.gym_audit_nu(amount int)
returns text
language sql
stable
set search_path = ''
as $$
  select 'Nu. ' || to_char(amount, 'FM999,999,999,990')
$$;

create or replace function public.gym_audit_day(day date)
returns text
language sql
stable
set search_path = ''
as $$
  select to_char(day, 'FMDD Mon YYYY')
$$;

-- Which entry names a joined action: registering beats confirming beats
-- selling beats the payment.
create or replace function public.gym_audit_rank(action text)
returns int
language sql
immutable
set search_path = ''
as $$
  select case action
    when 'member.registered' then 3
    when 'claim.confirmed' then 2
    when 'membership.confirmed' then 2
    when 'payment.received' then 0
    else 1
  end
$$;

-- Writes an entry by the signed-in person, or joins it to the one their
-- call already wrote for the same member. Nothing without a person (the
-- daily job), or for a gym or member being deleted.
create or replace function public.gym_audit(p_venue uuid, p_action text, p_summary text, p_details text default null,
                                           p_member uuid default null, p_member_name text default null,
                                           p_amount int default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_member uuid := p_member;
  v_rank int := public.gym_audit_rank(p_action);
  v_row public.gym_audit_log;
begin
  if v_actor is null or p_venue is null or p_summary is null
     or not exists (select 1 from public.venues v where v.id = p_venue) then
    return;
  end if;
  if v_member is not null and not exists (select 1 from public.gym_members g where g.id = v_member) then
    v_member := null;
  end if;
  select * into v_row from public.gym_audit_log l
  where l.tx = txid_current() and l.venue_id = p_venue and l.actor_id = v_actor
    and l.gym_member_id is not distinct from v_member
  order by l.id desc
  limit 1;
  if v_row.id is not null then
    update public.gym_audit_log l
       set action = case when v_rank > public.gym_audit_rank(l.action) then p_action else l.action end,
           summary = case when v_rank > public.gym_audit_rank(l.action) then p_summary else l.summary end,
           details = concat_ws(' · ', nullif(l.details, ''), nullif(p_details, '')),
           amount = coalesce(l.amount, p_amount),
           member_name = coalesce(l.member_name, p_member_name)
     where l.id = v_row.id;
    return;
  end if;
  insert into public.gym_audit_log (venue_id, actor_id, actor_name, action, summary, details, gym_member_id, member_name, amount)
  values (p_venue, v_actor, coalesce((select pr.full_name from public.profiles pr where pr.id = v_actor), ''), p_action,
          p_summary, coalesce(p_details, ''), v_member, p_member_name, p_amount);
end;
$$;


-- ---------------------------------------------------------------------
-- What each table's changes say
-- ---------------------------------------------------------------------

-- Registered, details or card changed, removed.
create or replace function public.gym_audit_members()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changes text[];
begin
  if tg_op = 'INSERT' then
    perform public.gym_audit(new.venue_id, 'member.registered', 'Registered ' || new.full_name || ' (' || new.code || ')',
                             null, new.id, new.full_name);
  elsif tg_op = 'DELETE' then
    perform public.gym_audit(old.venue_id, 'member.removed',
                             'Removed ' || old.full_name || ' (' || old.code || ') from the register', null, null, old.full_name);
  else
    if new.qr_token is distinct from old.qr_token then
      perform public.gym_audit(new.venue_id, 'member.card_reissued', 'Gave ' || new.full_name || ' a new QR card',
                               'Their old card no longer works', new.id, new.full_name);
    end if;
    v_changes := array_remove(array[
      case when new.full_name is distinct from old.full_name then 'name (was ' || old.full_name || ')' end,
      case when new.phone is distinct from old.phone then 'phone (was ' || old.phone || ')' end,
      case when new.email is distinct from old.email then 'email' end,
      case when new.date_of_birth is distinct from old.date_of_birth then 'date of birth' end,
      case when new.blood_group is distinct from old.blood_group then 'blood group' end,
      case when new.occupation is distinct from old.occupation then 'occupation' end,
      case when (new.dzongkhag_id, new.gewog_id, new.village_id) is distinct from (old.dzongkhag_id, old.gewog_id, old.village_id)
           then 'address' end,
      case when (new.emergency_contact_name, new.emergency_contact_phone)
                is distinct from (old.emergency_contact_name, old.emergency_contact_phone) then 'emergency contact' end,
      case when new.medical_notes is distinct from old.medical_notes then 'medical notes' end,
      case when new.joined_on is distinct from old.joined_on then 'joining date' end,
      -- Their first photo is part of registering them.
      case when old.photo_path is not null and new.photo_path is distinct from old.photo_path then 'photo' end
    ], null);
    if cardinality(v_changes) > 0 then
      perform public.gym_audit(new.venue_id, 'member.edited', 'Changed ' || old.full_name || '''s details',
                               'Changed ' || array_to_string(v_changes, ', '), new.id, new.full_name);
    end if;
  end if;
  return null;
end;
$$;

-- A package sold or renewed, a request, confirmed, cancelled. Dates a pause
-- moves are the pause's entry.
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
begin
  v_name := coalesce((select g.full_name from public.gym_members g where g.id = new.gym_member_id),
                     (select p.full_name from public.profiles p where p.id = new.member_id), 'a member');
  v_dates := new.plan_name || case when new.start_date is null then ''
                                   else ', ' || public.gym_audit_day(new.start_date) || ' to ' || public.gym_audit_day(new.end_date) end;
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

-- Money in (and refunds): how much, how, the journal number and receipt.
create or replace function public.gym_audit_payments()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sub public.gym_subscriptions;
  v_name text;
  v_how text;
begin
  if new.module_key <> 'gym_membership' then
    return null;
  end if;
  select * into v_sub from public.gym_subscriptions s where s.id = new.reference_id;
  v_name := coalesce(nullif(trim(new.payer_name), ''),
                     (select g.full_name from public.gym_members g where g.id = v_sub.gym_member_id),
                     (select p.full_name from public.profiles p where p.id = coalesce(new.user_id, v_sub.member_id)), 'a member');
  v_how := case new.method when 'mbob' then 'mBoB' when 'cash' then 'cash' when 'bank' then 'bank transfer' else 'other' end
           || coalesce(', JRN ' || new.reference, '');
  if tg_op = 'INSERT' then
    perform public.gym_audit(new.venue_id, 'payment.received', 'Received ' || public.gym_audit_nu(new.amount) || ' from ' || v_name,
                             public.gym_audit_nu(new.amount) || ' ' || v_how || coalesce(' · receipt ' || new.receipt_no, ''),
                             v_sub.gym_member_id, v_name, new.amount);
  elsif new.status = 'refunded' and old.status <> 'refunded' then
    perform public.gym_audit(new.venue_id, 'payment.refunded', 'Refunded ' || public.gym_audit_nu(new.amount) || ' to ' || v_name,
                             coalesce('Receipt ' || new.receipt_no, ''), v_sub.gym_member_id, v_name, new.amount);
  end if;
  return null;
end;
$$;

-- Paused, resumed early, taken back before it began.
create or replace function public.gym_audit_pauses()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.gym_membership_pauses;
  v_name text;
  v_days int;
begin
  if tg_op = 'DELETE' then p := old; else p := new; end if;
  select g.full_name into v_name from public.gym_members g where g.id = p.gym_member_id;
  if v_name is null then
    return null; -- the member is being removed
  end if;
  if tg_op = 'INSERT' then
    v_days := new.end_date - new.start_date + 1;
    perform public.gym_audit(new.venue_id, 'membership.paused',
                             'Paused ' || v_name || '''s membership for ' || v_days || case when v_days = 1 then ' day' else ' days' end,
                             public.gym_audit_day(new.start_date) || ' to ' || public.gym_audit_day(new.end_date)
                               || coalesce(' · ' || new.reason, ''),
                             new.gym_member_id, v_name);
  elsif tg_op = 'UPDATE' then
    if old.ended_at is null and new.ended_at is not null then
      perform public.gym_audit(new.venue_id, 'membership.resumed', 'Resumed ' || v_name || '''s membership',
                               'Back early: the pause ended on ' || public.gym_audit_day(new.end_date) || ', not '
                                 || public.gym_audit_day(old.end_date),
                               new.gym_member_id, v_name);
    end if;
  else
    perform public.gym_audit(old.venue_id, 'membership.pause_taken_back', 'Took back ' || v_name || '''s pause',
                             'It was to run ' || public.gym_audit_day(old.start_date) || ' to ' || public.gym_audit_day(old.end_date),
                             old.gym_member_id, v_name);
  end if;
  return null;
end;
$$;

-- Online payments: sent by the member, then confirmed, turned down or taken
-- back. Confirming joins the renewal and payment it makes.
create or replace function public.gym_audit_claims()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_paid text := public.gym_audit_nu(new.amount);
begin
  v_name := coalesce((select g.full_name from public.gym_members g where g.id = new.gym_member_id), 'a member');
  if tg_op = 'INSERT' then
    perform public.gym_audit(new.venue_id, 'claim.sent', v_name || ' paid ' || v_paid || ' online',
                             new.plan_name || ', ' || new.months || case when new.months = 1 then ' month' else ' months' end
                               || ' · JRN ' || new.jrn,
                             new.gym_member_id, v_name, new.amount);
  elsif old.status = 'pending' and new.status = 'confirmed' then
    perform public.gym_audit(new.venue_id, 'claim.confirmed', 'Confirmed ' || v_name || '''s online payment of ' || v_paid,
                             null, new.gym_member_id, v_name, new.amount);
  elsif old.status = 'pending' and new.status = 'rejected' then
    perform public.gym_audit(new.venue_id, 'claim.rejected', 'Turned down ' || v_name || '''s online payment of ' || v_paid,
                             'JRN ' || new.jrn || coalesce(' · ' || new.decision_note, ''), new.gym_member_id, v_name, new.amount);
  elsif old.status = 'pending' and new.status = 'cancelled' then
    perform public.gym_audit(new.venue_id, 'claim.cancelled',
                             case when new.user_id = (select auth.uid()) then v_name || ' took back their online payment of ' || v_paid
                                  else 'Cancelled ' || v_name || '''s online payment of ' || v_paid end,
                             'JRN ' || new.jrn, new.gym_member_id, v_name, new.amount);
  end if;
  return null;
end;
$$;

-- Packages: added, price, name, length, on sale or not; removed.
create or replace function public.gym_audit_plans()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changes text[];
begin
  if tg_op = 'INSERT' then
    perform public.gym_audit(new.venue_id, 'plan.added', 'Added the package ' || new.name,
                             public.gym_audit_nu(new.price) || ' for ' || new.duration_days || ' days');
  elsif tg_op = 'DELETE' then
    perform public.gym_audit(old.venue_id, 'plan.removed', 'Removed the package ' || old.name);
  else
    v_changes := array_remove(array[
      case when new.price <> old.price then 'price ' || public.gym_audit_nu(old.price) || ' to ' || public.gym_audit_nu(new.price) end,
      case when new.name <> old.name then 'renamed from ' || old.name end,
      case when new.duration_days <> old.duration_days then 'length ' || old.duration_days || ' to ' || new.duration_days || ' days' end,
      case when old.is_active and not new.is_active then 'no longer sold' end,
      case when new.is_active and not old.is_active then 'on sale again' end
    ], null);
    if cardinality(v_changes) > 0 then
      perform public.gym_audit(new.venue_id, 'plan.changed', 'Changed the package ' || new.name,
                               array_to_string(v_changes, ' · '));
    end if;
  end if;
  return null;
end;
$$;

-- Staff at a gym: added, role changed, removed.
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
  if not exists (select 1 from public.venues v where v.id = s.venue_id and v.type = 'gym') then
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

drop trigger if exists gym_members_audit on public.gym_members;
create trigger gym_members_audit after insert or update or delete on public.gym_members
  for each row execute function public.gym_audit_members();
drop trigger if exists gym_subscriptions_audit on public.gym_subscriptions;
create trigger gym_subscriptions_audit after insert or update on public.gym_subscriptions
  for each row execute function public.gym_audit_subscriptions();
drop trigger if exists payments_gym_audit on public.payments;
create trigger payments_gym_audit after insert or update on public.payments
  for each row execute function public.gym_audit_payments();
drop trigger if exists gym_membership_pauses_audit on public.gym_membership_pauses;
create trigger gym_membership_pauses_audit after insert or update or delete on public.gym_membership_pauses
  for each row execute function public.gym_audit_pauses();
drop trigger if exists gym_payment_claims_audit on public.gym_payment_claims;
create trigger gym_payment_claims_audit after insert or update on public.gym_payment_claims
  for each row execute function public.gym_audit_claims();
drop trigger if exists gym_plans_audit on public.gym_plans;
create trigger gym_plans_audit after insert or update or delete on public.gym_plans
  for each row execute function public.gym_audit_plans();
drop trigger if exists venue_staff_gym_audit on public.venue_staff;
create trigger venue_staff_gym_audit after insert or update or delete on public.venue_staff
  for each row execute function public.gym_audit_staff();

revoke execute on function public.gym_audit(uuid, text, text, text, uuid, text, int), public.gym_audit_members(),
  public.gym_audit_subscriptions(), public.gym_audit_payments(), public.gym_audit_pauses(), public.gym_audit_claims(),
  public.gym_audit_plans(), public.gym_audit_staff()
  from public, anon, authenticated;
