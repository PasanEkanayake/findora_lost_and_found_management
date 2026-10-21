-- ============================================================================
-- Findora — checks for 36_security_hardening.sql, plus audit queries that look
-- for problems ALREADY in your data. Run in the SQL editor on staging first.
-- Read-only. NOT run by the author.
-- ============================================================================

-- 1. The broad public-listing policies are gone and the own-folder ones exist
--    (expect 0, then 2).
select count(*) from pg_policies
where schemaname = 'storage' and tablename = 'objects'
  and policyname in ('item images are publicly readable', 'avatars are publicly readable');
select count(*) from pg_policies
where schemaname = 'storage' and tablename = 'objects'
  and policyname in ('people can list their own item images', 'people can list their own avatar files');

-- 2. Maintenance function locked; direct thread insert gone (expect false, false, false, then 0).
select has_function_privilege('anon', 'public.rescore_matches_for_item(uuid)', 'execute'),
       has_function_privilege('authenticated', 'public.rescore_matches_for_item(uuid)', 'execute'),
       has_function_privilege('public', 'public.rescore_matches_for_item(uuid)', 'execute');
select count(*) from pg_policies
where tablename = 'contact_threads' and cmd = 'INSERT';

-- 3. Guards installed (expect 2).
select count(*) from pg_trigger
where tgname in ('item_images_guard_url', 'profiles_guard_avatar_url') and not tgisinternal;

-- 4. Is the optional host check on? (expect one row; none means the guards only
--    check the path.)
select * from public.app_settings where key = 'storage_host';

-- 5. EXISTING data that points outside Findora's storage (expect 0 and 0; any
--    rows are pictures that other people's phones fetch from someone else's
--    server — look at them, and remove or re-upload them).
select id, item_id, image_url from public.item_images
where image_url !~ '/storage/v1/object/public/item-images/' limit 50;
select id, avatar_url from public.profiles
where avatar_url is not null
  and avatar_url !~ '/storage/v1/object/public/avatars/'
  and avatar_url !~ '^https://lh3\.googleusercontent\.com/'   -- Google sign-in avatars are expected
limit 50;

-- 6. Walk-through (staging, as an ordinary signed-in user, with the app or
--    the API): inserting an item_images row whose image_url is
--    'https://example.com/x.jpg' fails with "Photos must be uploaded to Findora.";
--    listing the item-images bucket through the storage API returns only your own
--    folder; start_contact_thread still works from the app.
