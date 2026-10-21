-- ============================================================================
-- Findora — checks for 35_post_expiry.sql
-- Run in the Supabase SQL editor against a STAGING project.
-- Read-only except where marked. NOT run by the author.
-- ============================================================================

-- 1. The enum value, columns and trigger exist (expect 'expired' among the
--    values, 2 columns, 1 trigger).
select unnest(enum_range(null::public.item_status))::text as status;
select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'items'
  and column_name in ('expires_at', 'expiry_reminders_sent');
select count(*) from pg_trigger where tgname = 'items_expiry_defaults' and not tgisinternal;

-- 2. The tunables (expect 60 days, 7 days, 1 day).
select public.post_lifetime(), public.post_expiry_first_reminder(), public.post_expiry_final_reminder();

-- 3. Every live post has an expiry (expect 0).
select count(*) from public.items where expires_at is null;

-- 4. Nobody but the server can run the job or renew as anon (expect false, false, true).
select has_function_privilege('authenticated', 'public.process_item_expiry()', 'execute'),
       has_function_privilege('anon', 'public.renew_item(uuid)', 'execute'),
       has_function_privilege('authenticated', 'public.renew_item(uuid)', 'execute');

-- 5. The job is scheduled (expect one row, if pg_cron is on).
select jobname, schedule from cron.job where jobname = 'findora-item-expiry';

-- 6. Invariants (expect 0 each): an expired post is never deleted-by-owner,
--    and no post with a confirmed match or live claim got expired by the job
--    (check after the job has run a few days).
select count(*) from public.items where status::text = 'expired' and deleted_at is not null;
select count(*) from public.items i
where i.status::text = 'expired'
  and exists (select 1 from public.matches m
              where (m.item_a_id = i.id or m.item_b_id = i.id) and m.status = 'confirmed');

-- 7. Walk-through (staging). Make a post P, then in the SQL editor:
--      -- pretend it is 6 days from expiry:
--      update items set expires_at = now() + interval '6 days' where id = '<P>';
--      select process_item_expiry();   -- -> {"expired": 0, "reminded": 1}; owner gets "Still looking...?"
--      select process_item_expiry();   -- -> reminded 0 (no repeat)
--      update items set expires_at = now() + interval '20 hours' where id = '<P>';
--      select process_item_expiry();   -- -> reminded 1 ("Last day...")
--      update items set expires_at = now() - interval '1 minute' where id = '<P>';
--      select process_item_expiry();   -- -> expired 1; status = 'expired'
--    In the app: P is gone from Browse/map and from others' matches; the owner's
--    My posts shows it "Expired" with Renew; Renew -> status 'open', a fresh
--    expires_at, reminders reset. Another user's "Message about this post" on an
--    expired P is refused. A post with a confirmed match is skipped by the job.
