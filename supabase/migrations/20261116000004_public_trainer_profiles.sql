-- A trainer is public only after a public application has been verified.
-- Trainers added directly by a gym stay visible to that gym and to the
-- trainer, but do not appear in the public trainer directory or profiles.

create or replace function public.trainer_is_public(trainer uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.gym_trainers g
    where g.user_id = trainer
      and g.source = 'request'
      and g.status = 'verified'
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
  using (status = 'verified' and source = 'request');
drop policy if exists "gym_trainers: the trainer and the gym" on public.gym_trainers;
create policy "gym_trainers: the trainer and the gym"
  on public.gym_trainers for select to authenticated
  using ((status = 'verified' and source = 'request')
         or user_id = (select auth.uid())
         or public.has_venue_permission(venue_id, 'gym.trainers'));

drop policy if exists "trainer_reviews: everyone" on public.trainer_reviews;
create policy "trainer_reviews: public trainers"
  on public.trainer_reviews for select to anon, authenticated
  using (public.trainer_is_public(trainer_id));

-- Public trainer pages can request their own availability only when that
-- trainer is public. Gym staff can also request the schedule at their own
-- gym for trainers they manage.
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
            and own_gym.source = 'request'
        )
      )
    )
  order by s.weekday, s.starts_at;
$$;

notify pgrst, 'reload schema';
