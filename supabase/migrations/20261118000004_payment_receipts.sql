-- Numbered receipts: every payment a gym records gets the gym's next
-- receipt number (1, 2, 3... per gym, never reused), and
-- gym_payment_receipt() gives what the receipt shows, for the desk to
-- print or send, and for the member who paid. Payments recorded before
-- this are numbered oldest first. Safe to re-run.

alter table public.payments add column if not exists receipt_no int check (receipt_no >= 1);

-- Each gym's last receipt number. Only the trigger below touches it.
create table if not exists public.venue_receipt_counters (
  venue_id uuid primary key references public.venues (id) on delete cascade,
  last_no  int not null default 0
);
alter table public.venue_receipt_counters enable row level security;
revoke all on public.venue_receipt_counters from anon, authenticated;

-- Payments without a number, oldest first, after the gym's highest.
with numbered as (
  select p.id,
         coalesce((select max(q.receipt_no) from public.payments q where q.venue_id = p.venue_id), 0)
           + row_number() over (partition by p.venue_id order by p.created_at, p.id) as n
  from public.payments p
  where p.receipt_no is null
)
update public.payments p set receipt_no = numbered.n from numbered where numbered.id = p.id;

insert into public.venue_receipt_counters (venue_id, last_no)
select p.venue_id, max(p.receipt_no) from public.payments p group by p.venue_id
on conflict (venue_id) do update
  set last_no = greatest(public.venue_receipt_counters.last_no, excluded.last_no);

create unique index if not exists payments_venue_receipt on public.payments (venue_id, receipt_no);

-- A new payment takes its gym's next number (the counter's row lock keeps
-- two at once apart).
create or replace function public.payments_give_receipt_no()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.receipt_no is null then
    insert into public.venue_receipt_counters as c (venue_id, last_no) values (new.venue_id, 1)
    on conflict (venue_id) do update set last_no = c.last_no + 1
    returning c.last_no into new.receipt_no;
  end if;
  return new;
end;
$$;
revoke execute on function public.payments_give_receipt_no() from public, anon, authenticated;

drop trigger if exists payments_receipt_no on public.payments;
create trigger payments_receipt_no before insert on public.payments
  for each row execute function public.payments_give_receipt_no();

alter table public.payments alter column receipt_no set not null;

-- What [payment_id]'s receipt shows: the gym, the receipt's number and
-- date, who paid, for which package and dates, how much and how, and who
-- took it. For the gym's staff who see members, payments or income, and
-- for the member who paid (their account, or the person the desk
-- registered when it's linked to their account).
create or replace function public.gym_payment_receipt(payment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_pay public.payments;
  v_sub public.gym_subscriptions;
  v_member public.gym_members;
  v_profile public.profiles;
  v_venue public.venues;
  v_me uuid := (select auth.uid());
begin
  select * into v_pay from public.payments p where p.id = gym_payment_receipt.payment_id;
  if not found then
    raise exception 'There''s no such payment.';
  end if;
  if v_pay.reference_id is not null then
    select * into v_sub from public.gym_subscriptions s where s.id = v_pay.reference_id;
  end if;
  if v_sub.gym_member_id is not null then
    select * into v_member from public.gym_members g where g.id = v_sub.gym_member_id;
  end if;
  -- coalesce: a payment without an account (user_id null) is nobody's own.
  if not coalesce(public.has_venue_permission(v_pay.venue_id, 'gym.members')
                  or public.has_venue_permission(v_pay.venue_id, 'gym.payments')
                  or public.has_venue_permission(v_pay.venue_id, 'venue.income')
                  or v_pay.user_id = v_me
                  or exists (select 1 from public.people p where p.id = v_member.person_id and p.user_id = v_me),
                  false) then
    raise exception 'Only the gym''s staff and the member who paid can see this receipt.';
  end if;
  select * into v_venue from public.venues v where v.id = v_pay.venue_id;
  select * into v_profile from public.profiles pr where pr.id = coalesce(v_pay.user_id, v_sub.member_id);

  return jsonb_build_object(
    'payment_id', v_pay.id,
    'receipt_no', v_pay.receipt_no,
    'paid_at', v_pay.created_at,
    'amount', v_pay.amount,
    'method', v_pay.method,
    'reference', v_pay.reference,
    'status', v_pay.status,
    'gym_name', v_venue.name,
    'gym_phone', v_venue.phone,
    'gym_email', v_venue.email,
    'gym_address', concat_ws(', ', nullif(trim(v_venue.address), ''), nullif(trim(v_venue.town), ''), v_venue.dzongkhag),
    'member_name', coalesce(v_member.full_name, nullif(trim(v_profile.full_name), ''), v_pay.payer_name, 'Member'),
    'member_code', coalesce(v_member.code, v_profile.member_code),
    'member_phone', coalesce(v_member.phone, v_profile.phone),
    'plan_name', v_sub.plan_name,
    'start_date', v_sub.start_date,
    'end_date', v_sub.end_date,
    'received_by', (select nullif(trim(pr.full_name), '') from public.profiles pr where pr.id = v_pay.recorded_by)
  );
end;
$$;
revoke execute on function public.gym_payment_receipt(uuid) from public, anon;
grant execute on function public.gym_payment_receipt(uuid) to authenticated;
