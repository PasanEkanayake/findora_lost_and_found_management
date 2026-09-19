-- ============================================================================
-- Findora — Upgrade: soft-delete items instead of removing rows
-- Run this after 07_email_confirmation.sql.
--
-- Deleting a post (My Items, item detail's owner menu) and an admin
-- removing a flagged item both used to run a real `delete from items`.
-- That's now considered too risky for a "one tap, are-you-sure" action:
-- accidental taps, disputes over a moderation call, or wanting to recover
-- something a user regrets deleting all need the row to still exist
-- somewhere. This migration switches both paths to a soft delete instead:
-- the row stays in the table forever (unless someone manually hard-deletes
-- it later), just flagged as inactive and filtered out of every
-- user-facing query.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- items.deleted_at — null means active/visible; a timestamp means "hidden
-- from the app as of this moment", not "gone". A nullable timestamptz
-- rather than a boolean, so *when* something was removed is preserved too
-- (useful for exactly the "unexpected situations" this is for — e.g.
-- figuring out whether a deletion lines up with a support request).
-- ----------------------------------------------------------------------------
alter table public.items add column if not exists deleted_at timestamptz;

create index if not exists items_deleted_at_idx on public.items (deleted_at);

-- ----------------------------------------------------------------------------
-- Hard deletes are no longer how the app removes an item (see
-- ItemsRepository.deleteItem / AdminRepository.removeItem, both now doing
-- an update instead) — dropping these policies enforces that at the
-- database level too, so a real `delete` on `items` fails outright even if
-- someone calls the Supabase client directly with a valid session,
-- bypassing the app entirely. Nothing else in the app issues a `delete`
-- against this table.
-- ----------------------------------------------------------------------------
drop policy if exists "users can delete their own items" on public.items;
drop policy if exists "admins can delete any item" on public.items;

-- ----------------------------------------------------------------------------
-- match_items — same candidate search as before, now also excluding
-- soft-deleted items so a removed item never surfaces as a new match
-- candidate going forward.
-- ----------------------------------------------------------------------------
create or replace function public.match_items(
  query_embedding vector(1280),
  source_item_id uuid,
  match_category_id uuid default null,
  match_threshold float default 0.75,
  match_count int default 10
)
returns table (
  item_id uuid,
  image_id uuid,
  title text,
  similarity float
)
language sql
stable
as $$
  select
    i.id as item_id,
    img.id as image_id,
    i.title,
    1 - (img.embedding <=> query_embedding) as similarity
  from public.item_images img
  join public.items i on i.id = img.item_id
  where i.id <> source_item_id
    and i.user_id <> (select user_id from public.items where id = source_item_id)
    and i.type <> (select type from public.items where id = source_item_id)
    and i.status = 'open'
    and i.deleted_at is null
    and (match_category_id is null or i.category_id = match_category_id)
    and 1 - (img.embedding <=> query_embedding) >= match_threshold
  order by img.embedding <=> query_embedding
  limit match_count;
$$;

-- ----------------------------------------------------------------------------
-- my_matches — excludes matches where either side has since been deleted.
-- Deliberately different from my_conversations() below, which leaves
-- deleted items' chat history reachable — a *pending* match (not yet
-- acted on) against a now-deleted item is just noise to clean up, but an
-- already-confirmed conversation is history worth keeping visible.
-- ----------------------------------------------------------------------------
drop function if exists public.my_matches();

create function public.my_matches()
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
  order by m.created_at desc;
$$;

-- ----------------------------------------------------------------------------
-- nearby_items — the map view's radius search, now excluding soft-deleted
-- items the same way the list view (fetchOpenItems, filtered client-side
-- via `.filter('deleted_at', 'is', null)`) already does.
-- ----------------------------------------------------------------------------
drop function if exists public.nearby_items(double precision, double precision, int);

create function public.nearby_items(
  center_lat double precision,
  center_lng double precision,
  radius_meters int default 5000
)
returns table (
  id uuid,
  title text,
  type public.item_type,
  category_name text,
  location_label text,
  latitude double precision,
  longitude double precision,
  image_url text,
  created_at timestamptz
)
language sql
stable
as $$
  select
    i.id,
    i.title,
    i.type,
    c.name as category_name,
    i.location_label,
    st_y(i.location::geometry) as latitude,
    st_x(i.location::geometry) as longitude,
    (
      select img.image_url from public.item_images img
      where img.item_id = i.id
      order by img.created_at
      limit 1
    ) as image_url,
    i.created_at
  from public.items i
  left join public.categories c on c.id = i.category_id
  where i.status = 'open'
    and i.deleted_at is null
    and i.location is not null
    and st_dwithin(
      i.location,
      st_setsrid(st_makepoint(center_lng, center_lat), 4326)::geography,
      radius_meters
    );
$$;

-- ----------------------------------------------------------------------------
-- get_item_coordinates — defense-in-depth: ItemsRepository.fetchItemById
-- already excludes deleted items client-side, so this normally never runs
-- for one, but the function is safe to call directly too.
-- ----------------------------------------------------------------------------
create or replace function public.get_item_coordinates(p_item_id uuid)
returns table (latitude double precision, longitude double precision)
language sql
stable
as $$
  select st_y(location::geometry), st_x(location::geometry)
  from public.items
  where id = p_item_id and location is not null and deleted_at is null;
$$;
