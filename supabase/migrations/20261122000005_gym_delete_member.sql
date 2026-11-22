-- Deleting a member from a gym's register. Their registration there goes,
-- and with it everything kept on it (packages, visits, pauses, trainer,
-- progress, plans, goals, class bookings, follow-ups), so they lose all
-- access to that gym. Their Health Pro account stays: they still sign in,
-- keep their other gyms, can ask to join again, and are told.
--
-- What the gym took stays: payments (income, receipts) and the activity log
-- keep their own copy of the name.
--
-- Needs 'gym.register' (the register is theirs). A membership still running,
-- paused or to come also needs 'gym.payments' (it was paid for), and is
-- deleted only when the caller confirms it (even_if_active), so nobody does
-- it by mistake. An online payment waiting to be checked is confirmed or
-- rejected first.
--
-- A person the desk registered without an account, at no other gym now, is
-- forgotten too. Safe to re-run.

create or replace function public.gym_delete_member(gym_member_id uuid, even_if_active boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_member public.gym_members;
  v_today date := public.bhutan_today();
  v_until date;
  v_user uuid;
  v_gym text;
begin
  select * into v_member from public.gym_members g where g.id = gym_delete_member.gym_member_id;
  if not found then
    raise exception 'This member is no longer registered.';
  end if;
  if not public.has_venue_permission(v_member.venue_id, 'gym.register') then
    raise exception 'Your role here can''t delete members.';
  end if;
  -- Serialises with pauses, renewals and check-ins of the same member.
  perform 1 from public.gym_members g where g.id = v_member.id for update;

  if exists (select 1 from public.gym_payment_claims c where c.gym_member_id = v_member.id and c.status = 'pending') then
    raise exception '% has an online payment waiting to be checked. Confirm or reject it first.', v_member.full_name;
  end if;
  select max(s.end_date) into v_until from public.gym_subscriptions s
  where s.gym_member_id = v_member.id and s.status = 'active' and s.end_date >= v_today;
  if v_until is not null then
    if not public.has_venue_permission(v_member.venue_id, 'gym.payments') then
      raise exception '%''s membership is active until %. Only staff who take payments can delete them.',
        v_member.full_name, to_char(v_until, 'FMDD Mon YYYY');
    end if;
    if not coalesce(gym_delete_member.even_if_active, false) then
      raise exception '%''s membership is still active until %. Confirm to delete them anyway.',
        v_member.full_name, to_char(v_until, 'FMDD Mon YYYY');
    end if;
  end if;

  select p.user_id into v_user from public.people p where p.id = v_member.person_id;
  select v.name into v_gym from public.venues v where v.id = v_member.venue_id;

  delete from public.gym_members g where g.id = v_member.id;
  if v_until is not null then
    -- Joins the register's own 'member.removed' entry (same call).
    perform public.gym_audit(v_member.venue_id, 'member.removed', 'Removed ' || v_member.full_name,
                             'Their membership was active until ' || public.gym_audit_day(v_until), null,
                             v_member.full_name);
  end if;

  delete from public.people p
  where p.id = v_member.person_id and p.user_id is null
    and not exists (select 1 from public.gym_members g where g.person_id = p.id)
    and not exists (select 1 from public.people o where o.merged_into = p.id);

  if v_user is not null then
    perform public.notify(v_user, 'gym_membership', 'Removed from ' || v_gym,
      v_gym || ' removed you from its members'
        || case when v_until is not null then ' (your membership ran until ' || to_char(v_until, 'FMDD Mon YYYY') || ')'
                else '' end
        || '. Your Health Pro account stays: sign in as before, and join a gym any time.',
      '/gyms');
  end if;

  return jsonb_build_object('photo_path', v_member.photo_path, 'active_until', v_until, 'told', v_user is not null);
end;
$$;

revoke execute on function public.gym_delete_member(uuid, boolean) from public, anon;
grant execute on function public.gym_delete_member(uuid, boolean) to authenticated;
