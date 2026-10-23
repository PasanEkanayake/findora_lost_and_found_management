-- ============================================================================
-- Findora — Limit repeated claims on the same post
-- Run this after 37_signup_hook.sql (or 36 if you skipped 37). Safe to re-run.
--
-- THE GAP. A claim is how someone proves a found item is theirs (usually by
-- answering the finder's question). The rules only allowed ONE live claim per
-- person per post — a rejected claim isn't live — plus 5 claims a day across all
-- posts. So after a rejection the same person could file again at once, and
-- again, guessing the answer until it was accepted.
--
-- THE RULES NOW (per person, per post):
--   * at most 3 claims in total, whatever happened to them
--     (claim_max_attempts());
--   * after a rejection, a wait of 1 hour before the next one
--     (claim_retry_wait()) — time to check the answer instead of guessing;
--   * both enforced by the database, so no app version can get around them.
--
-- WHAT PEOPLE ARE TOLD (the app shows these; this file supplies the numbers):
--   * BEFORE: the claim form says "Attempt 2 of 3" and, on the last one, warns
--     that it is the last; the chat banner shows how many attempts are left.
--   * ON A REJECTION: the claimant gets an alert saying how many attempts are
--     left (and a clear warning when it is the last one).
--   * AT THE LIMIT: the alert says they can't claim this post again, the banner
--     says so and offers no button, and a further attempt is refused with the
--     same explanation.
--
-- Everyone starts with a clean slate: claims rejected before this migration do
-- NOT count (they are marked `forgiven`). Support can also give someone their
-- attempts back — admin_reset_claim_attempts() below.
-- ============================================================================

-- ---- 1. the numbers --------------------------------------------------------------------
create or replace function public.claim_max_attempts()
returns integer language sql immutable as $$ select 3 $$;

create or replace function public.claim_retry_wait()
returns interval language sql immutable as $$ select interval '1 hour' $$;

-- ---- 2. columns --------------------------------------------------------------------------
alter table public.claims add column if not exists decided_at timestamptz;
alter table public.claims add column if not exists forgiven boolean not null default false;

-- Existing decided claims: stamp the time, and start everyone fresh (a claim
-- already rejected doesn't count). Only touches rows not stamped yet, so
-- re-running changes nothing.
update public.claims
set decided_at = created_at,
    forgiven = (status = 'rejected')
where status <> 'pending' and decided_at is null;

create index if not exists claims_attempts_idx
  on public.claims (item_id, claimant_id)
  where not forgiven;

-- ---- 3. when a claim was decided (only the database sets it) -----------------------------
create or replace function public.protect_claim_fields()
returns trigger
language plpgsql
as $$
begin
  if not public.is_api_caller() or public.is_admin() then
    return new;
  end if;

  if new.item_id is distinct from old.item_id
     or new.claimant_id is distinct from old.claimant_id
     or new.verification_answer is distinct from old.verification_answer
     or new.created_at is distinct from old.created_at
     or new.decided_at is distinct from old.decided_at
     or new.forgiven is distinct from old.forgiven then
    raise exception 'Only a claim''s status can be changed.' using errcode = '42501';
  end if;

  if new.status is distinct from old.status then
    if old.status <> 'pending' or new.status not in ('approved', 'rejected') then
      raise exception 'A claim can only be approved or rejected while it is pending.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

-- Runs after claims_protect_fields (triggers fire in name order).
create or replace function public.claims_stamp_decision()
returns trigger
language plpgsql
as $$
begin
  if old.status = 'pending' and new.status <> 'pending' then
    new.decided_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists claims_stamp_decision on public.claims;
create trigger claims_stamp_decision
  before update on public.claims
  for each row execute function public.claims_stamp_decision();

-- ---- 4. the limit itself ---------------------------------------------------------------------
-- Fires before the 5-a-day rate limit (name order), so the person hears the
-- more specific reason first.
create or replace function public.enforce_claim_attempt_limit()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  used integer;
  last_rejected timestamptz;
  ready_at timestamptz;
  minutes_left integer;
begin
  select count(*) into used
  from public.claims c
  where c.item_id = new.item_id and c.claimant_id = new.claimant_id and not c.forgiven;

  if used >= public.claim_max_attempts() then
    raise exception 'You have used all % attempts to claim this post, so it can''t be claimed again from this account. If you think this is a mistake, contact support.',
      public.claim_max_attempts()
      using errcode = '22023';
  end if;

  select max(c.decided_at) into last_rejected
  from public.claims c
  where c.item_id = new.item_id and c.claimant_id = new.claimant_id
    and c.status = 'rejected' and not c.forgiven;

  if last_rejected is not null then
    ready_at := last_rejected + public.claim_retry_wait();
    if ready_at > now() then
      minutes_left := greatest(1, ceil(extract(epoch from (ready_at - now())) / 60.0)::integer);
      raise exception 'Please wait about % minute% before filing another claim on this post — use the time to check your answer.',
        minutes_left, case when minutes_left = 1 then '' else 's' end
        using errcode = '22023';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_claim_attempt_limit() from public, anon, authenticated;

drop trigger if exists claims_attempt_limit on public.claims;
create trigger claims_attempt_limit
  before insert on public.claims
  for each row execute function public.enforce_claim_attempt_limit();

-- ---- 5. what the app shows before claiming ----------------------------------------------------
-- The caller's own standing on one post. Reads only the caller's own claims.
create or replace function public.claim_attempt_status(p_item_id uuid)
returns table (
  attempts_used integer,
  max_attempts integer,
  attempts_left integer,
  has_live_claim boolean,
  retry_at timestamptz
)
language sql
stable
security definer set search_path = public
as $$
  with mine as (
    select * from public.claims c
    where c.item_id = p_item_id and c.claimant_id = auth.uid()
  ),
  counted as (
    select count(*) filter (where not forgiven)::integer as used,
           max(decided_at) filter (where status = 'rejected' and not forgiven) as last_rejected,
           bool_or(status in ('pending', 'approved')) as live
    from mine
  )
  select
    counted.used,
    public.claim_max_attempts(),
    greatest(public.claim_max_attempts() - counted.used, 0),
    coalesce(counted.live, false),
    case
      when counted.used < public.claim_max_attempts()
       and counted.last_rejected is not null
       and counted.last_rejected + public.claim_retry_wait() > now()
      then counted.last_rejected + public.claim_retry_wait()
    end
  from counted;
$$;

revoke all on function public.claim_attempt_status(uuid) from public, anon;
grant execute on function public.claim_attempt_status(uuid) to authenticated;

-- ---- 6. what the claimant is told after a decision -------------------------------------------------
create or replace function public.notify_claim_decision()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  item_title text;
  used integer;
  attempts_left integer;
  v_title text;
  v_body text;
begin
  if new.status in ('approved', 'rejected') and old.status is distinct from new.status then
    select title into item_title from public.items where id = new.item_id;

    if new.status = 'approved' then
      v_title := 'Claim approved: "' || coalesce(item_title, 'the post') || '"';
      v_body := 'Arrange to get it back, then mark it as returned in the chat.';
    else
      select count(*) into used
      from public.claims c
      where c.item_id = new.item_id and c.claimant_id = new.claimant_id and not c.forgiven;
      attempts_left := greatest(public.claim_max_attempts() - used, 0);

      if attempts_left = 0 then
        v_title := 'Claim not approved — no attempts left: "' || coalesce(item_title, 'the post') || '"';
        v_body := 'You''ve used all ' || public.claim_max_attempts()
                  || ' attempts for this post, so you can''t claim it again. If you think this is a mistake, contact support.';
      elsif attempts_left = 1 then
        v_title := 'Claim not approved — last attempt left: "' || coalesce(item_title, 'the post') || '"';
        v_body := 'You have 1 attempt left for this post. Check your answer carefully — if the next claim is rejected you won''t be able to claim it again.';
      else
        v_title := 'Claim not approved: "' || coalesce(item_title, 'the post') || '"';
        v_body := 'You have ' || attempts_left || ' attempts left for this post. You can try again after a short wait.';
      end if;
    end if;

    perform public.create_notification(
      new.claimant_id,
      case when new.status = 'approved' then 'claim_approved' else 'claim_rejected' end,
      v_title, v_body,
      new.item_id, null, new.id
    );
  end if;
  return new;
end;
$$;

-- ---- 7. support can give attempts back ---------------------------------------------------------------
create or replace function public.admin_reset_claim_attempts(p_item_id uuid, p_claimant_id uuid)
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_count integer;
  v_title text;
begin
  if not public.is_admin() then
    raise exception 'Only admins can do that.' using errcode = '42501';
  end if;

  update public.claims set forgiven = true
  where item_id = p_item_id and claimant_id = p_claimant_id and not forgiven and status = 'rejected';
  get diagnostics v_count = row_count;

  select title into v_title from public.items where id = p_item_id;
  perform public.log_moderation(
    'claim_attempts_reset', 'admin', p_item_id, p_claimant_id, null, null, null,
    jsonb_build_object('title', v_title, 'attempts_given_back', v_count)
  );
  if v_count > 0 then
    perform public.create_notification(
      p_claimant_id, 'claim_rejected',
      'You can claim "' || coalesce(v_title, 'the post') || '" again',
      'A moderator gave you your claim attempts back.',
      p_item_id
    );
  end if;
  return v_count;
end;
$$;

revoke all on function public.admin_reset_claim_attempts(uuid, uuid) from public, anon;
grant execute on function public.admin_reset_claim_attempts(uuid, uuid) to authenticated;
