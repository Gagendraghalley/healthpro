-- Everyone's own profile photo (Account -> Edit profile), shown on their
-- account and at the top right of every page. The picture is in the public
-- profile-photos bucket, in a folder named after their account, which only
-- they change; profiles.avatar_url is its public address. Safe to re-run.

alter table public.profiles add column if not exists avatar_url text;

-- An http(s) address of a sensible length, or none (their initials show).
alter table public.profiles drop constraint if exists profiles_avatar_url;
alter table public.profiles add constraint profiles_avatar_url check (
  avatar_url is null or (avatar_url ~ '^https?://' and length(avatar_url) <= 600)
);

-- They change their own ("profiles: update own"); nothing else is opened up.
grant update (avatar_url) on public.profiles to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-photos', 'profile-photos', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

drop policy if exists "profile-photos: they add to their own folder" on storage.objects;
create policy "profile-photos: they add to their own folder" on storage.objects for insert to authenticated
  with check (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
-- Seeing their own files lets them replace and remove them (the bucket is
-- public, so anyone can still load a photo by its address).
drop policy if exists "profile-photos: they see their own" on storage.objects;
create policy "profile-photos: they see their own" on storage.objects for select to authenticated
  using (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "profile-photos: they replace their own" on storage.objects;
create policy "profile-photos: they replace their own" on storage.objects for update to authenticated
  using (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "profile-photos: they remove their own" on storage.objects;
create policy "profile-photos: they remove their own" on storage.objects for delete to authenticated
  using (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
