-- ============================================================================
-- Findora — Upgrade: "Contact poster" direct messaging
-- Run this after 05_multimodal_matching.sql. Safe to re-run.
--
-- The existing `matches`/`messages` tables power chat that's deliberately
-- gated behind a *confirmed AI match* (see README, "Item detail screen:
-- carousel, map preview, smart contact") — that gate exists specifically so
-- contact details aren't exchanged before ownership looks plausible.
--
-- This adds a second, parallel messaging surface for a lighter case: asking
-- the poster a quick question about *any* open item, before/without an AI
-- match existing at all (e.g. "is the strap adjustable?" on a found bag).
-- It's intentionally still just messaging — the claim → approve → mark
-- returned → rate lifecycle in ChatScreen/claims stays the only path that
-- actually resolves an item, so this doesn't weaken that verification flow.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- contact_threads — one row per (item, person asking about it). The poster
-- doesn't create these; whoever taps "Contact poster" does, via
-- start_contact_thread() below.
-- ----------------------------------------------------------------------------
create table if not exists public.contact_threads (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items (id) on delete cascade,
  item_owner_id uuid not null references public.profiles (id) on delete cascade,
  contacter_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint contact_threads_not_self check (contacter_id <> item_owner_id),
  constraint contact_threads_unique_pair unique (item_id, contacter_id)
);

create index if not exists contact_threads_item_idx on public.contact_threads (item_id);

-- ----------------------------------------------------------------------------
-- contact_messages — deliberately a separate table from `messages` rather
-- than a shared one with a nullable match_id/thread_id: the two flows have
-- different RLS shapes (participants of a thread vs. sender/receiver of a
-- match-scoped message) and keeping them apart means neither policy set
-- has to reason about the other's rows.
-- ----------------------------------------------------------------------------
create table if not exists public.contact_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.contact_threads (id) on delete cascade,
  sender_id uuid not null references public.profiles (id),
  content text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists contact_messages_thread_idx
  on public.contact_messages (thread_id, created_at);

alter table public.contact_threads enable row level security;
alter table public.contact_messages enable row level security;

drop policy if exists "contact threads are viewable by both participants" on public.contact_threads;
create policy "contact threads are viewable by both participants"
  on public.contact_threads for select using (
    auth.uid() = item_owner_id or auth.uid() = contacter_id
  );

-- item_owner_id is client-supplied (see start_contact_thread()) but this
-- check re-derives it from the item row itself, so nobody can create a
-- thread claiming a different owner than the item actually has.
drop policy if exists "users can start a contact thread as themselves" on public.contact_threads;
create policy "users can start a contact thread as themselves"
  on public.contact_threads for insert with check (
    auth.uid() = contacter_id
    and item_owner_id = (select user_id from public.items where id = item_id)
  );

drop policy if exists "contact messages are viewable by thread participants" on public.contact_messages;
create policy "contact messages are viewable by thread participants"
  on public.contact_messages for select using (
    exists (
      select 1 from public.contact_threads t
      where t.id = contact_messages.thread_id
        and (t.item_owner_id = auth.uid() or t.contacter_id = auth.uid())
    )
  );

drop policy if exists "thread participants can send contact messages" on public.contact_messages;
create policy "thread participants can send contact messages"
  on public.contact_messages for insert with check (
    auth.uid() = sender_id
    and exists (
      select 1 from public.contact_threads t
      where t.id = contact_messages.thread_id
        and (t.item_owner_id = auth.uid() or t.contacter_id = auth.uid())
    )
  );

drop policy if exists "recipients can mark contact messages as read" on public.contact_messages;
create policy "recipients can mark contact messages as read"
  on public.contact_messages for update using (
    exists (
      select 1 from public.contact_threads t
      where t.id = contact_messages.thread_id
        and (t.item_owner_id = auth.uid() or t.contacter_id = auth.uid())
    )
  );

-- ----------------------------------------------------------------------------
-- start_contact_thread — idempotent: tapping "Contact poster" again on an
-- item you already messaged about just re-opens the same thread rather
-- than creating a duplicate, via the unique (item_id, contacter_id)
-- constraint + an upsert.
-- ----------------------------------------------------------------------------
create or replace function public.start_contact_thread(p_item_id uuid)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  owner_id uuid;
  thread_id uuid;
begin
  select user_id into owner_id from public.items where id = p_item_id;
  if owner_id is null then
    raise exception 'Item not found';
  end if;
  if owner_id = auth.uid() then
    raise exception 'Cannot start a contact thread with yourself';
  end if;

  insert into public.contact_threads (item_id, item_owner_id, contacter_id)
  values (p_item_id, owner_id, auth.uid())
  on conflict (item_id, contacter_id)
    do update set item_id = excluded.item_id -- no-op, just to allow RETURNING below
  returning id into thread_id;

  return thread_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- my_contact_threads — one row per thread the caller is in, either as the
-- item's owner or as the person who reached out, with the other side's
-- name, a message preview, and an unread count — same shape as
-- my_conversations() so the Dart model/UI can follow the same pattern.
-- ----------------------------------------------------------------------------
create or replace function public.my_contact_threads()
returns table (
  thread_id uuid,
  item_id uuid,
  item_title text,
  item_image_url text,
  other_user_id uuid,
  other_user_name text,
  am_i_owner boolean,
  last_message text,
  last_message_at timestamptz,
  unread_count bigint,
  created_at timestamptz
)
language sql
stable
as $$
  select
    t.id,
    i.id,
    i.title,
    (
      select img.image_url from public.item_images img
      where img.item_id = i.id
      order by img.created_at
      limit 1
    ),
    case when t.item_owner_id = auth.uid() then t.contacter_id else t.item_owner_id end,
    coalesce(p.full_name, p.username, 'Findora user'),
    t.item_owner_id = auth.uid(),
    latest.content,
    latest.created_at,
    (
      select count(*) from public.contact_messages cm
      where cm.thread_id = t.id
        and cm.sender_id <> auth.uid()
        and cm.read_at is null
    ),
    t.created_at
  from public.contact_threads t
  join public.items i on i.id = t.item_id
  join public.profiles p
    on p.id = (case when t.item_owner_id = auth.uid() then t.contacter_id else t.item_owner_id end)
  left join lateral (
    select content, created_at
    from public.contact_messages cm2
    where cm2.thread_id = t.id
    order by cm2.created_at desc
    limit 1
  ) latest on true
  where t.item_owner_id = auth.uid() or t.contacter_id = auth.uid()
  order by coalesce(latest.created_at, t.created_at) desc;
$$;

-- ----------------------------------------------------------------------------
-- mark_contact_thread_read — same "mark the other person's messages as
-- read" pattern as messages_repository.dart's markConversationRead, just
-- expressed as an RPC since "not sender" is easier to say in SQL than as a
-- PostgREST filter from the client.
-- ----------------------------------------------------------------------------
create or replace function public.mark_contact_thread_read(p_thread_id uuid)
returns void
language sql
security invoker
as $$
  update public.contact_messages
  set read_at = now()
  where thread_id = p_thread_id
    and sender_id <> auth.uid()
    and read_at is null;
$$;
