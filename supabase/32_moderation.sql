-- ============================================================================
-- Findora — Auto-hide after several reports, a moderation audit log, appeals
-- Run this after 31_two_sided_confirmation.sql. Safe to re-run.
--
-- 1. AUTO-HIDE. When a post collects open reports from 3 different people
--    (see auto_hide_report_threshold()), it is hidden at once instead of
--    waiting in the admin queue. Only reports from accounts at least 2 days old
--    count (auto_hide_min_reporter_age()), and never the owner's own, so a
--    brand-new throwaway account can't hide someone's post alone. "Hidden"
--    reuses the existing soft delete (items.deleted_at): the post disappears
--    from Browse, the map, search, matching, saved-search alerts and other
--    people's lists exactly like a deleted post, with nothing else to keep in
--    step. New column items.moderation_state tells WHY: 'auto_hidden' (reports)
--    or 'removed' (an admin); null with deleted_at set still means "the owner
--    deleted it". Nothing is ever erased, and an admin can restore it.
--
-- 2. AUDIT LOG. moderation_log is an append-only record of every moderation
--    event: auto-hides, admin removals and restorations, each report being
--    dismissed or marked reviewed (posts and people), appeals sent and decided.
--    Who did it (an admin, the system, or the owner), when, which post and
--    owner, and any note. Admins read it (app: Flagged reports > Activity);
--    nobody can edit or delete rows, not even an admin through the API.
--
-- 3. APPEALS. The owner of a hidden or removed post can appeal once per hiding
--    (a message of 10-1000 characters, submit_appeal()). Admins uphold it (the
--    post comes back) or deny it with a reason the owner sees; a denied appeal
--    is final for that hiding. my_moderated_items() feeds the owner's
--    "Hidden posts" screen.
--
-- 4. Admin actions are now functions so each is logged and the owner told:
--    admin_remove_item(), admin_restore_item(), admin_decide_appeal().
--    New alerts: post_hidden, post_removed, post_restored, appeal_denied (to the
--    owner) and admin_review (to admins: a post was auto-hidden / an appeal
--    arrived).
-- ============================================================================

-- ---- 1. columns and tunables -----------------------------------------------------
alter table public.items add column if not exists moderation_state text;
alter table public.items add column if not exists moderation_at timestamptz;

do $$ begin
  alter table public.items
    add constraint items_moderation_state_values
    check (moderation_state is null or moderation_state in ('auto_hidden', 'removed'));
exception when duplicate_object then null; end $$;

create index if not exists items_moderation_idx
  on public.items (user_id) where moderation_state is not null;

-- How many different people must report a post before it hides itself.
create or replace function public.auto_hide_report_threshold()
returns integer language sql immutable as $$ select 3 $$;

-- A reporter's account must be at least this old for their report to count.
create or replace function public.auto_hide_min_reporter_age()
returns interval language sql immutable as $$ select interval '2 days' $$;

-- Only moderators may change the moderation columns (the owner can edit their
-- own post, but not clear its hidden state).
create or replace function public.protect_item_lifecycle()
returns trigger
language plpgsql
as $$
begin
  -- Only direct API writes by non-admins are restricted. Our own functions
  -- (mark_returned, claim triggers, rematching) and admins are not.
  if not public.is_api_caller() or public.is_admin() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.status <> 'open'
       or new.deleted_at is not null
       or new.resolved_at is not null
       or new.returned_with_item_id is not null
       or new.returned_with_user_id is not null
       or new.moderation_state is not null then
      raise exception 'New posts must start open.' using errcode = '42501';
    end if;
    return new;
  end if;

  if new.user_id is distinct from old.user_id then
    raise exception 'A post cannot be moved to another owner.' using errcode = '42501';
  end if;
  if new.moderation_state is distinct from old.moderation_state
     or new.moderation_at is distinct from old.moderation_at then
    raise exception 'Only moderators can change a post''s moderation status.' using errcode = '42501';
  end if;
  if old.deleted_at is not null and new.deleted_at is null then
    raise exception 'A removed post cannot be restored.' using errcode = '42501';
  end if;
  if new.status is distinct from old.status
     or new.resolved_at is distinct from old.resolved_at
     or new.returned_with_item_id is distinct from old.returned_with_item_id
     or new.returned_with_user_id is distinct from old.returned_with_user_id then
    raise exception 'A post''s status changes through claims and returns, not directly.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

-- ---- 2. the audit log ----------------------------------------------------------------
create table if not exists public.moderation_log (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  actor_kind text not null check (actor_kind in ('admin', 'system', 'owner')),
  actor_id uuid references public.profiles (id) on delete set null,
  action text not null,
  item_id uuid,
  owner_id uuid,
  report_id uuid,
  appeal_id uuid,
  note text,
  details jsonb not null default '{}'::jsonb
);

create index if not exists moderation_log_recent_idx on public.moderation_log (created_at desc, id desc);
create index if not exists moderation_log_item_idx on public.moderation_log (item_id);

alter table public.moderation_log enable row level security;
revoke all on public.moderation_log from anon, authenticated;
grant select on public.moderation_log to authenticated;

drop policy if exists "admins can read the moderation log" on public.moderation_log;
create policy "admins can read the moderation log"
  on public.moderation_log for select to authenticated
  using ((select public.is_admin()));

-- Append-only: no edits, no deletes — through the API or otherwise. The one
-- thing that may change is actor_id going to null when that person's account
-- is deleted (the foreign key does it): their identity is erased, the record
-- of what happened is not.
create or replace function public.moderation_log_append_only()
returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE'
     and old.actor_id is not null and new.actor_id is null
     and (to_jsonb(new) - 'actor_id') = (to_jsonb(old) - 'actor_id') then
    return new;
  end if;
  raise exception 'The moderation log is append-only.' using errcode = '42501';
end;
$$;

drop trigger if exists moderation_log_no_change on public.moderation_log;
create trigger moderation_log_no_change
  before update or delete on public.moderation_log
  for each row execute function public.moderation_log_append_only();

create or replace function public.log_moderation(
  p_action text,
  p_actor_kind text,
  p_item_id uuid default null,
  p_owner_id uuid default null,
  p_report_id uuid default null,
  p_appeal_id uuid default null,
  p_note text default null,
  p_details jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.moderation_log
    (actor_kind, actor_id, action, item_id, owner_id, report_id, appeal_id, note, details)
  values
    (p_actor_kind, case when p_actor_kind = 'system' then null else auth.uid() end,
     p_action, p_item_id, p_owner_id, p_report_id, p_appeal_id, nullif(btrim(p_note), ''), p_details);
end;
$$;

revoke all on function public.log_moderation(text, text, uuid, uuid, uuid, uuid, text, jsonb)
  from public, anon, authenticated;

-- ---- 3. appeals ------------------------------------------------------------------------
create table if not exists public.appeals (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  message text not null check (char_length(message) between 10 and 1000),
  status text not null default 'open' check (status in ('open', 'upheld', 'denied')),
  decided_by uuid references public.profiles (id) on delete set null,
  decision_note text check (decision_note is null or char_length(decision_note) <= 500),
  created_at timestamptz not null default now(),
  decided_at timestamptz
);

create unique index if not exists appeals_one_open_per_item
  on public.appeals (item_id) where status = 'open';
create index if not exists appeals_open_idx
  on public.appeals (created_at desc) where status = 'open';
create index if not exists appeals_user_idx on public.appeals (user_id);

alter table public.appeals enable row level security;
revoke all on public.appeals from anon, authenticated;
grant select on public.appeals to authenticated;

drop policy if exists "people read their own appeals" on public.appeals;
create policy "people read their own appeals"
  on public.appeals for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

-- ---- 4. auto-hide on the third report -------------------------------------------------
create or replace function public.notify_admins(p_type text, p_title text, p_body text, p_item_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  admin_row record;
begin
  for admin_row in select id from public.profiles where is_admin loop
    perform public.create_notification(admin_row.id, p_type, p_title, p_body, p_item_id);
  end loop;
end;
$$;

revoke all on function public.notify_admins(text, text, text, uuid) from public, anon, authenticated;

create or replace function public.auto_hide_reported_item()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  it public.items%rowtype;
  reporters integer;
begin
  select * into it from public.items where id = new.item_id for update;
  if not found or it.deleted_at is not null or it.status = 'resolved' then
    return new;
  end if;

  select count(distinct r.reporter_id) into reporters
  from public.reports r
  join public.profiles p on p.id = r.reporter_id
  where r.item_id = new.item_id
    and r.status = 'open'
    and r.reporter_id <> it.user_id
    and p.created_at <= now() - public.auto_hide_min_reporter_age();

  if reporters < public.auto_hide_report_threshold() then
    return new;
  end if;

  update public.items
  set deleted_at = now(), moderation_state = 'auto_hidden', moderation_at = now()
  where id = it.id;

  perform public.log_moderation(
    'auto_hidden', 'system', it.id, it.user_id, new.id, null, null,
    jsonb_build_object('title', it.title, 'reporters', reporters)
  );
  perform public.create_notification(
    it.user_id, 'post_hidden',
    'Your post was hidden: "' || it.title || '"',
    'Several people reported it, so it is hidden while we take a look. If you think that''s a mistake, you can appeal.',
    it.id
  );
  perform public.notify_admins(
    'admin_review',
    'Post auto-hidden: "' || it.title || '"',
    reporters || ' people reported it. Review it in Flagged reports.',
    it.id
  );
  return new;
end;
$$;

drop trigger if exists reports_auto_hide on public.reports;
create trigger reports_auto_hide
  after insert on public.reports
  for each row execute function public.auto_hide_reported_item();

revoke all on function public.auto_hide_reported_item() from public, anon, authenticated;

-- ---- 5. log every report being handled -----------------------------------------------
create or replace function public.log_report_handled()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_item_id uuid;
  v_owner uuid;
  v_title text;
begin
  if tg_table_name = 'reports' then
    select i.id, i.user_id, i.title into v_item_id, v_owner, v_title
    from public.items i where i.id = new.item_id;
    perform public.log_moderation(
      case new.status when 'dismissed' then 'report_dismissed' else 'report_reviewed' end,
      case when public.is_admin() then 'admin' else 'system' end,
      v_item_id, v_owner, new.id, null, null,
      jsonb_build_object('title', v_title, 'reason', left(new.reason, 200))
    );
  else
    perform public.log_moderation(
      case new.status when 'dismissed' then 'user_report_dismissed' else 'user_report_reviewed' end,
      case when public.is_admin() then 'admin' else 'system' end,
      null, new.reported_user_id, new.id, null, null,
      jsonb_build_object('reason', left(new.reason, 200))
    );
  end if;
  return new;
end;
$$;

drop trigger if exists reports_log_handled on public.reports;
create trigger reports_log_handled
  after update of status on public.reports
  for each row
  when (old.status = 'open' and new.status <> 'open')
  execute function public.log_report_handled();

drop trigger if exists user_reports_log_handled on public.user_reports;
create trigger user_reports_log_handled
  after update of status on public.user_reports
  for each row
  when (old.status = 'open' and new.status <> 'open')
  execute function public.log_report_handled();

revoke all on function public.log_report_handled() from public, anon, authenticated;

-- ---- 6. admin actions --------------------------------------------------------------------
-- Brings a hidden/removed post back. Internal: called by the two admin
-- functions below (never by the app directly).
create or replace function public.moderation_restore(
  p_item_id uuid, p_appeal_id uuid, p_note text, p_action text
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  it public.items%rowtype;
begin
  select * into it from public.items where id = p_item_id for update;
  if not found then
    raise exception 'That post no longer exists.' using errcode = 'P0002';
  end if;
  if it.moderation_state is null then
    raise exception 'That post was not hidden by moderation.' using errcode = '22023';
  end if;

  update public.items
  set deleted_at = null, moderation_state = null, moderation_at = null
  where id = p_item_id;

  update public.reports set status = 'dismissed' where item_id = p_item_id and status = 'open';

  update public.appeals
  set status = 'upheld', decided_by = auth.uid(), decided_at = now(),
      decision_note = nullif(btrim(p_note), '')
  where item_id = p_item_id and status = 'open';

  perform public.log_moderation(
    p_action, 'admin', p_item_id, it.user_id, null, p_appeal_id, p_note,
    jsonb_build_object('title', it.title, 'was', it.moderation_state)
  );
  perform public.create_notification(
    it.user_id, 'post_restored',
    'Your post is back: "' || it.title || '"',
    case when p_appeal_id is not null then 'Your appeal was accepted.' else 'A moderator reviewed it and restored it.' end
      || coalesce(' ' || nullif(btrim(p_note), ''), ''),
    it.id
  );
end;
$$;

revoke all on function public.moderation_restore(uuid, uuid, text, text) from public, anon, authenticated;

create or replace function public.admin_restore_item(p_item_id uuid, p_note text default null)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can do that.' using errcode = '42501';
  end if;
  perform public.moderation_restore(p_item_id, null, p_note, 'item_restored');
end;
$$;

create or replace function public.admin_remove_item(p_item_id uuid, p_note text default null)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  it public.items%rowtype;
  v_reviewed integer;
begin
  if not public.is_admin() then
    raise exception 'Only admins can do that.' using errcode = '42501';
  end if;
  select * into it from public.items where id = p_item_id for update;
  if not found then
    raise exception 'That post no longer exists.' using errcode = 'P0002';
  end if;

  -- Reports about it were acted on.
  update public.reports set status = 'reviewed' where item_id = p_item_id and status = 'open';

  -- Already deleted by its owner: nothing to take down.
  if it.deleted_at is not null and it.moderation_state is null then
    return;
  end if;

  update public.items
  set deleted_at = coalesce(deleted_at, now()),
      moderation_state = 'removed',
      moderation_at = case when moderation_state is null then now() else moderation_at end
  where id = p_item_id;

  -- An appeal still open against an auto-hide is settled by this decision.
  update public.appeals
  set status = 'denied', decided_by = auth.uid(), decided_at = now(),
      decision_note = coalesce(nullif(btrim(p_note), ''), 'A moderator removed this post.')
  where item_id = p_item_id and status = 'open';

  perform public.log_moderation(
    'item_removed', 'admin', p_item_id, it.user_id, null, null, p_note,
    jsonb_build_object('title', it.title, 'was', it.moderation_state)
  );
  perform public.create_notification(
    it.user_id, 'post_removed',
    'Your post was removed: "' || it.title || '"',
    'A moderator removed it.' || coalesce(' ' || nullif(btrim(p_note), ''), '')
      || ' If you think that''s a mistake, you can appeal.',
    it.id
  );
end;
$$;

create or replace function public.admin_decide_appeal(
  p_appeal_id uuid, p_decision text, p_note text default null
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  ap public.appeals%rowtype;
  it public.items%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Only admins can do that.' using errcode = '42501';
  end if;
  if p_decision not in ('upheld', 'denied') then
    raise exception 'Unknown decision.' using errcode = '22023';
  end if;
  if p_decision = 'denied' and char_length(btrim(coalesce(p_note, ''))) < 3 then
    raise exception 'Give the owner a reason when denying an appeal.' using errcode = '22023';
  end if;

  select * into ap from public.appeals where id = p_appeal_id for update;
  if not found then
    raise exception 'That appeal no longer exists.' using errcode = 'P0002';
  end if;
  if ap.status <> 'open' then
    raise exception 'That appeal was already decided.' using errcode = '22023';
  end if;

  if p_decision = 'upheld' then
    perform public.moderation_restore(ap.item_id, ap.id, p_note, 'appeal_upheld');
    return;
  end if;

  select * into it from public.items where id = ap.item_id for update;

  update public.appeals
  set status = 'denied', decided_by = auth.uid(), decided_at = now(),
      decision_note = btrim(p_note)
  where id = ap.id;

  -- Denied: an auto-hide becomes a removal (still not erased).
  update public.items
  set moderation_state = 'removed'
  where id = ap.item_id and moderation_state = 'auto_hidden';
  update public.reports set status = 'reviewed' where item_id = ap.item_id and status = 'open';

  perform public.log_moderation(
    'appeal_denied', 'admin', ap.item_id, ap.user_id, null, ap.id, p_note,
    jsonb_build_object('title', it.title)
  );
  perform public.create_notification(
    ap.user_id, 'appeal_denied',
    'Appeal denied: "' || coalesce(it.title, 'your post') || '"',
    btrim(p_note), ap.item_id
  );
end;
$$;

revoke all on function public.admin_restore_item(uuid, text) from public, anon;
revoke all on function public.admin_remove_item(uuid, text) from public, anon;
revoke all on function public.admin_decide_appeal(uuid, text, text) from public, anon;
grant execute on function public.admin_restore_item(uuid, text) to authenticated;
grant execute on function public.admin_remove_item(uuid, text) to authenticated;
grant execute on function public.admin_decide_appeal(uuid, text, text) to authenticated;

-- ---- 7. the owner's side -----------------------------------------------------------------
create or replace function public.submit_appeal(p_item_id uuid, p_message text)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  me uuid := auth.uid();
  it public.items%rowtype;
  v_message text := btrim(coalesce(p_message, ''));
  v_id uuid;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  select * into it from public.items where id = p_item_id for update;
  if not found or it.user_id is distinct from me then
    raise exception 'That is not your post.' using errcode = '42501';
  end if;
  if it.moderation_state is null then
    raise exception 'That post was not hidden by moderation.' using errcode = '22023';
  end if;
  if char_length(v_message) < 10 or char_length(v_message) > 1000 then
    raise exception 'Please explain in 10 to 1000 characters.' using errcode = '22023';
  end if;
  -- One appeal per hiding, whatever its outcome.
  if exists (
    select 1 from public.appeals a
    where a.item_id = p_item_id and a.created_at >= coalesce(it.moderation_at, '-infinity'::timestamptz)
  ) then
    raise exception 'You have already appealed this decision.' using errcode = '22023';
  end if;

  insert into public.appeals (item_id, user_id, message)
  values (p_item_id, me, v_message)
  returning id into v_id;

  perform public.log_moderation(
    'appeal_submitted', 'owner', p_item_id, me, null, v_id, null,
    jsonb_build_object('title', it.title)
  );
  perform public.notify_admins(
    'admin_review', 'Appeal received: "' || it.title || '"',
    'The owner disputes the decision. Review it in Flagged reports.', p_item_id
  );
  return v_id;
end;
$$;

revoke all on function public.submit_appeal(uuid, text) from public, anon;
grant execute on function public.submit_appeal(uuid, text) to authenticated;

-- The caller's posts that moderation has hidden or removed, with where any
-- appeal stands. (Not security definer: the owner can read their own posts and
-- appeals under row-level security.)
create or replace function public.my_moderated_items()
returns table (
  item_id uuid,
  title text,
  item_type public.item_type,
  moderation_state text,
  moderated_at timestamptz,
  appeal_status text,
  appeal_note text,
  can_appeal boolean
)
language sql
stable
as $$
  select
    i.id,
    i.title,
    i.type,
    i.moderation_state,
    i.moderation_at,
    ap.status,
    ap.decision_note,
    ap.id is null
  from public.items i
  left join lateral (
    select a.id, a.status, a.decision_note
    from public.appeals a
    where a.item_id = i.id and a.created_at >= coalesce(i.moderation_at, '-infinity'::timestamptz)
    order by a.created_at desc
    limit 1
  ) ap on true
  where i.user_id = auth.uid()
    and i.moderation_state is not null
  order by i.moderation_at desc nulls last;
$$;

revoke all on function public.my_moderated_items() from public, anon;
grant execute on function public.my_moderated_items() to authenticated;
