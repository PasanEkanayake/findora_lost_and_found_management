-- ============================================================================
-- Findora — Photos in chats (and nothing else: typing indicators need no SQL)
-- Run this after 29_matches_paging.sql. Safe to re-run.
--
-- 1. PHOTO MESSAGES. A message in either kind of chat (the confirmed-match
--    chat, and a direct "Contact poster" thread) can carry one photo, with or
--    without text. The photo is stored as `image_path` on the message row.
-- 2. PRIVATE STORAGE. Photos live in a PRIVATE bucket, `chat-images`, unlike
--    post photos: people send things like the lock screen of a found phone.
--    Only the two people in that conversation can read or add files in its
--    folder (`m/<match id>/…` or `c/<thread id>/…`), and the app shows a
--    photo through a one-hour signed link. A match that is un-confirmed stops
--    its photos being readable until it is confirmed again.
-- 3. The insert rules for both message tables gain one clause: a message can
--    only point at a file inside ITS OWN conversation's folder. `image_path`
--    can't be changed after sending (same as the text).
-- 4. The chat lists show "📷 Photo" as the preview of a photo-only message.
--
-- TYPING INDICATORS use Supabase Realtime *Broadcast* — short-lived messages
-- between the two open chat screens that are never written to the database —
-- so there is nothing to migrate for them. The channel name contains the
-- conversation's id (an unguessable uuid only its two members can look up)
-- and a typing event carries just the sender's id and true/false.
-- ============================================================================

-- ---- 1. columns and length rules ---------------------------------------------
alter table public.messages add column if not exists image_path text;
alter table public.contact_messages add column if not exists image_path text;

-- Text is optional when there is a photo; never longer than 2000 either way.
alter table public.messages drop constraint if exists messages_content_len;
alter table public.messages
  add constraint messages_content_len
  check (char_length(content) <= 2000 and (char_length(content) >= 1 or image_path is not null)) not valid;

alter table public.contact_messages drop constraint if exists contact_messages_content_len;
alter table public.contact_messages
  add constraint contact_messages_content_len
  check (char_length(content) <= 2000 and (char_length(content) >= 1 or image_path is not null)) not valid;

-- Shape of a stored path: <m|c>/<conversation uuid>/<file uuid>.<jpg|png|webp>
do $$ begin
  alter table public.messages
    add constraint messages_image_path_shape
    check (image_path is null or image_path ~ '^m/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$') not valid;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.contact_messages
    add constraint contact_messages_image_path_shape
    check (image_path is null or image_path ~ '^c/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$') not valid;
exception when duplicate_object then null; end $$;

-- ---- 2. the private bucket ----------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-images', 'chat-images', false, 5242880,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = false,
      file_size_limit = 5242880,
      allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

-- Is the caller one of the two people in the conversation a storage path
-- belongs to? (case/early-return so a malformed path is "no", never an error)
create or replace function public.can_use_chat_folder(p_path text)
returns boolean
language plpgsql
stable
security definer set search_path = public
as $$
declare
  parts text[] := storage.foldername(p_path);
  kind text;
  cid text;
begin
  if parts is null or array_length(parts, 1) is distinct from 2 then
    return false;
  end if;
  kind := parts[1];
  cid := parts[2];
  if cid !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;

  if kind = 'm' then
    return exists (
      select 1
      from public.matches mt
      join public.items a on a.id = mt.item_a_id
      join public.items b on b.id = mt.item_b_id
      where mt.id = cid::uuid
        and mt.status = 'confirmed'
        and (a.user_id = auth.uid() or b.user_id = auth.uid())
    );
  elsif kind = 'c' then
    return exists (
      select 1 from public.contact_threads t
      where t.id = cid::uuid
        and (t.item_owner_id = auth.uid() or t.contacter_id = auth.uid())
    );
  end if;
  return false;
end;
$$;

revoke all on function public.can_use_chat_folder(text) from public, anon;
grant execute on function public.can_use_chat_folder(text) to authenticated;

drop policy if exists "chat images readable by the conversation" on storage.objects;
create policy "chat images readable by the conversation"
  on storage.objects for select to authenticated
  using (bucket_id = 'chat-images' and public.can_use_chat_folder(name));

drop policy if exists "chat images uploadable into the conversation" on storage.objects;
create policy "chat images uploadable into the conversation"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-images' and public.can_use_chat_folder(name));

-- Lets the app remove a photo it uploaded when the message then failed to send.
drop policy if exists "chat images removable by their uploader" on storage.objects;
create policy "chat images removable by their uploader"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'chat-images'
    and public.can_use_chat_folder(name)
    and owner_id = (select auth.uid())::text
  );

-- ---- 3. message rules ----------------------------------------------------------
-- Same as 20_chat_safety.sql, plus: a photo must be inside this conversation's folder.
drop policy if exists "users can send messages as themselves" on public.messages;
create policy "users can send messages as themselves"
  on public.messages for insert to authenticated
  with check (
    (select auth.uid()) = sender_id
    and public.is_confirmed_match_pair(match_id, sender_id, receiver_id)
    and not public.is_blocked_between(sender_id, receiver_id)
    and (image_path is null or image_path like 'm/' || match_id::text || '/%')
  );

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
    and (image_path is null or image_path like 'c/' || thread_id::text || '/%')
  );

-- Only read_at may change after sending — now including the photo.
create or replace function public.protect_message_immutable_fields()
returns trigger
language plpgsql
as $$
begin
  if public.is_api_caller() and (
       new.content is distinct from old.content
    or new.image_path is distinct from old.image_path
    or new.sender_id is distinct from old.sender_id
    or new.receiver_id is distinct from old.receiver_id
    or new.match_id is distinct from old.match_id
    or new.created_at is distinct from old.created_at
  ) then
    raise exception 'Only read_at can be updated on an existing message' using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function public.protect_contact_message_immutable_fields()
returns trigger
language plpgsql
as $$
begin
  if new.content is distinct from old.content
    or new.image_path is distinct from old.image_path
    or new.sender_id is distinct from old.sender_id
    or new.thread_id is distinct from old.thread_id
    or new.created_at is distinct from old.created_at then
    raise exception 'Only read_at can be updated on an existing contact message';
  end if;
  return new;
end;
$$;

-- ---- 4. chat list previews --------------------------------------------------------
-- Same columns as before; only last_message changes ("📷 Photo" for a photo-only message).
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
    case when latest.image_path is not null and latest.content = '' then '📷 Photo' else latest.content end as last_message,
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
    select content, image_path, created_at
    from public.messages msg2
    where msg2.match_id = m.id
    order by msg2.created_at desc
    limit 1
  ) latest on true
  where (a.user_id = auth.uid() or b.user_id = auth.uid())
    and m.status = 'confirmed'
  order by coalesce(latest.created_at, m.created_at) desc;
$$;

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
    case when latest.image_path is not null and latest.content = '' then '📷 Photo' else latest.content end,
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
    select content, image_path, created_at
    from public.contact_messages cm2
    where cm2.thread_id = t.id
    order by cm2.created_at desc
    limit 1
  ) latest on true
  where t.item_owner_id = auth.uid() or t.contacter_id = auth.uid()
  order by coalesce(latest.created_at, t.created_at) desc;
$$;
