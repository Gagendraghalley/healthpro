-- Classes (gym_classes) as a screen right of their own: 'gym.classes'
-- lets a role see the Classes page, who's booked into each, book
-- members in and take anyone out, and see who has registered to date. The
-- owner gives it to the roles they choose (front desk, manager...) on Roles.
-- Changing the timetable stays with 'gym.plans'.
--
-- Made now, it goes to the roles that could see the page until today
-- (those with 'gym.members': owner, manager, front desk, trainer, and the
-- gym's own roles), here and in each organisation's own version of a role;
-- the owner takes it away where they want.
--
-- gym_class_registrations: how many have registered to date, in all, for
-- each class, and everyone who has booked (members and
-- non-members), how many times and when last.
--
-- Safe to re-run.

do $$
declare
  v_new boolean;
begin
  with saved as (
    insert into public.permissions (key, scope, module_key, name, description, sort_order)
    values ('gym.classes', 'venue', 'gym_membership', 'Classes',
            'See the classes, who''s booked into each and who has registered to date; book members in', 145)
    on conflict (key) do update
      set name = excluded.name, description = excluded.description, sort_order = excluded.sort_order
    returning (xmax = 0) as inserted
  )
  select inserted into v_new from saved;
  if v_new then
    insert into public.role_permissions (role_id, permission_key)
    select rp.role_id, 'gym.classes' from public.role_permissions rp where rp.permission_key = 'gym.members'
    on conflict do nothing;
    insert into public.organisation_role_permissions (organisation_id, role_id, permission_key)
    select op.organisation_id, op.role_id, 'gym.classes' from public.organisation_role_permissions op
    where op.permission_key = 'gym.members'
    on conflict do nothing;
  end if;
end;
$$;

drop policy if exists "gym_class_bookings: the desk and the member" on public.gym_class_bookings;
create policy "gym_class_bookings: the desk and the member" on public.gym_class_bookings for select to authenticated
  using (public.has_venue_permission(venue_id, 'gym.classes') or user_id = (select auth.uid())
         or public.gym_member_is_me(gym_member_id));

-- Everyone who has booked a place at the gym (not cancelled), to date: the
-- totals, each class's, and each person's. A non-member the desk
-- has registered since counts once, as the member they are now.
create or replace function public.gym_class_registrations(venue_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_venue uuid := gym_class_registrations.venue_id;
  v_today date := public.bhutan_today();
begin
  if not public.has_venue_permission(v_venue, 'gym.classes') then
    raise exception 'Only the gym''s staff can see who has registered for its classes.';
  end if;
  return (
    with b as (
      select x.class_id, x.class_date, x.booked_at, c.name as class_name,
             coalesce('m:' || coalesce(x.gym_member_id, reg.id), 'u:' || x.user_id) as who,
             coalesce(g.full_name, reg.full_name, nullif(trim(pr.full_name), ''), pr.email, 'Member') as full_name,
             coalesce(g.code, reg.code) as member_code,
             coalesce(g.phone, reg.phone, pr.phone) as phone,
             coalesce(g.email, reg.email, pr.email) as email,
             g.id is not null or reg.id is not null
               or exists (select 1 from public.gym_subscriptions s
                          where s.member_id = x.user_id and s.venue_id = x.venue_id and s.status in ('active', 'expired'))
               as is_member
      from public.gym_class_bookings x
      join public.gym_classes c on c.id = x.class_id
      left join public.gym_members g on g.id = x.gym_member_id
      left join public.profiles pr on pr.id = x.user_id
      left join lateral (select m.id, m.full_name, m.code, m.phone, m.email
                         from public.gym_members m join public.people p on p.id = m.person_id
                         where x.user_id is not null and p.user_id = x.user_id and m.venue_id = x.venue_id
                         limit 1) reg on true
      where x.venue_id = v_venue and x.status = 'booked'
    ),
    people as (
      select who, bool_or(is_member) as is_member,
             (array_agg(full_name order by booked_at desc))[1] as full_name,
             (array_agg(member_code order by booked_at desc) filter (where member_code is not null))[1] as member_code,
             (array_agg(phone order by booked_at desc) filter (where phone is not null))[1] as phone,
             (array_agg(email order by booked_at desc) filter (where email is not null))[1] as email,
             count(*) as bookings, count(*) filter (where class_date >= v_today) as upcoming,
             min(class_date) as first_date, max(class_date) as last_date,
             (array_agg(class_name order by class_date desc, booked_at desc))[1] as last_class
      from b group by who
    )
    select jsonb_build_object(
      'totals', jsonb_build_object(
        'bookings', (select count(*) from b),
        'people', (select count(*) from people),
        'members', (select count(*) from people where is_member),
        'non_members', (select count(*) from people where not is_member),
        'upcoming', (select count(*) from b where class_date >= v_today),
        'cancelled', (select count(*) from public.gym_class_bookings x where x.venue_id = v_venue and x.status = 'cancelled')),
      'classes', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'class_id', c.id, 'name', c.name, 'weekday', c.weekday, 'starts_at', c.starts_at, 'is_active', c.is_active,
          'bookings', k.bookings, 'people', k.people, 'members', k.members, 'non_members', k.people - k.members,
          'upcoming', k.upcoming, 'last_date', k.last_date
        ) order by k.bookings desc, c.name), '[]'::jsonb)
        from public.gym_classes c
        join (select b.class_id, count(*) as bookings, count(distinct b.who) as people,
                     count(distinct b.who) filter (where p.is_member) as members,
                     count(*) filter (where b.class_date >= v_today) as upcoming, max(b.class_date) as last_date
              from b join people p on p.who = b.who group by b.class_id) k on k.class_id = c.id),
      'people', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'key', p.who, 'full_name', p.full_name, 'is_member', p.is_member, 'member_code', p.member_code,
          'phone', p.phone, 'email', p.email, 'bookings', p.bookings, 'upcoming', p.upcoming,
          'first_date', p.first_date, 'last_date', p.last_date, 'last_class', p.last_class
        ) order by p.last_date desc, p.full_name), '[]'::jsonb)
        from people p)
    )
  );
end;
$$;

revoke execute on function public.gym_class_registrations(uuid) from public, anon;
grant execute on function public.gym_class_registrations(uuid) to authenticated;
