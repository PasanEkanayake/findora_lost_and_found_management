-- ============================================================================
-- Findora — Row Level Security
-- Every table holding user data needs RLS enabled, or the publishable key
-- can read and write everything regardless of who's signed in.
-- Run this after 02_functions_and_triggers.sql.
-- ============================================================================

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.items enable row level security;
alter table public.item_images enable row level security;
alter table public.matches enable row level security;
alter table public.messages enable row level security;
alter table public.claims enable row level security;
alter table public.reports enable row level security;

-- profiles: everyone can read (needed to show poster names/avatars on
-- items), only the owner can edit their own row.
create policy "profiles are viewable by everyone"
  on public.profiles for select using (true);

create policy "users can update their own profile"
  on public.profiles for update using (auth.uid() = id);

-- categories: read-only reference data, writable only via the dashboard
-- or a service-role key (never from the client).
create policy "categories are viewable by everyone"
  on public.categories for select using (true);

-- items: anyone signed in can browse open items; only the owner can
-- insert/update/delete their own.
create policy "items are viewable by everyone"
  on public.items for select using (true);

create policy "users can insert their own items"
  on public.items for insert with check (auth.uid() = user_id);

create policy "users can update their own items"
  on public.items for update using (auth.uid() = user_id);

create policy "users can delete their own items"
  on public.items for delete using (auth.uid() = user_id);

-- item_images: viewable by everyone (matching needs to compare across all
-- users' photos); only the owning item's user can add/remove images.
create policy "item images are viewable by everyone"
  on public.item_images for select using (true);

create policy "users can add images to their own items"
  on public.item_images for insert with check (
    exists (
      select 1 from public.items
      where items.id = item_images.item_id and items.user_id = auth.uid()
    )
  );

create policy "users can delete images from their own items"
  on public.item_images for delete using (
    exists (
      select 1 from public.items
      where items.id = item_images.item_id and items.user_id = auth.uid()
    )
  );

-- matches: visible only to the two item owners involved.
create policy "matches are viewable by the item owners"
  on public.matches for select using (
    exists (
      select 1 from public.items
      where items.id in (matches.item_a_id, matches.item_b_id)
        and items.user_id = auth.uid()
    )
  );

-- messages: only sender and receiver can read or write.
create policy "messages are viewable by sender and receiver"
  on public.messages for select using (
    auth.uid() = sender_id or auth.uid() = receiver_id
  );

create policy "users can send messages as themselves"
  on public.messages for insert with check (auth.uid() = sender_id);

create policy "receivers can mark messages as read"
  on public.messages for update using (auth.uid() = receiver_id);

-- claims: the claimant and the item's owner can both see a claim; only the
-- claimant can create it, only the owner can approve/reject it.
create policy "claims are viewable by claimant and item owner"
  on public.claims for select using (
    auth.uid() = claimant_id
    or exists (
      select 1 from public.items
      where items.id = claims.item_id and items.user_id = auth.uid()
    )
  );

create policy "users can file their own claims"
  on public.claims for insert with check (auth.uid() = claimant_id);

create policy "item owners can update claims on their items"
  on public.claims for update using (
    exists (
      select 1 from public.items
      where items.id = claims.item_id and items.user_id = auth.uid()
    )
  );

-- reports: reporter can see their own report; inserts must be self-attributed.
create policy "users can view their own reports"
  on public.reports for select using (auth.uid() = reporter_id);

create policy "users can file their own reports"
  on public.reports for insert with check (auth.uid() = reporter_id);
