-- ============================================================================
-- Findora — checks for 34_thumbnails.sql and the make-thumbnails function
-- Run in the Supabase SQL editor against a STAGING project. Read-only.
-- NOT run by the author.
-- ============================================================================

-- 1. The column and the partial index exist (expect 1 row, 1 row).
select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'item_images' and column_name = 'thumb_url';
select indexname from pg_indexes where indexname = 'item_images_missing_thumb_idx';

-- 2. The protect trigger exists (expect 1).
select count(*) from pg_trigger where tgname = 'item_images_protect_thumb' and not tgisinternal;

-- 3. Lists prefer the thumbnail (expect the count of functions below to be 5).
select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('nearby_items', 'my_conversations', 'my_contact_threads',
                    'my_returned_items', 'my_matches_page')
  and pg_get_functiondef(p.oid) like '%coalesce(img.thumb_url, img.image_url)%';

-- 4. Progress of the backlog (should fall towards 0 as people open the app, or
--    after the admin backfill in supabase/functions/make-thumbnails/README.md).
select count(*) filter (where thumb_url is null) as without_thumbnail,
       count(*) filter (where thumb_url is not null) as with_thumbnail
from public.item_images;

-- 5. Every thumbnail points into our bucket and is named thumb_*.jpg (expect 0).
select count(*) from public.item_images
where thumb_url is not null
  and (thumb_url not like '%/item-images/%' or thumb_url not like '%/thumb\_%.jpg' escape '\');

-- 6. Walk-through (staging):
--    a. Post an item with 2 photos. Within a few seconds
--         select image_url, thumb_url from item_images where item_id = '<id>';
--       shows both thumb_url values filled in. Open one in a browser: a small
--       JPEG (long side 480 px), noticeably smaller than the original.
--    b. Browse / My posts / Matches show the thumbnail; the post page's gallery
--       shows the full photo.
--    c. In the editor, remove a photo: its original AND thumb_ file disappear
--       from Storage; replace a photo: the row's thumb_url is cleared, then
--       refilled.
--    d. From the app (or SQL as an API user), try to set thumb_url to any URL:
--       it is ignored.
