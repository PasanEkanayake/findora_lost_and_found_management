-- ============================================================================
-- Findora — Storage buckets and policies
-- Run this after 03_rls_policies.sql. You can also create the buckets from
-- Dashboard > Storage instead of SQL — either approach works.
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('item-images', 'item-images', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- item-images: publicly readable (needed for cached_network_image and for
-- displaying other users' items); uploads restricted to a folder named
-- after the uploader's own user id, e.g. item-images/{user_id}/{item_id}/1.jpg
create policy "item images are publicly readable"
  on storage.objects for select
  using (bucket_id = 'item-images');

create policy "users can upload item images into their own folder"
  on storage.objects for insert
  with check (
    bucket_id = 'item-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "users can delete their own item images"
  on storage.objects for delete
  using (
    bucket_id = 'item-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- avatars: same one-folder-per-user pattern.
create policy "avatars are publicly readable"
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy "users can upload their own avatar"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "users can replace their own avatar"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
