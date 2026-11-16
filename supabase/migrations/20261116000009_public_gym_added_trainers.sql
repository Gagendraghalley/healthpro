-- Any trainer verified by a gym is public, whether they applied themselves
-- or the gym added their profile. Pending, inactive and declined trainers
-- remain private.
create or replace function public.trainer_is_public(trainer uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.gym_trainers g
    where g.user_id = trainer and g.status = 'verified'
  );
$$;

drop policy if exists "trainer_profiles: public once verified" on public.trainer_profiles;
create policy "trainer_profiles: public once verified"
  on public.trainer_profiles for select to anon
  using (public.trainer_is_public(user_id));
drop policy if exists "trainer_profiles: theirs, and the gyms they asked" on public.trainer_profiles;
create policy "trainer_profiles: theirs, and the gyms they asked"
  on public.trainer_profiles for select to authenticated
  using (user_id = (select auth.uid())
         or public.trainer_is_public(user_id)
         or public.trainer_asked_my_gym(user_id, 'gym.trainers'));

drop policy if exists "trainer_certificates: public once verified" on public.trainer_certificates;
create policy "trainer_certificates: public once verified"
  on public.trainer_certificates for select to anon
  using (public.trainer_is_public(user_id));
drop policy if exists "trainer_certificates: as the profile" on public.trainer_certificates;
create policy "trainer_certificates: as the profile"
  on public.trainer_certificates for select to authenticated
  using (user_id = (select auth.uid())
         or public.trainer_is_public(user_id)
         or public.trainer_asked_my_gym(user_id, 'gym.trainers'));

drop policy if exists "gym_trainers: verified for all" on public.gym_trainers;
create policy "gym_trainers: verified for all"
  on public.gym_trainers for select to anon
  using (status = 'verified');
drop policy if exists "gym_trainers: the trainer and the gym" on public.gym_trainers;
create policy "gym_trainers: the trainer and the gym"
  on public.gym_trainers for select to authenticated
  using (status = 'verified'
         or user_id = (select auth.uid())
         or public.has_venue_permission(venue_id, 'gym.trainers'));

drop policy if exists "trainer_reviews: public trainers" on public.trainer_reviews;
create policy "trainer_reviews: public trainers"
  on public.trainer_reviews for select to anon, authenticated
  using (public.trainer_is_public(trainer_id));

-- Keep the trainer's own workspace flag aligned with public visibility.
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
               'venue_id', g.venue_id,
               'venue_name', v.name,
               'place', concat_ws(', ', v.town, v.dzongkhag),
               'status', g.status,
               'decision_note', g.decision_note,
               'requested_at', g.requested_at,
               'slots', coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'weekday', s.weekday,
                          'starts', to_char(s.starts_at, 'HH24:MI'),
                          'ends', to_char(s.ends_at, 'HH24:MI'))
                          order by s.weekday, s.starts_at)
                 from public.trainer_slots s
                 where s.venue_id = g.venue_id and s.user_id = uid
               ), '[]'::jsonb),
               'attendance', coalesce((
                 select jsonb_agg(c.checked_in_at order by c.checked_in_at desc)
                 from (
                   select c.checked_in_at from public.trainer_check_ins c
                   where c.venue_id = g.venue_id and c.user_id = uid
                   order by c.checked_in_at desc limit 60
                 ) c
               ), '[]'::jsonb),
               'attendance_30_days', (
                 select count(*) from public.trainer_check_ins c
                 where c.venue_id = g.venue_id and c.user_id = uid
                   and c.checked_in_at > now() - interval '30 days'
               ),
               'members', coalesce((
                 select jsonb_agg(jsonb_build_object('name', m.full_name, 'since', l.started_at)
                                  order by l.started_at desc)
                 from public.trainer_links l
                 join public.gym_members m on m.id = l.gym_member_id
                 where l.venue_id = g.venue_id and l.trainer_id = uid and l.ended_at is null
               ), '[]'::jsonb)
             ) order by (g.status = 'verified') desc, v.name)
      from public.gym_trainers g
      join public.venues v on v.id = g.venue_id
      where g.user_id = uid and g.status <> 'left'
    ), '[]'::jsonb),
    'reviews', coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc)
                         from public.trainer_reviews r where r.trainer_id = uid), '[]'::jsonb),
    'joined_publicly', exists (
      select 1 from public.gym_trainers g
      where g.user_id = uid and g.status = 'verified'
    )
  );
end;
$$;

-- Public profile pages can now read schedules for all verified trainers;
-- venue-scoped requests still reveal no other gym's identity.
create or replace function public.trainer_timings(trainer uuid, venue uuid default null)
returns table (weekday int, starts_at text, ends_at text, venue_id uuid, venue_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select s.weekday::int,
         to_char(s.starts_at, 'HH24:MI'),
         to_char(s.ends_at, 'HH24:MI'),
         case when venue is null or s.venue_id = venue then s.venue_id end,
         case when venue is null or s.venue_id = venue then v.name end
  from public.trainer_slots s
  join public.gym_trainers g
    on g.venue_id = s.venue_id and g.user_id = s.user_id and g.status = 'verified'
  join public.venues v on v.id = s.venue_id
  where s.user_id = trainer
    and (
      (venue is null and public.trainer_is_public(trainer))
      or (
        venue is not null
        and s.venue_id = venue
        and public.has_venue_permission(venue, 'gym.trainers')
      )
      or (
        venue is not null
        and public.trainer_is_public(trainer)
        and exists (
          select 1 from public.gym_trainers own_gym
          where own_gym.user_id = trainer
            and own_gym.venue_id = venue
            and own_gym.status = 'verified'
        )
      )
    )
  order by s.weekday, s.starts_at;
$$;

notify pgrst, 'reload schema';
