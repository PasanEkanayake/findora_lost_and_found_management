-- ============================================================================
-- Findora — Upgrade: in-app Notifications tab
-- Run this after 13_returned_items_and_ratings.sql. Safe to re-run.
--
-- Adds a `notifications` table and the triggers that fill it, covering six
-- events, each written from exactly one place so none can be missed or
-- duplicated:
--   - new_match         — a new match is found             (upsert_match_score, 12_text_matching.sql)
--   - match_confirmed   — the *other* owner taps "This is it!" (new trigger on matches)
--   - claim_filed       — someone files a claim              (new trigger on claims)
--   - claim_approved / claim_rejected — the finder decides   (new trigger on claims)
--   - item_returned     — mark_returned() resolves both posts (mark_returned, 13_returned_items_and_ratings.sql)
--   - new_rating        — someone leaves a rating            (new trigger on ratings)
--
-- Deliberately NOT covered: individual chat messages. The Chats tab is
-- already the notification mechanism for those (preview + unread count per
-- conversation) — duplicating every message as a notification row too would
-- make this table the most frequently-written table in the app for no real
-- benefit, and would bury the less-frequent events above under message
-- noise. This table is for things that happen a handful of times per item,
-- not dozens of times per conversation.
-- ============================================================================

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  type text not null, -- new_match | match_confirmed | claim_filed | claim_approved | claim_rejected | item_returned | new_rating
  title text not null,
  body text,
  -- Which post to open for this notification — always the *recipient's
  -- own* item, so a single `/item/:id` (or `/item/:id/matches`) link works
  -- the same way for every type without needing to know whose item is
  -- whose. match_id/claim_id/rating_id are carried for reference/future use
  -- even where the client doesn't currently route on them.
  item_id uuid references public.items (id) on delete set null,
  match_id uuid references public.matches (id) on delete set null,
  claim_id uuid references public.claims (id) on delete set null,
  rating_id uuid references public.ratings (id) on delete set null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_idx
  on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;

drop policy if exists "users can view their own notifications" on public.notifications;
create policy "users can view their own notifications"
  on public.notifications for select using (auth.uid() = user_id);

-- The only field a client ever legitimately changes is read_at, and only
-- on their own notifications (marking one, or all, as read). There's no
-- INSERT policy at all: every row is written by a SECURITY DEFINER
-- function below, which bypasses RLS by design — a plain client INSERT is
-- correctly rejected, which is what keeps this list trustworthy (a client
-- can't forge a notification claiming to be from someone else).
drop policy if exists "users can mark their own notifications read" on public.notifications;
create policy "users can mark their own notifications read"
  on public.notifications for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ----------------------------------------------------------------------------
-- create_notification — the one place every trigger/function below actually
-- writes a row, so the insert shape only needs to be right in one place.
-- ----------------------------------------------------------------------------
create or replace function public.create_notification(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text default null,
  p_item_id uuid default null,
  p_match_id uuid default null,
  p_claim_id uuid default null,
  p_rating_id uuid default null
)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.notifications (user_id, type, title, body, item_id, match_id, claim_id, rating_id)
  values (p_user_id, p_type, p_title, p_body, p_item_id, p_match_id, p_claim_id, p_rating_id);
end;
$$;

revoke all on function public.create_notification(uuid, text, text, text, uuid, uuid, uuid, uuid)
  from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- upsert_match_score — redefined again (from 12_text_matching.sql) to
-- notify both owners the moment a genuinely *new* match row is created.
-- Only the insert branch notifies — re-scoring an existing pair (a photo
-- arriving later, say) enriches silently, the same as before this
-- migration, since that isn't new information worth a notification.
-- ----------------------------------------------------------------------------
create or replace function public.upsert_match_score(
  p_item_a uuid,
  p_item_b uuid,
  p_image_similarity real,
  p_text_similarity real
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  a public.items%rowtype;
  b public.items%rowtype;
  gps_sim real;
  time_sim real;
  dist real;
  existing_id uuid;
  v_new_id uuid;
begin
  select * into a from public.items where id = p_item_a;
  if not found then return; end if;
  select * into b from public.items where id = p_item_b;
  if not found then return; end if;

  gps_sim := public.gps_proximity_score(a.location, b.location);
  time_sim := public.time_proximity_score(a.event_time, b.event_time);
  dist := case when a.location is not null and b.location is not null
    then st_distance(a.location, b.location)::real
    else null
  end;

  select id into existing_id from public.matches
  where (item_a_id = p_item_a and item_b_id = p_item_b)
     or (item_a_id = p_item_b and item_b_id = p_item_a)
  limit 1;

  if existing_id is not null then
    update public.matches m
    set
      image_similarity = coalesce(p_image_similarity, m.image_similarity),
      text_similarity = coalesce(p_text_similarity, m.text_similarity),
      distance_meters = dist,
      time_proximity = time_sim,
      similarity_score = public.combined_match_score(
        coalesce(p_image_similarity, m.image_similarity),
        coalesce(p_text_similarity, m.text_similarity),
        gps_sim,
        time_sim
      )
    where m.id = existing_id;
  else
    insert into public.matches (
      item_a_id, item_b_id, image_similarity, text_similarity,
      distance_meters, time_proximity, similarity_score
    ) values (
      p_item_a, p_item_b, p_image_similarity, p_text_similarity,
      dist, time_sim,
      public.combined_match_score(p_image_similarity, p_text_similarity, gps_sim, time_sim)
    )
    on conflict (item_a_id, item_b_id) do nothing -- race safety only
    returning id into v_new_id;

    -- v_new_id is null if the on-conflict branch actually fired (another
    -- concurrent call won the race) — in that case this call found
    -- nothing new, so there's nothing to notify about.
    if v_new_id is not null then
      perform public.create_notification(
        a.user_id, 'new_match',
        'New match: "' || b.title || '"',
        'Compared with your "' || a.title || '".',
        a.id, v_new_id
      );
      perform public.create_notification(
        b.user_id, 'new_match',
        'New match: "' || a.title || '"',
        'Compared with your "' || b.title || '".',
        b.id, v_new_id
      );
    end if;
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- notify_match_confirmed — fires when a match's status becomes
-- 'confirmed' (MatchCard's "This is it!" / ItemsRepository.updateStatus,
-- a plain client update, not an RPC — a trigger is the only hook available
-- for it). Notifies whichever of the two owners *didn't* just do that —
-- the person who tapped the button already knows.
-- ----------------------------------------------------------------------------
create or replace function public.notify_match_confirmed()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  a_user uuid;
  a_title text;
  b_user uuid;
  b_title text;
begin
  if new.status = 'confirmed' and old.status is distinct from 'confirmed' then
    select user_id, title into a_user, a_title from public.items where id = new.item_a_id;
    select user_id, title into b_user, b_title from public.items where id = new.item_b_id;

    if a_user is not null and a_user <> auth.uid() then
      perform public.create_notification(
        a_user, 'match_confirmed',
        'Match confirmed: "' || coalesce(b_title, 'a post') || '"',
        'You can chat about it now.',
        new.item_a_id, new.id
      );
    end if;
    if b_user is not null and b_user <> auth.uid() then
      perform public.create_notification(
        b_user, 'match_confirmed',
        'Match confirmed: "' || coalesce(a_title, 'a post') || '"',
        'You can chat about it now.',
        new.item_b_id, new.id
      );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists matches_notify_confirmed on public.matches;
create trigger matches_notify_confirmed
  after update on public.matches
  for each row execute function public.notify_match_confirmed();

-- ----------------------------------------------------------------------------
-- notify_claim_filed / notify_claim_decision — the found item's owner
-- learns a claim arrived; the claimant learns the decision.
-- ----------------------------------------------------------------------------
create or replace function public.notify_claim_filed()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  owner_id uuid;
  item_title text;
begin
  select user_id, title into owner_id, item_title from public.items where id = new.item_id;
  if owner_id is not null then
    perform public.create_notification(
      owner_id, 'claim_filed',
      'New claim on "' || coalesce(item_title, 'your post') || '"',
      'Open the chat to review it.',
      new.item_id, null, new.id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists claims_notify_filed on public.claims;
create trigger claims_notify_filed
  after insert on public.claims
  for each row execute function public.notify_claim_filed();

create or replace function public.notify_claim_decision()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  item_title text;
begin
  if new.status in ('approved', 'rejected') and old.status is distinct from new.status then
    select title into item_title from public.items where id = new.item_id;
    perform public.create_notification(
      new.claimant_id,
      case when new.status = 'approved' then 'claim_approved' else 'claim_rejected' end,
      case when new.status = 'approved'
        then 'Claim approved: "' || coalesce(item_title, 'the post') || '"'
        else 'Claim not approved: "' || coalesce(item_title, 'the post') || '"'
      end,
      case when new.status = 'approved'
        then 'Arrange to get it back, then mark it as returned in the chat.'
        else 'You can file a new claim with a different detail.'
      end,
      new.item_id, null, new.id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists claims_notify_decision on public.claims;
create trigger claims_notify_decision
  after update on public.claims
  for each row execute function public.notify_claim_decision();

-- ----------------------------------------------------------------------------
-- notify_new_rating — the ratee learns they were rated. Shares the
-- "coalesce(full_name, username, 'Findora user')" display-name fallback
-- used throughout 13_returned_items_and_ratings.sql.
-- ----------------------------------------------------------------------------
create or replace function public.notify_new_rating()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  rater_name text;
begin
  select coalesce(full_name, username, 'Findora user') into rater_name
  from public.profiles where id = new.rater_id;

  perform public.create_notification(
    new.ratee_id, 'new_rating',
    'New rating from ' || coalesce(rater_name, 'Findora user'),
    new.stars::text || ' star' || (case when new.stars = 1 then '' else 's' end) ||
      case when new.comment is not null and new.comment <> ''
        then ': "' || new.comment || '"'
        else ''
      end,
    new.item_id, null, null, new.id
  );
  return new;
end;
$$;

drop trigger if exists ratings_notify_new on public.ratings;
create trigger ratings_notify_new
  after insert on public.ratings
  for each row execute function public.notify_new_rating();

-- ----------------------------------------------------------------------------
-- mark_returned — redefined again (from 13_returned_items_and_ratings.sql)
-- to notify both owners once the return is recorded. Everything above the
-- final two UPDATEs is unchanged from migration 13.
-- ----------------------------------------------------------------------------
create or replace function public.mark_returned(
  p_found_item_id uuid,
  p_lost_item_id uuid
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  found_item public.items%rowtype;
  lost_item public.items%rowtype;
  found_owner_name text;
  lost_owner_name text;
begin
  select * into found_item from public.items where id = p_found_item_id;
  if not found then
    raise exception 'That found post no longer exists.' using errcode = 'P0002';
  end if;
  select * into lost_item from public.items where id = p_lost_item_id;
  if not found then
    raise exception 'That lost post no longer exists.' using errcode = 'P0002';
  end if;

  if found_item.user_id is distinct from auth.uid() then
    raise exception 'Only the person who posted the found item can mark it as returned.'
      using errcode = '42501';
  end if;
  if found_item.type <> 'found' or lost_item.type <> 'lost' then
    raise exception 'A return needs one found post and one lost post.' using errcode = '22023';
  end if;
  if found_item.user_id = lost_item.user_id then
    raise exception 'Both posts belong to the same person.' using errcode = '22023';
  end if;

  -- Already done for exactly this pair: nothing to do.
  if found_item.status = 'resolved' and found_item.returned_with_item_id = lost_item.id then
    return;
  end if;

  if found_item.deleted_at is not null or lost_item.deleted_at is not null then
    raise exception 'One of the posts has been removed.' using errcode = '22023';
  end if;
  if found_item.status = 'resolved' or lost_item.status = 'resolved' then
    raise exception 'One of these posts was already returned.' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.claims c
    where c.item_id = found_item.id
      and c.claimant_id = lost_item.user_id
      and c.status = 'approved'
  ) then
    raise exception 'Approve the other person''s claim before marking this as returned.'
      using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.matches m
    where m.status = 'confirmed'
      and ((m.item_a_id = found_item.id and m.item_b_id = lost_item.id)
        or (m.item_a_id = lost_item.id and m.item_b_id = found_item.id))
  ) then
    raise exception 'These two posts are not a confirmed match.' using errcode = '22023';
  end if;

  update public.items
  set status = 'resolved',
      resolved_at = now(),
      returned_with_item_id = lost_item.id,
      returned_with_user_id = lost_item.user_id
  where id = found_item.id;

  update public.items
  set status = 'resolved',
      resolved_at = now(),
      returned_with_item_id = found_item.id,
      returned_with_user_id = found_item.user_id
  where id = lost_item.id;

  select coalesce(full_name, username, 'the other person') into found_owner_name
    from public.profiles where id = found_item.user_id;
  select coalesce(full_name, username, 'the other person') into lost_owner_name
    from public.profiles where id = lost_item.user_id;

  perform public.create_notification(
    found_item.user_id, 'item_returned',
    'Returned: "' || found_item.title || '"',
    'You can rate ' || coalesce(lost_owner_name, 'the other person') || ' now.',
    found_item.id
  );
  perform public.create_notification(
    lost_item.user_id, 'item_returned',
    'Returned: "' || lost_item.title || '"',
    'You can rate ' || coalesce(found_owner_name, 'the other person') || ' now.',
    lost_item.id
  );
end;
$$;

-- ============================================================================
-- Verify (optional) — run these one at a time after the above:
--
--   -- should return true for all:
--   select
--     exists (select 1 from information_schema.tables
--             where table_name = 'notifications') as has_table,
--     exists (select 1 from pg_proc where proname = 'create_notification')
--       as has_helper_fn,
--     exists (select 1 from pg_trigger
--             where tgname = 'matches_notify_confirmed') as has_match_trigger,
--     exists (select 1 from pg_trigger
--             where tgname = 'claims_notify_filed') as has_claim_trigger,
--     exists (select 1 from pg_trigger
--             where tgname = 'ratings_notify_new') as has_rating_trigger;
--
--   -- your own notifications, newest first:
--   select type, title, body, read_at, created_at
--   from public.notifications
--   where user_id = auth.uid()
--   order by created_at desc;
-- ============================================================================
