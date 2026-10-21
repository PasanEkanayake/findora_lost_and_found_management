-- ============================================================================
-- Findora — checks for 31_two_sided_confirmation.sql
-- Run in the Supabase SQL editor against a STAGING project after applying 31.
-- Read-only. NOT run by the author.
-- ============================================================================

-- 1. Both decision columns exist (expect 2 rows).
select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'matches'
  and column_name in ('item_a_decision', 'item_b_decision');

-- 2. Every confirmed match was grandfathered onto both sides (expect 0).
select count(*) as confirmed_but_not_mutual
from public.matches
where status = 'confirmed'
  and (item_a_decision is distinct from 'confirmed' or item_b_decision is distinct from 'confirmed');

-- 3. The invariant: status 'confirmed' only with BOTH sides confirmed (expect 0).
--    (Same query as 2 — keep it in your routine checks after the rollout.)

-- 4. No match is 'confirmed' while a side is 'dismissed' (expect 0).
select count(*) from public.matches
where status = 'confirmed'
  and (item_a_decision = 'dismissed' or item_b_decision = 'dismissed');

-- 5. decide_match now returns text; signed-out callers can't run it
--    (expect text, then false).
select pg_get_function_result('public.decide_match(uuid, text)'::regprocedure);
select has_function_privilege('anon', 'public.decide_match(uuid, text)', 'execute');

-- 6. Walk-through (two real accounts, on staging): A taps "This is it!" -> the
--    match is in A's "Waiting" section, in B's "Needs your input" with "The
--    other person says this is a match", B gets a 'match_waiting' alert, and
--    NEITHER can open the chat. B taps "This is it!" -> both see it under
--    "Already decided" with a Message button; A gets 'match_confirmed'.
