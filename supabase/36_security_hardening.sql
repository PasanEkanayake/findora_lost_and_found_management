-- ============================================================================
-- Findora — Security and privacy hardening (from the full audit)
-- Run this after 35_post_expiry.sql. Safe to re-run. Changes no user data.
-- (The audit report lists each finding; the numbers below match it.)
--
--   H3  item_images.image_url and profiles.avatar_url accepted ANY address. A
--       post (or avatar) could point at a picture on someone else's server:
--       every person who opened it would send their IP address and device
--       details there, and the owner could swap the picture later to track who
--       looks. They must now point into Findora's own storage, inside the
--       owner's own folder.
--   H4  Anyone with the project URL + public key could LIST every file in the
--       photo and avatar buckets (a broad SELECT policy), learning every
--       user's id and every photo's path — including photos of deleted,
--       resolved or moderated posts. Photos still load by their link (public
--       buckets don't need that policy); listing is now limited to your own
--       folder.
--   M5  rescore_matches_for_item() — an internal maintenance function — could be
--       called by anyone, signed in or not. Locked.
--   M6  Direct inserts into contact_threads bypassed start_contact_thread()
--       (its blocked-user, expired-post and rate-limit checks). The direct
--       insert policy is removed; the app never used it.
--
-- The optional `storage_host` setting below makes the image-URL rule check the
-- web address too (recommended).
-- ============================================================================

-- ---- settings the guards can read ----------------------------------------------------------
create table if not exists public.app_settings (
  key text primary key,
  value text not null
);
alter table public.app_settings enable row level security;
revoke all on public.app_settings from anon, authenticated;
-- No policies on purpose: only the functions below (and you, in the SQL editor).

-- OPTIONAL BUT RECOMMENDED. Put your project's address here so the rules below
-- also check the web address, not just the path. Use the host of SUPABASE_URL
-- (no https://), e.g.:
--   insert into public.app_settings (key, value)
--   values ('storage_host', 'abcdwxyz.supabase.co')
--   on conflict (key) do update set value = excluded.value;

-- ---- H4. no listing of other people's files ---------------------------------------------------
drop policy if exists "item images are publicly readable" on storage.objects;
drop policy if exists "avatars are publicly readable" on storage.objects;
drop policy if exists "people can list their own item images" on storage.objects;
drop policy if exists "people can list their own avatar files" on storage.objects;

-- Reading a photo by its link needs no policy (the buckets are public); these
-- only govern the list/info API and the "DELETE ... RETURNING" a removal does.
create policy "people can list their own item images"
  on storage.objects for select to authenticated
  using (bucket_id = 'item-images' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "people can list their own avatar files"
  on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ---- M5 ------------------------------------------------------------------------------------------
revoke all on function public.rescore_matches_for_item(uuid) from public, anon, authenticated;

-- ---- M6 ------------------------------------------------------------------------------------------
drop policy if exists "users can start a contact thread as themselves" on public.contact_threads;

-- ---- H3. photo and avatar addresses ------------------------------------------------------------
create or replace function public.item_images_guard_url()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  owner_id uuid;
  expected_host text;
begin
  -- Our own functions and admins (SQL editor, service role) are not restricted.
  if not public.is_api_caller() then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.image_url is not distinct from old.image_url then
    return new;
  end if;

  select user_id into owner_id from public.items where id = new.item_id;

  -- <host>/storage/v1/object/public/item-images/<owner>/<this post>/<file>
  if owner_id is null or new.image_url !~ (
       '^https?://[A-Za-z0-9.-]+(:[0-9]+)?/storage/v1/object/public/item-images/'
       || owner_id::text || '/' || new.item_id::text || '/[A-Za-z0-9._-]+$'
     ) then
    raise exception 'Photos must be uploaded to Findora.' using errcode = '22023';
  end if;

  select value into expected_host from public.app_settings where key = 'storage_host';
  if expected_host is not null
     and substring(new.image_url from '^https?://([^/]+)/') is distinct from expected_host then
    raise exception 'Photos must be uploaded to Findora.' using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke all on function public.item_images_guard_url() from public, anon, authenticated;

drop trigger if exists item_images_guard_url on public.item_images;
create trigger item_images_guard_url
  before insert or update of image_url on public.item_images
  for each row execute function public.item_images_guard_url();

create or replace function public.profiles_guard_avatar_url()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  expected_host text;
begin
  if not public.is_api_caller() then
    return new;
  end if;
  if new.avatar_url is null or new.avatar_url is not distinct from old.avatar_url then
    return new;
  end if;

  if new.avatar_url !~ (
       '^https?://[A-Za-z0-9.-]+(:[0-9]+)?/storage/v1/object/public/avatars/'
       || new.id::text || '/[A-Za-z0-9._/-]+$'
     ) then
    raise exception 'Profile photos must be uploaded to Findora.' using errcode = '22023';
  end if;

  select value into expected_host from public.app_settings where key = 'storage_host';
  if expected_host is not null
     and substring(new.avatar_url from '^https?://([^/]+)/') is distinct from expected_host then
    raise exception 'Profile photos must be uploaded to Findora.' using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke all on function public.profiles_guard_avatar_url() from public, anon, authenticated;

drop trigger if exists profiles_guard_avatar_url on public.profiles;
create trigger profiles_guard_avatar_url
  before update of avatar_url on public.profiles
  for each row execute function public.profiles_guard_avatar_url();
