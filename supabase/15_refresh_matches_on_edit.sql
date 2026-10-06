-- ============================================================================
-- Findora — Fix: editing a post now refreshes its existing matches
-- Run this after 14_notifications.sql. Safe to re-run.
--
-- THE BUG
-- A match row stores a snapshot of how similar two posts were when the pair
-- was found: image_similarity, text_similarity, distance_meters,
-- time_proximity, and the combined similarity_score built from them. Nothing
-- ever refreshed that snapshot when a post was edited:
--   - location / event time: no trigger at all -> the "9 m" on a match card
--     stayed "9 m" after the post was moved somewhere else;
--   - title / description: items_record_text_matches_update re-ran, but only
--     for pairs still ABOVE the text threshold (pairs that had become less
--     similar kept their old text score), and the app never refreshed the
--     post's text embedding on edit, so the "meaning" comparison kept using
--     the OLD wording;
--   - photos: removing a photo left the image score it had produced, and a
--     replaced photo only ever overwrote the score for pairs that still
--     cleared the image threshold.
--
-- THE FIX
-- refresh_matches_for_item() recomputes ALL four signals from the two posts'
-- CURRENT data, and triggers call it whenever something a signal depends on
-- changes. It rewrites scores only — it never creates, deletes, confirms or
-- dismisses a match, so a pair you've already confirmed or chatted about is
-- never pulled out from under you.
--
-- AFTER RUNNING THIS FILE, run once to correct rows that went stale before:
--
--   select public.refresh_all_matches();
-- ============================================================================

-- ----------------------------------------------------------------------------
-- refresh_matches_for_item — recompute the score snapshot for every match that
-- involves p_item_id, or for every match at all when p_item_id is null.
-- Returns how many rows it looked at.
--
--   image_similarity: the best cosine similarity between ANY photo of one post
--     and ANY photo of the other — the same definition match_items() uses when
--     it first finds a pair. Null when either side currently has no analysed
--     photo (e.g. its only photo was removed).
--   text_similarity: text_similarity_between() — semantic when both posts
--     have a text embedding, otherwise pg_trgm on title/description.
--   distance_meters / time_proximity: from the posts' current location and
--     event time; null when either side has none.
-- ----------------------------------------------------------------------------
create or replace function public.refresh_matches_for_item(p_item_id uuid default null)
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  touched integer;
begin
  with fresh as (
    select
      m.id as match_id,
      (
        select max(1 - (ia.embedding <=> ib.embedding))::real
        from public.item_images ia
        join public.item_images ib on ib.item_id = m.item_b_id
        where ia.item_id = m.item_a_id
          and ia.embedding is not null
          and ib.embedding is not null
      ) as image_sim,
      public.text_similarity_between(m.item_a_id, m.item_b_id) as text_sim,
      public.gps_proximity_score(a.location, b.location) as gps_sim,
      public.time_proximity_score(a.event_time, b.event_time) as time_sim,
      case when a.location is not null and b.location is not null
        then st_distance(a.location, b.location)::real
        else null
      end as dist
    from public.matches m
    join public.items a on a.id = m.item_a_id
    join public.items b on b.id = m.item_b_id
    where p_item_id is null or m.item_a_id = p_item_id or m.item_b_id = p_item_id
  )
  update public.matches m
  set
    image_similarity = f.image_sim,
    text_similarity = f.text_sim,
    distance_meters = f.dist,
    time_proximity = f.time_sim,
    -- similarity_score is NOT NULL; combined_match_score is only null when
    -- every signal is null, in which case keep what was there.
    similarity_score = coalesce(
      public.combined_match_score(f.image_sim, f.text_sim, f.gps_sim, f.time_sim),
      m.similarity_score
    )
  from fresh f
  where m.id = f.match_id;

  get diagnostics touched = row_count;
  return touched;
end;
$$;

-- One-shot for the SQL editor: fix every match row that went stale before
-- this migration. Safe to run any number of times.
create or replace function public.refresh_all_matches()
returns integer
language sql
security definer set search_path = public
as $$
  select public.refresh_matches_for_item(null);
$$;

-- ----------------------------------------------------------------------------
-- Trigger: a post's text, text embedding, location or event time changed.
-- "update of" + "when" so it only runs for edits that actually changed one of
-- them (the app's edit form always sends every column, changed or not).
--
-- Named so it sorts AFTER items_record_text_matches_update (Postgres fires
-- same-event triggers alphabetically): that one may create NEW text matches,
-- this one then refreshes every match, new ones included.
-- ----------------------------------------------------------------------------
create or replace function public.refresh_matches_after_item_edit()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.deleted_at is null then
    perform public.refresh_matches_for_item(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists items_refresh_matches_on_edit on public.items;
create trigger items_refresh_matches_on_edit
  after update of title, description, text_embedding, location, event_time on public.items
  for each row
  when (
    old.title is distinct from new.title
    or old.description is distinct from new.description
    or old.text_embedding is distinct from new.text_embedding
    or old.location::text is distinct from new.location::text
    or old.event_time is distinct from new.event_time
  )
  execute function public.refresh_matches_after_item_edit();

-- ----------------------------------------------------------------------------
-- Trigger: a post's photos changed (added, analysed, or removed).
-- Sorts after item_images_record_matches (which finds NEW matches for an
-- added photo) so the refresh sees them too. A removed photo can no longer
-- vouch for the image score it produced, so its pairs are re-scored without it.
-- ----------------------------------------------------------------------------
create or replace function public.refresh_matches_after_image_change()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_matches_for_item(old.item_id);
    return old;
  end if;
  perform public.refresh_matches_for_item(new.item_id);
  return new;
end;
$$;

drop trigger if exists item_images_refresh_matches_insert on public.item_images;
create trigger item_images_refresh_matches_insert
  after insert on public.item_images
  for each row
  execute function public.refresh_matches_after_image_change();

drop trigger if exists item_images_refresh_matches_embedding on public.item_images;
create trigger item_images_refresh_matches_embedding
  after update of embedding on public.item_images
  for each row
  when (old.embedding is distinct from new.embedding)
  execute function public.refresh_matches_after_image_change();

drop trigger if exists item_images_refresh_matches_delete on public.item_images;
create trigger item_images_refresh_matches_delete
  after delete on public.item_images
  for each row
  execute function public.refresh_matches_after_image_change();

-- Internal building blocks, like the other matching helpers: reached through
-- triggers or the SQL editor, never directly through PostgREST's /rpc.
revoke all on function public.refresh_matches_for_item(uuid) from public, anon, authenticated;
revoke all on function public.refresh_all_matches() from public, anon, authenticated;

-- ============================================================================
-- Verify (optional) — run one at a time:
--
--   -- all five new triggers should be listed:
--   select tgname from pg_trigger
--   where tgname like '%refresh_matches%' and not tgisinternal;
--
--   -- fix rows that went stale before this migration:
--   select public.refresh_all_matches();
-- ============================================================================
