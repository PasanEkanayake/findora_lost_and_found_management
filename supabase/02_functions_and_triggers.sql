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
  insert into public.profiles (id, username, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'username', split_part(new.email, '@', 1)),
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
    and i.type <> (select type from public.items where id = source_item_id)
    and i.status = 'open'
    and (match_category_id is null or i.category_id = match_category_id)
    and 1 - (img.embedding <=> query_embedding) >= match_threshold
  order by img.embedding <=> query_embedding
  limit match_count;
$$;

-- ----------------------------------------------------------------------------
-- nearby_items — simple radius search using PostGIS, for the map/browse view.
-- ----------------------------------------------------------------------------
create or replace function public.nearby_items(
  center_lat double precision,
  center_lng double precision,
  radius_meters int default 5000
)
returns setof public.items
language sql
stable
as $$
  select *
  from public.items
  where status = 'open'
    and st_dwithin(
      location,
      st_setsrid(st_makepoint(center_lng, center_lat), 4326)::geography,
      radius_meters
    );
$$;
