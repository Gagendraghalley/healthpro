-- Profile photos in the staff's lists. Everyone can upload their own photo
-- (20261118000001_profile_photos.sql); the Users and Staff lists read it
-- from profiles. Here: the gym's Members list (when the desk took no photo)
-- and its Trainers list (when the trainer added no trainer photo). Safe to
-- re-run.

-- ---------------------------------------------------------------------
-- 1. A member's profile photo: people.avatar_url
-- ---------------------------------------------------------------------

-- The photo of the account a person is (or was joined into), read as a
-- column of people: `person:people(qr_token, avatar_url)`. Whoever may see
-- the person (themselves, their gyms' staff) gets only the photo's public
-- address, not the rest of the account.
create or replace function public.avatar_url(p public.people)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select pr.avatar_url from public.profiles pr where pr.id = (public.person_current(p)).user_id;
$$;

revoke execute on function public.avatar_url(public.people) from public, anon;
grant execute on function public.avatar_url(public.people) to authenticated;


-- ---------------------------------------------------------------------
-- 2. A trainer's profile photo in the gym's Trainers list
-- ---------------------------------------------------------------------

-- As in 20261116000002_bank_account_and_gym_trainers.sql, plus avatar_url.
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
             'email', pr.email, 'phone', pr.phone, 'avatar_url', pr.avatar_url,
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
