-- ============================================================================
-- Findora — extensions and core tables
-- Run this file first in the Supabase SQL editor (or via `supabase db push`).
-- ============================================================================

-- pgvector powers the AI similarity search between item photo embeddings.
create extension if not exists vector;

-- PostGIS powers "items near me" radius queries.
create extension if not exists postgis;

-- ----------------------------------------------------------------------------
-- profiles — one row per Supabase Auth user, created automatically by the
-- trigger defined in 02_functions_and_triggers.sql
-- ----------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text unique,
  full_name text,
  avatar_url text,
  phone text,
  rating numeric(3, 2) not null default 0,
  rating_count integer not null default 0,
  fcm_token text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

-- Phase 7/8 additions — no-ops on a fresh install, only matter if you ran
-- this file earlier.
alter table public.profiles add column if not exists fcm_token text;
alter table public.profiles add column if not exists is_admin boolean not null default false;

-- ----------------------------------------------------------------------------
-- categories — seeded once, referenced by items and by the on-device
-- model's label set so the classifier's output maps directly onto a row.
-- ----------------------------------------------------------------------------
create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  icon text
);

insert into public.categories (name, icon) values
  ('Electronics', 'devices'),
  ('Bags', 'work_outline'),
  ('Pets', 'pets'),
  ('Documents', 'badge'),
  ('Keys', 'key'),
  ('Jewelry', 'diamond'),
  ('Clothing', 'checkroom'),
  ('Other', 'category')
on conflict (name) do nothing;

-- ----------------------------------------------------------------------------
-- items — one row per lost/found report
-- ----------------------------------------------------------------------------
do $$ begin
  create type public.item_type as enum ('lost', 'found');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.item_status as enum ('open', 'matched', 'claimed', 'resolved');
exception when duplicate_object then null;
end $$;

create table if not exists public.items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  category_id uuid references public.categories (id),
  type public.item_type not null,
  status public.item_status not null default 'open',
  title text not null,
  description text,
  location geography(point, 4326),
  location_label text,
  event_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists items_location_idx on public.items using gist (location);
create index if not exists items_category_idx on public.items (category_id);
create index if not exists items_status_idx on public.items (status);

-- ----------------------------------------------------------------------------
-- item_images — one row per photo; `embedding` is the on-device model's
-- output vector, uploaded instead of raw pixels for the similarity search.
-- The dimension (1280) matches MobileNetV2's penultimate layer — change it
-- if you ship a different feature-extractor model.
-- ----------------------------------------------------------------------------
create table if not exists public.item_images (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items (id) on delete cascade,
  image_url text not null,
  embedding vector(1280),
  predicted_label text,
  confidence real,
  created_at timestamptz not null default now()
);

-- HNSW doesn't need pre-populated data to build efficiently, unlike ivfflat,
-- which makes it the better default while your table is still small.
create index if not exists item_images_embedding_idx
  on public.item_images using hnsw (embedding vector_cosine_ops);

-- ----------------------------------------------------------------------------
-- matches — candidate pairs surfaced by the similarity search RPC
-- ----------------------------------------------------------------------------
create table if not exists public.matches (
  id uuid primary key default gen_random_uuid(),
  item_a_id uuid not null references public.items (id) on delete cascade,
  item_b_id uuid not null references public.items (id) on delete cascade,
  similarity_score real not null,
  status text not null default 'pending', -- pending | confirmed | dismissed
  created_at timestamptz not null default now(),
  constraint matches_distinct_items check (item_a_id <> item_b_id),
  constraint matches_unique_pair unique (item_a_id, item_b_id)
);

-- ----------------------------------------------------------------------------
-- messages — in-app chat. Scoped to a match, not a single item, since a
-- conversation is fundamentally between the two people on either side of
-- a match — not about one item in isolation.
-- ----------------------------------------------------------------------------
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  match_id uuid references public.matches (id) on delete cascade,
  sender_id uuid not null references public.profiles (id),
  receiver_id uuid not null references public.profiles (id),
  content text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

-- Phase 7 replaced this table's original `item_id` column with `match_id`.
-- On a fresh install these are no-ops. If you ran this file before Phase 7
-- and already have rows in `messages`, run `truncate table public.messages;`
-- first — there's no production data at stake yet at this point in the build.
alter table public.messages add column if not exists match_id uuid references public.matches(id) on delete cascade;
alter table public.messages drop column if exists item_id;
alter table public.messages alter column match_id set not null;

create index if not exists messages_match_idx on public.messages (match_id, created_at);

-- ----------------------------------------------------------------------------
-- claims — verification workflow before contact info is shared
-- ----------------------------------------------------------------------------
create table if not exists public.claims (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items (id) on delete cascade,
  claimant_id uuid not null references public.profiles (id),
  verification_answer text,
  status text not null default 'pending', -- pending | approved | rejected
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- reports — moderation/flagging
-- ----------------------------------------------------------------------------
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items (id) on delete cascade,
  reporter_id uuid not null references public.profiles (id),
  reason text not null,
  status text not null default 'open', -- open | reviewed | dismissed
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- ratings — one row per completed return, so trust scores have an audit
-- trail instead of being a bare mutable counter. profiles.rating and
-- rating_count stay as a fast-read cache, kept in sync by a trigger in
-- 02_functions_and_triggers.sql rather than computed on every profile read.
-- ----------------------------------------------------------------------------
create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items (id) on delete cascade,
  rater_id uuid not null references public.profiles (id),
  ratee_id uuid not null references public.profiles (id),
  stars smallint not null check (stars between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  constraint ratings_one_per_item_rater unique (item_id, rater_id)
);
