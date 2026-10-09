-- ============================================================================
-- Findora — Private proof questions for claims
-- Run this after 23_time_direction.sql. Safe to re-run.
--
-- Until now a claim was a single free-text answer to a generic prompt ("describe
-- a unique detail that proves this is yours"), and the finder had nothing to
-- compare it with except a hunch. Now someone who FOUND something can set a
-- question only the real owner could answer ("What is on the lock screen?",
-- "What is written inside the cover?") and, privately, what the right answer
-- is:
--   * items.proof_question     — the question. Visible to signed-in people (the
--     claimant has to see it to answer it). Never include the answer in it.
--   * item_private.proof_answer — the expected answer. Readable and writable
--     ONLY by the post's owner (row-level security); no one else, including
--     the claimant, can ever read it. The finder sees it next to the
--     claimant's answer when deciding.
-- Both are optional; claims without a proof question work exactly as before.
-- The answer is deleted as soon as the post is removed (including when its
-- owner deletes their account).
-- ============================================================================

alter table public.items add column if not exists proof_question text;

do $$ begin
  alter table public.items
    add constraint items_proof_question_len
    check (proof_question is null or char_length(proof_question) <= 200) not valid;
exception when duplicate_object then null; end $$;

create table if not exists public.item_private (
  item_id uuid primary key references public.items (id) on delete cascade,
  proof_answer text,
  updated_at timestamptz not null default now(),
  constraint item_private_answer_len
    check (proof_answer is null or char_length(proof_answer) <= 300)
);

alter table public.item_private enable row level security;
revoke all on public.item_private from anon;

drop policy if exists "owners can read their private item details" on public.item_private;
create policy "owners can read their private item details"
  on public.item_private for select to authenticated
  using (exists (
    select 1 from public.items i
    where i.id = item_id and i.user_id = (select auth.uid())
  ));

drop policy if exists "owners can add private item details" on public.item_private;
create policy "owners can add private item details"
  on public.item_private for insert to authenticated
  with check (exists (
    select 1 from public.items i
    where i.id = item_id and i.user_id = (select auth.uid())
  ));

drop policy if exists "owners can change private item details" on public.item_private;
create policy "owners can change private item details"
  on public.item_private for update to authenticated
  using (exists (
    select 1 from public.items i
    where i.id = item_id and i.user_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.items i
    where i.id = item_id and i.user_id = (select auth.uid())
  ));

drop policy if exists "owners can delete their private item details" on public.item_private;
create policy "owners can delete their private item details"
  on public.item_private for delete to authenticated
  using (exists (
    select 1 from public.items i
    where i.id = item_id and i.user_id = (select auth.uid())
  ));

-- A post is only ever soft-deleted (deleted_at), so the ON DELETE CASCADE above
-- never fires for it. Remove the private answer at that moment instead.
create or replace function public.clear_item_private_on_removal()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  delete from public.item_private where item_id = new.id;
  return new;
end;
$$;

drop trigger if exists items_clear_private_on_removal on public.items;
create trigger items_clear_private_on_removal
  after update of deleted_at on public.items
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.clear_item_private_on_removal();

revoke all on function public.clear_item_private_on_removal() from public, anon, authenticated;

-- ============================================================================
-- Verify (optional): as a user who does NOT own the post, this returns nothing:
--   select proof_answer from public.item_private;
-- ============================================================================
