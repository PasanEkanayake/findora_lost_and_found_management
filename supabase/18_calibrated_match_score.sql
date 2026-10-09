-- ============================================================================
-- Findora — Calibrated match scores
-- Run this after 17_harden_policies.sql. Safe to re-run.
--
-- THE PROBLEM
-- The match score was a weighted AVERAGE of whichever signals happened to be
-- present (image 0.40, text 0.25, location 0.20, time 0.15), re-normalised over
-- the present ones. Two flaws made it say "100% match" with little evidence:
--   1. A pair found through TEXT never had its photos compared (the photo
--      score only existed for pairs found through photos), so a lost phone and
--      a found phone with completely different photos simply had NO photo
--      score — and the average ignored the gap instead of treating it as
--      "the photos were never checked / didn't agree".
--   2. Identical one-word titles ("phone" / "phone") counted as a perfect text
--      match, even though that only says both posts name the same kind of
--      object, not that they describe the same one.
--
-- WHAT THIS CHANGES
--   * The photo signal is now ALWAYS computed from the two posts' current
--     photos whenever both have an analysed photo — best cosine similarity
--     over every photo pair, the same definition match_items() uses — even
--     when it is low. (Previously absent = "no information"; now low =
--     "photos disagree".)
--   * Text agreement is weighted by SPECIFICITY (text_specificity()): shared
--     informative words (a model, a colour, a brand) count in full; agreement
--     only on generic category words ("phone", "wallet", "keys"...) or no
--     shared words at all counts for 60%.
--   * When the photos disagree the score is pulled DOWN, smoothly: full effect
--     at/below (image threshold - 0.25), none at/above the image threshold.
--   * When there is no photo comparison available (a post has no analysed
--     photo) the score is CAPPED — 0.70 if the wording agrees strongly AND
--     specifically (specificity-weighted text >= 0.70), 0.50 otherwise — so text + nearness alone can never read as certain.
--   Net effect: "Strong" needs agreeing photos; the app shows tiers
--   (Strong >= 80%, Likely >= 55%, Possible below) instead of presenting the
--   number as a probability.
--
-- This changes only HOW SCORES ARE COMPUTED. Which pairs get proposed in the
-- first place (matching_threshold(), text_matching_threshold()) is unchanged,
-- no match is created, deleted, confirmed or dismissed, and notifications
-- still fire exactly when a new pair is found.
--
-- All the numbers (0.6, 0.85, 0.25, 0.55, 0.70, 0.50, the word list) are
-- starting points, not measured values — see "Tuning" at the end.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Words that name a KIND of thing or are filler: agreeing on only these says
-- little about whether two posts describe the SAME thing. Edit freely.
-- ----------------------------------------------------------------------------
create or replace function public.generic_match_words()
returns text[]
language sql
immutable
as $$
  select array[
    -- filler / stop words
    'the','and','for','with','was','were','has','have','had','this','that','from',
    'near','found','lost','item','items','thing','one','my','is','it','of','in',
    'on','at','to','an','are','you','your','me','its','not','but','can','who',
    'someone','somebody','please','contact','left','got','get',
    -- generic kinds of object
    'phone','phones','mobile','cell','cellphone','cellular','telephone','smartphone',
    'wallet','purse','bag','bags','backpack','handbag','keys','key','card','cards',
    'watch','laptop','tablet','bottle','umbrella','glasses','spectacles','charger',
    'earphones','earphone','earbuds','headphones','headphone','camera','book',
    'books','id','document','documents','bike','bicycle','helmet','jacket'
  ];
$$;

-- ----------------------------------------------------------------------------
-- text_specificity — how much weight the wording agreement between two posts
-- deserves: 1.0 when they share 2+ informative words, 0.85 for exactly one,
-- 0.60 for none (agreement only on generic words, or on meaning alone).
-- "Informative" = any word (of 2+ letters/digits) that isn't in
-- generic_match_words(): brands, models, colours, distinguishing marks.
-- Uses [[:alnum:]] so non-Latin scripts (Sinhala, Tamil) are tokenised too.
-- ----------------------------------------------------------------------------
create or replace function public.text_specificity(a_id uuid, b_id uuid)
returns real
language sql
stable
as $$
  with words as (
    select
      (select array_agg(distinct w)
         from regexp_split_to_table(lower(coalesce(a.title, '') || ' ' || coalesce(a.description, '')), '[^[:alnum:]]+') w
        where char_length(w) >= 2 and w <> all (public.generic_match_words())) as aw,
      (select array_agg(distinct w)
         from regexp_split_to_table(lower(coalesce(b.title, '') || ' ' || coalesce(b.description, '')), '[^[:alnum:]]+') w
        where char_length(w) >= 2 and w <> all (public.generic_match_words())) as bw
    from public.items a, public.items b
    where a.id = a_id and b.id = b_id
  ),
  shared as (
    select coalesce(cardinality(array(
      select unnest(aw) intersect select unnest(bw)
    )), 0) as k
    from words
  )
  select (case when k >= 2 then 1.0 when k = 1 then 0.85 else 0.60 end)::real
  from shared;
$$;

-- ----------------------------------------------------------------------------
-- calibrated_match_score — the number stored in matches.similarity_score.
-- (combined_match_score() is unchanged and still does the plain weighted
-- blend; this wraps it with the evidence rules described at the top.)
-- ----------------------------------------------------------------------------
create or replace function public.calibrated_match_score(
  image_sim real,
  text_sim real,
  specificity real,
  gps_sim real,
  time_sim real
)
returns real
language sql
immutable
as $$
  select case
    when w.base is null then null
    when image_sim is null then
      -- Nothing visual to compare: never better than "Likely".
      least(w.base, case when w.eff_text is not null and w.eff_text >= 0.70 then 0.70::real else 0.50::real end)
    else
      w.base * (
        0.55 + 0.45 * least(1.0, greatest(0.0,
          (image_sim - (public.matching_threshold() - 0.25)) / 0.25
        ))
      )
  end::real
  from (
    select
      eff.v as eff_text,
      public.combined_match_score(image_sim, eff.v, gps_sim, time_sim) as base
    from (select (text_sim * coalesce(specificity, 1.0::real))::real as v) eff
  ) w;
$$;

-- ----------------------------------------------------------------------------
-- pair_match_signals — every signal for one pair, computed fresh from the two
-- posts' CURRENT data, plus the calibrated score. The single source of truth
-- used by both upsert_match_score() (new/updated matches) and
-- refresh_matches_for_item() (edits and the backfill below).
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- upsert_match_score — same contract and same notification behaviour as the
-- version in 14_notifications.sql (record or enrich a pair; notify both owners
-- ONLY when a genuinely new row is created), but every signal now comes from
-- pair_match_signals(). The image/text numbers the caller passes are only used
-- as a fallback if the fresh computation has nothing (should not happen).
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
  s record;
  v_image real;
  v_text real;
  v_score real;
  existing_id uuid;
  v_new_id uuid;
begin
  select * into a from public.items where id = p_item_a;
  if not found then return; end if;
  select * into b from public.items where id = p_item_b;
  if not found then return; end if;

  select * into s from public.pair_match_signals(p_item_a, p_item_b);
  v_image := coalesce(s.image_sim, p_image_similarity);
  v_text := coalesce(s.text_sim, p_text_similarity);
  v_score := coalesce(
    public.calibrated_match_score(
      v_image, v_text, public.text_specificity(p_item_a, p_item_b), s.gps_sim, s.time_sim
    ),
    0
  );

  -- The unique constraint is on the ordered pair, so an existing row could be
  -- stored in either order — check both.
  select id into existing_id from public.matches
  where (item_a_id = p_item_a and item_b_id = p_item_b)
     or (item_a_id = p_item_b and item_b_id = p_item_a)
  limit 1;

  if existing_id is not null then
    update public.matches m
    set
      image_similarity = v_image,
      text_similarity = v_text,
      distance_meters = s.dist,
      time_proximity = s.time_sim,
      similarity_score = v_score
    where m.id = existing_id;
  else
    insert into public.matches (
      item_a_id, item_b_id, image_similarity, text_similarity,
      distance_meters, time_proximity, similarity_score
    ) values (
      p_item_a, p_item_b, v_image, v_text, s.dist, s.time_sim, v_score
    )
    on conflict (item_a_id, item_b_id) do nothing -- race safety only
    returning id into v_new_id;

    if v_new_id is not null then
      perform public.create_notification(
        a.user_id, 'new_match',
        'New match: "' || b.title || '"',
        'Compared with your "' || a.title || '".',
        a.id, v_new_id
      );
      perform public.create_notification(
        b.user_id, 'new_match',
        'New match: "' || a.title || '"',
        'Compared with your "' || b.title || '".',
        b.id, v_new_id
      );
    end if;
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- refresh_matches_for_item — from 15_refresh_matches_on_edit.sql, now built on
-- pair_match_signals() so it applies the same calibrated rules. Everything
-- else about it (triggers, scope, never creating/removing matches) is as before.
-- ----------------------------------------------------------------------------
create or replace function public.refresh_matches_for_item(p_item_id uuid default null)
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  touched integer;
begin
  update public.matches m
  set
    image_similarity = s.image_sim,
    text_similarity = s.text_sim,
    distance_meters = s.dist,
    time_proximity = s.time_sim,
    -- similarity_score is NOT NULL; keep the old value if nothing could be computed.
    similarity_score = coalesce(s.score, m.similarity_score)
  from public.matches m2
  cross join lateral public.pair_match_signals(m2.item_a_id, m2.item_b_id) s
  where m.id = m2.id
    and (p_item_id is null or m2.item_a_id = p_item_id or m2.item_b_id = p_item_id);

  get diagnostics touched = row_count;
  return touched;
end;
$$;

revoke all on function public.pair_match_signals(uuid, uuid) from public, anon, authenticated;
revoke all on function public.upsert_match_score(uuid, uuid, real, real) from public, anon, authenticated;
revoke all on function public.refresh_matches_for_item(uuid) from public, anon, authenticated;

-- Re-score every existing match with the new rules (only touches the score
-- columns; takes a moment on large tables, fine at this size).
select public.refresh_all_matches();

-- ============================================================================
-- Tuning — everything lives in this file's functions; change a number and
-- re-run the file (it re-scores all matches at the end).
--
--   * See what the new rules do to real pairs:
--       select i1.title, i2.title,
--              m.image_similarity, m.text_similarity, m.distance_meters,
--              m.similarity_score
--       from public.matches m
--       join public.items i1 on i1.id = m.item_a_id
--       join public.items i2 on i2.id = m.item_b_id
--       order by m.similarity_score desc;
--   * Strong should be pairs you'd personally call "same item"; if good pairs
--     sit at Likely, loosen the image window (0.25) or the 0.80 tier in the
--     app (match_model.dart); if bad pairs reach Strong, tighten them.
--   * Confirmations/dismissals are free labels: compare the scores of matches
--     people confirmed vs dismissed before moving any number.
-- ============================================================================
