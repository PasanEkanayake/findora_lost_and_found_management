-- ============================================================================
-- Findora — Push tokens per DEVICE, not per person
-- Run this after 20_chat_safety.sql. Safe to re-run.
--
-- Until now each person had ONE push token (profile_private.fcm_token), so:
--   * signing in on a second phone silently switched notifications OFF on the
--     first one (the newer token overwrote the older);
--   * a phone passed on to someone else could keep receiving the previous
--     owner's notifications if it was never signed out cleanly.
-- Now every device is its own row in device_tokens, owned by whoever is signed
-- in on it. A token can only ever belong to one person at a time — signing in
-- as someone else on the same phone moves it — and a person can have as many
-- devices as they like. The send-push-notification Edge Function sends to all
-- of a person's devices and deletes tokens Firebase says are dead.
-- ============================================================================

create table if not exists public.device_tokens (
  token text primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  platform text not null default 'android',
  updated_at timestamptz not null default now(),
  constraint device_tokens_token_len check (char_length(token) between 20 and 4096)
);

create index if not exists device_tokens_user_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;
revoke all on public.device_tokens from anon;
-- Written only through the two functions below (they handle the "this phone
-- used to belong to someone else" case, which a plain INSERT policy can't).
revoke insert, update, delete on public.device_tokens from authenticated;

drop policy if exists "people can see their own devices" on public.device_tokens;
create policy "people can see their own devices"
  on public.device_tokens for select to authenticated
  using ((select auth.uid()) = user_id);

-- Called by the app whenever it learns this device's token (sign-in, token
-- refresh, turning notifications back on). Takes the token over if another
-- account was last signed in on this phone.
create or replace function public.register_device_token(p_token text, p_platform text default 'android')
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  insert into public.device_tokens (token, user_id, platform)
  values (p_token, auth.uid(), coalesce(nullif(btrim(p_platform), ''), 'android'))
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
end;
$$;

-- Called on sign-out and when notifications are switched off on this device.
-- Only removes the caller's own row for that token.
create or replace function public.unregister_device_token(p_token text)
returns void
language sql
security definer set search_path = public
as $$
  delete from public.device_tokens
  where token = p_token and user_id = auth.uid();
$$;

revoke all on function public.register_device_token(text, text) from public, anon;
revoke all on function public.unregister_device_token(text) from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated;
grant execute on function public.unregister_device_token(text) to authenticated;

-- Carry over the old single tokens, then retire the column.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profile_private' and column_name = 'fcm_token'
  ) then
    insert into public.device_tokens (token, user_id)
    select pp.fcm_token, pp.id
    from public.profile_private pp
    join public.profiles p on p.id = pp.id and p.deleted_at is null
    where pp.fcm_token is not null and char_length(pp.fcm_token) between 20 and 4096
    on conflict (token) do nothing;
  end if;
end $$;

alter table public.profile_private drop column if exists fcm_token;

-- request_account_deletion (from 17) — identical, plus: a deleted account's
-- devices stop receiving anything.
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
      deleted_at = now()
  where id = target_id;

  delete from public.profile_private where id = target_id;
  delete from public.device_tokens where user_id = target_id;

  perform public.release_account_identity(target_id, now());
end;
$$;

-- ============================================================================
-- Verify (optional):
--   select user_id, platform, updated_at from public.device_tokens order by updated_at desc;
-- Also redeploy the Edge Function (it now reads device_tokens):
--   supabase functions deploy send-push-notification
-- ============================================================================
