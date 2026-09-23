-- ============================================================================
-- Findora — Upgrade: category no longer gates matching; add time proximity
-- Run this after 09_account_deletion.sql.
--
-- Two changes:
--   1. Matching used to only compare items within the same category — a
--      lost item and a found item never got compared at all if the
--      on-device model (or the person posting) picked different
--      categories for them, even if the photos were genuinely the same
--      object. Category is dropped as a hard requirement: image, text,
--      GPS, and now time proximity all still factor into the score
--      exactly as before, category just no longer excludes a candidate
--      from being scored at all.
--   2. Adds event_time proximity as a fourth scoring signal, alongside
--      image/text/GPS — items reported lost/found close together in time
--      are more likely to be the same handoff than ones weeks apart.
-- ============================================================================

alter table public.matches add column if not exists time_proximity real;

-- ----------------------------------------------------------------------------
-- time_proximity_score — same exponential-decay shape as
-- gps_proximity_score (05_multimodal_matching.sql), over hours instead of
-- meters. decay_hours=72 (3 days): two reports whose event_time is 3 days
-- apart still score ~37%, ones within a few hours score much higher.
-- Null whenever either item never had an event_time set — not everyone
-- fills that in, and combined_match_score already knows how to
-- renormalize around a missing signal rather than penalize for it.
-- ----------------------------------------------------------------------------
create or replace function public.time_proximity_score(
  time_a timestamptz,
  time_b timestamptz,
  decay_hours float default 72
)
returns real
language sql
immutable
as $$
  select case
    when time_a is null or time_b is null then null
    else exp(-1 * abs(extract(epoch from (time_a - time_b)) / 3600.0) / decay_hours)::real
  end;
$$;

-- ----------------------------------------------------------------------------
-- combined_match_score — now blends four signals instead of three:
-- 0.4 image / 0.25 text / 0.2 GPS / 0.15 time, re-normalized over
-- whichever are actually available for a given pair (same renormalization
-- reasoning as before — a pair missing GPS and time entirely still gets a
-- combined score on the same 0..1 scale, just derived from image+text
-- alone). Image's weight drops from 0.5 to 0.4 to make room for time
-- rather than shrinking everything else proportionally, since image
-- similarity is still the most reliable single signal (it's also the
-- mandatory recall-stage filter every candidate already passed — see
-- match_items() — so it's never absent the way text/GPS/time can be).
-- ----------------------------------------------------------------------------
create or replace function public.combined_match_score(
  image_sim real,
  text_sim real,
  gps_sim real,
  time_sim real default null
)
returns real
language sql
immutable
as $$
  select case when total_weight = 0 then null else (weighted_sum / total_weight)::real end
  from (
    select
      coalesce(image_sim, 0) * 0.4 + coalesce(text_sim, 0) * 0.25
        + coalesce(gps_sim, 0) * 0.2 + coalesce(time_sim, 0) * 0.15
        as weighted_sum,
      (case when image_sim is null then 0 else 0.4 end)
        + (case when text_sim is null then 0 else 0.25 end)
        + (case when gps_sim is null then 0 else 0.2 end)
        + (case when time_sim is null then 0 else 0.15 end)
        as total_weight
  ) w;
$$;

-- ----------------------------------------------------------------------------
-- record_matches_for_image — same trigger, two changes from the
-- 05_multimodal_matching.sql version: passes null instead of
-- source_item.category_id to match_items() (see this file's header), and
-- computes/stores time_proximity alongside the existing three signals.
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
  from public.match_items(
    new.embedding,
    source_item.id,
    null, -- category no longer restricts candidates, see file header
    0.75,
    5
  ) as candidate
  join public.items c_item on c_item.id = candidate.item_id
  on conflict (item_a_id, item_b_id) do nothing;

  return new;
end;
$$;

-- ----------------------------------------------------------------------------
-- my_matches — now also returns time_proximity, alongside the existing
-- score breakdown. Explicit drop+create because this changes the
-- function's return type, which `create or replace` can't do.
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
  time_proximity real,
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
    m.time_proximity,
    m.status,
    m.created_at
  from public.matches m
  join public.items a on a.id = m.item_a_id
  join public.items b on b.id = m.item_b_id
  join public.items mine on mine.id = (case when a.user_id = auth.uid() then a.id else b.id end)
  join public.items theirs on theirs.id = (case when a.user_id = auth.uid() then b.id else a.id end)
  where (a.user_id = auth.uid() or b.user_id = auth.uid())
    and a.deleted_at is null
    and b.deleted_at is null
  order by m.created_at desc;
$$;

-- ----------------------------------------------------------------------------
-- rescore_matches_for_item — same helper as 05_multimodal_matching.sql,
-- updated to also refresh time_proximity for consistency (less likely to
-- matter in practice than the text_embedding case this function was
-- originally built for, since event_time is set at posting time rather
-- than arriving asynchronously — included anyway so this function stays a
-- complete "recompute everything for this item's matches" operation).
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
    time_proximity = t.time_score,
    similarity_score = public.combined_match_score(
      m.image_similarity, t.text_similarity, t.gps_score, t.time_score
    )
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
      public.gps_proximity_score(src.location, other.location) as gps_score,
      public.time_proximity_score(src.event_time, other.event_time) as time_score
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
