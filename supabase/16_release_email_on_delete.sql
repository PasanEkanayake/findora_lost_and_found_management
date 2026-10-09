-- ============================================================================
-- Findora — Account deletion that releases the email address
-- Run this after 15_refresh_matches_on_edit.sql. Safe to re-run.
--
-- BEFORE: "Delete account" (09_account_deletion.sql) kept the auth.users row
-- and just banned it for 100 years. The row still carried the person's email,
-- so (a) that email could never be used to sign up again — the sign-up screen
-- said "check your email" while Supabase quietly created nothing — and (b) the
-- email address was still stored even though the README promised nothing
-- personal was left.
--
-- NOW: deleting an account ANONYMISES its auth.users row instead of only
-- banning it. The row itself is kept — everything else (matches, chats,
-- ratings, other people's threads) points at that id, which is exactly why
-- 09 refused to hard-delete — but it no longer holds anything identifying:
--   * email  -> a unique placeholder  deleted-<id>@deleted.invalid
--   * phone, password hash, user metadata (name, avatar)  -> cleared
--   * linked sign-in identities (e.g. Google) and sessions  -> removed
--   * still banned, so the husk can never sign in
-- The old email is therefore free: signing up with it creates a brand-new
-- account (new id, new profile, no history, no rating). The old history stays
-- attached to the old id and shows as "Findora user".
--
-- COOLDOWN: so deleting and re-registering can't be used to wipe a bad rating,
-- an email is blocked from new sign-ups for email_reuse_cooldown() (14 days)
-- after deletion. Only a SHA-256 fingerprint of the email is kept for that
-- (public.email_reuse_blocks), never the address itself, and expired rows are
-- cleaned up. The same table can hold PERMANENT blocks for people removed by
-- moderation — see block_email() below.
--
-- Limit worth knowing: the fingerprint is of the exact address, so
-- name+anything@gmail.com style aliases are different addresses to it. The
-- cooldown deters casual reputation-resetting; it is not identity checking.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Knobs and helpers
-- ----------------------------------------------------------------------------

-- How long a deleted account's email stays unavailable. Change the number and
-- re-run this file; it applies to deletions from then on.
create or replace function public.email_reuse_cooldown()
returns interval
language sql
immutable
as $$
  select interval '14 days';
$$;

-- Case/whitespace-insensitive fingerprint. Built-in sha256() (Postgres 11+),
-- so no extension is needed.
create or replace function public.email_fingerprint(p_email text)
returns text
language sql
immutable
as $$
  select encode(sha256(convert_to(lower(trim(p_email)), 'UTF8')), 'hex');
$$;

-- ----------------------------------------------------------------------------
-- email_reuse_blocks — emails that can't (yet) be used to create an account.
-- blocked_until null = permanent. Row-level security is on with NO policies
-- and the API roles have no privileges: it is only ever reached through the
-- security-definer functions in this file.
-- ----------------------------------------------------------------------------
create table if not exists public.email_reuse_blocks (
  email_hash text primary key,
  reason text not null default 'self_deleted'
    check (reason in ('self_deleted', 'moderation')),
  blocked_until timestamptz,
  created_at timestamptz not null default now()
);

alter table public.email_reuse_blocks enable row level security;
revoke all on public.email_reuse_blocks from anon, authenticated;

-- ----------------------------------------------------------------------------
-- release_account_identity — the anonymise-and-release step, shared by
-- request_account_deletion() and the one-off backfill below. Internal: not
-- callable through the API.
-- ----------------------------------------------------------------------------
create or replace function public.release_account_identity(
  p_user_id uuid,
  p_deleted_at timestamptz default now()
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  old_email text;
begin
  select email into old_email from auth.users where id = p_user_id;
  -- Nothing to release (no email, or already anonymised by an earlier run).
  if old_email is null or old_email like 'deleted-%@deleted.invalid' then
    return;
  end if;

  -- Start the cooldown. Never weakens a block that already exists: a
  -- permanent moderation block stays permanent and keeps its reason.
  insert into public.email_reuse_blocks as b (email_hash, reason, blocked_until)
  values (
    public.email_fingerprint(old_email),
    'self_deleted',
    p_deleted_at + public.email_reuse_cooldown()
  )
  on conflict (email_hash) do update
  set
    reason = case when b.reason = 'moderation' then 'moderation' else excluded.reason end,
    blocked_until = case
      when b.reason = 'moderation' and b.blocked_until is null then null
      else greatest(b.blocked_until, excluded.blocked_until)
    end;

  -- Housekeeping: forget cooldowns that ended a while ago.
  delete from public.email_reuse_blocks
  where blocked_until is not null and blocked_until < now() - interval '30 days';

  update auth.users
  set email = 'deleted-' || id || '@deleted.invalid',
      phone = null,
      encrypted_password = '',
      raw_user_meta_data = '{}'::jsonb,
      banned_until = greatest(coalesce(banned_until, now()), now() + interval '100 years')
  where id = p_user_id;

  -- Linked sign-in methods (Google etc.). Without this, signing in with the
  -- same Google account would find the old, banned user instead of making a
  -- new one.
  delete from auth.identities where user_id = p_user_id;

  -- Ends any other devices' sessions too. Guarded only so an unexpected auth
  -- schema difference can't make account deletion itself fail.
  begin
    delete from auth.sessions where user_id = p_user_id;
  exception when undefined_table or undefined_column then
    null;
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- request_account_deletion — same as 09, with the "ban the user" step replaced
-- by release_account_identity() (which still bans, and now also anonymises).
-- Existing grants are kept by `create or replace`.
-- ----------------------------------------------------------------------------
create or replace function public.request_account_deletion()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  target_id uuid := auth.uid();
begin
  if target_id is null then
    raise exception 'Not authenticated';
  end if;

  update public.items
  set deleted_at = now()
  where user_id = target_id and deleted_at is null;

  update public.profiles
  set full_name = null,
      username = null,
      avatar_url = null,
      phone = null,
      fcm_token = null,
      deleted_at = now()
  where id = target_id;

  perform public.release_account_identity(target_id, now());
end;
$$;

-- ----------------------------------------------------------------------------
-- Enforcing the block at sign-up. A BEFORE INSERT trigger on auth.users, so it
-- covers every way an account can be created (password, Google, ...), not just
-- the screen that happens to ask first. When it fires, Supabase reports a
-- generic "Database error saving new user" — which is why the app asks
-- signup_email_status() below BEFORE signing up, to show a proper message.
-- ----------------------------------------------------------------------------
create or replace function public.enforce_email_reuse_block()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.email is not null and exists (
    select 1 from public.email_reuse_blocks b
    where b.email_hash = public.email_fingerprint(new.email)
      and (b.blocked_until is null or b.blocked_until > now())
  ) then
    raise exception 'This email cannot be used to create an account right now.';
  end if;
  return new;
end;
$$;

drop trigger if exists a_enforce_email_reuse_block on auth.users;
create trigger a_enforce_email_reuse_block
  before insert on auth.users
  for each row execute function public.enforce_email_reuse_block();

-- ----------------------------------------------------------------------------
-- signup_email_status — what the sign-up screen asks before calling signUp().
-- Returns ONE row only when the email is currently blocked (retry_at null =
-- permanently), and NO rows otherwise. Callable by signed-out users on
-- purpose. It does reveal that an address was recently deleted or blocked,
-- and nothing about any other address — a deliberate trade for being able to
-- say something more useful than "Database error saving new user".
-- ----------------------------------------------------------------------------
create or replace function public.signup_email_status(p_email text)
returns table (blocked boolean, retry_at timestamptz)
language sql
stable
security definer set search_path = public
as $$
  select true, b.blocked_until
  from public.email_reuse_blocks b
  where b.email_hash = public.email_fingerprint(p_email)
    and (b.blocked_until is null or b.blocked_until > now())
  limit 1;
$$;

grant execute on function public.signup_email_status(text) to anon, authenticated;

-- ----------------------------------------------------------------------------
-- block_email — for the SQL editor: stop an address being used to sign up,
-- e.g. after removing an abusive account. Permanent by default; pass a number
-- of days for a temporary block. (Banning the existing account is separate —
-- this only stops the address being registered again.)
--
--   select public.block_email('someone@example.com');       -- permanent
--   select public.block_email('someone@example.com', 90);   -- 90 days
-- ----------------------------------------------------------------------------
create or replace function public.block_email(p_email text, p_days integer default null)
returns void
language sql
security definer set search_path = public
as $$
  insert into public.email_reuse_blocks (email_hash, reason, blocked_until)
  values (
    public.email_fingerprint(p_email),
    'moderation',
    case when p_days is null then null else now() + make_interval(days => p_days) end
  )
  on conflict (email_hash) do update
  set reason = 'moderation', blocked_until = excluded.blocked_until;
$$;

-- ----------------------------------------------------------------------------
-- One-off backfill: accounts deleted under the OLD behaviour (09) still hold
-- their email. This anonymises them the same way; their cooldown counts from
-- when they were actually deleted, so older ones are free immediately.
-- Safe to run any number of times. Runs once automatically at the end of this
-- file.
-- ----------------------------------------------------------------------------
create or replace function public.release_previously_deleted_emails()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  r record;
  released integer := 0;
begin
  for r in
    select p.id, p.deleted_at
    from public.profiles p
    join auth.users u on u.id = p.id
    where p.deleted_at is not null
      and u.email is not null
      and u.email not like 'deleted-%@deleted.invalid'
  loop
    perform public.release_account_identity(r.id, r.deleted_at);
    released := released + 1;
  end loop;
  return released;
end;
$$;

-- Internal building blocks: never reachable through PostgREST's /rpc.
revoke all on function public.release_account_identity(uuid, timestamptz)
  from public, anon, authenticated;
revoke all on function public.release_previously_deleted_emails()
  from public, anon, authenticated;
revoke all on function public.block_email(text, integer) from public, anon, authenticated;
revoke all on function public.email_fingerprint(text) from public, anon, authenticated;
revoke all on function public.enforce_email_reuse_block() from public, anon, authenticated;

select public.release_previously_deleted_emails();

-- ============================================================================
-- Verify (optional) — run one at a time:
--
--   -- the sign-up block is installed:
--   select tgname from pg_trigger
--   where tgrelid = 'auth.users'::regclass and tgname = 'a_enforce_email_reuse_block';
--
--   -- deleted accounts now hold placeholders, not real addresses:
--   select email, banned_until from auth.users where email like 'deleted-%';
--
--   -- emails currently unavailable (hashes only):
--   select reason, blocked_until from public.email_reuse_blocks;
-- ============================================================================
