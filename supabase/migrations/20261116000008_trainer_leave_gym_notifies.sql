-- A verified trainer may end their role at one gym. Their active member
-- assignments and schedule end there, while the gym and affected members
-- are notified. A pending application is still simply withdrawn.
create or replace function public.trainer_leave_gym(venue_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  uid uuid := (select auth.uid());
  p_venue uuid := trainer_leave_gym.venue_id;
  v_status text;
  v_gym text;
  v_member_user uuid;
begin
  select g.status into v_status
  from public.gym_trainers g
  where g.venue_id = p_venue
    and g.user_id = uid
    and g.status in ('pending', 'verified')
  for update;
  if not found then
    raise exception 'You don''t train there.';
  end if;

  select v.name into v_gym from public.venues v where v.id = p_venue;

  if v_status = 'pending' then
    update public.gym_trainers g
    set status = 'left', decided_at = now()
    where g.venue_id = p_venue and g.user_id = uid;
    delete from public.trainer_slots s where s.venue_id = p_venue and s.user_id = uid;
    perform public.notify_venue_permission(
      p_venue,
      'gym.trainers',
      'gym_membership',
      'Trainer request withdrawn',
      public.trainer_name(uid) || ' withdrew their request to train at ' || v_gym || '.',
      '/gyms/' || p_venue || '/manage/trainers'
    );
    return;
  end if;

  update public.gym_trainers g
  set status = 'inactive', decided_at = now()
  where g.venue_id = p_venue and g.user_id = uid;

  for v_member_user in
    select distinct p.user_id
    from public.trainer_links l
    join public.gym_members m on m.id = l.gym_member_id
    join public.people p on p.id = m.person_id
    where l.venue_id = p_venue and l.trainer_id = uid
      and l.ended_at is null and p.user_id is not null
  loop
    perform public.notify(
      v_member_user,
      'gym_membership',
      'Trainer unavailable at ' || v_gym,
      public.trainer_name(uid) || ' has stopped training at ' || v_gym
        || '. Your trainer assignment was removed. Choose another trainer from My gyms.',
      '/gyms/my'
    );
  end loop;

  update public.trainer_links l
  set ended_at = now()
  where l.venue_id = p_venue and l.trainer_id = uid and l.ended_at is null;

  delete from public.trainer_slots s
  where s.venue_id = p_venue and s.user_id = uid;

  perform public.notify_venue_permission(
    p_venue,
    'gym.trainers',
    'gym_membership',
    'Trainer is no longer active',
    public.trainer_name(uid) || ' stopped training at ' || v_gym
      || '. Their schedule was cleared and member assignments were removed.',
    '/gyms/' || p_venue || '/manage/trainers'
  );
end;
$$;

notify pgrst, 'reload schema';
