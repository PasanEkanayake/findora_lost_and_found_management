-- ============================================================================
-- Findora — Matching: time has a direction
-- Run this after 22_limits_and_housekeeping.sql. Safe to re-run.
--
-- The time signal only measured how far apart the "lost" and "found" times
-- were, in either direction. Something cannot be FOUND before it was LOST, so a
-- found post dated days before a lost one is, if anything, evidence AGAINST a
-- match (usually a wrong date, sometimes two different items) — yet it scored
-- as well as one dated just after.
--
-- Change: when both posts have a time and the found one is more than 6 hours
-- earlier than the lost one, the time signal is multiplied by 0.25. Nothing
-- else about scoring changes (see 18_calibrated_match_score.sql), no match is
-- created or removed, and every existing match is re-scored at the end.
-- The 6 hours of tolerance and the 0.25 factor are starting points: change them
-- below and re-run this file.
-- ============================================================================

create or replace function public.pair_match_signals(a_id uuid, b_id uuid)
returns table (
  image_sim real,
  text_sim real,
  gps_sim real,
  time_sim real,
  dist real,
  score real
)
language plpgsql
stable
security definer set search_path = public
as $$
declare
  a public.items%rowtype;
  b public.items%rowtype;
  lost_time timestamptz;
  found_time timestamptz;
begin
  select * into a from public.items where id = a_id;
  if not found then return; end if;
  select * into b from public.items where id = b_id;
  if not found then return; end if;

  image_sim := (
    select max(1 - (ia.embedding <=> ib.embedding))::real
    from public.item_images ia
    join public.item_images ib on ib.item_id = b_id
    where ia.item_id = a_id and ia.embedding is not null and ib.embedding is not null
  );
  text_sim := public.text_similarity_between(a_id, b_id);
  gps_sim := public.gps_proximity_score(a.location, b.location);
  time_sim := public.time_proximity_score(a.event_time, b.event_time);

  -- DIRECTION: something can't be found before it was lost. time_proximity_score
  -- only measures the GAP between the two times, so a "found" dated days
  -- BEFORE the "lost" looked as good as one dated just after. When both times
  -- are known and the found one precedes the lost one by more than a tolerance
  -- (people recall times loosely — "yesterday evening"), the time signal is
  -- cut to a quarter: such a pair is possible (a wrong date) but suspicious.
  if a.type = 'lost' and b.type = 'found' then
    lost_time := a.event_time; found_time := b.event_time;
  elsif a.type = 'found' and b.type = 'lost' then
    lost_time := b.event_time; found_time := a.event_time;
  end if;
  if time_sim is not null
     and lost_time is not null and found_time is not null
     and found_time < lost_time - interval '6 hours' then
    time_sim := time_sim * 0.25;
  end if;
  dist := case when a.location is not null and b.location is not null
    then st_distance(a.location, b.location)::real
    else null
  end;
  score := public.calibrated_match_score(
    image_sim, text_sim, public.text_specificity(a_id, b_id), gps_sim, time_sim
  );
  return next;
end;
$$;

revoke all on function public.pair_match_signals(uuid, uuid) from public, anon, authenticated;

-- Re-score existing matches with the directional time signal.
select public.refresh_all_matches();
