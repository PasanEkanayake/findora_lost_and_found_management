-- ============================================================================
-- Findora — matching diagnostic
-- Run each block below in the Supabase SQL Editor ONE AT A TIME: select
-- (highlight) just that query's text, then click Run — the editor runs
-- only the highlighted part. Don't run the whole file at once: the editor
-- shows the result of the last statement only, so you'd miss the rest.
-- Every query here works as-is, with nothing to edit.
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

-- 2b) START HERE. Every item with its owner, type and whether its photo
-- has an AI embedding — one row per item, newest first. This only affects
-- PHOTO matching — text matching (title/description) doesn't need a photo
-- at all and isn't shown here; see query 3d for that. Compare with the
-- app: a Lost item and a Found item from DIFFERENT owners, both showing
-- has_embedding = true, are the pairs that should have photo-matched. Any
-- has_embedding = false row is invisible to *photo* matching until its
-- owner opens the updated app (it embeds their photos automatically at
-- launch) or taps the scan icon on their Matches tab.
select
  i.title,
  i.type,
  coalesce(p.full_name, p.username, i.user_id::text) as owner,
  i.status,
  (i.deleted_at is not null) as deleted,
  count(img.id) as photos,
  count(img.embedding) as photos_with_embedding,
  (count(img.id) > 0 and count(img.id) = count(img.embedding)) as has_embedding,
  i.created_at
from public.items i
left join public.profiles p on p.id = i.user_id
left join public.item_images img on img.item_id = i.id
group by i.id, p.full_name, p.username
order by i.created_at desc
limit 40;

-- 3) (Optional, and the only query here that needs editing.) The exact
-- similarity between two specific photos. It is commented out so that
-- running the whole file can't fail on the placeholders — to use it,
-- replace both placeholders with item_images.id values from query 2 (one
-- photo from each test item), remove the leading "-- " from each line,
-- and run it on its own.
--
-- select 1 - (a.embedding <=> b.embedding) as similarity
-- from item_images a, item_images b
-- where a.id = 'PASTE_IMAGE_ID_1'
--   and b.id = 'PASTE_IMAGE_ID_2';
--
-- Photos are only proposed as a match if this is >= matching_threshold()
-- (0.60 after 11_realtime_and_matching_fixes.sql; it was 0.75 before). If
-- it comes back lower, the photos genuinely aren't similar *to the model*
-- even if they look similar to a person — MobileNetV2 embeddings don't
-- always track human visual similarity perfectly. Query 3b below shows
-- every pair at once with no editing, so try that first.

-- 3b) Every cross-account, opposite-type pair of photos that both have an
-- embedding, best first, with NO threshold applied. This is the query to
-- tune matching_threshold() from: pairs you'd consider "the same thing"
-- should sit above the line, obviously-different ones below it. Anything
-- at or above matching_threshold() should already be in `matches` (query 5)
-- — if a pair is above it and missing there, run:
--   select public.rematch_all_images();
select
  a.title as title_a, a.type as type_a,
  b.title as title_b, b.type as type_b,
  round((1 - (ia.embedding <=> ib.embedding))::numeric, 3) as similarity,
  (1 - (ia.embedding <=> ib.embedding)) >= public.matching_threshold() as above_threshold
from item_images ia
join items a on a.id = ia.item_id
join item_images ib on ib.id > ia.id
join items b on b.id = ib.item_id
where a.type <> b.type
  and a.user_id <> b.user_id
  and a.deleted_at is null and b.deleted_at is null
  and ia.embedding is not null and ib.embedding is not null
order by similarity desc
limit 30;

-- 3c) How many photos does each account have with / without an embedding?
-- A photo WITHOUT one is invisible to AI matching. If an account shows a
-- non-zero `without_embedding`, log into it in the app and open the Matches
-- tab (it scans and fills these in automatically), or tap the scan icon.
select
  coalesce(p.full_name, p.username, p.id::text) as account,
  count(*) filter (where img.embedding is not null) as with_embedding,
  count(*) filter (where img.embedding is null) as without_embedding
from item_images img
join items i on i.id = img.item_id
join profiles p on p.id = i.user_id
where i.deleted_at is null
group by 1
order by without_embedding desc;

-- 3d) Every cross-account, opposite-type pair of ITEMS (no photo needed),
-- best first, with NO threshold applied — the text-matching equivalent of
-- 3b. This is the query to tune text_matching_threshold() from. A pair
-- above text_matching_threshold() should already be in `matches` (query 5)
-- — if it's above the line and missing there, run:
--   select public.rematch_all_text();
select
  a.title as title_a, a.type as type_a,
  b.title as title_b, b.type as type_b,
  round(public.text_similarity_between(a.id, b.id)::numeric, 3) as similarity,
  public.text_similarity_between(a.id, b.id) >= public.text_matching_threshold()
    as above_threshold
from items a
join items b on b.id > a.id
where a.type <> b.type
  and a.user_id <> b.user_id
  and a.deleted_at is null and b.deleted_at is null
order by similarity desc
limit 30;

-- 4) Are the migrations that matter for matching / chat actually applied?
select
  exists (select 1 from information_schema.columns
          where table_name = 'items' and column_name = 'deleted_at') as has_deleted_at,
  exists (select 1 from information_schema.columns
          where table_name = 'items' and column_name = 'event_time') as has_event_time,
  exists (select 1 from pg_proc where proname = 'record_matches_for_image') as has_trigger_fn,
  exists (select 1 from pg_trigger where tgname = 'item_images_record_matches') as has_trigger,
  -- migration 11:
  exists (select 1 from pg_proc where proname = 'match_image') as has_11_match_image,
  exists (select 1 from pg_trigger
          where tgname = 'item_images_record_matches_on_embedding') as has_11_update_trigger,
  exists (select 1 from pg_policies
          where tablename = 'item_images'
            and policyname = 'users can update images on their own items') as has_11_update_policy,
  -- live chat needs BOTH of these to be true (migration 11):
  exists (select 1 from pg_publication_tables
          where pubname = 'supabase_realtime' and schemaname = 'public'
            and tablename = 'contact_messages') as realtime_contact_messages,
  exists (select 1 from pg_publication_tables
          where pubname = 'supabase_realtime' and schemaname = 'public'
            and tablename = 'messages') as realtime_messages,
  -- migration 12:
  exists (select 1 from pg_proc where proname = 'match_item_by_text') as has_12_text_match_fn,
  exists (select 1 from pg_trigger
          where tgname = 'items_record_text_matches_insert') as has_12_insert_trigger,
  exists (select 1 from pg_trigger
          where tgname = 'items_record_text_matches_update') as has_12_update_trigger;

-- 5) Has the trigger ever actually inserted anything into `matches`, for
-- ANY pair of items, ever? If this is empty even after fixing embeddings
-- and testing with two different accounts, something deeper is wrong and
-- needs more detail than this script can capture — reply with what all
-- five queries above show.
select * from matches order by created_at desc limit 10;
