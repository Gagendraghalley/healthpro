-- Classes ('gym.classes') covers booking members in and registering
-- newcomers, without the Members or Register rights:
--
--   gym_class_member_choices: the gym's members to book into a class (name,
--   card code, phone), for who has Classes or Members.
--
--   gym_register_member: who has Classes registers someone new (the desk's
--   form, as for a non-member who booked a class), with their photo, and a
--   package only with 'gym.payments' as before. Someone's Health Pro QR code
--   or request to join stays with 'gym.register', as do changing a member's
--   details, their photo once set, and their card.
--
-- Safe to re-run.

update public.permissions
   set description = 'See the classes, who''s booked into each and who has registered to date; book members in; '
                     'add and change the classes on the timetable; register newcomers'
 where key = 'gym.classes';

create or replace function public.gym_class_member_choices(venue_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_venue uuid := gym_class_member_choices.venue_id;
begin
  if not (public.has_venue_permission(v_venue, 'gym.classes') or public.has_venue_permission(v_venue, 'gym.members')) then
    raise exception 'Only the gym''s staff can book members into its classes.';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'full_name', g.full_name, 'code', g.code, 'phone', g.phone)
                              order by g.full_name), '[]'::jsonb)
    from public.gym_members g
    where g.venue_id = v_venue
  );
end;
$$;
revoke execute on function public.gym_class_member_choices(uuid) from public, anon;
grant execute on function public.gym_class_member_choices(uuid) to authenticated;

-- A new member's photo: uploaded by who registers them (with Classes too),
-- and read back by them as it's saved.
drop policy if exists "gym-member-photos: who sees members" on storage.objects;
create policy "gym-member-photos: who sees members" on storage.objects for select to authenticated
  using (bucket_id = 'gym-member-photos'
         and (public.gym_member_photo_access(name, 'gym.members') or public.gym_member_photo_access(name, 'gym.classes')));
drop policy if exists "gym-member-photos: who registers upload" on storage.objects;
create policy "gym-member-photos: who registers upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'gym-member-photos'
              and (public.gym_member_photo_access(name, 'gym.register') or public.gym_member_photo_access(name, 'gym.classes')));

-- As in 20261108000004; who has Classes sets a member's first photo only.
create or replace function public.gym_set_member_photo(gym_member_id uuid, photo_path text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_member public.gym_members;
  p_path text := nullif(trim(gym_set_member_photo.photo_path), '');
begin
  select * into v_member from public.gym_members g where g.id = gym_set_member_photo.gym_member_id for update;
  if not found then
    raise exception 'This member is no longer registered.';
  end if;
  if not public.has_venue_permission(v_member.venue_id, 'gym.register')
     and not (v_member.photo_path is null and p_path is not null
              and public.has_venue_permission(v_member.venue_id, 'gym.classes')) then
    raise exception 'Only the gym''s staff who register members can change their photo.';
  end if;
  if p_path is not null and p_path not like v_member.venue_id::text || '/%' then
    raise exception 'The photo must be uploaded to this gym''s folder.';
  end if;
  update public.gym_members g set photo_path = p_path where g.id = v_member.id;
end;
$$;

-- As in 20261118000010; who has Classes registers someone new.
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
  if not public.has_venue_permission(p_venue, 'gym.register')
     and not (gym_register_member.join_request_id is null
              and nullif(trim(coalesce(gym_register_member.person_qr, '')), '') is null
              and public.has_venue_permission(p_venue, 'gym.classes')) then
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
