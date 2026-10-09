-- ============================================================================
-- Findora — Phase 0 hardening: row-level rules that also constrain WHAT may be
-- written, not just WHO may write. Run after 16_release_email_on_delete.sql.
-- Safe to re-run. TRY IT ON A STAGING PROJECT FIRST (see the end of this file
-- for how to check it, and supabase/tests/17_policy_checks.sql).
--
-- Why this exists: the publishable key ships inside the APK, so anyone can talk
-- to your API directly with it. Until now many policies said "the owner may
-- update this row" without saying which columns, e.g.:
--   * any user could set profiles.is_admin = true  (-> become an admin);
--   * phone numbers and push tokens of every user were readable by anyone;
--   * ratings could be written for any person/item;
--   * claims could be inserted already "approved";
--   * messages could be inserted into matches you aren't part of, and edited
--     by their receiver;
--   * either side of a match could re-point it at someone else's item;
--   * soft-deleted / admin-removed posts were still served by the API, and
--     their owner could un-delete them.
--
-- The tools used below, so the pattern is clear for future tables:
--   1. Column-level GRANTs  (profiles)         - only listed columns are writable.
--   2. RPC functions        (ratings, matches) - the client calls a function that
--      validates the action, and has no direct write access to the table.
--   3. Triggers that only fire for API roles   - `current_user` is 'authenticated'
--      for a direct API write but the function OWNER inside a security-definer
--      function, so mark_returned() and friends are not affected.
--   4. WITH CHECK clauses                      - constrain the values of new rows.
--
-- NOTE for the app: this migration changes where phone / push token live
-- (public.profile_private) and how ratings and match decisions are written
-- (submit_rating(), decide_match()). The matching app changes ship with it —
-- install the updated app (and redeploy the send-push-notification function)
-- before or right after running this file. Older app versions will fail to
-- save a phone/push token and to rate/confirm matches.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 0. Helpers
-- ----------------------------------------------------------------------------

-- Is the caller an admin? SECURITY DEFINER so it can read profiles regardless
-- of the caller's own access, and so policies can use one cheap call.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select coalesce(
    (select p.is_admin from public.profiles p where p.id = auth.uid()),
    false
  );
$$;

revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

-- True when the statement comes straight from the API (PostgREST) rather than
-- from inside one of our SECURITY DEFINER functions or from the SQL editor.
create or replace function public.is_api_caller()
returns boolean
language sql
stable
as $$
  select current_user in ('authenticated', 'anon');
$$;


-- ----------------------------------------------------------------------------
-- 1. profiles
--    a) phone + push token move to profile_private (owner-only);
--    b) only display columns stay writable by clients, so is_admin / rating /
--       rating_count / deleted_at can no longer be set from the API;
--    c) reading profiles requires being signed in.
-- ----------------------------------------------------------------------------
create table if not exists public.profile_private (
  id uuid primary key references public.profiles (id) on delete cascade,
  phone text,
  fcm_token text,
  updated_at timestamptz not null default now(),
  constraint profile_private_phone_len check (phone is null or char_length(phone) <= 32)
);

alter table public.profile_private enable row level security;

drop policy if exists "owners can read their private profile" on public.profile_private;
create policy "owners can read their private profile"
  on public.profile_private for select to authenticated
  using ((select auth.uid()) = id);

drop policy if exists "owners can create their private profile" on public.profile_private;
create policy "owners can create their private profile"
  on public.profile_private for insert to authenticated
  with check ((select auth.uid()) = id);

drop policy if exists "owners can update their private profile" on public.profile_private;
create policy "owners can update their private profile"
  on public.profile_private for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

drop policy if exists "owners can delete their private profile" on public.profile_private;
create policy "owners can delete their private profile"
  on public.profile_private for delete to authenticated
  using ((select auth.uid()) = id);

revoke all on public.profile_private from anon;

-- Carry existing values over, then drop the public columns. Guarded so the
-- file can be re-run after the columns are gone.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles'
      and column_name in ('phone', 'fcm_token')
  ) then
    insert into public.profile_private (id, phone, fcm_token)
    select p.id, p.phone, p.fcm_token
    from public.profiles p
    where p.phone is not null or p.fcm_token is not null
    on conflict (id) do update
      set phone = coalesce(public.profile_private.phone, excluded.phone),
          fcm_token = coalesce(public.profile_private.fcm_token, excluded.fcm_token);
  end if;
end $$;

alter table public.profiles drop column if exists phone;
alter table public.profiles drop column if exists fcm_token;

-- Clients may write ONLY these columns of their own row.
revoke update on public.profiles from anon, authenticated;
grant update (full_name, username, avatar_url) on public.profiles to authenticated;

-- Reading profiles: signed-in users only (names/avatars/ratings are shown on
-- posts, but there is no reason for signed-out API callers to enumerate them).
drop policy if exists "profiles are viewable by everyone" on public.profiles;
drop policy if exists "profiles are viewable by signed-in users" on public.profiles;
create policy "profiles are viewable by signed-in users"
  on public.profiles for select to authenticated using (true);

drop policy if exists "users can update their own profile" on public.profiles;
create policy "users can update their own profile"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- request_account_deletion (from 16) — identical except that phone and push
-- token are now removed from profile_private instead of nulled on profiles.
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

  perform public.release_account_identity(target_id, now());
end;
$$;


-- ----------------------------------------------------------------------------
-- 2. items / item_images
--    a) removed (soft-deleted) posts are no longer served to other people;
--    b) clients can't change who owns a post, restore a removed post, or set
--       lifecycle fields (status, returned_*) — those change only through the
--       claim/return functions and triggers;
--    c) basic length limits.
-- ----------------------------------------------------------------------------
drop policy if exists "items are viewable unless returned" on public.items;
drop policy if exists "items are viewable unless returned or removed" on public.items;
create policy "items are viewable unless returned or removed"
  on public.items for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.is_admin())
    or (
      deleted_at is null
      and (status <> 'resolved' or returned_with_user_id = (select auth.uid()))
    )
  );

drop policy if exists "item images are viewable with their post" on public.item_images;
create policy "item images are viewable with their post"
  on public.item_images for select to authenticated
  using (exists (select 1 from public.items i where i.id = item_id));

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
       or new.returned_with_user_id is not null then
      raise exception 'New posts must start open.' using errcode = '42501';
    end if;
    return new;
  end if;

  if new.user_id is distinct from old.user_id then
    raise exception 'A post cannot be moved to another owner.' using errcode = '42501';
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

drop trigger if exists items_protect_lifecycle on public.items;
create trigger items_protect_lifecycle
  before insert or update on public.items
  for each row execute function public.protect_item_lifecycle();

-- NOT VALID: enforced for every new/updated row, without failing on any old
-- row that is already longer. Run `alter table ... validate constraint ...`
-- later if you want the old rows checked too.
do $$ begin
  alter table public.items
    add constraint items_title_len check (char_length(btrim(title)) between 1 and 120) not valid;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.items
    add constraint items_description_len check (description is null or char_length(description) <= 2000) not valid;
exception when duplicate_object then null; end $$;


-- ----------------------------------------------------------------------------
-- 3. ratings — only through submit_rating()
-- ----------------------------------------------------------------------------
drop policy if exists "users can rate as themselves" on public.ratings;
revoke insert, update, delete on public.ratings from anon, authenticated;

do $$ begin
  alter table public.ratings
    add constraint ratings_comment_len check (comment is null or char_length(comment) <= 500) not valid;
exception when duplicate_object then null; end $$;

-- Rate the other person in a completed return. p_item_id is the FOUND post of
-- the returned pair (what the chat screen already has); who is rated is worked
-- out here from the return itself, never taken from the caller.
create or replace function public.submit_rating(
  p_item_id uuid,
  p_stars integer,
  p_comment text default null
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  me uuid := auth.uid();
  it public.items%rowtype;
  ratee uuid;
  cleaned text;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_stars is null or p_stars < 1 or p_stars > 5 then
    raise exception 'Choose between 1 and 5 stars.' using errcode = '22023';
  end if;

  select * into it from public.items where id = p_item_id;
  if not found then
    raise exception 'That post no longer exists.' using errcode = 'P0002';
  end if;
  if it.status <> 'resolved' or it.returned_with_user_id is null then
    raise exception 'You can rate someone once the item has been returned.' using errcode = '22023';
  end if;

  if it.user_id = me then
    ratee := it.returned_with_user_id;
  elsif it.returned_with_user_id = me then
    ratee := it.user_id;
  else
    raise exception 'Only the two people involved in this return can rate each other.'
      using errcode = '42501';
  end if;

  cleaned := nullif(btrim(coalesce(p_comment, '')), '');
  if cleaned is not null and char_length(cleaned) > 500 then
    raise exception 'Keep the comment under 500 characters.' using errcode = '22023';
  end if;

  insert into public.ratings (item_id, rater_id, ratee_id, stars, comment)
  values (p_item_id, me, ratee, p_stars, cleaned);
exception
  when unique_violation then
    raise exception 'You have already rated this return.' using errcode = '23505';
end;
$$;

revoke all on function public.submit_rating(uuid, integer, text) from public, anon;
grant execute on function public.submit_rating(uuid, integer, text) to authenticated;


-- ----------------------------------------------------------------------------
-- 4. claims
--    a) a new claim must be "pending", for a still-open FOUND post, by someone
--       with a confirmed match to it (the app only ever offers claiming from
--       a confirmed match's chat);
--    b) one live (pending/approved) claim per person per post;
--    c) the owner can decide a pending claim — and change nothing else.
-- ----------------------------------------------------------------------------
create or replace function public.can_file_claim(p_item_id uuid, p_claimant uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1
    from public.items found_item
    join public.matches m
      on m.status = 'confirmed'
     and (m.item_a_id = found_item.id or m.item_b_id = found_item.id)
    join public.items lost_item
      on lost_item.id = case when m.item_a_id = found_item.id then m.item_b_id else m.item_a_id end
    where found_item.id = p_item_id
      and found_item.type = 'found'
      and found_item.deleted_at is null
      and found_item.status in ('open', 'matched')
      and found_item.user_id <> p_claimant
      and lost_item.user_id = p_claimant
      and lost_item.type = 'lost'
      and lost_item.deleted_at is null
  );
$$;

revoke all on function public.can_file_claim(uuid, uuid) from public, anon;
grant execute on function public.can_file_claim(uuid, uuid) to authenticated;

drop policy if exists "users can file their own claims" on public.claims;
create policy "users can file their own claims"
  on public.claims for insert to authenticated
  with check (
    (select auth.uid()) = claimant_id
    and status = 'pending'
    and public.can_file_claim(item_id, claimant_id)
  );

do $$ begin
  create unique index claims_one_live_claim_per_claimant
    on public.claims (item_id, claimant_id)
    where status in ('pending', 'approved');
exception when unique_violation then
  raise notice 'Skipped claims_one_live_claim_per_claimant: duplicate live claims already exist. Resolve them, then re-run this file.';
end $$;

do $$ begin
  alter table public.claims
    add constraint claims_answer_len
    check (verification_answer is null or char_length(verification_answer) <= 500) not valid;
exception when duplicate_object then null; end $$;

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
     or new.created_at is distinct from old.created_at then
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

drop trigger if exists claims_protect_fields on public.claims;
create trigger claims_protect_fields
  before update on public.claims
  for each row execute function public.protect_claim_fields();


-- ----------------------------------------------------------------------------
-- 5. matches — decisions only through decide_match()
-- ----------------------------------------------------------------------------
drop policy if exists "item owners can update their matches" on public.matches;
revoke update, insert, delete on public.matches from anon, authenticated;

-- status: 'confirmed' | 'dismissed' | 'pending' ("pending" is Undo). Only an
-- owner of one of the two posts may decide, and a confirmed match can't be
-- taken back once a claim exists or the item is claimed/returned (the app
-- checks this too, to explain it nicely; this is the part that can't be
-- bypassed).
create or replace function public.decide_match(p_match_id uuid, p_status text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  me uuid := auth.uid();
  m public.matches%rowtype;
  a public.items%rowtype;
  b public.items%rowtype;
  found_item public.items%rowtype;
  lost_item public.items%rowtype;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_status not in ('pending', 'confirmed', 'dismissed') then
    raise exception 'Unknown match status.' using errcode = '22023';
  end if;

  select * into m from public.matches where id = p_match_id;
  if not found then
    raise exception 'That match no longer exists.' using errcode = 'P0002';
  end if;
  select * into a from public.items where id = m.item_a_id;
  select * into b from public.items where id = m.item_b_id;
  if a.user_id is distinct from me and b.user_id is distinct from me then
    raise exception 'This match is not yours to decide.' using errcode = '42501';
  end if;

  if m.status = p_status then
    return;
  end if;

  if m.status = 'confirmed' and p_status <> 'confirmed' then
    if a.type = 'found' and b.type = 'lost' then
      found_item := a; lost_item := b;
    elsif b.type = 'found' and a.type = 'lost' then
      found_item := b; lost_item := a;
    end if;

    if found_item.id is not null and (
      exists (
        select 1 from public.claims c
        where c.item_id = found_item.id and c.claimant_id = lost_item.user_id
      )
      or found_item.status in ('claimed', 'resolved')
      or lost_item.status in ('claimed', 'resolved')
    ) then
      raise exception 'A claim has already been filed for this match, so it can no longer be undone.'
        using errcode = '22023';
    end if;
  end if;

  update public.matches set status = p_status where id = p_match_id;
end;
$$;

revoke all on function public.decide_match(uuid, text) from public, anon;
grant execute on function public.decide_match(uuid, text) to authenticated;


-- ----------------------------------------------------------------------------
-- 6. messages / contact_messages
--    a) you can only message inside a CONFIRMED match you are part of, and
--       only the other person in it;
--    b) after sending, only read_at can change;
--    c) length limit.
-- ----------------------------------------------------------------------------
create or replace function public.is_confirmed_match_pair(
  p_match_id uuid,
  p_sender uuid,
  p_receiver uuid
)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1
    from public.matches m
    join public.items a on a.id = m.item_a_id
    join public.items b on b.id = m.item_b_id
    where m.id = p_match_id
      and m.status = 'confirmed'
      and (
        (a.user_id = p_sender and b.user_id = p_receiver)
        or (a.user_id = p_receiver and b.user_id = p_sender)
      )
  );
$$;

revoke all on function public.is_confirmed_match_pair(uuid, uuid, uuid) from public, anon;
grant execute on function public.is_confirmed_match_pair(uuid, uuid, uuid) to authenticated;

drop policy if exists "users can send messages as themselves" on public.messages;
create policy "users can send messages as themselves"
  on public.messages for insert to authenticated
  with check (
    (select auth.uid()) = sender_id
    and public.is_confirmed_match_pair(match_id, sender_id, receiver_id)
  );

create or replace function public.protect_message_immutable_fields()
returns trigger
language plpgsql
as $$
begin
  if public.is_api_caller() and (
       new.content is distinct from old.content
    or new.sender_id is distinct from old.sender_id
    or new.receiver_id is distinct from old.receiver_id
    or new.match_id is distinct from old.match_id
    or new.created_at is distinct from old.created_at
  ) then
    raise exception 'Only read_at can be updated on an existing message' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists messages_protect_immutable_fields on public.messages;
create trigger messages_protect_immutable_fields
  before update on public.messages
  for each row execute function public.protect_message_immutable_fields();

do $$ begin
  alter table public.messages
    add constraint messages_content_len check (char_length(content) between 1 and 2000) not valid;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.contact_messages
    add constraint contact_messages_content_len check (char_length(content) between 1 and 2000) not valid;
exception when duplicate_object then null; end $$;


-- ----------------------------------------------------------------------------
-- 7. reports — start "open", one open report per person per post, length cap
-- ----------------------------------------------------------------------------
drop policy if exists "users can file their own reports" on public.reports;
create policy "users can file their own reports"
  on public.reports for insert to authenticated
  with check ((select auth.uid()) = reporter_id and status = 'open');

do $$ begin
  create unique index reports_one_open_per_reporter
    on public.reports (reporter_id, item_id)
    where status = 'open';
exception when unique_violation then
  raise notice 'Skipped reports_one_open_per_reporter: duplicate open reports already exist. Dismiss the extras, then re-run this file.';
end $$;

do $$ begin
  alter table public.reports
    add constraint reports_reason_len check (char_length(reason) between 1 and 500) not valid;
exception when duplicate_object then null; end $$;


-- ----------------------------------------------------------------------------
-- 8. Storage — size / type limits, and let people remove their own avatar
-- ----------------------------------------------------------------------------
update storage.buckets
set file_size_limit = 10485760,  -- 10 MB
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
where id in ('item-images', 'avatars');

drop policy if exists "users can delete their own avatar" on storage.objects;
create policy "users can delete their own avatar"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );


-- ----------------------------------------------------------------------------
-- 9. Signed-out API access: this app has no signed-out screens that read
--    tables (sign-in/sign-up use the auth endpoints and signup_email_status()).
--    Remove the signed-out role's direct table access as a second line of
--    defence behind the policies above. If you later add a public page that
--    reads a table, grant just that table back.
-- ----------------------------------------------------------------------------
revoke all on all tables in schema public from anon;

-- ============================================================================
-- Verify (optional) — see supabase/tests/17_policy_checks.sql for an automated
-- check, or by hand:
--
--   -- no update policy left on matches, no rating/claim self-approval, etc.:
--   select tablename, policyname, cmd, roles from pg_policies
--   where schemaname = 'public' order by 1, 2;
--
--   -- profiles no longer has phone / fcm_token / writable is_admin:
--   select column_name from information_schema.columns
--   where table_schema = 'public' and table_name = 'profiles';
--
--   -- who is an admin right now (should be only people you expect):
--   select id, full_name from public.profiles where is_admin;
-- ============================================================================
