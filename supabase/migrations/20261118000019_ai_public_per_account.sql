-- Health Pro's assistant counts signed-in people by their account, not their
-- address: people on the same mobile network or office Wi-Fi share one
-- address, and would share one allowance. Visitors who aren't signed in are
-- still counted by the hash of their address.
--
-- 15 questions a Bhutan day for each account. The 150 a day for everyone
-- counts visitors only, so someone using up the visitors' share can't stop
-- members asking. Rows are kept 30 days, and go with a deleted account.

alter table public.ai_public_questions
  add column if not exists user_id uuid references auth.users (id) on delete cascade;
alter table public.ai_public_questions alter column client_hash drop not null;
alter table public.ai_public_questions drop constraint if exists ai_public_questions_who;
alter table public.ai_public_questions
  add constraint ai_public_questions_who check (client_hash is not null or user_id is not null);
create index if not exists ai_public_questions_user on public.ai_public_questions (user_id, asked_at);

-- The old one-argument version would make one-argument calls ambiguous.
drop function if exists public.ai_take_public_question(text);

-- Counts a question from [member] (the signed-in account the Edge Function
-- checked), or else from [client] (the hash of a visitor's address). Only
-- the Edge Function calls it, with the service role. Returns how many they
-- have left today after this one.
create or replace function public.ai_take_public_question(client text, member uuid default null)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_each constant int := 15;
  v_visitors constant int := 150;
  v_day_start timestamptz := public.bhutan_today()::timestamp at time zone 'Asia/Thimphu';
  v_all int;
  v_mine int;
begin
  if member is null then
    if client is null or length(client) < 16 then
      raise exception 'Who is asking?';
    end if;
    select count(*) into v_all
    from public.ai_public_questions q
    where q.user_id is null and q.asked_at >= v_day_start;
    if v_all >= v_visitors then
      raise exception 'Health Pro''s assistant has answered all it can for today. Sign in to ask more, or ask again tomorrow; the suggestions still work.';
    end if;
    select count(*) into v_mine
    from public.ai_public_questions q
    where q.user_id is null and q.client_hash = client and q.asked_at >= v_day_start;
  else
    select count(*) into v_mine
    from public.ai_public_questions q
    where q.user_id = member and q.asked_at >= v_day_start;
  end if;
  if v_mine >= v_each then
    raise exception 'You''ve asked % questions today. Ask again tomorrow; the suggestions still work.', v_each;
  end if;

  insert into public.ai_public_questions (client_hash, user_id)
  values (case when member is null then client end, member);
  delete from public.ai_public_questions q where q.asked_at < now() - interval '30 days';
  return v_each - v_mine - 1;
end;
$$;

revoke execute on function public.ai_take_public_question(text, uuid) from public, anon, authenticated;
grant execute on function public.ai_take_public_question(text, uuid) to service_role;
