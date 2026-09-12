-- ============================================================================
-- Findora — functions and triggers
-- Run this after 01_extensions_and_tables.sql.
-- ============================================================================

-- Auto-creates a `profiles` row whenever someone signs up through Supabase
-- Auth, so the rest of the schema can assume every auth user has one.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, full_name, avatar_url)
  values (
    new.id,
    split_part(new.email, '@', 1),
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'avatar_url'
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Keeps items.updated_at current on every edit.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists items_set_updated_at on public.items;
create trigger items_set_updated_at
  before update on public.items
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- match_items — the core AI matching query. Given the embedding for a photo
-- just uploaded, find the closest photos belonging to *opposite-type* items
-- (a "lost" report should surface "found" candidates and vice versa),
-- excluding the reporter's own items, ranked by cosine distance and
-- optionally narrowed by category to cut down on false positives.
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
    and (match_category_id is null or i.category_id = match_category_id)
    and 1 - (img.embedding <=> query_embedding) >= match_threshold
  order by img.embedding <=> query_embedding
  limit match_count;
$$;

-- ----------------------------------------------------------------------------
-- record_matches_for_image — runs match_items() automatically whenever a
-- photo with an embedding is uploaded, and writes any candidates straight
-- into `matches`. This is what turns "we have a similarity search
-- function" into "matches actually appear" without every client needing
-- to remember to call it — it fires no matter which screen, platform, or
-- future admin tool inserts the row.
--
-- security definer because the inserting user only has an INSERT policy
-- on their own item_images, not automatically on `matches` — this
-- function runs as its owner so the resulting match rows can be written
-- regardless of whose row triggered it.
-- ----------------------------------------------------------------------------
create or replace function public.record_matches_for_image()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  source_item public.items%rowtype;
begin
  if new.embedding is null then
    return new;
  end if;

  select * into source_item from public.items where id = new.item_id;

  insert into public.matches (item_a_id, item_b_id, similarity_score)
  select source_item.id, candidate.item_id, candidate.similarity
  from public.match_items(
    new.embedding,
    source_item.id,
    source_item.category_id,
    0.75,
    5
  ) as candidate
  on conflict (item_a_id, item_b_id) do nothing;

  return new;
end;
$$;

drop trigger if exists item_images_record_matches on public.item_images;
create trigger item_images_record_matches
  after insert on public.item_images
  for each row execute function public.record_matches_for_image();

-- ----------------------------------------------------------------------------
-- my_matches — resolves `matches` rows (which just store two item ids)
-- into "my item" vs "the matched item" from the caller's perspective, plus
-- the matched item's title/type/first photo, so the client can render a
-- match card in one query instead of several round trips.
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
    m.status,
    m.created_at
  from public.matches m
  join public.items a on a.id = m.item_a_id
  join public.items b on b.id = m.item_b_id
  join public.items mine on mine.id = (case when a.user_id = auth.uid() then a.id else b.id end)
  join public.items theirs on theirs.id = (case when a.user_id = auth.uid() then b.id else a.id end)
  where a.user_id = auth.uid() or b.user_id = auth.uid()
  order by m.created_at desc;
$$;

-- ----------------------------------------------------------------------------
-- nearby_items — radius search using PostGIS, for the map view. Returns
-- plain lat/lng doubles (via st_y/st_x) rather than the raw geography
-- column, since that doesn't serialize predictably over PostgREST — plus
-- category name and first photo so the client can build a map marker in
-- one query.
--
-- The explicit drop is required because this replaces an earlier version
-- of the function that returned `setof items` — Postgres allows
-- `create or replace` to change a function's body, but not its return
-- type, so a straight `create or replace` here would error on a database
-- that already has the old version.
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
    and i.location is not null
    and st_dwithin(
      i.location,
      st_setsrid(st_makepoint(center_lng, center_lat), 4326)::geography,
      radius_meters
    );
$$;

-- ----------------------------------------------------------------------------
-- my_conversations — one row per *confirmed* match the caller is part of,
-- with the other side's item, the most recent message (if any), and an
-- unread count. Chat is deliberately gated behind a confirmed match, not
-- available the moment a candidate match appears — see Phase 5's notes on
-- why "confirmed" needed a next step.
-- ----------------------------------------------------------------------------
create or replace function public.my_conversations()
returns table (
  match_id uuid,
  my_item_id uuid,
  matched_item_id uuid,
  matched_item_title text,
  matched_item_type public.item_type,
  matched_item_image_url text,
  other_user_id uuid,
  last_message text,
  last_message_at timestamptz,
  unread_count bigint
)
language sql
stable
as $$
  select
    m.id as match_id,
    mine.id as my_item_id,
    theirs.id as matched_item_id,
    theirs.title as matched_item_title,
    theirs.type as matched_item_type,
    (
      select img.image_url from public.item_images img
      where img.item_id = theirs.id
      order by img.created_at
      limit 1
    ) as matched_item_image_url,
    theirs.user_id as other_user_id,
    latest.content as last_message,
    latest.created_at as last_message_at,
    (
      select count(*) from public.messages msg
      where msg.match_id = m.id
        and msg.receiver_id = auth.uid()
        and msg.read_at is null
    ) as unread_count
  from public.matches m
  join public.items a on a.id = m.item_a_id
  join public.items b on b.id = m.item_b_id
  join public.items mine on mine.id = (case when a.user_id = auth.uid() then a.id else b.id end)
  join public.items theirs on theirs.id = (case when a.user_id = auth.uid() then b.id else a.id end)
  left join lateral (
    select content, created_at
    from public.messages msg2
    where msg2.match_id = m.id
    order by msg2.created_at desc
    limit 1
  ) latest on true
  where (a.user_id = auth.uid() or b.user_id = auth.uid())
    and m.status = 'confirmed'
  order by coalesce(latest.created_at, m.created_at) desc;
$$;

-- ----------------------------------------------------------------------------
-- handle_claim_approved — once an item owner approves a claim, the item
-- moves to 'claimed' automatically, rather than relying on the client to
-- remember a second write. "Claimed" is a distinct state from "resolved":
-- claimed means ownership is verified, resolved means the handoff
-- actually happened (see ChatScreen's "Mark as returned").
-- ----------------------------------------------------------------------------
create or replace function public.handle_claim_approved()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    update public.items set status = 'claimed' where id = new.item_id;
  end if;
  return new;
end;
$$;

drop trigger if exists claims_handle_approved on public.claims;
create trigger claims_handle_approved
  after update on public.claims
  for each row execute function public.handle_claim_approved();

-- ----------------------------------------------------------------------------
-- handle_new_rating — recomputes a profile's aggregate rating/rating_count
-- from the `ratings` table whenever a new rating comes in, so those
-- columns never drift from the actual rows backing them.
-- ----------------------------------------------------------------------------
create or replace function public.handle_new_rating()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update public.profiles
  set
    rating = (select avg(stars)::numeric(3, 2) from public.ratings where ratee_id = new.ratee_id),
    rating_count = (select count(*) from public.ratings where ratee_id = new.ratee_id)
  where id = new.ratee_id;
  return new;
end;
$$;

drop trigger if exists ratings_handle_new on public.ratings;
create trigger ratings_handle_new
  after insert on public.ratings
  for each row execute function public.handle_new_rating();
