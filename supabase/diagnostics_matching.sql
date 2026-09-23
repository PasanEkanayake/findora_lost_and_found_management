-- ============================================================================
-- Findora — matching diagnostic
-- Run each block below in the Supabase SQL Editor, one at a time, and
-- share the results. Together they narrow down exactly which of the
-- several possible causes is actually the one in play.
-- ============================================================================

-- 1) Do the two most recent items belong to the SAME user?
-- match_items() deliberately excludes matching an item against another
-- item posted by the same account (you'd never want your own "lost"
-- report matched against your own "found" report in real use) — if
-- you've been testing solo, posting both a lost and a found report from
-- one account, THIS is very likely the actual answer: it's not a bug,
-- matching two of your own items is supposed to never happen.
select id, title, type, user_id, category_id, status, deleted_at, created_at
from items
order by created_at desc
limit 5;

-- 2) Do those items actually have a stored image embedding?
-- (This is what the last round of fixes targeted — confirms whether
-- that's still the problem, or whether it's now something else.)
select
  i.title,
  i.type,
  img.id as image_id,
  img.embedding is not null as has_embedding,
  img.created_at
from item_images img
join items i on i.id = img.item_id
order by img.created_at desc
limit 5;

-- 3) If two items DO have embeddings, what's their actual similarity?
-- Replace the two uuids with item_images.id values from query 2 above
-- (pick one image from each of your two test items).
select 1 - (a.embedding <=> b.embedding) as similarity
from item_images a, item_images b
where a.id = 'PASTE_IMAGE_ID_1'
  and b.id = 'PASTE_IMAGE_ID_2';
-- match_items() requires this to be >= 0.75 by default. If it comes back
-- lower than that, the photos genuinely aren't similar *to the model* even
-- if they look similar to a person — MobileNetV2 embeddings don't always
-- track human visual similarity perfectly, especially at a 0.75 bar.

-- 4) Are the migrations that matter for matching actually applied?
select
  exists (select 1 from information_schema.columns
          where table_name = 'items' and column_name = 'deleted_at') as has_deleted_at,
  exists (select 1 from information_schema.columns
          where table_name = 'items' and column_name = 'event_time') as has_event_time,
  exists (select 1 from pg_proc where proname = 'record_matches_for_image') as has_trigger_fn,
  exists (select 1 from pg_trigger where tgname = 'item_images_record_matches') as has_trigger;

-- 5) Has the trigger ever actually inserted anything into `matches`, for
-- ANY pair of items, ever? If this is empty even after fixing embeddings
-- and testing with two different accounts, something deeper is wrong and
-- needs more detail than this script can capture — reply with what all
-- five queries above show.
select * from matches order by created_at desc limit 10;
