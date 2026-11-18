-- Account memberships into the desk's register. Early on, a member asked
-- for a package in the app and the desk activated it: the membership was on
-- their account (gym_subscriptions.member_id), with no registration at the
-- gym. Everything since (member codes and cards, pausing, paying online,
-- progress, plans, trainers, classes) works on registrations (gym_members).
--
-- Each account with a package (running or ended) at a gym, and no
-- registration there, now gets one: their person on Health Pro (the one
-- their QR code is), their name, phone and email from their account, joined
-- on their first package's day, and a new member code and card. Their
-- packages, visits and class bookings there move onto it. Payments stay as
-- they are (the packages keep their receipts). With a registration there
-- already (the desk added them later), the account's packages and visits
-- join it.
--
-- Their Health Pro QR code, old account QR code and old member code still
-- check them in: check-in finds a person's registration first.
--
-- An account without a phone number can't be registered (the register needs
-- one): it stays as it is, and still works as before (20261118000014 lets it
-- book classes). The migration says how many were left. Run
-- "select public.gym_register_account_members()" again once they have one.
-- Safe to re-run: what's moved isn't found again.

create or replace function public.gym_register_account_members()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  pr public.profiles;
  v public.people;
  g public.gym_members;
  v_phone text;
  v_email text;
  v_name text;
  v_joined date;
  v_new int := 0;
  v_joined_existing int := 0;
  v_left jsonb := '[]'::jsonb;
begin
  for r in
    select s.venue_id, s.member_id
    from public.gym_subscriptions s
    join public.venues ven on ven.id = s.venue_id and ven.type = 'gym'
    where s.member_id is not null and s.gym_member_id is null
    group by s.venue_id, s.member_id
    having bool_or(s.status in ('active', 'expired'))
  loop
    select * into pr from public.profiles p where p.id = r.member_id;
    continue when pr.id is null;
    v := public.person_for_user(r.member_id);
    g := null;
    select * into g from public.gym_members m where m.person_id = v.id and m.venue_id = r.venue_id;

    if g.id is null then
      v_phone := regexp_replace(coalesce(pr.phone, v.phone, ''), '[\s()-]', '', 'g');
      if v_phone ~ '^[0-9]{8}$' then
        v_phone := '+975' || v_phone;
      end if;
      if v_phone !~ '^\+[0-9]{8,15}$' then
        v_left := v_left || jsonb_build_object('venue_id', r.venue_id, 'member_id', r.member_id,
                                               'name', coalesce(nullif(trim(pr.full_name), ''), pr.email), 'why', 'no phone number');
        continue;
      end if;
      v_name := left(coalesce(nullif(trim(pr.full_name), ''), nullif(trim(v.full_name), ''), 'Member'), 100);
      if char_length(v_name) < 2 then
        v_name := 'Member';
      end if;
      v_email := nullif(lower(trim(coalesce(pr.email, v.email, ''))), '');
      if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 320 then
        v_email := null;
      end if;
      select least(min(s.start_date), min((s.requested_at at time zone 'Asia/Thimphu')::date)) into v_joined
      from public.gym_subscriptions s where s.venue_id = r.venue_id and s.member_id = r.member_id;

      insert into public.gym_members (venue_id, person_id, code, qr_token, full_name, phone, email, joined_on)
      values (r.venue_id, v.id, public.gym_new_member_code(), public.gym_new_qr_token(), v_name, v_phone, v_email,
              coalesce(v_joined, public.bhutan_today()))
      returning * into g;
      v_new := v_new + 1;
    else
      v_joined_existing := v_joined_existing + 1;
    end if;

    -- Their packages (receipts kept: the payment stays linked), visits and
    -- class bookings at this gym.
    update public.gym_subscriptions s
       set payment_id = coalesce(s.payment_id, (select p.id from public.payments p where p.reference_id = s.id
                                                 order by p.created_at limit 1))
     where s.venue_id = r.venue_id and s.member_id = r.member_id and s.payment_id is null;
    update public.gym_subscriptions s set gym_member_id = g.id, member_id = null
     where s.venue_id = r.venue_id and s.member_id = r.member_id;
    update public.gym_check_ins c set gym_member_id = g.id, member_id = null
     where c.venue_id = r.venue_id and c.member_id = r.member_id;
    -- A class they're booked into twice (both ways) keeps one booking.
    update public.gym_class_bookings b set status = 'cancelled', cancelled_at = now()
     where b.venue_id = r.venue_id and b.user_id = r.member_id and b.status = 'booked'
       and exists (select 1 from public.gym_class_bookings x
                   where x.class_id = b.class_id and x.class_date = b.class_date and x.gym_member_id = g.id
                     and x.status = 'booked');
    update public.gym_class_bookings b set gym_member_id = g.id, user_id = null
     where b.venue_id = r.venue_id and b.user_id = r.member_id;
  end loop;
  return jsonb_build_object('registered', v_new, 'joined_existing', v_joined_existing, 'left', v_left);
end;
$$;

revoke execute on function public.gym_register_account_members() from public, anon, authenticated;

do $$
declare
  v_result jsonb := public.gym_register_account_members();
begin
  raise notice 'Account memberships: % registered, % joined an existing registration, % left (no phone number): %',
    v_result ->> 'registered', v_result ->> 'joined_existing', jsonb_array_length(v_result -> 'left'), v_result -> 'left';
end;
$$;
