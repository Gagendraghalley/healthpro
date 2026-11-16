-- A gym can deactivate a trainer without treating it as a declined request
-- or deleting the trainer's history at other gyms.
alter table public.gym_trainers
  drop constraint if exists gym_trainers_status_check;

alter table public.gym_trainers
  add constraint gym_trainers_status_check
  check (status in ('pending', 'verified', 'inactive', 'rejected', 'left'));

create or replace function public.gym_deactivate_trainer(venue_id uuid, user_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_deactivate_trainer.venue_id;
  p_user uuid := gym_deactivate_trainer.user_id;
  v_gym text;
  v_name text;
  v_member_user uuid;
begin
  if not public.has_venue_permission(p_venue, 'gym.trainers') then
    raise exception 'Only the gym''s staff who manage trainers can do this.';
  end if;

  update public.gym_trainers g
  set status = 'inactive', decided_at = now(), decided_by = (select auth.uid())
  where g.venue_id = p_venue and g.user_id = p_user and g.status = 'verified';
  if not found then
    raise exception 'That trainer is not active at this gym.';
  end if;

  select v.name into v_gym from public.venues v where v.id = p_venue;
  v_name := public.trainer_name(p_user);

  for v_member_user in
    select distinct p.user_id
    from public.trainer_links l
    join public.gym_members m on m.id = l.gym_member_id
    join public.people p on p.id = m.person_id
    where l.venue_id = p_venue and l.trainer_id = p_user
      and l.ended_at is null and p.user_id is not null
  loop
    perform public.notify(
      v_member_user,
      'gym_membership',
      'Trainer unavailable at ' || v_gym,
      v_name || ' is no longer available as your trainer at ' || v_gym
        || '. Your trainer assignment was removed. Choose another trainer from My gyms.',
      '/gyms/my'
    );
  end loop;

  update public.trainer_links l
  set ended_at = now()
  where l.venue_id = p_venue and l.trainer_id = p_user and l.ended_at is null;

  delete from public.trainer_slots s
  where s.venue_id = p_venue and s.user_id = p_user;

  perform public.notify(
    p_user,
    'gym_membership',
    'You were made inactive at ' || v_gym,
    'Your trainer role at ' || v_gym || ' is inactive. Your public listing, weekly times, '
      || 'and member assignments at this gym were removed. Your trainer profile at other gyms is unchanged.',
    '/gyms/trainer'
  );
end;
$$;

create or replace function public.gym_reactivate_trainer(venue_id uuid, user_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_reactivate_trainer.venue_id;
  p_user uuid := gym_reactivate_trainer.user_id;
  v_gym text;
begin
  if not public.has_venue_permission(p_venue, 'gym.trainers') then
    raise exception 'Only the gym''s staff who manage trainers can do this.';
  end if;

  update public.gym_trainers g
  set status = 'verified', decided_at = now(), decided_by = (select auth.uid())
  where g.venue_id = p_venue and g.user_id = p_user and g.status = 'inactive';
  if not found then
    raise exception 'That trainer is not inactive at this gym.';
  end if;

  select v.name into v_gym from public.venues v where v.id = p_venue;
  perform public.notify(
    p_user,
    'gym_membership',
    'You are active again at ' || v_gym,
    'Your trainer profile is listed at ' || v_gym || ' again. Add your weekly times and reconnect with members there.',
    '/gyms/trainer'
  );
end;
$$;

-- Serialize new member assignments with trainer deactivation. If an
-- assignment wins the lock first, deactivation will end it; if deactivation
-- wins, the assignment sees the inactive status and is refused.
create or replace function public.gym_set_member_trainer(gym_member_id uuid, trainer_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  uid uuid := (select auth.uid());
  m public.gym_members;
  v_member_user uuid;
  v_old uuid;
  v_gym text;
  v_by_member boolean;
begin
  select * into m from public.gym_members g
  where g.id = gym_set_member_trainer.gym_member_id for update;
  if not found then
    raise exception 'This member is no longer registered.';
  end if;

  select p.user_id into v_member_user from public.people p where p.id = m.person_id;
  v_by_member := v_member_user is not null and v_member_user = uid;
  if not v_by_member and not public.has_venue_permission(m.venue_id, 'gym.check_in') then
    raise exception 'Only the member, or the gym''s front desk, can choose their trainer.';
  end if;

  if gym_set_member_trainer.trainer_id is not null then
    perform 1 from public.gym_trainers g
    where g.venue_id = m.venue_id
      and g.user_id = gym_set_member_trainer.trainer_id
      and g.status = 'verified'
    for share;
    if not found then
      raise exception 'Choose one of the gym''s verified trainers.';
    end if;
    if gym_set_member_trainer.trainer_id = v_member_user then
      raise exception 'A trainer can''t train themselves.';
    end if;
  end if;

  select l.trainer_id into v_old from public.trainer_links l
  where l.gym_member_id = m.id and l.ended_at is null;
  if v_old is not distinct from gym_set_member_trainer.trainer_id then
    return;
  end if;

  update public.trainer_links l set ended_at = now()
  where l.gym_member_id = m.id and l.ended_at is null;
  if gym_set_member_trainer.trainer_id is not null then
    insert into public.trainer_links (gym_member_id, venue_id, trainer_id, set_by)
    values (m.id, m.venue_id, gym_set_member_trainer.trainer_id, uid);
  end if;

  select v.name into v_gym from public.venues v where v.id = m.venue_id;
  perform public.notify(v_old, 'gym_membership', 'Trainer changed',
    m.full_name || ' at ' || v_gym || ' has another trainer now.', '/gyms/trainer');
  perform public.notify(gym_set_member_trainer.trainer_id, 'gym_membership',
    case when v_old is null then 'New member' else 'Trainer changed' end,
    m.full_name || ' at ' || v_gym ||
      case when v_by_member then ' chose you as their trainer.' else ' was given to you as their trainer.' end,
    '/gyms/trainer');
  if not v_by_member and gym_set_member_trainer.trainer_id is not null then
    perform public.notify(v_member_user, 'gym_membership', 'Your trainer at ' || v_gym,
      public.trainer_name(gym_set_member_trainer.trainer_id) ||
        ' is your trainer now. You can change it in My gyms.', '/gyms/my');
  end if;
end;
$$;

revoke execute on function public.gym_deactivate_trainer(uuid, uuid),
  public.gym_reactivate_trainer(uuid, uuid) from public, anon;
grant execute on function public.gym_deactivate_trainer(uuid, uuid),
  public.gym_reactivate_trainer(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
