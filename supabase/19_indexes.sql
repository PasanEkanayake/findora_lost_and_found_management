-- ============================================================================
-- Findora — Performance: indexes (+ a counts function) for the feed
-- Run this after 18_calibrated_match_score.sql. Safe to re-run, changes no
-- data and no behaviour — it only makes lookups faster as tables grow.
--
-- Until now the tables had indexes on location, category, status, soft-delete,
-- photo embeddings, chat messages per match, contact messages and
-- notifications — and nothing on the columns most screens filter or join by.
-- On a small test database that is invisible; with thousands of posts, every
-- feed load, "my posts", match lookup and RLS check would scan whole tables.
--
-- Every index below is named for the screen/query it serves. Each is cheap to
-- keep (these tables are read far more than written). Plain CREATE INDEX takes
-- a brief write lock on a small table; on a large live table use
-- CREATE INDEX CONCURRENTLY one statement at a time instead.
-- ============================================================================

-- ---- items ------------------------------------------------------------------
-- Feed: open, not removed, newest first. Partial so it only holds the rows the
-- feed can ever return and stays small as old posts resolve or get deleted.
create index if not exists items_feed_idx
  on public.items (created_at desc, id desc)
  where status = 'open' and deleted_at is null;

-- "My posts", and every RLS check that asks "is this row mine?"
create index if not exists items_user_idx
  on public.items (user_id, created_at desc);

-- Text search (the feed's search box uses ILIKE '%term%' on both columns).
-- Trigram GIN indexes are what let ILIKE with a leading wildcard avoid a scan.
create index if not exists items_title_trgm_idx
  on public.items using gin (title gin_trgm_ops);
create index if not exists items_description_trgm_idx
  on public.items using gin (description gin_trgm_ops);

-- Semantic text matching (cosine distance on the 384-d title+description
-- embedding) — the same HNSW setup the photo embeddings already use.
create index if not exists items_text_embedding_idx
  on public.items using hnsw (text_embedding vector_cosine_ops);

-- ---- item_images ------------------------------------------------------------
-- Every feed card, match card and post screen loads "the photos of this item,
-- first one first".
create index if not exists item_images_item_idx
  on public.item_images (item_id, created_at);

-- ---- matches ----------------------------------------------------------------
-- The unique (item_a_id, item_b_id) constraint already serves lookups by
-- item_a_id; this serves the other side. my_matches(), rematching, the
-- "possible matches" count and the RLS check all look a post up on either side.
create index if not exists matches_item_b_idx
  on public.matches (item_b_id);

-- ---- claims / ratings / reports ---------------------------------------------
create index if not exists claims_item_claimant_idx
  on public.claims (item_id, claimant_id);
create index if not exists claims_claimant_idx
  on public.claims (claimant_id);

create index if not exists ratings_ratee_idx
  on public.ratings (ratee_id);

-- The admin queue only ever reads open reports.
create index if not exists reports_open_idx
  on public.reports (created_at desc)
  where status = 'open';

-- ---- chat -------------------------------------------------------------------
-- Unread badge / mark-as-read: "messages sent to me that I haven't read".
create index if not exists messages_unread_idx
  on public.messages (receiver_id)
  where read_at is null;

-- Direct-message lists load "threads where I'm the owner" and "threads where
-- I'm the person who reached out" (the unique (item_id, contacter_id) pair
-- only helps lookups that start from the item).
create index if not exists contact_threads_owner_idx
  on public.contact_threads (item_owner_id);
create index if not exists contact_threads_contacter_idx
  on public.contact_threads (contacter_id);

-- ---- feed_counts ------------------------------------------------------------
-- The Browse header shows "N lost - N found" for the current search/category.
-- The feed now loads 20 posts at a time, so those totals can no longer be
-- counted from the loaded list; this returns them in one cheap indexed query.
-- SECURITY INVOKER (the default) on purpose: row-level security still applies,
-- so the counts are exactly the posts this person is allowed to see.
create or replace function public.feed_counts(
  p_category_id uuid default null,
  p_search text default null
)
returns table (lost_count bigint, found_count bigint)
language sql
stable
as $$
  select
    count(*) filter (where i.type = 'lost'),
    count(*) filter (where i.type = 'found')
  from public.items i
  where i.status = 'open'
    and i.deleted_at is null
    and (p_category_id is null or i.category_id = p_category_id)
    and (
      nullif(btrim(coalesce(p_search, '')), '') is null
      or i.title ilike '%' || replace(replace(replace(btrim(p_search), '\', '\\'), '%', '\%'), '_', '\_') || '%'
      or i.description ilike '%' || replace(replace(replace(btrim(p_search), '\', '\\'), '%', '\%'), '_', '\_') || '%'
    );
$$;

revoke all on function public.feed_counts(uuid, text) from public, anon;
grant execute on function public.feed_counts(uuid, text) to authenticated;

-- ============================================================================
-- Verify (optional):
--   select indexname from pg_indexes
--   where schemaname = 'public' and indexname in (
--     'items_feed_idx', 'items_user_idx', 'item_images_item_idx', 'matches_item_b_idx');
--
-- Check a query actually uses one (run on real data, not an empty table):
--   explain select * from public.items
--   where status = 'open' and deleted_at is null
--   order by created_at desc, id desc limit 20;
--   -- expect "Index Scan using items_feed_idx"
--
-- Still worth doing, separately: Supabase Dashboard -> Advisors -> Performance
-- also flags policies that call auth.uid() per row instead of once per query
-- (the fix is writing it as (select auth.uid()) — 17_harden_policies.sql does
-- this for the policies it rewrote; the older ones in 03/13/14 can follow).
-- ============================================================================
