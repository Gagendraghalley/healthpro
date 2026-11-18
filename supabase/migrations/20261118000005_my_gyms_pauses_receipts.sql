-- A member sees their own pause and receipts (My gym, My dashboard).
-- my_gyms() as in 20261116000002, with for each gym:
--   'pause':    their pause running or planned (one at a time), or null;
--   'receipts': their last 10 payments there, latest first, each opening
--               with gym_payment_receipt (which lets the member who paid).
-- A gym registration's receipts are the payments for its packages; an
-- account membership's from before, the account's payments at the gym.
-- Safe to re-run.

create or replace function public.my_gyms()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  v public.people := public.person_for_user(uid);
  v_today date := public.bhutan_today();
begin
  return jsonb_build_object(
    'gyms', coalesce((
      select jsonb_agg(x.gym order by x.sort_end desc nulls last, x.name)
      from (
        select jsonb_build_object(
                 'venue_id', ven.id, 'venue_name', ven.name, 'dzongkhag', ven.dzongkhag, 'town', ven.town,
                 'phone', ven.phone, 'member_code', g.code, 'joined_on', g.joined_on, 'gym_member_id', g.id,
                 'plan_name', s.plan_name, 'start_date', s.start_date, 'end_date', s.end_date,
                 'last_visit', (select max(c.checked_in_at) from public.gym_check_ins c where c.gym_member_id = g.id),
                 'payment_account', public.gym_payment_account(ven.id),
                 'payment_qr_path', (select st.payment_qr_path from public.gym_settings st where st.venue_id = ven.id),
                 'payment_info', ven.payment_info,
                 'claim', (select jsonb_build_object('id', c.id, 'status', c.status, 'plan_name', c.plan_name,
                                                     'months', c.months, 'amount', c.amount, 'jrn', c.jrn,
                                                     'decision_note', c.decision_note, 'created_at', c.created_at,
                                                     'decided_at', c.decided_at)
                           from public.gym_payment_claims c
                           where c.gym_member_id = g.id and c.status <> 'cancelled'
                             and (c.status = 'pending' or c.decided_at > now() - interval '30 days')
                           order by (c.status = 'pending') desc, c.created_at desc
                           limit 1),
                 'trainer', (select jsonb_build_object('id', l.trainer_id, 'name', public.trainer_name(l.trainer_id),
                                                       'photo_url', t.photo_url)
                             from public.trainer_links l
                             left join public.trainer_profiles t on t.user_id = l.trainer_id
                             where l.gym_member_id = g.id and l.ended_at is null),
                 'pause', (select jsonb_build_object('id', z.id, 'venue_id', z.venue_id, 'gym_member_id', z.gym_member_id,
                                                     'start_date', z.start_date, 'end_date', z.end_date,
                                                     'reason', z.reason)
                           from public.gym_membership_pauses z
                           where z.gym_member_id = g.id and z.end_date >= v_today
                           order by z.start_date
                           limit 1),
                 'receipts', coalesce((
                   select jsonb_agg(jsonb_build_object('payment_id', y.id, 'receipt_no', y.receipt_no,
                                                       'amount', y.amount, 'method', y.method, 'status', y.status,
                                                       'paid_at', y.created_at, 'plan_name', y.plan_name)
                                    order by y.created_at desc)
                   from (
                     select p.id, p.receipt_no, p.amount, p.method, p.status, p.created_at, s2.plan_name
                     from public.payments p
                     join public.gym_subscriptions s2 on s2.payment_id = p.id
                     where s2.gym_member_id = g.id
                     order by p.created_at desc
                     limit 10
                   ) y
                 ), '[]'::jsonb)
               ) as gym,
               s.end_date as sort_end, ven.name
        from public.gym_members g
        join public.venues ven on ven.id = g.venue_id
        left join lateral (
          select * from public.gym_subscriptions s
          where s.gym_member_id = g.id and s.status in ('active', 'expired')
          order by s.end_date desc
          limit 1
        ) s on true
        where g.person_id = v.id
        union all
        select jsonb_build_object(
                 'venue_id', ven.id, 'venue_name', ven.name, 'dzongkhag', ven.dzongkhag, 'town', ven.town,
                 'phone', ven.phone, 'member_code', null, 'joined_on', null,
                 'plan_name', s.plan_name, 'start_date', s.start_date, 'end_date', s.end_date,
                 'last_visit', (select max(c.checked_in_at) from public.gym_check_ins c
                                where c.member_id = uid and c.venue_id = ven.id),
                 'payment_info', ven.payment_info,
                 'receipts', coalesce((
                   select jsonb_agg(jsonb_build_object('payment_id', y.id, 'receipt_no', y.receipt_no,
                                                       'amount', y.amount, 'method', y.method, 'status', y.status,
                                                       'paid_at', y.created_at, 'plan_name', y.plan_name)
                                    order by y.created_at desc)
                   from (
                     select p.id, p.receipt_no, p.amount, p.method, p.status, p.created_at, s2.plan_name
                     from public.payments p
                     left join public.gym_subscriptions s2 on s2.id = p.reference_id
                     where p.user_id = uid and p.venue_id = ven.id
                     order by p.created_at desc
                     limit 10
                   ) y
                 ), '[]'::jsonb)
               ),
               s.end_date, ven.name
        from public.venues ven
        join lateral (
          select * from public.gym_subscriptions s
          where s.member_id = uid and s.venue_id = ven.id and s.status in ('active', 'expired')
          order by s.end_date desc
          limit 1
        ) s on true
        where not exists (select 1 from public.gym_members g where g.person_id = v.id and g.venue_id = ven.id)
      ) x
    ), '[]'::jsonb),
    'requests', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', j.id, 'venue_id', j.venue_id, 'venue_name', ven.name, 'status', j.status,
               'plan_name', pl.name, 'message', j.message, 'decision_note', j.decision_note,
               'created_at', j.created_at, 'decided_at', j.decided_at
             ) order by j.created_at desc)
      from public.gym_join_requests j
      join public.venues ven on ven.id = j.venue_id
      left join public.gym_plans pl on pl.id = j.plan_id
      where (j.person_id = v.id or j.user_id = uid) and j.created_at > now() - interval '90 days'
    ), '[]'::jsonb),
    'visits', coalesce((
      select jsonb_agg(jsonb_build_object('venue_name', y.name, 'checked_in_at', y.checked_in_at)
                       order by y.checked_in_at desc)
      from (
        select ven.name, c.checked_in_at
        from public.gym_check_ins c
        join public.venues ven on ven.id = c.venue_id
        where c.gym_member_id in (select g.id from public.gym_members g where g.person_id = v.id)
           or c.member_id = uid
        order by c.checked_in_at desc
        limit 30
      ) y
    ), '[]'::jsonb),
    'today', v_today
  );
end;
$$;
