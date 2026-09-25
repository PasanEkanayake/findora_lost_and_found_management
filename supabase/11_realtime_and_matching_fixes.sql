-- ============================================================================
-- Findora — Upgrade: live chat (Realtime) + AI matching fixes
-- Run this after 10_open_matching_and_time.sql. Safe to re-run.
--
-- Two unrelated problems, fixed together because both are "the feature
-- silently does nothing until the database is configured for it":
--
--   1. LIVE CHAT. Both chat screens listen for new rows over Supabase
--      Realtime (`postgres_changes`), but Realtime only broadcasts changes
--      for tables that are members of the `supabase_realtime` publication —
--      and no earlier migration ever added `messages` or `contact_messages`
--      to it. The subscription "worked" (no error), it just never received
--      anything, so a sent message only appeared after the app was closed
--      and reopened (which does a fresh fetch).
--
--   2. AI MATCHING, database half. (The other half was in the Flutter app:
--      the on-device model's outputs were read in the wrong order, so photos
--      were uploaded with no embedding at all — see TfliteClassifier.) Here:
--        a. a photo that gets its embedding *later* (the app's "scan my
--           photos" catch-up) now triggers the match search too — before,
--           only a brand-new photo insert did;
--        b. owners are allowed to write that embedding onto their own
--           photo (there was no UPDATE policy on item_images at all);
--        c. the image-similarity cut-off moves from 0.75 to 0.60 and lives
--           in one tunable function, matching_threshold();
--        d. a matches row is no longer created twice for the same pair in
--           opposite directions.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Realtime: add the two chat tables to the publication.
--    `alter publication ... add table` errors if the table is already a
--    member, hence the existence check (that's what makes this re-runnable).
-- ----------------------------------------------------------------------------
do $$
declare
  t text;
  publishes_everything boolean;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;

  select puballtables into publishes_everything
  from pg_publication where pubname = 'supabase_realtime';

  if publishes_everything then
    raise notice 'supabase_realtime already publishes every table - nothing to add.';
  else
    foreach t in array array['messages', 'contact_messages'] loop
      if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = t
      ) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 2a. matching_threshold — the minimum image (cosine) similarity for two
--     photos to be proposed as a match at all. One place to tune.
--
--     Was a hardcoded 0.75 inside the trigger. MobileNetV2 embeddings are
--     non-negative (post-ReLU), so cosine similarity between two photos of
--     the *same kind* of object taken separately — say two different
--     phones on different backgrounds — typically lands around 0.6-0.8,
--     and 0.75 quietly rejected many of those. Identical or near-identical
--     photos score ~0.9+ either way. The blended score shown in the app
--     also mixes in text/GPS/time, and every match can be dismissed, so a
--     slightly permissive cut-off is the better failure mode.
--
--     To tune: run supabase/diagnostics_matching.sql query 3b to see the
--     real similarity of your own test pairs, then re-create this function
--     with a different number (and run `select public.rematch_all_images();`
--     to apply it to photos that are already in the database).
-- ----------------------------------------------------------------------------
create or replace function public.matching_threshold()
returns float
language sql
immutable
as $$
  select 0.60::float;
$$;

-- ----------------------------------------------------------------------------
-- 2b. Owners may update their own photos (needed to fill in `embedding`
--     after the fact). Without a policy, an UPDATE under RLS doesn't error —
--     it just silently matches zero rows, which is exactly the kind of
--     failure this migration exists to get rid of. The `with check` half
--     stops a photo being re-pointed at someone else's item.
-- ----------------------------------------------------------------------------
drop policy if exists "users can update images on their own items" on public.item_images;
create policy "users can update images on their own items"
  on public.item_images for update
  using (
    exists (
      select 1 from public.items
      where items.id = item_images.item_id and items.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.items
      where items.id = item_images.item_id and items.user_id = auth.uid()
    )
  );

-- ----------------------------------------------------------------------------
-- 2c. match_image — the whole "find candidates for this photo and record
--     them" step, as its own function so the insert trigger, the
--     update-embedding trigger and rematch_all_images() below all run
--     exactly the same logic instead of three copies of it.
--
--     Compared with the trigger body in 10_open_matching_and_time.sql:
--       - threshold comes from matching_threshold(), and it looks at up to
--         20 candidate photos instead of 5 (then keeps the best photo per
--         item, so one item with three photos can't crowd out the rest);
--       - skips items that are deleted or no longer 'open';
--       - skips a pair that already exists in the *opposite* direction.
--         `matches` is unique on (item_a_id, item_b_id) in that order, so
--         (A,B) and (B,A) are different rows to the constraint — without
--         this, re-embedding a photo could list the same pair twice.
--
--     security definer: the caller only has rights on their own rows, but
--     the match row involves someone else's item. Not callable by app
--     users — see the REVOKE below; it's only ever reached through the
--     triggers (which run as this function's owner) or from the SQL editor.
-- ----------------------------------------------------------------------------
create or replace function public.match_image(p_image_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  photo public.item_images%rowtype;
  source_item public.items%rowtype;
begin
  select * into photo from public.item_images where id = p_image_id;
  if not found or photo.embedding is null then
    return;
  end if;

  select * into source_item from public.items where id = photo.item_id;
  if not found or source_item.deleted_at is not null or source_item.status <> 'open' then
    return;
  end if;

  insert into public.matches (
    item_a_id, item_b_id, similarity_score,
    image_similarity, text_similarity, distance_meters, time_proximity
  )
  select
    source_item.id,
    candidate.item_id,
    public.combined_match_score(
      candidate.similarity::real,
      case when source_item.text_embedding is not null and c_item.text_embedding is not null
        then (1 - (source_item.text_embedding <=> c_item.text_embedding))::real
        else null
      end,
      public.gps_proximity_score(source_item.location, c_item.location),
      public.time_proximity_score(source_item.event_time, c_item.event_time)
    ),
    candidate.similarity::real,
    case when source_item.text_embedding is not null and c_item.text_embedding is not null
      then (1 - (source_item.text_embedding <=> c_item.text_embedding))::real
      else null
    end,
    case when source_item.location is not null and c_item.location is not null
      then st_distance(source_item.location, c_item.location)::real
      else null
    end,
    public.time_proximity_score(source_item.event_time, c_item.event_time)
  from (
    select distinct on (c.item_id) c.item_id, c.similarity
    from public.match_items(
      photo.embedding,
      source_item.id,
      null, -- category never restricts candidates (see 10_open_matching_and_time.sql)
      public.matching_threshold(),
      20
    ) as c
    order by c.item_id, c.similarity desc
  ) as candidate
  join public.items c_item on c_item.id = candidate.item_id
  where not exists (
    select 1 from public.matches existing
    where existing.item_a_id = candidate.item_id
      and existing.item_b_id = source_item.id
  )
  on conflict (item_a_id, item_b_id) do nothing;
end;
$$;

-- The trigger function keeps its old name (the existing insert trigger
-- points at it) but is now just a thin wrapper.
create or replace function public.record_matches_for_image()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  perform public.match_image(new.id);
  return new;
end;
$$;

-- Insert trigger: re-stated so this file is runnable standalone (same
-- definition as 05_multimodal_matching.sql).
drop trigger if exists item_images_record_matches on public.item_images;
create trigger item_images_record_matches
  after insert on public.item_images
  for each row execute function public.record_matches_for_image();

-- NEW — update trigger: fires when a photo that had NO embedding gets one
-- (the app's "scan my photos" catch-up for photos posted while on-device
-- AI wasn't working). Before this, only INSERTs ever ran the match search,
-- so back-filling an embedding onto an existing row could never produce a
-- match.
drop trigger if exists item_images_record_matches_on_embedding on public.item_images;
create trigger item_images_record_matches_on_embedding
  after update of embedding on public.item_images
  for each row
  when (old.embedding is null and new.embedding is not null)
  execute function public.record_matches_for_image();

-- ----------------------------------------------------------------------------
-- 2d. rematch_all_images — one-shot helper for the SQL editor: re-runs the
--     match search for every photo that has an embedding. Use it after
--     changing matching_threshold(), or after embeddings were filled in in
--     bulk. Safe to run any number of times: pairs that already exist are
--     skipped, never duplicated. Returns how many photos it processed.
--
--       select public.rematch_all_images();
-- ----------------------------------------------------------------------------
create or replace function public.rematch_all_images()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  r record;
  processed integer := 0;
begin
  for r in
    select img.id
    from public.item_images img
    join public.items i on i.id = img.item_id
    where img.embedding is not null
      and i.deleted_at is null
      and i.status = 'open'
  loop
    perform public.match_image(r.id);
    processed := processed + 1;
  end loop;
  return processed;
end;
$$;

-- Neither helper should be callable by app users through PostgREST's
-- /rpc endpoint. (Triggers and the SQL editor's postgres role are
-- unaffected: triggers run as the function owner.)
revoke all on function public.match_image(uuid) from public, anon, authenticated;
revoke all on function public.rematch_all_images() from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 2e. Housekeeping: 05_multimodal_matching.sql defined combined_match_score
--     with 3 parameters; 10_open_matching_and_time.sql then added a
--     4-parameter version (time proximity, default null) *alongside* it
--     instead of replacing it, because the parameter lists differ. Both
--     existing together makes any 3-argument call ambiguous ("function is
--     not unique"). Nothing calls the 3-parameter one any more, and the
--     4-parameter version already accepts 3-argument calls via its default.
-- ----------------------------------------------------------------------------
drop function if exists public.combined_match_score(real, real, real);

-- ============================================================================
-- Verify (optional) — run these one at a time after the above:
--
--   -- both chat tables should be listed:
--   select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime' and schemaname = 'public';
--
--   -- should return 0.6:
--   select public.matching_threshold();
--
--   -- both triggers should be listed:
--   select tgname from pg_trigger
--   where tgrelid = 'public.item_images'::regclass and not tgisinternal;
-- ============================================================================
