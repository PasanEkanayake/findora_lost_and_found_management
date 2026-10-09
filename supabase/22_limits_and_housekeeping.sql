-- ============================================================================
-- Findora — Abuse limits, scheduled housekeeping, and faster older policies
-- Run this after 21_device_tokens.sql. Safe to re-run.
--
-- 1. LIMITS. Nothing stopped one account from posting hundreds of items,
--    messaging in a flood, or opening hundreds of direct threads in a minute.
--    Each limit below counts a person's recent rows and refuses the next one
--    with a plain-language message (SQLSTATE RL001, which the app shows as is).
--    They apply to direct app/API writes only — not to admins, not to the
--    database's own functions. The numbers are generous for real use:
--        posts            20 per 24 h
--        chat messages    30 per minute (match chats and direct messages)
--        new direct chats 15 per 24 h
--        claims            5 per 24 h
--        post reports     10 per 24 h        person reports 10 per 24 h
--    Change a number below and re-run the file.
-- 2. HOUSEKEEPING. housekeeping() deletes alerts older than 90 days and
--    expired email cooldowns; it is scheduled nightly if the pg_cron extension
--    is enabled (Dashboard -> Database -> Extensions), else run it by hand.
-- 3. POLICY SPEED. Older row-level-security policies call auth.uid() once per
--    ROW checked; written as (select auth.uid()) Postgres evaluates it once per
--    QUERY. Same meaning, much cheaper on big tables (it is Supabase's own
--    Performance Advisor recommendation). This rewrites every policy that
--    still has the slow form.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Limits
-- ----------------------------------------------------------------------------

-- Generic guard, configured per table through the trigger arguments:
--   (max rows, window, owner column, message shown to the person)
create or replace function public.rate_limit_guard()
returns trigger
language plpgsql
as $$
declare
  max_rows int := tg_argv[0]::int;
  look_back interval := tg_argv[1]::interval;
  owner_column text := tg_argv[2];
  message text := tg_argv[3];
  owner uuid;
  recent bigint;
begin
  if not public.is_api_caller() or public.is_admin() then
    return new;
  end if;

  owner := (to_jsonb(new) ->> owner_column)::uuid;
  execute format(
    'select count(*) from %I.%I where %I = $1 and created_at > now() - $2',
    tg_table_schema, tg_table_name, owner_column
  ) into recent using owner, look_back;

  if recent >= max_rows then
    raise exception '%', message using errcode = 'RL001';
  end if;
  return new;
end;
$$;

-- Indexes so the counts above stay cheap.
create index if not exists messages_sender_recent_idx
  on public.messages (sender_id, created_at desc);
create index if not exists contact_messages_sender_recent_idx
  on public.contact_messages (sender_id, created_at desc);
create index if not exists reports_reporter_recent_idx
  on public.reports (reporter_id, created_at desc);
create index if not exists user_reports_reporter_recent_idx
  on public.user_reports (reporter_id, created_at desc);

drop trigger if exists items_rate_limit on public.items;
create trigger items_rate_limit
  before insert on public.items
  for each row execute function public.rate_limit_guard(
    '20', '24 hours', 'user_id',
    'Posting limit reached: 20 posts per day. Please try again tomorrow.');

drop trigger if exists messages_rate_limit on public.messages;
create trigger messages_rate_limit
  before insert on public.messages
  for each row execute function public.rate_limit_guard(
    '30', '1 minute', 'sender_id',
    'You are sending messages too fast. Please wait a moment.');

drop trigger if exists contact_messages_rate_limit on public.contact_messages;
create trigger contact_messages_rate_limit
  before insert on public.contact_messages
  for each row execute function public.rate_limit_guard(
    '30', '1 minute', 'sender_id',
    'You are sending messages too fast. Please wait a moment.');

drop trigger if exists claims_rate_limit on public.claims;
create trigger claims_rate_limit
  before insert on public.claims
  for each row execute function public.rate_limit_guard(
    '5', '24 hours', 'claimant_id',
    'Claim limit reached: 5 claims per day. Please try again tomorrow.');

drop trigger if exists reports_rate_limit on public.reports;
create trigger reports_rate_limit
  before insert on public.reports
  for each row execute function public.rate_limit_guard(
    '10', '24 hours', 'reporter_id',
    'Report limit reached for today. Thank you - we are reviewing what you sent.');

drop trigger if exists user_reports_rate_limit on public.user_reports;
create trigger user_reports_rate_limit
  before insert on public.user_reports
  for each row execute function public.rate_limit_guard(
    '10', '24 hours', 'reporter_id',
    'Report limit reached for today. Thank you - we are reviewing what you sent.');

-- Starting a direct chat goes through a SECURITY DEFINER function (so the
-- trigger approach, which only polices direct writes, can't see it) — the
-- limit lives inside it instead. Otherwise identical to 20_chat_safety.sql.
create or replace function public.start_contact_thread(p_item_id uuid)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  owner_id uuid;
  thread_id uuid;
  started_today bigint;
begin
  select user_id into owner_id from public.items where id = p_item_id;
  if owner_id is null then
    raise exception 'Item not found';
  end if;
  if owner_id = auth.uid() then
    raise exception 'Cannot start a contact thread with yourself';
  end if;
  if public.is_blocked_between(auth.uid(), owner_id) then
    raise exception 'This person can''t be contacted.' using errcode = '42501';
  end if;

  -- Re-opening a conversation that already exists is always fine; only NEW
  -- conversations count towards the limit.
  select id into thread_id from public.contact_threads
  where item_id = p_item_id and contacter_id = auth.uid();
  if thread_id is not null then
    return thread_id;
  end if;

  select count(*) into started_today from public.contact_threads
  where contacter_id = auth.uid() and created_at > now() - interval '24 hours';
  if started_today >= 15 then
    raise exception 'Chat limit reached: you can start 15 new conversations per day. Please try again tomorrow.'
      using errcode = 'RL001';
  end if;

  insert into public.contact_threads (item_id, item_owner_id, contacter_id)
  values (p_item_id, owner_id, auth.uid())
  on conflict (item_id, contacter_id)
    do update set item_id = excluded.item_id -- no-op, just to allow RETURNING below
  returning id into thread_id;

  return thread_id;
end;
$$;


-- ----------------------------------------------------------------------------
-- 2. Housekeeping
-- ----------------------------------------------------------------------------
create or replace function public.housekeeping()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  old_alerts bigint;
  old_blocks bigint;
begin
  delete from public.notifications where created_at < now() - interval '90 days';
  get diagnostics old_alerts = row_count;

  delete from public.email_reuse_blocks
  where blocked_until is not null and blocked_until < now() - interval '30 days';
  get diagnostics old_blocks = row_count;

  return jsonb_build_object(
    'alerts_deleted', old_alerts,
    'email_cooldowns_deleted', old_blocks
  );
end;
$$;

revoke all on function public.housekeeping() from public, anon, authenticated;

-- Schedule it nightly, and re-score matches weekly as a safety net, if pg_cron
-- is available. Not an error if it isn't — run `select public.housekeeping();`
-- yourself now and then instead.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('findora-housekeeping', '17 3 * * *', 'select public.housekeeping()');
    perform cron.schedule('findora-rescore-matches', '47 3 * * 0', 'select public.refresh_all_matches()');
    raise notice 'Scheduled findora-housekeeping (nightly) and findora-rescore-matches (weekly).';
  else
    raise notice 'pg_cron is not enabled, so nothing was scheduled. Enable it (Database -> Extensions) and re-run this file, or call public.housekeeping() by hand.';
  end if;
exception when others then
  raise notice 'Could not schedule jobs (%). Call public.housekeeping() by hand instead.', sqlerrm;
end $$;


-- ----------------------------------------------------------------------------
-- 3. Policy speed: auth.uid() -> (select auth.uid())
--    Rewrites each policy IN PLACE (ALTER POLICY keeps its name, command and
--    roles). Policies that already use the fast form are left alone. If any
--    single rewrite fails the whole file rolls back and nothing changes.
-- ----------------------------------------------------------------------------
do $$
declare
  p record;
  new_qual text;
  new_check text;
  stmt text;
  rewritten int := 0;
begin
  for p in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where schemaname in ('public', 'storage')
      and (coalesce(qual, '') ~ 'auth\.uid\(\)' or coalesce(with_check, '') ~ 'auth\.uid\(\)')
  loop
    -- "SELECT auth.uid()" is how Postgres prints the already-fast form, so
    -- only occurrences NOT preceded by it are rewritten.
    new_qual := regexp_replace(p.qual, '(?<!SELECT )auth\.uid\(\)', '(select auth.uid())', 'g');
    new_check := regexp_replace(p.with_check, '(?<!SELECT )auth\.uid\(\)', '(select auth.uid())', 'g');

    if new_qual is not distinct from p.qual and new_check is not distinct from p.with_check then
      continue;
    end if;

    stmt := format('alter policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);
    if p.qual is not null then
      stmt := stmt || ' using (' || new_qual || ')';
    end if;
    if p.with_check is not null then
      stmt := stmt || ' with check (' || new_check || ')';
    end if;
    execute stmt;
    rewritten := rewritten + 1;
  end loop;

  raise notice 'Rewrote % policies to use (select auth.uid()).', rewritten;
end $$;

-- ============================================================================
-- Verify (optional):
--   -- should list nothing left in the slow form:
--   select tablename, policyname from pg_policies
--   where schemaname in ('public', 'storage')
--     and (coalesce(qual, '') ~ '(?<!SELECT )auth\.uid\(\)'
--       or coalesce(with_check, '') ~ '(?<!SELECT )auth\.uid\(\)');
--   -- scheduled jobs (if pg_cron is on):
--   select jobname, schedule from cron.job where jobname like 'findora-%';
--   -- the limits really apply (as a test user, 21 quick inserts into items
--   -- should fail on the 21st with "Posting limit reached").
-- ============================================================================
