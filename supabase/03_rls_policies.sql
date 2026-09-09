-- ============================================================================
-- Findora — Row Level Security
-- Every table holding user data needs RLS enabled, or the publishable key
-- can read and write everything regardless of who's signed in.
-- Run this after 02_functions_and_triggers.sql.
--
-- Every `create policy` below is preceded by `drop policy if exists`.
-- Postgres has no `create policy if not exists`, so without the drop,
-- re-running this file against a database that already has these
-- policies fails with "policy already exists" instead of quietly no-op'ing
-- the way `create table if not exists` / `create or replace function`
-- do elsewhere in these scripts.
-- ============================================================================

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.items enable row level security;
alter table public.item_images enable row level security;
alter table public.matches enable row level security;
alter table public.messages enable row level security;
alter table public.claims enable row level security;
alter table public.reports enable row level security;
alter table public.ratings enable row level security;

-- profiles: everyone can read (needed to show poster names/avatars on
-- items), only the owner can edit their own row.
drop policy if exists "profiles are viewable by everyone" on public.profiles;
create policy "profiles are viewable by everyone"
  on public.profiles for select using (true);

drop policy if exists "users can update their own profile" on public.profiles;
create policy "users can update their own profile"
  on public.profiles for update using (auth.uid() = id);

-- categories: read-only reference data, writable only via the dashboard
-- or a service-role key (never from the client).
drop policy if exists "categories are viewable by everyone" on public.categories;
create policy "categories are viewable by everyone"
  on public.categories for select using (true);

-- items: anyone signed in can browse open items; only the owner can
-- insert/update/delete their own.
drop policy if exists "items are viewable by everyone" on public.items;
create policy "items are viewable by everyone"
  on public.items for select using (true);

drop policy if exists "users can insert their own items" on public.items;
create policy "users can insert their own items"
  on public.items for insert with check (auth.uid() = user_id);

drop policy if exists "users can update their own items" on public.items;
create policy "users can update their own items"
  on public.items for update using (auth.uid() = user_id);

drop policy if exists "users can delete their own items" on public.items;
create policy "users can delete their own items"
  on public.items for delete using (auth.uid() = user_id);

-- Moderation: admins (profiles.is_admin) can update or remove any item,
-- on top of the owner-only policies above — RLS policies for the same
-- command are OR'd together, so this adds admin access without loosening
-- what regular users can do.
drop policy if exists "admins can update any item" on public.items;
create policy "admins can update any item"
  on public.items for update using (
    exists (select 1 from public.profiles where id = auth.uid() and is_admin = true)
  );

drop policy if exists "admins can delete any item" on public.items;
create policy "admins can delete any item"
  on public.items for delete using (
    exists (select 1 from public.profiles where id = auth.uid() and is_admin = true)
  );

-- item_images: viewable by everyone (matching needs to compare across all
-- users' photos); only the owning item's user can add/remove images.
drop policy if exists "item images are viewable by everyone" on public.item_images;
create policy "item images are viewable by everyone"
  on public.item_images for select using (true);

drop policy if exists "users can add images to their own items" on public.item_images;
create policy "users can add images to their own items"
  on public.item_images for insert with check (
    exists (
      select 1 from public.items
      where items.id = item_images.item_id and items.user_id = auth.uid()
    )
  );

drop policy if exists "users can delete images from their own items" on public.item_images;
create policy "users can delete images from their own items"
  on public.item_images for delete using (
    exists (
      select 1 from public.items
      where items.id = item_images.item_id and items.user_id = auth.uid()
    )
  );

-- matches: visible only to the two item owners involved. Update is opened
-- up (not insert) so either side can confirm/dismiss a candidate match
-- via MatchesScreen — inserts only ever come from the
-- `record_matches_for_image` trigger, which runs as its owner.
drop policy if exists "matches are viewable by the item owners" on public.matches;
create policy "matches are viewable by the item owners"
  on public.matches for select using (
    exists (
      select 1 from public.items
      where items.id in (matches.item_a_id, matches.item_b_id)
        and items.user_id = auth.uid()
    )
  );

drop policy if exists "item owners can update their matches" on public.matches;
create policy "item owners can update their matches"
  on public.matches for update using (
    exists (
      select 1 from public.items
      where items.id in (matches.item_a_id, matches.item_b_id)
        and items.user_id = auth.uid()
    )
  );

-- messages: only sender and receiver can read or write.
drop policy if exists "messages are viewable by sender and receiver" on public.messages;
create policy "messages are viewable by sender and receiver"
  on public.messages for select using (
    auth.uid() = sender_id or auth.uid() = receiver_id
  );

drop policy if exists "users can send messages as themselves" on public.messages;
create policy "users can send messages as themselves"
  on public.messages for insert with check (auth.uid() = sender_id);

drop policy if exists "receivers can mark messages as read" on public.messages;
create policy "receivers can mark messages as read"
  on public.messages for update using (auth.uid() = receiver_id);

-- claims: the claimant and the item's owner can both see a claim; only the
-- claimant can create it, only the owner can approve/reject it.
drop policy if exists "claims are viewable by claimant and item owner" on public.claims;
create policy "claims are viewable by claimant and item owner"
  on public.claims for select using (
    auth.uid() = claimant_id
    or exists (
      select 1 from public.items
      where items.id = claims.item_id and items.user_id = auth.uid()
    )
  );

drop policy if exists "users can file their own claims" on public.claims;
create policy "users can file their own claims"
  on public.claims for insert with check (auth.uid() = claimant_id);

drop policy if exists "item owners can update claims on their items" on public.claims;
create policy "item owners can update claims on their items"
  on public.claims for update using (
    exists (
      select 1 from public.items
      where items.id = claims.item_id and items.user_id = auth.uid()
    )
  );

-- reports: reporter can see their own report; inserts must be self-attributed.
drop policy if exists "users can view their own reports" on public.reports;
create policy "users can view their own reports"
  on public.reports for select using (auth.uid() = reporter_id);

drop policy if exists "users can file their own reports" on public.reports;
create policy "users can file their own reports"
  on public.reports for insert with check (auth.uid() = reporter_id);

-- Moderation: admins can see and act on every report, not just their own.
drop policy if exists "admins can view all reports" on public.reports;
create policy "admins can view all reports"
  on public.reports for select using (
    exists (select 1 from public.profiles where id = auth.uid() and is_admin = true)
  );

drop policy if exists "admins can update reports" on public.reports;
create policy "admins can update reports"
  on public.reports for update using (
    exists (select 1 from public.profiles where id = auth.uid() and is_admin = true)
  );

-- ratings: viewable by everyone (that's the point — trust signals on a
-- profile), but only insertable as yourself. Not restricted here to only
-- items you actually completed a return on; the app only ever offers the
-- rating dialog after a "mark as returned" action, so this is a
-- reasonable trust boundary for now rather than a hard guarantee.
drop policy if exists "ratings are viewable by everyone" on public.ratings;
create policy "ratings are viewable by everyone"
  on public.ratings for select using (true);

drop policy if exists "users can rate as themselves" on public.ratings;
create policy "users can rate as themselves"
  on public.ratings for insert with check (auth.uid() = rater_id);
