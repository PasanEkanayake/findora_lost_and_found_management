-- ============================================================================
-- Findora — Upgrade: returned items leave every list; ratings & reviews
-- Run this after 12_text_matching.sql. Safe to re-run.
--
-- What this does
--   1. When a found item is handed back, BOTH posts (the found one and the
--      lost one it was matched with) become 'resolved' together, through
--      mark_returned() — previously only the found post was ever resolved,
--      so the matching lost post kept appearing in the feed and kept being
--      offered as a match to other people's found posts.
--   2. A resolved post is then visible only to its two owners (row level
--      security on items and item_images), so it can't show up in
--      anyone else's feed, search, map, matches, or chats — and can't
--      confuse matching for other posts.
--   3. Adds my_returned_items() (the profile's "Returned items" section)
--      and my_ratings() (the profile's "Ratings & reviews" section).
--   4. Tightens ratings: the written reviews were readable by any signed-in
--      user; now only the two people involved can read a rating. Each
--      profile's average and review COUNT are still public — those live on
--      profiles.rating / rating_count, which is separate.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Columns: when it was returned, and which post/person it was returned
--    with. Both posts of a returned pair point at each other.
-- ----------------------------------------------------------------------------
alter table public.items add column if not exists resolved_at timestamptz;
alter table public.items add column if not exists returned_with_item_id uuid
  references public.items (id) on delete set null;
alter table public.items add column if not exists returned_with_user_id uuid
  references public.profiles (id) on delete set null;

create index if not exists items_returned_with_user_idx
  on public.items (returned_with_user_id)
  where returned_with_user_id is not null;

-- ----------------------------------------------------------------------------
-- 2) Backfill: posts already marked resolved before this migration.
--    Old code only resolved the FOUND post and never recorded who it went
--    to. Where an approved claim + a confirmed match identify the lost post
--    unambiguously enough, link the pair (and resolve the lost post too, to
--    match how returns work from now on). A found post that can't be
--    paired stays resolved with no counterpart — its owner still sees it
--    under Returned items; nobody else can see it.
-- ----------------------------------------------------------------------------
update public.items
set resolved_at = updated_at
where status = 'resolved' and resolved_at is null;

update public.items f
set returned_with_item_id = l.id,
    returned_with_user_id = l.user_id
from public.claims c, public.matches m, public.items l
where f.status = 'resolved'
  and f.type = 'found'
  and f.returned_with_item_id is null
  and c.item_id = f.id
  and c.status = 'approved'
  and m.status = 'confirmed'
  and f.id in (m.item_a_id, m.item_b_id)
  and l.id in (m.item_a_id, m.item_b_id)
  and l.id <> f.id
  and l.type = 'lost'
  and l.user_id = c.claimant_id;

update public.items l
set status = 'resolved',
    resolved_at = f.resolved_at,
    returned_with_item_id = f.id,
    returned_with_user_id = f.user_id
from public.items f
where f.returned_with_item_id = l.id
  and l.returned_with_item_id is null
  and l.type = 'lost';

-- ----------------------------------------------------------------------------
-- 3) Visibility. Replaces "items are viewable by everyone".
--    A resolved post is visible to: its owner, the owner of the post it was
--    returned with, and admins (moderation still needs to see reported
--    posts). Everything that reads items as the signed-in user — the feed,
--    search, the map's nearby_items(), my_matches(), my_conversations(),
--    my_contact_threads() — inherits this automatically, since those all
--    run with the caller's permissions.
-- ----------------------------------------------------------------------------
drop policy if exists "items are viewable by everyone" on public.items;
drop policy if exists "items are viewable unless returned" on public.items;
create policy "items are viewable unless returned"
  on public.items for select using (
    status <> 'resolved'
    or auth.uid() = user_id
    or auth.uid() = returned_with_user_id
    or exists (select 1 from public.profiles where id = auth.uid() and is_admin = true)
  );

-- A photo is visible exactly when its post is. (The subquery is itself
-- subject to the items policy above.)
drop policy if exists "item images are viewable by everyone" on public.item_images;
drop policy if exists "item images are viewable with their post" on public.item_images;
create policy "item images are viewable with their post"
  on public.item_images for select using (
    exists (select 1 from public.items i where i.id = item_id)
  );

-- ----------------------------------------------------------------------------
-- 4) Ratings: only the two people involved can read a rating and its
--    comment. Averages stay public through profiles.rating/rating_count.
-- ----------------------------------------------------------------------------
drop policy if exists "ratings are viewable by everyone" on public.ratings;
drop policy if exists "ratings are viewable by the two people involved" on public.ratings;
create policy "ratings are viewable by the two people involved"
  on public.ratings for select using (
    auth.uid() = rater_id or auth.uid() = ratee_id
  );

-- ----------------------------------------------------------------------------
-- 5) mark_returned — the ONLY way a post becomes 'resolved'.
--    Resolves both posts in one step, after checking that the return is
--    real: the caller owns the found post, there's an approved claim on it
--    by the lost post's owner, and the two posts have a confirmed match.
--    Idempotent: calling it again for an already-returned pair is a no-op.
--
--    `is distinct from` rather than `<>` below is deliberate: with no
--    signed-in user auth.uid() is null, and `x <> null` is null (not true),
--    which would silently skip the check instead of failing it.
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
end;
$$;

revoke all on function public.mark_returned(uuid, uuid) from public, anon;
grant execute on function public.mark_returned(uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 6) my_matches — as in 10_open_matching_and_time.sql, plus: a match
--    involving a returned post is over, so it leaves the Matches tab (the
--    returned pair moves to Returned items instead). Same columns, so
--    `create or replace` is enough.
-- ----------------------------------------------------------------------------
create or replace function public.my_matches()
returns table (
  match_id uuid,
  my_item_id uuid,
  my_item_title text,
  matched_item_id uuid,
  matched_item_title text,
  matched_item_type public.item_type,
  matched_item_image_url text,
  matched_item_user_id uuid,
  similarity_score real,
  image_similarity real,
  text_similarity real,
  distance_meters real,
  time_proximity real,
  match_status text,
  created_at timestamptz
)
language sql
stable
as $$
  select
    m.id,
    mine.id,
    mine.title,
    theirs.id,
    theirs.title,
    theirs.type,
    (
      select img.image_url from public.item_images img
      where img.item_id = theirs.id
      order by img.created_at
      limit 1
    ),
    theirs.user_id,
    m.similarity_score,
    m.image_similarity,
    m.text_similarity,
    m.distance_meters,
    m.time_proximity,
    m.status,
    m.created_at
  from public.matches m
  join public.items a on a.id = m.item_a_id
  join public.items b on b.id = m.item_b_id
  join public.items mine on mine.id = (case when a.user_id = auth.uid() then a.id else b.id end)
  join public.items theirs on theirs.id = (case when a.user_id = auth.uid() then b.id else a.id end)
  where (a.user_id = auth.uid() or b.user_id = auth.uid())
    and a.deleted_at is null
    and b.deleted_at is null
    and a.status <> 'resolved'
    and b.status <> 'resolved'
  order by m.created_at desc;
$$;

-- ----------------------------------------------------------------------------
-- 7) my_returned_items — the caller's own returned posts, each with the
--    post it was returned with. One row per returned post the caller owns.
--    Left joins on purpose: a returned post from before this migration may
--    have no counterpart recorded (see the backfill above) and must still
--    be listed.
-- ----------------------------------------------------------------------------
drop function if exists public.my_returned_items();

create function public.my_returned_items()
returns table (
  my_item_id uuid,
  my_item_title text,
  my_item_type public.item_type,
  my_item_image_url text,
  other_item_id uuid,
  other_item_title text,
  other_item_type public.item_type,
  other_item_image_url text,
  other_user_id uuid,
  other_user_name text,
  match_id uuid,
  resolved_at timestamptz,
  stars_i_gave smallint,
  stars_i_received smallint
)
language sql
stable
as $$
  select
    mine.id,
    mine.title,
    mine.type,
    (
      select img.image_url from public.item_images img
      where img.item_id = mine.id
      order by img.created_at
      limit 1
    ),
    theirs.id,
    theirs.title,
    theirs.type,
    (
      select img.image_url from public.item_images img
      where img.item_id = theirs.id
      order by img.created_at
      limit 1
    ),
    mine.returned_with_user_id,
    coalesce(p.full_name, p.username, 'Findora user'),
    (
      select m.id from public.matches m
      where (m.item_a_id = mine.id and m.item_b_id = theirs.id)
         or (m.item_a_id = theirs.id and m.item_b_id = mine.id)
      order by (m.status = 'confirmed') desc
      limit 1
    ),
    coalesce(mine.resolved_at, mine.updated_at),
    (
      select r.stars from public.ratings r
      where r.item_id = f.found_id and r.rater_id = auth.uid()
    ),
    (
      select r.stars from public.ratings r
      where r.item_id = f.found_id and r.ratee_id = auth.uid()
    )
  from public.items mine
  left join public.items theirs on theirs.id = mine.returned_with_item_id
  left join public.profiles p on p.id = mine.returned_with_user_id
  cross join lateral (
    select case when mine.type = 'found' then mine.id else mine.returned_with_item_id end
      as found_id
  ) f
  where mine.user_id = auth.uid()
    and mine.status = 'resolved'
    and mine.deleted_at is null
  order by coalesce(mine.resolved_at, mine.updated_at) desc;
$$;

-- ----------------------------------------------------------------------------
-- 8) my_ratings — every rating the caller received or gave, newest first,
--    with the other person's name and the item it was about.
-- ----------------------------------------------------------------------------
drop function if exists public.my_ratings();

create function public.my_ratings()
returns table (
  rating_id uuid,
  direction text,
  stars smallint,
  comment text,
  created_at timestamptz,
  other_user_id uuid,
  other_user_name text,
  item_id uuid,
  item_title text
)
language sql
stable
as $$
  select
    r.id,
    case when r.ratee_id = auth.uid() then 'received' else 'given' end,
    r.stars,
    r.comment,
    r.created_at,
    case when r.ratee_id = auth.uid() then r.rater_id else r.ratee_id end,
    coalesce(p.full_name, p.username, 'Findora user'),
    r.item_id,
    i.title
  from public.ratings r
  join public.profiles p
    on p.id = (case when r.ratee_id = auth.uid() then r.rater_id else r.ratee_id end)
  left join public.items i on i.id = r.item_id
  where r.ratee_id = auth.uid() or r.rater_id = auth.uid()
  order by r.created_at desc;
$$;

-- ============================================================================
-- Verify (optional) — run these one at a time after the above:
--
--   -- should return true for all three:
--   select
--     exists (select 1 from pg_proc where proname = 'mark_returned') as has_mark_returned,
--     exists (select 1 from pg_policies
--             where tablename = 'items'
--               and policyname = 'items are viewable unless returned') as has_items_policy,
--     exists (select 1 from information_schema.columns
--             where table_name = 'items' and column_name = 'returned_with_item_id')
--       as has_columns;
--
--   -- how many posts are currently hidden from the public feed:
--   select count(*) from public.items where status = 'resolved';
-- ============================================================================
