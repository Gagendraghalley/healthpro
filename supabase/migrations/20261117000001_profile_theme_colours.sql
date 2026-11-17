-- Each person's own app colours (Account -> Appearance -> App theme), kept on
-- their account so every device they sign in on shows them. The ids of the
-- app's palettes ('blue', 'plum'); null is Health Pro's own orange and navy.
-- Safe to re-run.

alter table public.profiles add column if not exists theme_primary text;
alter table public.profiles add column if not exists theme_accent text;

-- Short lower-case ids only; the app treats one it doesn't offer as its own.
alter table public.profiles drop constraint if exists profiles_theme_ids;
alter table public.profiles add constraint profiles_theme_ids check (
  (theme_primary is null or theme_primary ~ '^[a-z]{1,20}$')
  and (theme_accent is null or theme_accent ~ '^[a-z]{1,20}$')
);

-- They change their own ("profiles: update own"); nothing else is opened up.
grant update (theme_primary, theme_accent) on public.profiles to authenticated;
