-- ============================================================================
-- Findora — Upgrade: event time, text embeddings, and multimodal matching
-- Run this after 04_storage_setup.sql. Safe to re-run.
--
-- What this adds on top of the original image-only matching:
--   1. items.event_time — when the item was actually lost/found (separate
--      from created_at, which is just when the report was posted).
--   2. items.text_embedding — a 384-d sentence embedding of title +
--      description, produced by a Sentence-Transformers model
--      (all-MiniLM-L6-v2) running in ai_service/ (see that folder's
--      README). NLTK does the tokenization/stopword cleanup before the
--      text is embedded — see ai_service/text_pipeline.py.
--   3. GPS proximity scoring via PostGIS, and a combined_score that blends
--      image similarity (CNN embeddings, already existed), text similarity
--      (NLP embeddings, new), and GPS proximity (new) into one ranked
--      score — see "How multimodal matching works" in README.md.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- items.event_time — nullable on purpose: not everyone remembers/knows the
-- exact time, and the report is still useful without it. Kept alongside the
-- pre-existing (and until now, unused) `event_date` column rather than
-- replacing it, so nothing that already reads `event_date` breaks; the app
-- itself now only reads/writes `event_time`.
-- ----------------------------------------------------------------------------
alter table public.items add column if not exists event_time timestamptz;

-- ----------------------------------------------------------------------------
-- items.text_embedding — sentence-transformers' all-MiniLM-L6-v2 outputs
-- 384 dimensions. A plain ivfflat/hnsw index isn't added here the way
-- item_images.embedding has one: matching re-ranks a small candidate set
-- already narrowed down by the image ANN search (see
-- record_matches_for_image() below), so text similarity is computed
-- directly between specific pairs rather than searched over the whole
-- table — an index would add write overhead for a lookup pattern that
-- never happens.
-- ----------------------------------------------------------------------------
alter table public.items add column if not exists text_embedding vector(384);

-- ----------------------------------------------------------------------------
-- matches — score breakdown columns, additive to the existing
-- `similarity_score`. `similarity_score` now holds the *combined* score
-- (what the UI already sorts/labels by); the three new columns hold its
-- ingredients so the client can show "92% photo match, 3.4 km away" instead
-- of just one opaque number.
-- ----------------------------------------------------------------------------
alter table public.matches add column if not exists image_similarity real;
alter table public.matches add column if not exists text_similarity real;
alter table public.matches add column if not exists distance_meters real;

-- ----------------------------------------------------------------------------
-- gps_proximity_score — converts a distance in meters into a 0..1 score
-- via exponential decay, so it combines on the same scale as cosine
-- similarity. `decay_meters` is the distance at which the score drops to
-- ~37% (1/e) — 3000m by default, i.e. two reports 3km apart still score
-- meaningfully, but ones a few hundred meters apart score much higher.
-- Tune this per how tightly clustered your users' reports tend to be.
-- ----------------------------------------------------------------------------
create or replace function public.gps_proximity_score(
  point_a geography,
  point_b geography,
  decay_meters float default 3000
)
returns real
language sql
immutable
as $$
  select case
    when point_a is null or point_b is null then null
    else exp(-1 * st_distance(point_a, point_b) / decay_meters)::real
  end;
$$;

-- ----------------------------------------------------------------------------
-- combined_match_score — blends up to three 0..1 signals with weights
-- 0.5 image / 0.3 text / 0.2 GPS, re-normalized over whichever signals are
-- actually available (e.g. if neither item has a location, the 0.2 GPS
-- weight is redistributed proportionally across image+text rather than
-- just being dropped, so the combined score stays on a comparable 0..1
-- scale regardless of which items have text/location and which don't).
-- ----------------------------------------------------------------------------
create or replace function public.combined_match_score(
  image_sim real,
  text_sim real,
  gps_sim real
)
returns real
language sql
immutable
as $$
  select case when total_weight = 0 then null else (weighted_sum / total_weight)::real end
  from (
    select
      coalesce(image_sim, 0) * 0.5 + coalesce(text_sim, 0) * 0.3 + coalesce(gps_sim, 0) * 0.2
        as weighted_sum,
      (case when image_sim is null then 0 else 0.5 end)
        + (case when text_sim is null then 0 else 0.3 end)
        + (case when gps_sim is null then 0 else 0.2 end)
        as total_weight
  ) w;
$$;

-- ----------------------------------------------------------------------------
-- match_items — unchanged in spirit from the original (still the fast ANN
-- "recall" stage: find candidates whose *photos* look similar, using the
-- HNSW index on item_images.embedding, which only works for a plain vector
-- distance search like this one). Multimodal re-ranking happens as a
-- second step in record_matches_for_image() below, once we already have a
-- short candidate list — that's standard practice for combining an ANN
-- vector search with other signals: index search narrows millions of rows
-- to a handful in milliseconds, then the more expensive/composite scoring
-- only has to run over that handful.
-- ----------------------------------------------------------------------------
create or replace function public.match_items(
  query_embedding vector(1280),
  source_item_id uuid,
  match_category_id uuid default null,
  match_threshold float default 0.75,
  match_count int default 10
)
returns table (
  item_id uuid,
  image_id uuid,
  title text,
  similarity float
)
language sql
stable
as $$
  select
    i.id as item_id,
    img.id as image_id,
    i.title,
    1 - (img.embedding <=> query_embedding) as similarity
  from public.item_images img
  join public.items i on i.id = img.item_id
  where i.id <> source_item_id
    and i.user_id <> (select user_id from public.items where id = source_item_id)
    and i.type <> (select type from public.items where id = source_item_id)
    and i.status = 'open'
    and (match_category_id is null or i.category_id = match_category_id)
    and 1 - (img.embedding <=> query_embedding) >= match_threshold
  order by img.embedding <=> query_embedding
  limit match_count;
$$;

-- ----------------------------------------------------------------------------
-- record_matches_for_image — same trigger as before (fires after an
-- item_images insert that has an embedding), but now computes the full
-- multimodal score for each image-similarity candidate before writing it:
-- text similarity (via items.text_embedding, when both sides have one) and
-- GPS proximity (via items.location, when both sides have one), blended
-- with the image similarity from match_items() via combined_match_score().
-- `matches.similarity_score` stores that blended result — everywhere the
-- app already reads `similarity_score` (MatchesScreen, my_matches()) keeps
-- working unchanged, now with a more informed ranking.
-- ----------------------------------------------------------------------------
create or replace function public.record_matches_for_image()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  source_item public.items%rowtype;
begin
  if new.embedding is null then
    return new;
  end if;

  select * into source_item from public.items where id = new.item_id;

  insert into public.matches (
    item_a_id, item_b_id, similarity_score,
    image_similarity, text_similarity, distance_meters
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
      public.gps_proximity_score(source_item.location, c_item.location)
    ),
    candidate.similarity::real,
    case when source_item.text_embedding is not null and c_item.text_embedding is not null
      then (1 - (source_item.text_embedding <=> c_item.text_embedding))::real
      else null
    end,
    case when source_item.location is not null and c_item.location is not null
      then st_distance(source_item.location, c_item.location)::real
      else null
    end
  from public.match_items(
    new.embedding,
    source_item.id,
    source_item.category_id,
    0.75,
    5
  ) as candidate
  join public.items c_item on c_item.id = candidate.item_id
  on conflict (item_a_id, item_b_id) do nothing;

  return new;
end;
$$;

-- Trigger declaration itself is unchanged (already exists from
-- 02_functions_and_triggers.sql) — re-creating the function body above is
-- enough since triggers call the function by name, not by a frozen copy of
-- its body. Re-stated here anyway so this file is runnable standalone.
drop trigger if exists item_images_record_matches on public.item_images;
create trigger item_images_record_matches
  after insert on public.item_images
  for each row execute function public.record_matches_for_image();

-- ----------------------------------------------------------------------------
-- my_matches — now also returns the score breakdown, so the client can
-- show e.g. "92% photo · 78% text · 1.2 km away" instead of one number.
-- Explicit drop+create because this changes the function's return type,
-- which `create or replace` can't do.
-- ----------------------------------------------------------------------------
drop function if exists public.my_matches();

create function public.my_matches()
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
  match_status text,
  created_at timestamptz
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
    m.status,
    m.created_at
  from public.matches m
  join public.items a on a.id = m.item_a_id
  join public.items b on b.id = m.item_b_id
  join public.items mine on mine.id = (case when a.user_id = auth.uid() then a.id else b.id end)
  join public.items theirs on theirs.id = (case when a.user_id = auth.uid() then b.id else a.id end)
  where a.user_id = auth.uid() or b.user_id = auth.uid()
  order by m.created_at desc;
$$;

-- ----------------------------------------------------------------------------
-- rescore_matches_for_item — one-off helper (not trigger-driven) to refresh
-- text_similarity/distance_meters/similarity_score on a source item's
-- *existing* matches after its text_embedding is filled in asynchronously
-- (the client posts the item and uploads photos before the text-embedding
-- HTTP call to ai_service necessarily resolves — see
-- ItemsRepository.createItem in the Flutter app). Call this once that
-- embedding has been saved. Safe to call even if nothing changed.
-- ----------------------------------------------------------------------------
create or replace function public.rescore_matches_for_item(p_item_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update public.matches m
  set
    text_similarity = t.text_similarity,
    distance_meters = t.distance_meters,
    similarity_score = public.combined_match_score(m.image_similarity, t.text_similarity, t.gps_score)
  from (
    select
      m2.id as match_id,
      case
        when src.text_embedding is not null and other.text_embedding is not null
          then (1 - (src.text_embedding <=> other.text_embedding))::real
        else m2.text_similarity
      end as text_similarity,
      case
        when src.location is not null and other.location is not null
          then st_distance(src.location, other.location)::real
        else m2.distance_meters
      end as distance_meters,
      public.gps_proximity_score(src.location, other.location) as gps_score
    from public.matches m2
    join public.items src
      on src.id = (case when m2.item_a_id = p_item_id then m2.item_a_id else m2.item_b_id end)
    join public.items other
      on other.id = (case when m2.item_a_id = p_item_id then m2.item_b_id else m2.item_a_id end)
    where m2.item_a_id = p_item_id or m2.item_b_id = p_item_id
  ) t
  where m.id = t.match_id;
end;
$$;
