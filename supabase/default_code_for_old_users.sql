-- Old accounts onto 6-digit sign-in codes: run once, after the app that
-- signs in with a 6-digit code (no passwords) goes live.
--
-- Accounts made before that have an old password, or none, and neither
-- signs them in any more. This gives each of them the starting code 123456
-- and marks them to choose their own: the first time they sign in, nothing
-- opens until they have (the same as an account an admin makes for someone).
--
-- How: Supabase -> SQL Editor -> New query, paste this whole file and Run.
-- The table at the end lists the accounts it changed.
--
-- Left alone:
--   - anyone who has already chosen a 6-digit code, or is already on the
--     starting code (so it's safe to run again);
--   - the test accounts (@example.com): supabase/test_users.sql sets theirs;
--   - sign-ups whose email was never confirmed.
-- Accounts that were turned off stay off.
--
-- Until someone signs in and chooses their code, anyone who knows their
-- email can sign in as them with 123456, admins included. Tell people to
-- sign in straight away.

with changed as (
  update auth.users u
  -- The sign-in code is the account's password, kept as Supabase Auth
  -- keeps them (bcrypt).
  set encrypted_password = extensions.crypt('123456', extensions.gen_salt('bf')),
      raw_user_meta_data = coalesce(u.raw_user_meta_data, '{}'::jsonb) || '{"must_choose_code": true}'::jsonb,
      updated_at = now()
  where not (coalesce(u.raw_user_meta_data, '{}'::jsonb) ? 'must_choose_code')
    and u.email_confirmed_at is not null
    and u.email not like '%@example.com'
  returning u.email, u.banned_until
)
select email, case when banned_until > now() then 'Turned off' else 'Signs in with 123456, then chooses a code' end as now
from changed
order by email;
