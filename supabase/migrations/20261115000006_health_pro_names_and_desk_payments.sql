-- Health Pro: the member hears when the desk takes their payment, and the
-- database speaks of Health Pro, not SportsHub.
--
-- - gym_renew_member (a package sold or renewed on the member's page, paid
--   at the desk, or an online payment the desk confirmed): the member, if
--   they have an account, is told "Payment confirmed", with the amount, the
--   journal number and until when their package runs. So
--   gym_confirm_payment_claim no longer tells them itself (they'd hear it
--   twice).
-- - The messages and notifications of functions from before the rebrand
--   say Health Pro (each function as it was, with only that changed); so do
--   the Administrator role's description, if nobody changed it, and the
--   notifications already sent.
--
-- Safe to run again.


-- ---------------------------------------------------------------------
-- 1. Paying at the desk: the member is told
-- ---------------------------------------------------------------------

create or replace function public.gym_renew_member(gym_member_id uuid, plan_id uuid, months int, amount int,
                                                   method text default null, reference text default null)
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
                                            gym_renew_member.method, gym_renew_member.reference);

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

-- The gym found the payment: the package starts (from the day the current
-- one ends, or today), the payment is recorded with its journal number, and
-- the member is told (by gym_renew_member).
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
  return v_membership;
end;
$$;


-- ---------------------------------------------------------------------
-- 2. Health Pro in messages from before the rebrand
-- ---------------------------------------------------------------------

-- From 20261107000003_gym_membership.sql.
create or replace function public.gym_require_gym(venue uuid)
returns public.venues
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_venue public.venues;
begin
  select * into v_venue from public.venues v where v.id = venue;
  if not found or v_venue.type <> 'gym' then
    raise exception 'This gym isn''t on Health Pro.';
  end if;
  return v_venue;
end;
$$;

-- From 20261107000003_gym_membership.sql.
create or replace function public.gym_request_subscription(plan_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_plan uuid := gym_request_subscription.plan_id;
  v_user uuid := (select auth.uid());
  v_plan public.gym_plans;
  v_venue public.venues;
  v_member text;
  v_id uuid;
begin
  if v_user is null then
    raise exception 'Please sign in first.';
  end if;
  select * into v_plan from public.gym_plans pl where pl.id = p_plan;
  if not found or not v_plan.is_active then
    raise exception 'This plan is no longer offered.';
  end if;
  v_venue := public.gym_require_gym(v_plan.venue_id);
  if v_venue.verification_status <> 'verified' then
    raise exception 'This gym isn''t taking members on Health Pro yet.';
  end if;
  if not exists (select 1 from public.app_modules m where m.key = 'gym_membership' and m.is_enabled)
     and not public.is_admin() then
    raise exception 'Gym memberships aren''t open yet.';
  end if;
  if exists (select 1 from public.gym_subscriptions s
             where s.venue_id = v_venue.id and s.member_id = v_user and s.status = 'pending') then
    raise exception 'You already have a request waiting at this gym.';
  end if;

  insert into public.gym_subscriptions (venue_id, member_id, plan_id, plan_name, duration_days, price)
  values (v_venue.id, v_user, v_plan.id, v_plan.name, v_plan.duration_days, v_plan.price)
  returning gym_subscriptions.id into v_id;

  select coalesce(nullif(trim(p.full_name), ''), 'A member') into v_member from public.profiles p where p.id = v_user;
  perform public.notify_venue_staff(
    v_venue.id, 'gym_membership', 'New membership request',
    v_member || ' asked for ' || v_plan.name || ' (Nu. ' || v_plan.price || '). Confirm it once they have paid.',
    '/gyms/' || v_venue.id || '/manage/requests');
  return v_id;
end;
$$;

-- From 20261108000003_gym_permissions.sql.
create or replace function public.gym_check_in(venue_id uuid, member_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_check_in.venue_id;
  p_member uuid := gym_check_in.member_id;
  v_today date := public.bhutan_today();
  v_sub public.gym_subscriptions;
  v_profile public.profiles;
  v_other public.gym_subscriptions;
  v_earlier int;
begin
  perform public.gym_require_gym(p_venue);
  if not public.has_venue_permission(p_venue, 'gym.check_in') then
    raise exception 'Only the gym''s staff can check members in.';
  end if;
  select * into v_profile from public.profiles p where p.id = p_member;
  if not found then
    raise exception 'That isn''t a Health Pro member.';
  end if;

  v_sub := public.gym_current_subscription(p_venue, p_member, v_today);
  if v_sub.id is null then
    -- Why not: the most telling of their memberships here.
    select * into v_other from public.gym_subscriptions s
    where s.venue_id = p_venue and s.member_id = p_member and s.status in ('active', 'pending', 'expired')
    order by case when s.status = 'active' then 0 when s.status = 'pending' then 1 else 2 end,
             s.end_date desc nulls last
    limit 1;
    if v_other.id is null then
      raise exception '% has no membership at this gym.', coalesce(nullif(trim(v_profile.full_name), ''), 'This member');
    elsif v_other.status = 'active' then
      raise exception 'Their membership starts on %.', to_char(v_other.start_date, 'FMDD Mon YYYY');
    elsif v_other.status = 'pending' then
      raise exception 'Their request for % is waiting: confirm their payment first.', v_other.plan_name;
    else
      raise exception 'Their membership ended on %.', to_char(v_other.end_date, 'FMDD Mon YYYY');
    end if;
  end if;

  select count(*) into v_earlier from public.gym_check_ins c
  where c.venue_id = p_venue and c.member_id = p_member
    and (c.checked_in_at at time zone 'Asia/Thimphu')::date = v_today;

  insert into public.gym_check_ins (venue_id, member_id, subscription_id, recorded_by)
  values (p_venue, p_member, v_sub.id, (select auth.uid()));

  return jsonb_build_object(
    'member_name', coalesce(nullif(trim(v_profile.full_name), ''), 'Member'),
    'member_code', v_profile.member_code,
    'plan_name', v_sub.plan_name,
    'end_date', v_sub.end_date,
    'days_left', v_sub.end_date - v_today + 1,
    'earlier_today', v_earlier
  );
end;
$$;

-- From 20261107000001_core.sql.
create or replace function public.save_review(venue_id uuid, rating int, comment text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := save_review.venue_id;
  p_rating int := save_review.rating;
  p_comment text := nullif(trim(save_review.comment), '');
  v_user uuid := (select auth.uid());
  v_name text;
begin
  if v_user is null then
    raise exception 'Please sign in first.';
  end if;
  if p_rating is null or p_rating not between 1 and 5 then
    raise exception 'Give 1 to 5 stars.';
  end if;
  if not exists (select 1 from public.venues v where v.id = p_venue and v.verification_status = 'verified') then
    raise exception 'This venue isn''t on Health Pro.';
  end if;
  if public.is_venue_staff(p_venue) then
    raise exception 'You can''t review a venue you run.';
  end if;
  if not public.has_used_venue(p_venue) then
    raise exception 'Only members who have used this venue can review it.';
  end if;
  select coalesce(nullif(trim(p.full_name), ''), 'Member') into v_name from public.profiles p where p.id = v_user;
  insert into public.reviews (venue_id, user_id, reviewer_name, rating, comment)
  values (p_venue, v_user, v_name, p_rating, p_comment)
  on conflict on constraint reviews_one_per_user do update
    set rating = excluded.rating, comment = excluded.comment, reviewer_name = excluded.reviewer_name;
  perform public.notify_venue_staff(p_venue, null, 'New review: ' || p_rating || ' stars', p_comment,
                                    '/manage/' || p_venue, array['owner', 'manager']);
end;
$$;

-- From 20261108000001_masters_and_access.sql.
create or replace function public.review_venue(venue_id uuid, approve boolean, note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := review_venue.venue_id;
  p_approve boolean := review_venue.approve;
  p_note text := nullif(trim(review_venue.note), '');
  v_name text;
begin
  if not public.has_permission('venues.verify') then
    raise exception 'Only the Health Pro team can verify venues.';
  end if;
  if not p_approve and p_note is null then
    raise exception 'Say why it is sent back, so the owner can fix it.';
  end if;
  update public.venues v set
    verification_status = case when p_approve then 'verified' else 'rejected' end,
    verification_note   = case when p_approve then null else p_note end,
    verified_at         = case when p_approve then now() else null end,
    verified_by         = case when p_approve then (select auth.uid()) else null end
  where v.id = p_venue
  returning v.name into v_name;
  if v_name is null then
    raise exception 'This venue no longer exists.';
  end if;
  perform public.notify_venue_staff(
    p_venue, null,
    case when p_approve then v_name || ' is live on Health Pro' else v_name || ' needs changes' end,
    case when p_approve then 'Members can now find it and join.' else p_note end,
    '/manage/' || p_venue, array['owner', 'manager']);
end;
$$;

-- From 20261108000001_masters_and_access.sql.
create or replace function public.add_venue_staff(venue_id uuid, email text, staff_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_email text := lower(trim(add_venue_staff.email));
  v_user uuid;
begin
  if not (public.has_venue_permission(add_venue_staff.venue_id, 'venue.staff') or public.has_permission('users.manage')) then
    raise exception 'Only people who manage this venue''s staff can add staff.';
  end if;
  select p.id into v_user from public.profiles p where lower(p.email) = p_email;
  if v_user is null then
    raise exception 'No Health Pro account uses %. Make their account instead.', p_email;
  end if;
  perform public.set_venue_staff_role(add_venue_staff.venue_id, v_user, add_venue_staff.staff_role);
end;
$$;

-- From 20261108000001_masters_and_access.sql.
create or replace function public.remove_venue_staff(venue_id uuid, staff_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := remove_venue_staff.venue_id;
  p_user uuid := remove_venue_staff.staff_user_id;
  v_current text;
begin
  select s.role into v_current from public.venue_staff s where s.venue_id = p_venue and s.user_id = p_user for update;
  if public.has_permission('users.manage') then
    if v_current = 'owner' and not exists (select 1 from public.venue_staff s
                                           where s.venue_id = p_venue and s.role = 'owner' and s.user_id <> p_user) then
      raise exception 'A venue needs an owner. Make someone else the owner first.';
    end if;
  else
    if not public.has_venue_permission(p_venue, 'venue.staff') then
      raise exception 'Only people who manage this venue''s staff can remove staff.';
    end if;
    if v_current = 'owner' then
      raise exception 'The owner can''t be removed. Ask the Health Pro team to hand the venue over.';
    end if;
    if p_user = (select auth.uid()) then
      raise exception 'You can''t remove yourself. Ask the owner.';
    end if;
    if v_current is not null and not public.can_give_role((select r.id from public.roles r where r.key = v_current), p_venue) then
      raise exception 'You can only remove people whose permissions you have yourself.';
    end if;
  end if;
  delete from public.venue_staff s where s.venue_id = p_venue and s.user_id = p_user;
end;
$$;

-- From 20261108000001_masters_and_access.sql.
create or replace function public.set_module_enabled(module_key text, enabled boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not public.has_permission('modules.manage') then
    raise exception 'Only the Health Pro team can turn modules on and off.';
  end if;
  update public.app_modules m set is_enabled = set_module_enabled.enabled where m.key = set_module_enabled.module_key;
  if not found then
    raise exception 'There is no module %.', set_module_enabled.module_key;
  end if;
end;
$$;

-- From 20261108000001_masters_and_access.sql.
create or replace function public.set_user_platform_roles(user_id uuid, role_ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_user uuid := set_user_platform_roles.user_id;
  p_roles uuid[] := coalesce(set_user_platform_roles.role_ids, '{}');
  v_changed uuid[];
begin
  if not public.has_permission('users.manage') then
    raise exception 'Only people who manage users can give roles.';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_user) then
    raise exception 'This account no longer exists.';
  end if;
  if exists (select 1 from unnest(p_roles) r
             where not exists (select 1 from public.roles x where x.id = r and x.scope = 'platform')) then
    raise exception 'Those aren''t all Health Pro team roles.';
  end if;
  -- Roles given or taken away: only ones the caller could give.
  select coalesce(array_agg(r), '{}') into v_changed from (
    (select unnest(p_roles) except select ur.role_id from public.user_roles ur where ur.user_id = p_user)
    union
    (select ur.role_id from public.user_roles ur where ur.user_id = p_user except select unnest(p_roles))
  ) c (r);
  if exists (select 1 from unnest(v_changed) r where not public.can_give_role(r)) then
    raise exception 'You can only give or take away roles whose permissions you have yourself.';
  end if;

  delete from public.user_roles ur where ur.user_id = p_user and not (ur.role_id = any (p_roles));
  insert into public.user_roles (user_id, role_id, assigned_by)
  select p_user, r, (select auth.uid()) from unnest(p_roles) r
  on conflict do nothing;
end;
$$;

-- From 20261111000001_organisations_and_roles.sql.
create or replace function public.save_role(role_id uuid, scope text, name text, description text, active boolean,
                                            permission_keys text[], organisation_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_id uuid := save_role.role_id;
  p_name text := regexp_replace(trim(coalesce(save_role.name, '')), '\s+', ' ', 'g');
  p_description text := nullif(trim(save_role.description), '');
  p_active boolean := coalesce(save_role.active, true);
  p_keys text[] := array(select distinct k from unnest(coalesce(save_role.permission_keys, '{}')) k);
  v_team boolean := public.has_permission('roles.manage');
  v_role public.roles;
  v_scope text;
  v_org uuid;
  v_before text[] := '{}';
  v_check text[];
  v_key text;
  v_n int := 1;
begin
  if p_id is null then
    v_scope := save_role.scope;
    v_org := save_role.organisation_id;
    if v_scope is null or v_scope not in ('platform', 'venue') then
      raise exception 'Choose whether the role is for the Health Pro team or for venues.';
    end if;
    if v_org is not null then
      if v_scope <> 'venue' then
        raise exception 'An organisation''s own roles are for its venues.';
      end if;
      if not exists (select 1 from public.organisations o where o.id = v_org) then
        raise exception 'This organisation no longer exists.';
      end if;
    end if;
  else
    select * into v_role from public.roles r where r.id = p_id for update;
    if not found then
      raise exception 'This role no longer exists.';
    end if;
    v_scope := v_role.scope;
    v_org := v_role.organisation_id;
    v_before := array(select rp.permission_key from public.role_permissions rp where rp.role_id = p_id);
  end if;

  -- Who may: the team's role managers any role; an organisation's people
  -- only its own.
  if v_org is null then
    if not v_team then
      raise exception 'Only people who manage roles can change them.';
    end if;
  elsif not public.can_manage_organisation_roles(v_org) then
    raise exception 'Only people who manage this organisation''s roles can change them.';
  end if;
  if v_role.key = 'owner' then
    raise exception 'The Owner role always has every permission and can''t be changed.';
  end if;
  if char_length(p_name) not between 2 and 60 then
    raise exception 'Enter the role''s name (2 to 60 letters).';
  end if;
  if v_org is not null and exists (select 1 from public.roles r
                                   where r.organisation_id is null and r.scope = 'venue' and lower(r.name) = lower(p_name)) then
    raise exception 'Health Pro already has a % role: change what it allows for this organisation instead.', p_name;
  end if;
  if exists (select 1 from unnest(p_keys) k
             where not exists (select 1 from public.permissions pm where pm.key = k and pm.scope = v_scope)) then
    raise exception 'Some of those permissions aren''t for this kind of role.';
  end if;

  -- Nobody hands on what they don't have. Team roles: unless a super admin.
  -- An organisation's role, for its own people: what they add or take away,
  -- and all of it when they turn the role on or off, only from what they
  -- have at all of its venues. (Venue roles the team makes are templates:
  -- the venue staff rules apply when they are given.)
  if v_scope = 'platform' and not public.is_admin()
     and exists (select 1 from unnest(p_keys) k where not public.has_permission(k)) then
    raise exception 'You can only give a role permissions you have yourself.';
  end if;
  if v_org is not null and not v_team then
    v_check := array((select unnest(p_keys) except select unnest(v_before))
                     union (select unnest(v_before) except select unnest(p_keys)));
    if p_id is not null and v_role.is_active is distinct from p_active then
      v_check := v_check || p_keys || v_before;
    end if;
    if exists (select 1 from unnest(v_check) k where not public.has_organisation_permission(v_org, k)) then
      raise exception 'You can only give or take away permissions you have yourself, at all of the organisation''s venues.';
    end if;
  end if;

  if p_id is null then
    v_key := left(trim(both '_' from regexp_replace(lower(p_name), '[^a-z0-9]+', '_', 'g')), 36);
    if v_key !~ '^[a-z]' then
      v_key := 'role_' || v_key;
    end if;
    if char_length(v_key) < 2 then
      v_key := 'role';
    end if;
    while exists (select 1 from public.roles r where r.key = case when v_n = 1 then v_key else v_key || '_' || v_n end) loop
      v_n := v_n + 1;
    end loop;
    if v_n > 1 then
      v_key := v_key || '_' || v_n;
    end if;
    insert into public.roles (key, scope, organisation_id, name, description, is_active, created_by)
    values (v_key, v_scope, v_org, p_name, p_description, p_active, (select auth.uid()))
    returning * into v_role;
  else
    update public.roles r set name = p_name, description = p_description, is_active = p_active
    where r.id = p_id returning * into v_role;
  end if;

  delete from public.role_permissions rp where rp.role_id = v_role.id and not (rp.permission_key = any (p_keys));
  insert into public.role_permissions (role_id, permission_key)
  select v_role.id, k from unnest(p_keys) k
  on conflict do nothing;
  return v_role.id;
exception when unique_violation then
  raise exception 'There is already a role called %.', p_name;
end;
$$;

-- From 20261111000001_organisations_and_roles.sql.
create or replace function public.delete_role(role_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_role public.roles;
  v_people int;
begin
  select * into v_role from public.roles r where r.id = delete_role.role_id for update;
  if not found then
    return;
  end if;
  if v_role.organisation_id is null then
    if not public.has_permission('roles.manage') then
      raise exception 'Only people who manage roles can change them.';
    end if;
  elsif not public.can_manage_organisation_roles(v_role.organisation_id) then
    raise exception 'Only people who manage this organisation''s roles can change them.';
  end if;
  if v_role.is_system then
    raise exception '% comes with Health Pro and can''t be deleted. Turn it off instead.', v_role.name;
  end if;
  select (select count(*) from public.user_roles ur where ur.role_id = v_role.id)
       + (select count(*) from public.venue_staff s where s.role = v_role.key)
  into v_people;
  if v_people > 0 then
    raise exception '% people have this role. Give them another role first, or turn it off.', v_people;
  end if;
  delete from public.roles r where r.id = v_role.id;
end;
$$;

-- From 20261111000001_organisations_and_roles.sql.
create or replace function public.set_venue_staff_role(venue_id uuid, user_id uuid, role_key text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := set_venue_staff_role.venue_id;
  p_user uuid := set_venue_staff_role.user_id;
  p_role text := set_venue_staff_role.role_key;
  v_me uuid := (select auth.uid());
  v_role public.roles;
  v_current text;
  v_platform boolean := public.has_permission('users.manage');
  v_venue_name text;
  v_org uuid;
begin
  select v.name, v.organisation_id into v_venue_name, v_org from public.venues v where v.id = p_venue;
  if v_venue_name is null then
    raise exception 'This venue no longer exists.';
  end if;
  select * into v_role from public.roles r
  where r.key = p_role and r.scope = 'venue' and (r.organisation_id is null or r.organisation_id = v_org);
  if not found then
    raise exception 'Choose one of the venue roles.';
  end if;
  if not public.role_is_on_at(v_role.id, v_org) then
    raise exception 'The % role is turned off.', v_role.name;
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_user) then
    raise exception 'This account no longer exists.';
  end if;
  select s.role into v_current from public.venue_staff s where s.venue_id = p_venue and s.user_id = p_user for update;

  -- Who may first, so nobody learns anything from a change that changes nothing.
  if v_platform then
    if v_current = 'owner' and p_role <> 'owner'
       and not exists (select 1 from public.venue_staff s
                       where s.venue_id = p_venue and s.role = 'owner' and s.user_id <> p_user) then
      raise exception 'A venue needs an owner. Make someone else the owner first.';
    end if;
  else
    if not public.has_venue_permission(p_venue, 'venue.staff') then
      raise exception 'Only people who manage this venue''s staff can do this.';
    end if;
    if p_user = v_me then
      raise exception 'You can''t change your own role.';
    end if;
    if p_role = 'owner' then
      raise exception 'Only the Health Pro team can make someone an owner.';
    end if;
    if v_current = 'owner' then
      raise exception 'They own this venue already.';
    end if;
    if not public.can_give_role(v_role.id, p_venue)
       or (v_current is not null and not public.can_give_role((select r.id from public.roles r where r.key = v_current), p_venue)) then
      raise exception 'You can only give roles whose permissions you have yourself.';
    end if;
  end if;
  if v_current is not distinct from p_role then
    return;
  end if;

  insert into public.venue_staff (venue_id, user_id, role, added_by)
  values (p_venue, p_user, p_role, v_me)
  on conflict on constraint venue_staff_pkey do update set role = excluded.role;

  perform public.notify(p_user, null,
                        case when v_current is null then 'You were added to ' || v_venue_name
                             else 'Your role at ' || v_venue_name || ' changed' end,
                        'You are ' || v_role.name || ' there. Find it under Your venues.', '/manage/' || p_venue);
end;
$$;

-- From 20261111000001_organisations_and_roles.sql.
create or replace function public.set_venue_organisation(venue_id uuid, organisation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := set_venue_organisation.venue_id;
  p_org uuid := set_venue_organisation.organisation_id;
  v_venue public.venues;
  v_roles text;
begin
  if not public.has_permission('organisations.manage') then
    raise exception 'Only people who manage organisations can move venues.';
  end if;
  select * into v_venue from public.venues v where v.id = p_venue for update;
  if not found then
    raise exception 'This venue no longer exists.';
  end if;
  if not exists (select 1 from public.organisations o where o.id = p_org) then
    raise exception 'This organisation no longer exists.';
  end if;
  if v_venue.organisation_id = p_org then
    return;
  end if;
  select string_agg(distinct r.name, ', ') into v_roles
  from public.venue_staff s join public.roles r on r.key = s.role
  where s.venue_id = p_venue and r.organisation_id = v_venue.organisation_id;
  if v_roles is not null then
    raise exception 'Some of its staff have its organisation''s own roles (%). Give them Health Pro-wide roles first.', v_roles;
  end if;
  update public.venues v set organisation_id = p_org where v.id = p_venue;
end;
$$;

-- From 20261114000003_ai_public_cap.sql.
create or replace function public.ai_take_public_question(client text)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_each constant int := 15;
  v_everyone constant int := 150;
  v_day_start timestamptz := public.bhutan_today()::timestamp at time zone 'Asia/Thimphu';
  v_all int;
  v_mine int;
begin
  if client is null or length(client) < 16 then
    raise exception 'Who is asking?';
  end if;

  select count(*) into v_all from public.ai_public_questions q where q.asked_at >= v_day_start;
  if v_all >= v_everyone then
    raise exception 'Health Pro''s assistant has answered all it can for today. Ask again tomorrow; the suggestions still work.';
  end if;
  select count(*) into v_mine
  from public.ai_public_questions q
  where q.client_hash = client and q.asked_at >= v_day_start;
  if v_mine >= v_each then
    raise exception 'You''ve asked % questions today. Ask again tomorrow; the suggestions still work.', v_each;
  end if;

  insert into public.ai_public_questions (client_hash) values (client);
  delete from public.ai_public_questions q where q.asked_at < now() - interval '30 days';
  return v_each - v_mine - 1;
end;
$$;


-- ---------------------------------------------------------------------
-- 3. Health Pro in what's saved already
-- ---------------------------------------------------------------------

-- The Administrator role, unless the team wrote their own description.
update public.roles r set description = 'Runs Health Pro day to day: users, roles, masters, venues and modules'
where r.key = 'platform_admin'
  and r.description = 'Runs SportsHub day to day: users, roles, masters, venues and modules';

-- Notifications sent before (e.g. "Peak Fitness is live on SportsHub").
-- Changing them sends nothing: pushes go out only for new ones.
update public.notifications n set
  title = left(replace(n.title, 'SportsHub', 'Health Pro'), 200),
  body  = left(replace(n.body, 'SportsHub', 'Health Pro'), 1000)
where n.title like '%SportsHub%' or n.body like '%SportsHub%';
