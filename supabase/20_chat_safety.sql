-- ============================================================================
-- Findora — Chat safety: new-message alerts, blocking, and reporting people
-- Run this after 19_indexes.sql. Safe to re-run.
--
-- 1. NEW-MESSAGE ALERTS. Until now nothing told you someone had written to you
--    unless the app was open. A new message now creates an in-app alert (and a
--    push, through the existing webhook) — but only for the FIRST unread
--    message in a conversation, so a burst of messages is one notification,
--    and the next one rings again once you've read the chat. The alert names
--    the sender and the post ("Sam sent you a message — About "Black wallet"")
--    and never includes the message text (it would show on lock screens).
--    Opening the chat marks that alert read.
-- 2. BLOCKING. A block stops messages in BOTH directions (the database
--    refuses them, for match chats and direct messages alike) and stops the
--    blocked person starting a direct message thread. The blocked person is
--    not told; their sends simply fail.
-- 3. REPORTING A PERSON (not just a post), from inside a chat. Only someone
--    you actually share a conversation with can be reported; admins see the
--    queue in the app's Flagged reports screen.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Blocks
-- ----------------------------------------------------------------------------
create table if not exists public.user_blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint user_blocks_not_self check (blocker_id <> blocked_id)
);

create index if not exists user_blocks_blocked_idx on public.user_blocks (blocked_id);

alter table public.user_blocks enable row level security;
revoke all on public.user_blocks from anon;

drop policy if exists "people can see who they blocked" on public.user_blocks;
create policy "people can see who they blocked"
  on public.user_blocks for select to authenticated
  using ((select auth.uid()) = blocker_id);

drop policy if exists "people can block others" on public.user_blocks;
create policy "people can block others"
  on public.user_blocks for insert to authenticated
  with check ((select auth.uid()) = blocker_id);

drop policy if exists "people can unblock" on public.user_blocks;
create policy "people can unblock"
  on public.user_blocks for delete to authenticated
  using ((select auth.uid()) = blocker_id);

-- Has either person blocked the other? SECURITY DEFINER because a policy for
-- the sender has to see blocks the RECEIVER made, which RLS hides from them.
create or replace function public.is_blocked_between(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = p_a and b.blocked_id = p_b)
       or (b.blocker_id = p_b and b.blocked_id = p_a)
  );
$$;

revoke all on function public.is_blocked_between(uuid, uuid) from public, anon;
grant execute on function public.is_blocked_between(uuid, uuid) to authenticated;

-- Match chat: the 17_harden_policies.sql rule, plus "and not blocked".
drop policy if exists "users can send messages as themselves" on public.messages;
create policy "users can send messages as themselves"
  on public.messages for insert to authenticated
  with check (
    (select auth.uid()) = sender_id
    and public.is_confirmed_match_pair(match_id, sender_id, receiver_id)
    and not public.is_blocked_between(sender_id, receiver_id)
  );

-- Direct messages: the 06_contact_messaging.sql rule, plus "and not blocked".
drop policy if exists "thread participants can send contact messages" on public.contact_messages;
create policy "thread participants can send contact messages"
  on public.contact_messages for insert to authenticated
  with check (
    (select auth.uid()) = sender_id
    and exists (
      select 1 from public.contact_threads t
      where t.id = contact_messages.thread_id
        and (t.item_owner_id = (select auth.uid()) or t.contacter_id = (select auth.uid()))
        and not public.is_blocked_between(t.item_owner_id, t.contacter_id)
    )
  );

-- Starting a direct message thread with someone who has blocked you (or whom
-- you've blocked) is refused. Same as 06's version otherwise.
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
  if public.is_blocked_between(auth.uid(), owner_id) then
    raise exception 'This person can''t be contacted.' using errcode = '42501';
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
-- Reporting a person
-- ----------------------------------------------------------------------------
create or replace function public.is_contact_thread_pair(p_thread uuid, p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from public.contact_threads t
    where t.id = p_thread
      and ((t.item_owner_id = p_a and t.contacter_id = p_b)
        or (t.item_owner_id = p_b and t.contacter_id = p_a))
  );
$$;

revoke all on function public.is_contact_thread_pair(uuid, uuid, uuid) from public, anon;
grant execute on function public.is_contact_thread_pair(uuid, uuid, uuid) to authenticated;

create table if not exists public.user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  reported_user_id uuid not null references public.profiles (id) on delete cascade,
  -- Where the report was made from (one of these):
  match_id uuid references public.matches (id) on delete set null,
  thread_id uuid references public.contact_threads (id) on delete set null,
  reason text not null check (char_length(reason) between 1 and 500),
  status text not null default 'open' check (status in ('open', 'reviewed', 'dismissed')),
  created_at timestamptz not null default now(),
  constraint user_reports_not_self check (reporter_id <> reported_user_id)
);

-- One open report per person about another — the queue isn't a place to
-- repeat yourself, and it stops one angry person flooding it.
create unique index if not exists user_reports_one_open_per_pair
  on public.user_reports (reporter_id, reported_user_id)
  where status = 'open';
create index if not exists user_reports_open_idx
  on public.user_reports (created_at desc) where status = 'open';

alter table public.user_reports enable row level security;
revoke all on public.user_reports from anon;

-- You can only report someone you actually share a conversation with.
drop policy if exists "people can report who they talk to" on public.user_reports;
create policy "people can report who they talk to"
  on public.user_reports for insert to authenticated
  with check (
    (select auth.uid()) = reporter_id
    and status = 'open'
    and (
      (match_id is not null
        and public.is_confirmed_match_pair(match_id, reporter_id, reported_user_id))
      or (thread_id is not null
        and public.is_contact_thread_pair(thread_id, reporter_id, reported_user_id))
    )
  );

drop policy if exists "admins can read person reports" on public.user_reports;
create policy "admins can read person reports"
  on public.user_reports for select to authenticated
  using ((select public.is_admin()));

drop policy if exists "admins can resolve person reports" on public.user_reports;
create policy "admins can resolve person reports"
  on public.user_reports for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- Admins may change only the status.
revoke update on public.user_reports from anon, authenticated;
grant update (status) on public.user_reports to authenticated;


-- ----------------------------------------------------------------------------
-- New-message alerts
-- ----------------------------------------------------------------------------
create or replace function public.notify_new_match_message()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  sender_name text;
  my_item_id uuid;
  my_item_title text;
begin
  -- Only the first unread message in the conversation notifies.
  if exists (
    select 1 from public.messages m
    where m.match_id = new.match_id
      and m.receiver_id = new.receiver_id
      and m.read_at is null
      and m.id <> new.id
  ) then
    return new;
  end if;
  if public.is_blocked_between(new.sender_id, new.receiver_id) then
    return new;
  end if;

  select coalesce(nullif(btrim(p.full_name), ''), nullif(p.username, ''), 'Someone')
    into sender_name from public.profiles p where p.id = new.sender_id;

  select i.id, i.title into my_item_id, my_item_title
  from public.matches mt
  join public.items i on i.id in (mt.item_a_id, mt.item_b_id)
  where mt.id = new.match_id and i.user_id = new.receiver_id
  limit 1;

  perform public.create_notification(
    new.receiver_id, 'new_message',
    coalesce(sender_name, 'Someone') || ' sent you a message',
    case when my_item_title is null then null else 'About "' || my_item_title || '"' end,
    my_item_id, new.match_id
  );
  return new;
end;
$$;

drop trigger if exists messages_notify_new on public.messages;
create trigger messages_notify_new
  after insert on public.messages
  for each row execute function public.notify_new_match_message();

create or replace function public.notify_new_contact_message()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  t public.contact_threads%rowtype;
  receiver uuid;
  sender_name text;
  post_title text;
begin
  select * into t from public.contact_threads where id = new.thread_id;
  if not found then return new; end if;
  receiver := case when new.sender_id = t.item_owner_id then t.contacter_id else t.item_owner_id end;

  if exists (
    select 1 from public.contact_messages m
    where m.thread_id = new.thread_id
      and m.sender_id <> receiver
      and m.read_at is null
      and m.id <> new.id
  ) then
    return new;
  end if;
  if public.is_blocked_between(new.sender_id, receiver) then
    return new;
  end if;

  select coalesce(nullif(btrim(p.full_name), ''), nullif(p.username, ''), 'Someone')
    into sender_name from public.profiles p where p.id = new.sender_id;
  select title into post_title from public.items where id = t.item_id;

  perform public.create_notification(
    receiver, 'new_message',
    coalesce(sender_name, 'Someone') || ' sent you a message',
    case when post_title is null then null else 'About "' || post_title || '"' end,
    t.item_id, null
  );
  return new;
end;
$$;

drop trigger if exists contact_messages_notify_new on public.contact_messages;
create trigger contact_messages_notify_new
  after insert on public.contact_messages
  for each row execute function public.notify_new_contact_message();

-- Reading the chat clears its alert, so the Alerts badge doesn't keep counting
-- messages you've already seen.
create or replace function public.clear_message_alerts()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if tg_table_name = 'messages' then
    update public.notifications
    set read_at = now()
    where user_id = new.receiver_id
      and type = 'new_message'
      and match_id = new.match_id
      and read_at is null;
  else
    update public.notifications n
    set read_at = now()
    from public.contact_threads t
    where t.id = new.thread_id
      and n.user_id = case when new.sender_id = t.item_owner_id then t.contacter_id else t.item_owner_id end
      and n.type = 'new_message'
      and n.item_id = t.item_id
      and n.match_id is null
      and n.read_at is null;
  end if;
  return new;
end;
$$;

drop trigger if exists messages_clear_alerts on public.messages;
create trigger messages_clear_alerts
  after update of read_at on public.messages
  for each row
  when (old.read_at is null and new.read_at is not null)
  execute function public.clear_message_alerts();

drop trigger if exists contact_messages_clear_alerts on public.contact_messages;
create trigger contact_messages_clear_alerts
  after update of read_at on public.contact_messages
  for each row
  when (old.read_at is null and new.read_at is not null)
  execute function public.clear_message_alerts();

revoke all on function public.notify_new_match_message() from public, anon, authenticated;
revoke all on function public.notify_new_contact_message() from public, anon, authenticated;
revoke all on function public.clear_message_alerts() from public, anon, authenticated;

-- ============================================================================
-- Verify (optional): supabase/tests/20_chat_safety_checks.sql
--
-- Handling a person report as an admin (the app's Flagged reports screen has
-- a "People" tab), or by hand:
--   select r.id, r.reason, r.created_at, p.full_name as reported
--   from public.user_reports r join public.profiles p on p.id = r.reported_user_id
--   where r.status = 'open' order by r.created_at desc;
--   -- ban someone for good (stops them signing up again with that email too):
--   --   update auth.users set banned_until = now() + interval '100 years' where id = '<uuid>';
--   --   select public.block_email('their@email');
-- ============================================================================
