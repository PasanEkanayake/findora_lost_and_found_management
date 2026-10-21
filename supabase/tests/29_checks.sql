-- ============================================================================
-- Findora — checks for 29_matches_paging.sql
-- Run in the Supabase SQL editor against a STAGING project after applying 29.
-- Read-only. NOT run by the author.
-- ============================================================================

-- 1. The function and both indexes exist (expect 1, 2).
select count(*) as functions
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'my_matches_page';

select count(*) as indexes
from pg_indexes
where schemaname = 'public' and indexname in ('reports_open_idx', 'user_reports_open_idx');

-- 2. Signed-out callers can't run it (expect false).
select has_function_privilege('anon', 'public.my_matches_page(text, text, uuid, integer)', 'execute');

-- 3. As a real user (replace the uuid), the limit is honoured and 'pending'
--    comes best-score first.
-- select set_config('request.jwt.claims', '{"sub":"<user-uuid>","role":"authenticated"}', true);
-- set local role authenticated;
-- select similarity_score, match_status from public.my_matches_page('pending', 'all', null, 3);
