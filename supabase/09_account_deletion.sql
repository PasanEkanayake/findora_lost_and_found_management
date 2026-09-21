-- ============================================================================
-- Findora — Upgrade: self-service account deletion
-- Run this after 08_soft_delete.sql.
--
-- "Delete my account" can't be a real `delete from auth.users` here, for
-- the same reason item deletion isn't a real `delete from items` (see
-- 08_soft_delete.sql's header): `profiles.id references auth.users(id)
-- on delete cascade`, so hard-deleting the auth user would cascade-delete
-- their profile — and everything else in the app (matches, chats,
-- reports, other people's contact threads) that references that id by
-- foreign key would be left pointing at nothing, breaking *other* users'
-- history, not just this one's.
--
-- Instead, "delete account" here means: soft-delete everything they
-- posted (same items.deleted_at flag the per-item delete uses), scrub
-- their profile's personal fields (their name/photo/phone disappear
-- everywhere they're shown — chats, item posts — falling back to the
-- generic "Findora user" label already used elsewhere for this exact
-- case), and block the account from signing in again. The row itself
-- survives, same "recoverable, not erased" reasoning as item deletion.
-- ============================================================================

alter table public.profiles add column if not exists deleted_at timestamptz;

-- ----------------------------------------------------------------------------
-- request_account_deletion — callable directly by a signed-in user for
-- their own account (there's no "delete someone else's account" version
-- of this: target_id always comes from auth.uid(), never a parameter, so
-- there's nothing for a malicious caller to point at another user's id).
--
-- The `update auth.users set banned_until = ...` line is what actually
-- blocks future sign-ins — the same mechanism (and the same `banned_until`
-- column) the Admin API's "ban user" endpoint uses, reachable here
-- directly in SQL because `security definer` runs this function as its
-- owner (whichever role ran this migration — the SQL Editor's `postgres`
-- role has full access to the `auth` schema), not as the calling user,
-- without needing a service-role key or an Edge Function.
--
-- Already-issued JWTs for this session aren't instantly invalidated just
-- by this update (they're stateless, validated by signature/expiry, not
-- a live DB check on every request) — ProfileScreen calls
-- `supabase.auth.signOut()` right after this RPC returns, so the current
-- session ends immediately rather than relying solely on the ban to take
-- effect on next refresh.
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

  update auth.users
  set banned_until = (now() + interval '100 years')
  where id = target_id;
end;
$$;
