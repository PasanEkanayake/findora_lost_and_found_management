-- ============================================================================
-- Findora — checks for 32_moderation.sql
-- Run in the Supabase SQL editor against a STAGING project after applying 32.
-- Read-only except where marked. NOT run by the author.
-- ============================================================================

-- 1. Objects exist (expect 2 columns, 2 tables, 3 triggers on reports/items path).
select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'items'
  and column_name in ('moderation_state', 'moderation_at');
select table_name from information_schema.tables
where table_schema = 'public' and table_name in ('moderation_log', 'appeals');
select tgname from pg_trigger
where tgname in ('reports_auto_hide', 'reports_log_handled', 'user_reports_log_handled',
                 'moderation_log_no_change') and not tgisinternal;

-- 2. The thresholds (expect 3 and 2 days).
select public.auto_hide_report_threshold(), public.auto_hide_min_reporter_age();

-- 3. Signed-out callers can't run the moderation functions (expect all false).
select has_function_privilege('anon', 'public.submit_appeal(uuid, text)', 'execute'),
       has_function_privilege('anon', 'public.admin_remove_item(uuid, text)', 'execute'),
       has_function_privilege('anon', 'public.log_moderation(text, text, uuid, uuid, uuid, uuid, text, jsonb)', 'execute');

-- 4. Nobody can write the log directly (expect false, false).
select has_table_privilege('authenticated', 'public.moderation_log', 'insert'),
       has_table_privilege('authenticated', 'public.appeals', 'insert');

-- 5. Invariants (expect 0 each): a moderation state always comes with deleted_at;
--    at most one open appeal per post.
select count(*) from public.items where moderation_state is not null and deleted_at is null;
select count(*) from (
  select item_id from public.appeals where status = 'open' group by item_id having count(*) > 1
) x;

-- 6. Append-only (run as the table owner in the SQL editor; expect an error
--    "The moderation log is append-only."). Uncomment to try:
-- update public.moderation_log set note = 'x' where id = (select min(id) from public.moderation_log);

-- 7. Walk-through (staging, four accounts: owner O, reporters R1-R3 older than
--    2 days, admin A):
--    a. R1, R2 report O's post -> still visible. R3 reports it -> it disappears
--       from Browse; O gets "Your post was hidden"; A gets "Post auto-hidden".
--    b. O opens Profile > Hidden posts, taps Appeal, writes a reason -> A gets
--       "Appeal received".
--    c. A (Flagged reports > Appeals) taps Restore -> post is back for everyone,
--       O gets "Your post is back"; or Deny with a reason -> O sees the reason,
--       cannot appeal again.
--    d. Flagged reports > Activity lists every step above, newest first.
