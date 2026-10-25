-- ============================================================================
-- Findora — checks for 38_claim_attempt_limit.sql. Run in the SQL editor on
-- STAGING. Read-only except the walk-through. NOT run by the author.
-- ============================================================================

-- 1. Objects exist (expect 2 columns, 3 triggers, numbers 3 and 01:00:00).
select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'claims' and column_name in ('decided_at', 'forgiven');
select tgname from pg_trigger
where tgname in ('claims_attempt_limit', 'claims_stamp_decision', 'claims_protect_fields') and not tgisinternal;
select public.claim_max_attempts(), public.claim_retry_wait();

-- 2. Trigger order: the attempt limit must fire BEFORE the daily rate limit
--    (alphabetical) so the specific reason is shown first (expect true).
select 'claims_attempt_limit' < 'claims_rate_limit';

-- 3. Only admins can give attempts back; signed-out callers can't ask about
--    standing (expect false, false, true).
select has_function_privilege('anon', 'public.claim_attempt_status(uuid)', 'execute'),
       has_function_privilege('anon', 'public.admin_reset_claim_attempts(uuid, uuid)', 'execute'),
       has_function_privilege('authenticated', 'public.claim_attempt_status(uuid)', 'execute');

-- 4. Rollout: every decided claim has a time, and old rejections were forgiven
--    (expect 0).
select count(*) from public.claims where status <> 'pending' and decided_at is null;

-- 5. Walk-through (staging; a found post F with a confirmed match to the lost
--    post of user C; C files claims through the app):
--    a. Claim form says "Attempt 1 of 3". Owner rejects -> C gets "2 attempts left";
--       the chat banner says so and shows a countdown of about an hour.
--    b. C tries again at once -> refused: "Please wait about 59 minutes...".
--    c. After the hour, claim 2; rejected -> alert "last attempt left"; banner
--       warns; the form says "This is your last attempt".
--    d. Claim 3; rejected -> alert "no attempts left"; banner has no button; a
--       4th insert via the API is refused with the same explanation.
--    e. As an admin:  select public.admin_reset_claim_attempts('<F>', '<C>');
--       -> C can claim again and is told so.
