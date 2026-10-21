-- ============================================================================
-- Findora — Paging for the Matches tab and the admin report lists
-- Run this after 28_saved_searches.sql. Safe to re-run; changes no data.
--
-- 1. my_matches_page() — what the Matches tab (and a post's own "possible
--    matches" screen) now reads, instead of my_matches() which returned EVERY
--    match at once. It filters, orders and limits on the server:
--      p_section  'pending' (best score first) | 'decided' | 'confirmed' |
--                 'all' (newest first)
--      p_filter   'all' | 'image' | 'text' | 'both' | 'nearby' | 'time' — the
--                 Matches tab's chips. The thresholds below mirror
--                 kImageAgreesFrom / kTextAgreesFrom in
--                 lib/features/matches/data/match_model.dart; change both.
--      p_item_id  only matches involving this post (null = all of mine)
--      p_limit    at most this many rows (capped at 500)
--    It also returns the caller's own post's first photo, which the app used
--    to fetch with a second query, and leaves out people the caller has
--    blocked (previously hidden on the phone only, which would make a page
--    look short). Not security definer: row-level security applies as before.
-- 2. Partial indexes so the admin queues (open reports, newest first) stay
--    fast however many resolved reports pile up. No SQL is needed for the
--    admin paging itself — the app just asks for the newest N open reports.
-- ============================================================================

drop function if exists public.my_matches_page(text, text, uuid, integer);

create function public.my_matches_page(
  p_section text default 'all',
  p_filter text default 'all',
  p_item_id uuid default null,
  p_limit integer default 20
)
returns table (
  match_id uuid,
  my_item_id uuid,
  my_item_title text,
  matched_item_id uuid,
  matched_item_title text,
  matched_item_type public.item_type,
  matched_item_image_url text,
  matched_item_user_id uuid,
  similarity_score real,
  image_similarity real,
  text_similarity real,
  distance_meters real,
  time_proximity real,
  match_status text,
  created_at timestamptz,
  my_item_image_url text
)
language sql
stable
as $$
  select
    m.id,
    mine.id,
    mine.title,
    theirs.id,
    theirs.title,
    theirs.type,
    (
      select img.image_url from public.item_images img
      where img.item_id = theirs.id
      order by img.created_at
      limit 1
    ),
    theirs.user_id,
    m.similarity_score,
    m.image_similarity,
    m.text_similarity,
    m.distance_meters,
    m.time_proximity,
    m.status,
    m.created_at,
    (
      select img.image_url from public.item_images img
      where img.item_id = mine.id
      order by img.created_at
      limit 1
    )
  from public.matches m
  join public.items a on a.id = m.item_a_id
  join public.items b on b.id = m.item_b_id
  join public.items mine on mine.id = (case when a.user_id = auth.uid() then a.id else b.id end)
  join public.items theirs on theirs.id = (case when a.user_id = auth.uid() then b.id else a.id end)
  where (a.user_id = auth.uid() or b.user_id = auth.uid())
    and a.deleted_at is null
    and b.deleted_at is null
    and a.status <> 'resolved'
    and b.status <> 'resolved'
    and not exists (
      select 1 from public.user_blocks ub
      where ub.blocker_id = auth.uid() and ub.blocked_id = theirs.user_id
    )
    and (p_item_id is null or mine.id = p_item_id or theirs.id = p_item_id)
    and (
      case coalesce(p_section, 'all')
        when 'pending' then m.status = 'pending'
        when 'decided' then m.status <> 'pending'
        when 'confirmed' then m.status = 'confirmed'
        else true
      end
    )
    and (
      coalesce(p_filter, 'all') = 'all'
      or (p_filter = 'image'
          and coalesce(m.image_similarity >= 0.60::real, false)
          and not coalesce(m.text_similarity >= 0.50::real, false))
      or (p_filter = 'text'
          and coalesce(m.text_similarity >= 0.50::real, false)
          and not coalesce(m.image_similarity >= 0.60::real, false))
      or (p_filter = 'both'
          and coalesce(m.image_similarity >= 0.60::real, false)
          and coalesce(m.text_similarity >= 0.50::real, false))
      or (p_filter = 'nearby'
          and m.distance_meters is not null and m.distance_meters <= 5000)
      or (p_filter = 'time'
          and m.time_proximity is not null and m.time_proximity >= 0.5)
    )
  order by
    (case when p_section = 'pending' then m.similarity_score end) desc nulls last,
    m.created_at desc,
    m.id desc
  limit greatest(1, least(coalesce(p_limit, 20), 500));
$$;

revoke all on function public.my_matches_page(text, text, uuid, integer) from public, anon;
grant execute on function public.my_matches_page(text, text, uuid, integer) to authenticated;

-- ---- admin queues -----------------------------------------------------------
create index if not exists reports_open_idx
  on public.reports (created_at desc)
  where status = 'open';

create index if not exists user_reports_open_idx
  on public.user_reports (created_at desc)
  where status = 'open';
