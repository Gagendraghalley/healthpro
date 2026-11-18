-- Expenses, for the profit side of Payments & income: what the gym spent,
-- on what (rent, salaries, equipment...), when, how it paid and to whom.
-- Profit is the payments in a month less its expenses; the app works it out.
-- Who sees income ('venue.income': owners and managers) sees and records
-- them. Every change is in the activity log. Safe to re-run.

create table if not exists public.gym_expenses (
  id         uuid primary key default gen_random_uuid(),
  venue_id   uuid not null references public.venues (id) on delete cascade,
  spent_on   date not null, -- Bhutan date
  category   text not null check (category in ('rent', 'salaries', 'equipment', 'maintenance', 'utilities', 'supplies',
                                                'marketing', 'other')),
  amount     int not null check (amount between 1 and 10000000), -- Ngultrum
  method     text not null default 'cash' check (method in ('cash', 'mbob', 'bank', 'other')),
  paid_to    text check (char_length(paid_to) <= 100),
  note       text check (char_length(note) <= 500),
  created_by uuid constraint gym_expenses_created_by_fkey references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_by uuid constraint gym_expenses_updated_by_fkey references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now()
);
create index if not exists gym_expenses_venue on public.gym_expenses (venue_id, spent_on desc);

drop trigger if exists gym_expenses_updated_at on public.gym_expenses;
create trigger gym_expenses_updated_at before update on public.gym_expenses
  for each row execute function public.set_updated_at();

alter table public.gym_expenses enable row level security;
revoke all on public.gym_expenses from anon, authenticated;
grant select on public.gym_expenses to authenticated;
drop policy if exists "gym_expenses: who sees income" on public.gym_expenses;
create policy "gym_expenses: who sees income" on public.gym_expenses for select to authenticated
  using (public.has_venue_permission(venue_id, 'venue.income'));

-- 'rent' -> 'rent', 'utilities' -> 'electricity, water and internet'.
create or replace function public.gym_expense_label(category text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case category
    when 'utilities' then 'electricity, water and internet'
    when 'supplies' then 'supplies'
    when 'other' then 'something else'
    else category
  end
$$;

-- A new expense at [venue_id] ([expense_id] null) or changes to one, from
-- [details]: spent_on, category, amount, method, paid_to, note. Its id.
create or replace function public.gym_save_expense(venue_id uuid, expense_id uuid, details jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  d jsonb := coalesce(gym_save_expense.details, '{}');
  v_venue uuid := gym_save_expense.venue_id;
  v_on date := nullif(d ->> 'spent_on', '')::date;
  v_category text := nullif(d ->> 'category', '');
  v_amount int := nullif(d ->> 'amount', '')::int;
  v_method text := coalesce(nullif(d ->> 'method', ''), 'cash');
  v_paid_to text := nullif(trim(coalesce(d ->> 'paid_to', '')), '');
  v_note text := nullif(trim(coalesce(d ->> 'note', '')), '');
  v_id uuid;
begin
  if not public.has_venue_permission(v_venue, 'venue.income') then
    raise exception 'Only those who see the gym''s income can record its expenses.';
  end if;
  if gym_save_expense.expense_id is not null
     and not exists (select 1 from public.gym_expenses e where e.id = gym_save_expense.expense_id and e.venue_id = v_venue) then
    raise exception 'This expense isn''t there any more.';
  end if;
  if v_on is null or v_on > public.bhutan_today() or v_on < date '2000-01-01' then
    raise exception 'Choose the day it was spent (today or before).';
  end if;
  if v_category is null or v_category not in ('rent', 'salaries', 'equipment', 'maintenance', 'utilities', 'supplies',
                                              'marketing', 'other') then
    raise exception 'Choose what it was for.';
  end if;
  if v_amount is null or v_amount not between 1 and 10000000 then
    raise exception 'Enter the amount spent.';
  end if;
  if v_method not in ('cash', 'mbob', 'bank', 'other') then
    raise exception 'Choose how it was paid.';
  end if;
  if char_length(v_paid_to) > 100 then
    raise exception 'Keep who it was paid to under 100 characters.';
  end if;
  if char_length(v_note) > 500 then
    raise exception 'Keep the note under 500 characters.';
  end if;

  if gym_save_expense.expense_id is null then
    insert into public.gym_expenses (venue_id, spent_on, category, amount, method, paid_to, note, created_by, updated_by)
    values (v_venue, v_on, v_category, v_amount, v_method, v_paid_to, v_note, (select auth.uid()), (select auth.uid()))
    returning id into v_id;
    return v_id;
  end if;
  update public.gym_expenses e
     set spent_on = v_on, category = v_category, amount = v_amount, method = v_method, paid_to = v_paid_to, note = v_note,
         updated_by = (select auth.uid())
   where e.id = gym_save_expense.expense_id;
  return gym_save_expense.expense_id;
end;
$$;

create or replace function public.gym_delete_expense(expense_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venue uuid;
begin
  select e.venue_id into v_venue from public.gym_expenses e where e.id = gym_delete_expense.expense_id;
  if v_venue is null then
    raise exception 'This expense isn''t there any more.';
  end if;
  if not public.has_venue_permission(v_venue, 'venue.income') then
    raise exception 'Only those who see the gym''s income can record its expenses.';
  end if;
  delete from public.gym_expenses e where e.id = gym_delete_expense.expense_id;
end;
$$;

revoke execute on function public.gym_save_expense(uuid, uuid, jsonb), public.gym_delete_expense(uuid) from public, anon;
grant execute on function public.gym_save_expense(uuid, uuid, jsonb), public.gym_delete_expense(uuid) to authenticated;

-- In the activity log: spent, changed, removed.
create or replace function public.gym_audit_expenses()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changes text[];
  v_how text;
begin
  if tg_op = 'INSERT' then
    v_how := case new.method when 'mbob' then 'mBoB' when 'cash' then 'cash' when 'bank' then 'bank transfer' else 'other' end;
    perform public.gym_audit(new.venue_id, 'expense.added',
                             'Spent ' || public.gym_audit_nu(new.amount) || ' on ' || public.gym_expense_label(new.category),
                             concat_ws(' · ', public.gym_audit_day(new.spent_on), 'paid to ' || new.paid_to, v_how, new.note),
                             null, null, new.amount);
  elsif tg_op = 'DELETE' then
    perform public.gym_audit(old.venue_id, 'expense.removed', 'Removed an expense of ' || public.gym_audit_nu(old.amount),
                             public.gym_expense_label(old.category) || ', ' || public.gym_audit_day(old.spent_on),
                             null, null, old.amount);
  else
    v_changes := array_remove(array[
      case when new.amount <> old.amount then 'amount ' || public.gym_audit_nu(old.amount) || ' to ' || public.gym_audit_nu(new.amount) end,
      case when new.category <> old.category then 'for ' || public.gym_expense_label(new.category) || ', not '
                                                  || public.gym_expense_label(old.category) end,
      case when new.spent_on <> old.spent_on then 'day ' || public.gym_audit_day(old.spent_on) || ' to ' || public.gym_audit_day(new.spent_on) end,
      case when new.method <> old.method then 'how it was paid' end,
      case when new.paid_to is distinct from old.paid_to then 'who it was paid to' end,
      case when new.note is distinct from old.note then 'note' end
    ], null);
    if cardinality(v_changes) > 0 then
      perform public.gym_audit(new.venue_id, 'expense.changed',
                               'Changed an expense of ' || public.gym_audit_nu(new.amount) || ' (' || public.gym_expense_label(new.category) || ')',
                               array_to_string(v_changes, ' · '), null, null, new.amount);
    end if;
  end if;
  return null;
end;
$$;
drop trigger if exists gym_expenses_audit on public.gym_expenses;
create trigger gym_expenses_audit after insert or update or delete on public.gym_expenses
  for each row execute function public.gym_audit_expenses();
revoke execute on function public.gym_audit_expenses() from public, anon, authenticated;
