-- A venue's promotional video: one short clip, uploaded to Health Pro and
-- shown wherever the venue's details are (a gym's page, My gym, the review).
--
-- - venues.promo_video: where the clip is in the public venue-videos bucket
--   ('<venue id>/<file>'), or null.
-- - The bucket takes MP4, WebM and MOV files of up to 20 MB, so one gym can
--   never hold more than a few seconds' worth of storage. A venue's folder
--   holds one clip (two for the moment a new one replaces the old one).
-- - set_venue_promo_video(): whoever edits the venue sets or removes it.
--
-- Safe to run again.

alter table public.venues add column if not exists promo_video text
  check (promo_video ~ '^[0-9a-f-]{36}/[0-9A-Za-z._-]{1,100}\.(mp4|webm|mov)$');

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('venue-videos', 'venue-videos', true, 20971520, array['video/mp4', 'video/webm', 'video/quicktime'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- [object_name]'s venue folder has room for a clip: fewer than two files
-- there (the one in use, and the one about to replace it).
create or replace function public.venue_video_has_room(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select count(*) from storage.objects o
          where o.bucket_id = 'venue-videos'
            and (storage.foldername(o.name))[1] = (storage.foldername(object_name))[1]) < 2;
$$;
revoke execute on function public.venue_video_has_room(text) from public, anon;
grant execute on function public.venue_video_has_room(text) to authenticated;

-- No "replace" policy: a new clip is a new file, and the old one is removed.
drop policy if exists "venue-videos: venue editors upload" on storage.objects;
create policy "venue-videos: venue editors upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'venue-videos' and public.can_edit_venue_folder(name)
              and public.venue_video_has_room(name));
drop policy if exists "venue-videos: venue editors see" on storage.objects;
create policy "venue-videos: venue editors see" on storage.objects for select to authenticated
  using (bucket_id = 'venue-videos' and public.can_edit_venue_folder(name));
drop policy if exists "venue-videos: venue editors remove" on storage.objects;
create policy "venue-videos: venue editors remove" on storage.objects for delete to authenticated
  using (bucket_id = 'venue-videos' and public.can_edit_venue_folder(name));

-- Sets the venue's promotional video to the clip uploaded at [path] in its
-- folder, or removes it (null). Like photos, it doesn't send a venue that
-- was sent back for checking again.
create or replace function public.set_venue_promo_video(venue_id uuid, path text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  p_venue uuid := set_venue_promo_video.venue_id;
  p_path text := nullif(trim(set_venue_promo_video.path), '');
begin
  if not public.has_venue_permission(p_venue, 'venue.edit') then
    raise exception 'Only people who can edit this venue can change it.';
  end if;
  if p_path is not null then
    if p_path !~ ('^' || p_venue::text || '/[0-9A-Za-z._-]{1,100}\.(mp4|webm|mov)$') then
      raise exception 'Upload the video to Health Pro.';
    end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'venue-videos' and o.name = p_path) then
      raise exception 'Upload the video to Health Pro.';
    end if;
  end if;
  update public.venues v set promo_video = p_path where v.id = p_venue;
  if not found then
    raise exception 'This venue no longer exists.';
  end if;
end;
$$;

revoke execute on function public.set_venue_promo_video(uuid, text) from public, anon;
grant execute on function public.set_venue_promo_video(uuid, text) to authenticated;

notify pgrst, 'reload schema';
