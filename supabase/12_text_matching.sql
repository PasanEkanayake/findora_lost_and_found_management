-- ============================================================================
-- Findora — Upgrade: match by title/description, not just photos
-- Run this after 11_realtime_and_matching_fixes.sql. Safe to re-run.
--
-- Until now, two items could only ever be matched by comparing their
-- photos (see match_image() in 11_realtime_and_matching_fixes.sql) — a
-- post with no photo, or one whose photo failed on-device analysis, could
-- never be matched at all, no matter how obviously its title and
-- description described the same object as another post.
--
-- This file adds a second, independent way for two items to be matched:
-- comparing their title and description text. It runs alongside photo
-- matching, not instead of it — a pair can be found by either signal, and
-- once found, the other signal (if it later becomes available) enriches
-- the same row rather than being ignored or creating a duplicate. See
-- upsert_match_score() below, which both this file's text matching and
-- match_image() (redefined here to use it) now share.
--
-- Text comparison itself uses whichever of these two "how similar is this
-- text" methods is available for a given pair, decided fresh every time —
-- see text_similarity_between():
--   - if AI_SERVICE_URL is configured and both items were posted (or
--     edited) while it was awake, their sentence-embedding vectors
--     (items.text_embedding, from 05_multimodal_matching.sql) give a
--     *meaning*-based similarity — "wallet" and "purse" score highly even
--     though they don't share letters;
--   - otherwise, pg_trgm's word/substring similarity on the raw title and
--     description text — no external service, no setup, always available,
--     but literal: only helps when the words genuinely overlap.
-- ============================================================================

-- pg_trgm powers the always-available text-similarity fallback below.
create extension if not exists pg_trgm;

-- ----------------------------------------------------------------------------
-- text_matching_threshold — the minimum text similarity for two items to be
-- proposed as a match on text alone. Separate from matching_threshold()
-- (the photo cut-off, 11_realtime_and_matching_fixes.sql) since the two
-- scores aren't on comparable scales.
--
-- 0.30 is a starting point, not a measured value — there's no way to
-- calibrate it against real posts from here. Query 3d in
-- diagnostics_matching.sql shows the actual text similarity of every
-- cross-account item pair with no editing needed; use it to see whether
-- 0.30 is letting through unrelated items or missing obviously-the-same
-- ones, then redefine this function with a different number (re-running
-- this file is enough — it doesn't need rematch_all_text() run again for
-- the number to take effect on *new* posts, only to re-check old ones).
-- ----------------------------------------------------------------------------
create or replace function public.text_matching_threshold()
returns float
language sql
immutable
as $$
  select 0.30::float;
$$;

-- ----------------------------------------------------------------------------
-- text_similarity_between — "how similar are these two items' text",
-- 0 (unrelated) to 1 (same wording), or null if there's truly nothing to
-- compare (unreachable in practice: title is required on every item).
--
-- Title counts for more than description (0.7 / 0.3): the title is short
-- and deliberate ("Redmi phone"), while the description is free text whose
-- *wording* varies a lot even when it describes the same object ("found
-- near the gate" vs "left it on a bench") — weighting it equally would let
-- unrelated items with similarly-flavoured descriptions (e.g. both
-- mentioning the same neighbourhood) outweigh a strong title match.
-- Skipped entirely (falls back to title-only) whenever either item has no
-- description, rather than averaging in a comparison against an empty
-- string — pg_trgm's similarity() of an empty string is always low, which
-- would incorrectly drag the score down just because someone didn't write
-- a description.
-- ----------------------------------------------------------------------------
create or replace function public.text_similarity_between(a_id uuid, b_id uuid)
returns real
language sql
stable
as $$
  select case
    when a.text_embedding is not null and b.text_embedding is not null
      then (1 - (a.text_embedding <=> b.text_embedding))::real
    when coalesce(a.description, '') = '' or coalesce(b.description, '') = ''
      then similarity(lower(a.title), lower(b.title))::real
    else (
      0.7 * similarity(lower(a.title), lower(b.title))
        + 0.3 * similarity(lower(a.description), lower(b.description))
    )::real
  end
  from public.items a, public.items b
  where a.id = a_id and b.id = b_id;
$$;

-- ----------------------------------------------------------------------------
-- upsert_match_score — records (or enriches) the match between two items,
-- however it was found. Shared by match_image() (redefined below to call
-- this instead of its own INSERT) and match_item_by_text() so that whoever
-- discovers a pair first, the other signal updates the same row later
-- instead of being silently dropped by "on conflict do nothing" or
-- creating a second, reversed-direction row for the same pair.
--
-- p_image_similarity / p_text_similarity: pass null for "this call has
-- nothing to say about this signal" (e.g. the text-matching path never
-- computes an image similarity) — an existing value for that signal is
-- left as it was, via coalesce(new, existing). GPS and time proximity are
-- always recomputed from the two items' current data, since both callers
-- are able to compute them equally well and doing so here (once) is
-- simpler than every caller doing it themselves.
--
-- security definer: needed because whichever side calls this only has
-- update rights on their own item's data, but this writes a row that
-- names someone else's item too. Not reachable from the app directly —
-- see the REVOKE at the end of this file.
-- ----------------------------------------------------------------------------
create or replace function public.upsert_match_score(
  p_item_a uuid,
  p_item_b uuid,
  p_image_similarity real,
  p_text_similarity real
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  a public.items%rowtype;
  b public.items%rowtype;
  gps_sim real;
  time_sim real;
  dist real;
  existing_id uuid;
begin
  select * into a from public.items where id = p_item_a;
  if not found then return; end if;
  select * into b from public.items where id = p_item_b;
  if not found then return; end if;

  gps_sim := public.gps_proximity_score(a.location, b.location);
  time_sim := public.time_proximity_score(a.event_time, b.event_time);
  dist := case when a.location is not null and b.location is not null
    then st_distance(a.location, b.location)::real
    else null
  end;

  -- The unique constraint is on the ordered pair (item_a_id, item_b_id),
  -- so an existing row for these two items could be stored in either
  -- order — check both before deciding to insert.
  select id into existing_id from public.matches
  where (item_a_id = p_item_a and item_b_id = p_item_b)
     or (item_a_id = p_item_b and item_b_id = p_item_a)
  limit 1;

  if existing_id is not null then
    update public.matches m
    set
      image_similarity = coalesce(p_image_similarity, m.image_similarity),
      text_similarity = coalesce(p_text_similarity, m.text_similarity),
      distance_meters = dist,
      time_proximity = time_sim,
      similarity_score = public.combined_match_score(
        coalesce(p_image_similarity, m.image_similarity),
        coalesce(p_text_similarity, m.text_similarity),
        gps_sim,
        time_sim
      )
    where m.id = existing_id;
  else
    insert into public.matches (
      item_a_id, item_b_id, image_similarity, text_similarity,
      distance_meters, time_proximity, similarity_score
    ) values (
      p_item_a, p_item_b, p_image_similarity, p_text_similarity,
      dist, time_sim,
      public.combined_match_score(p_image_similarity, p_text_similarity, gps_sim, time_sim)
    )
    on conflict (item_a_id, item_b_id) do nothing; -- race safety only
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- match_image — redefined from 11_realtime_and_matching_fixes.sql to call
-- upsert_match_score() per candidate instead of a single set-based INSERT.
-- Behaviourally the same for anyone who only ever posts with photos; the
-- difference only shows up for a pair that text-matching already found
-- (no photo comparison yet) — this version enriches that row with the new
-- image similarity instead of leaving it untouched.
-- ----------------------------------------------------------------------------
create or replace function public.match_image(p_image_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  photo public.item_images%rowtype;
  source_item public.items%rowtype;
  candidate record;
begin
  select * into photo from public.item_images where id = p_image_id;
  if not found or photo.embedding is null then
    return;
  end if;

  select * into source_item from public.items where id = photo.item_id;
  if not found or source_item.deleted_at is not null or source_item.status <> 'open' then
    return;
  end if;

  for candidate in
    select distinct on (c.item_id) c.item_id, c.similarity
    from public.match_items(
      photo.embedding,
      source_item.id,
      null, -- category never restricts candidates (see 10_open_matching_and_time.sql)
      public.matching_threshold(),
      20
    ) as c
    order by c.item_id, c.similarity desc
  loop
    perform public.upsert_match_score(
      source_item.id,
      candidate.item_id,
      candidate.similarity::real,
      public.text_similarity_between(source_item.id, candidate.item_id)
    );
  end loop;
end;
$$;

-- ----------------------------------------------------------------------------
-- match_items_by_text — the text-matching equivalent of match_items(): one
-- item's id in, a list of opposite-type, different-owner, open candidate
-- items out, ordered by text similarity, best first.
-- ----------------------------------------------------------------------------
create or replace function public.match_items_by_text(
  source_item_id uuid,
  match_threshold float default null,
  match_count int default 20
)
returns table (item_id uuid, similarity real)
language plpgsql
stable
as $$
declare
  source public.items%rowtype;
  threshold float;
begin
  select * into source from public.items where id = source_item_id;
  if not found then
    return;
  end if;
  threshold := coalesce(match_threshold, public.text_matching_threshold());

  return query
  select i.id, public.text_similarity_between(source_item_id, i.id) as similarity
  from public.items i
  where i.id <> source_item_id
    and i.user_id <> source.user_id
    and i.type <> source.type
    and i.status = 'open'
    and i.deleted_at is null
    and public.text_similarity_between(source_item_id, i.id) >= threshold
  order by similarity desc
  limit match_count;
end;
$$;

-- ----------------------------------------------------------------------------
-- match_item_by_text — the text-matching equivalent of match_image(): find
-- this item's text-similar candidates and record/enrich a match for each.
-- Unlike match_image, this needs no photo to run at all — it only reads
-- the item's own title/description, so it works the moment an item (with
-- or without photos) is posted, and again whenever its title or
-- description changes (see the trigger below).
-- ----------------------------------------------------------------------------
create or replace function public.match_item_by_text(p_item_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  source_item public.items%rowtype;
  candidate record;
begin
  select * into source_item from public.items where id = p_item_id;
  if not found or source_item.deleted_at is not null or source_item.status <> 'open' then
    return;
  end if;

  for candidate in
    select item_id, similarity
    from public.match_items_by_text(source_item.id, public.text_matching_threshold(), 20)
  loop
    perform public.upsert_match_score(
      source_item.id,
      candidate.item_id,
      null, -- this path has no photo comparison to offer
      candidate.similarity
    );
  end loop;
end;
$$;

-- ----------------------------------------------------------------------------
-- record_text_matches_for_item — trigger wrapper, same shape as
-- record_matches_for_image(). Guards status/deleted_at itself (rather than
-- relying only on match_item_by_text's own guard) so the WHEN clauses
-- below stay simple.
-- ----------------------------------------------------------------------------
create or replace function public.record_text_matches_for_item()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.deleted_at is null and new.status = 'open' then
    perform public.match_item_by_text(new.id);
  end if;
  return new;
end;
$$;

-- New item posted: title is required on every item (description is not),
-- so there's always something to compare, with or without a photo.
drop trigger if exists items_record_text_matches_insert on public.items;
create trigger items_record_text_matches_insert
  after insert on public.items
  for each row execute function public.record_text_matches_for_item();

-- Title or description changed (Edit post, ItemsRepository.updateItem).
-- "update of title, description" limits this to statements that touch
-- either column at all; the WHEN clause further limits it to statements
-- that actually *changed* one of them, since the app's update always sends
-- both columns whether or not their values differ.
drop trigger if exists items_record_text_matches_update on public.items;
create trigger items_record_text_matches_update
  after update of title, description on public.items
  for each row
  when (old.title is distinct from new.title or old.description is distinct from new.description)
  execute function public.record_text_matches_for_item();

-- ----------------------------------------------------------------------------
-- rematch_all_text — one-shot helper for the SQL editor, the text-matching
-- equivalent of rematch_all_images(): re-runs text matching for every open
-- item. Use this once, after running this migration, to catch up every
-- item posted before text matching existed (the triggers above only fire
-- for items posted or edited *after* this point). Safe to run any number
-- of times.
--
--   select public.rematch_all_text();
-- ----------------------------------------------------------------------------
create or replace function public.rematch_all_text()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  r record;
  processed integer := 0;
begin
  for r in
    select id from public.items
    where deleted_at is null and status = 'open'
  loop
    perform public.match_item_by_text(r.id);
    processed := processed + 1;
  end loop;
  return processed;
end;
$$;

-- Same reasoning as 11_realtime_and_matching_fixes.sql's REVOKEs: these are
-- internal building blocks, reached through triggers or the SQL editor,
-- never directly by app users through PostgREST's /rpc endpoint.
revoke all on function public.upsert_match_score(uuid, uuid, real, real)
  from public, anon, authenticated;
revoke all on function public.match_item_by_text(uuid) from public, anon, authenticated;
revoke all on function public.rematch_all_text() from public, anon, authenticated;

-- ============================================================================
-- Verify (optional) — run these one at a time after the above:
--
--   -- should return 0.3:
--   select public.text_matching_threshold();
--
--   -- both triggers should be listed:
--   select tgname from pg_trigger
--   where tgrelid = 'public.items'::regclass and not tgisinternal;
--
--   -- catch up every item posted before this migration:
--   select public.rematch_all_text();
-- ============================================================================
