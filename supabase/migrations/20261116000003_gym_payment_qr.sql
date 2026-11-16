-- Save the bank-issued payment QR path together with each gym's bank
-- account. This is a forward migration because the previous settings RPC
-- may already be installed on the project.

-- Include the QR path in the account object returned by my_gyms(). The app
-- resolves it to the public storage URL after the RPC returns.
create or replace function public.gym_payment_account(venue uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'bank_name', s.bank_name,
    'account_number', s.account_number,
    'account_name', s.account_name,
    'payment_qr_path', s.payment_qr_path
  )
  from public.gym_settings s
  where s.venue_id = venue
    and s.account_number is not null
    and s.payment_qr_path is not null;
$$;

revoke execute on function public.gym_payment_account(uuid)
  from public, anon, authenticated;

-- Replace the deployed RPC signature. PostgREST resolves RPCs by their named
-- arguments, so the old overload must be removed.
drop function if exists public.gym_save_settings(uuid, text, text, text, int[], text);

create or replace function public.gym_save_settings(
  venue_id uuid,
  bank_name text,
  account_number text,
  account_name text,
  payment_qr_path text,
  reminder_days int[],
  join_approval text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := gym_save_settings.venue_id;
  p_bank text := nullif(regexp_replace(trim(coalesce(gym_save_settings.bank_name, '')), '\s+', ' ', 'g'), '');
  p_number text := nullif(regexp_replace(coalesce(gym_save_settings.account_number, ''), '[\s-]', '', 'g'), '');
  p_name text := nullif(regexp_replace(trim(coalesce(gym_save_settings.account_name, '')), '\s+', ' ', 'g'), '');
  p_qr text := nullif(trim(coalesce(gym_save_settings.payment_qr_path, '')), '');
  v_days int[];
begin
  perform public.gym_require_gym(p_venue);
  if not public.has_venue_permission(p_venue, 'venue.edit') then
    raise exception 'Only those who edit the gym can change its settings.';
  end if;

  if p_bank is not null or p_number is not null or p_name is not null then
    if p_bank is null or p_number is null or p_name is null then
      raise exception 'Enter the bank, the account number and the account name.';
    end if;
    if char_length(p_bank) not between 2 and 60 then
      raise exception 'Choose the bank.';
    end if;
    if p_number !~ '^[0-9]{6,20}$' then
      raise exception 'Enter the account number: 6 to 20 digits.';
    end if;
    if char_length(p_name) not between 2 and 100 then
      raise exception 'Enter the account name, as the bank has it.';
    end if;
  end if;

  if p_qr is not null and p_qr !~ ('^' || p_venue::text || '/[0-9A-Za-z._-]{1,100}$') then
    raise exception 'Upload a QR image for this gym.';
  end if;

  select coalesce(array_agg(distinct d order by d desc), '{}') into v_days
  from unnest(coalesce(gym_save_settings.reminder_days, '{}')) d;
  if exists (select 1 from unnest(v_days) d where d not between 1 and 60) then
    raise exception 'Reminders can be 1 to 60 days before a package ends.';
  end if;
  if cardinality(v_days) > 5 then
    raise exception 'Choose up to 5 reminders.';
  end if;
  if coalesce(gym_save_settings.join_approval, '') not in ('desk', 'managers') then
    raise exception 'Choose who answers requests to join.';
  end if;

  insert into public.gym_settings (
    venue_id, bank_name, account_number, account_name, payment_qr_path,
    reminder_days, join_approval, updated_by
  )
  values (
    p_venue, p_bank, p_number, p_name, p_qr,
    v_days, gym_save_settings.join_approval, (select auth.uid())
  )
  on conflict (venue_id) do update
    set bank_name = excluded.bank_name,
        account_number = excluded.account_number,
        account_name = excluded.account_name,
        payment_qr_path = excluded.payment_qr_path,
        reminder_days = excluded.reminder_days,
        join_approval = excluded.join_approval,
        updated_by = excluded.updated_by;
end;
$$;

revoke execute on function public.gym_save_settings(uuid, text, text, text, text, int[], text)
  from public, anon;
grant execute on function public.gym_save_settings(uuid, text, text, text, text, int[], text)
  to authenticated;

notify pgrst, 'reload schema';
