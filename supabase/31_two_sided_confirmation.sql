-- ============================================================================
-- Findora — Two-sided match confirmation
-- Run this after 30_chat_photos.sql. Safe to re-run.
--
-- BEFORE: either person tapping "This is it!" confirmed the match for both and
-- opened the chat — so one person could open a private chat with someone who
-- had never agreed it was their item.
-- NOW: each of the two owners records their OWN decision, and a match is
-- 'confirmed' (chat opens, claims allowed) only when BOTH have confirmed.
--
--   matches.item_a_decision / item_b_decision   null | 'confirmed' | 'dismissed'
--     — the decision of the owner of item_a / item_b. Never read directly by
--     the app; my_matches_page() turns them into "mine" and "theirs".
--   matches.status stays the overall state, so everything that already
--     depends on it (chat access, claims, returned items, chat photos,
--     notifications) keeps working unchanged, and now means "mutual":
--       'confirmed'  both confirmed
--       'dismissed'  either person said "Not a match" (it leaves both lists'
--                    "Needs your input", as before)
--       'pending'    anything else — including "I confirmed, waiting for them"
--
-- Existing matches are grandfathered: every match that was 'confirmed' becomes
-- confirmed on BOTH sides, so no existing chat, claim or return is touched.
-- Old dismissed matches stay dismissed and can still be undone.
--
-- Also here:
--   * decide_match() now returns the match's resulting status (the app uses it
--     to say "waiting for the other person" or "it's mutual").
--   * A new notification, 'match_waiting', tells a person the OTHER owner has
--     confirmed and is waiting for them. (The existing 'match_confirmed' one
--     now fires when the second person confirms, so it reaches the first.)
--   * my_matches_page() gains a 'waiting' section (I confirmed, they haven't
--     yet) and three columns: my_decision, other_confirmed, reopenable.
--     Someone's "Not a match" is never shown to the other as who-did-what.
--   * match_outcomes (admin score-band stats): 'confirmed' now means mutual.
-- ============================================================================

-- ---- 1. per-owner decisions ---------------------------------------------------
alter table public.matches add column if not exists item_a_decision text;
alter table public.matches add column if not exists item_b_decision text;

do $$ begin
  alter table public.matches
    add constraint matches_item_a_decision_values
    check (item_a_decision is null or item_a_decision in ('confirmed', 'dismissed'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.matches
    add constraint matches_item_b_decision_values
    check (item_b_decision is null or item_b_decision in ('confirmed', 'dismissed'));
exception when duplicate_object then null; end $$;

-- Grandfather existing confirmed matches (touches no status, so the outcome
-- log and the confirmation notification do not fire). Re-running changes nothing.
update public.matches
set item_a_decision = 'confirmed', item_b_decision = 'confirmed'
where status = 'confirmed'
  and (item_a_decision is distinct from 'confirmed' or item_b_decision is distinct from 'confirmed');

-- ---- 2. decide_match ------------------------------------------------------------
-- p_status: 'confirmed' | 'dismissed' | 'pending' ("pending" = Undo: clears MY
-- decision). Returns the match's status afterwards.
drop function if exists public.decide_match(uuid, text);

create function public.decide_match(p_match_id uuid, p_status text)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  me uuid := auth.uid();
  m public.matches%rowtype;
  a public.items%rowtype;
  b public.items%rowtype;
  found_item public.items%rowtype;
  lost_item public.items%rowtype;
  i_am_a boolean;
  my_new text;
  other_dec text;
  new_status text;
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_status not in ('pending', 'confirmed', 'dismissed') then
    raise exception 'Unknown match status.' using errcode = '22023';
  end if;

  select * into m from public.matches where id = p_match_id for update;
  if not found then
    raise exception 'That match no longer exists.' using errcode = 'P0002';
  end if;
  select * into a from public.items where id = m.item_a_id;
  select * into b from public.items where id = m.item_b_id;
  if a.user_id is distinct from me and b.user_id is distinct from me then
    raise exception 'This match is not yours to decide.' using errcode = '42501';
  end if;

  i_am_a := (a.user_id = me);
  my_new := case p_status when 'pending' then null else p_status end;
  other_dec := case when i_am_a then m.item_b_decision else m.item_a_decision end;

  new_status := case
    when my_new = 'dismissed' or other_dec = 'dismissed' then 'dismissed'
    when my_new = 'confirmed' and other_dec = 'confirmed' then 'confirmed'
    else 'pending'
  end;

  -- Taking back a confirmation is only safe while it is still just a chat.
  if m.status = 'confirmed' and new_status <> 'confirmed' then
    if a.type = 'found' and b.type = 'lost' then
      found_item := a; lost_item := b;
    elsif b.type = 'found' and a.type = 'lost' then
      found_item := b; lost_item := a;
    end if;

    if found_item.id is not null and (
      exists (
        select 1 from public.claims c
        where c.item_id = found_item.id and c.claimant_id = lost_item.user_id
      )
      or found_item.status in ('claimed', 'resolved')
      or lost_item.status in ('claimed', 'resolved')
    ) then
      raise exception 'A claim has already been filed for this match, so it can no longer be undone.'
        using errcode = '22023';
    end if;
  end if;

  update public.matches
  set item_a_decision = case when i_am_a then my_new else item_a_decision end,
      item_b_decision = case when i_am_a then item_b_decision else my_new end,
      status = new_status
  where id = p_match_id;

  return new_status;
end;
$$;

revoke all on function public.decide_match(uuid, text) from public, anon;
grant execute on function public.decide_match(uuid, text) to authenticated;

-- ---- 3. "they confirmed, your turn" notification -----------------------------------
create or replace function public.notify_match_waiting()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  a_user uuid;
  a_title text;
  b_user uuid;
  b_title text;
begin
  -- Only while the match is still open: once both confirm, notify_match_confirmed
  -- speaks instead.
  if new.status <> 'pending' then
    return new;
  end if;

  select user_id, title into a_user, a_title from public.items where id = new.item_a_id;
  select user_id, title into b_user, b_title from public.items where id = new.item_b_id;

  if new.item_a_decision = 'confirmed' and old.item_a_decision is distinct from 'confirmed'
     and b_user is not null and b_user <> auth.uid() then
    perform public.create_notification(
      b_user, 'match_waiting',
      'Match waiting for you: "' || coalesce(a_title, 'a post') || '"',
      'The other person says this is a match. Confirm too to start chatting.',
      new.item_b_id, new.id
    );
  end if;
  if new.item_b_decision = 'confirmed' and old.item_b_decision is distinct from 'confirmed'
     and a_user is not null and a_user <> auth.uid() then
    perform public.create_notification(
      a_user, 'match_waiting',
      'Match waiting for you: "' || coalesce(b_title, 'a post') || '"',
      'The other person says this is a match. Confirm too to start chatting.',
      new.item_a_id, new.id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists matches_notify_waiting on public.matches;
create trigger matches_notify_waiting
  after update of item_a_decision, item_b_decision on public.matches
  for each row execute function public.notify_match_waiting();

revoke all on function public.notify_match_waiting() from public, anon, authenticated;

-- ---- 4. my_matches_page: sections and per-person columns -----------------------------
drop function if exists public.my_matches_page(text, text, uuid, integer);

create function public.my_matches_page(
  p_section text default 'all',
  p_filter text default 'all',
  p_item_id uuid default null,
  p_limit integer default 20
)
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
  time_proximity real,
  match_status text,
  created_at timestamptz,
  my_item_image_url text,
  my_decision text,
  other_confirmed boolean,
  reopenable boolean
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
    m.time_proximity,
    m.status,
    m.created_at,
    (
      select img.image_url from public.item_images img
      where img.item_id = mine.id
      order by img.created_at
      limit 1
    ),
    (case when a.user_id = auth.uid() then m.item_a_decision else m.item_b_decision end),
    coalesce(
      (case when a.user_id = auth.uid() then m.item_b_decision else m.item_a_decision end) = 'confirmed',
      false
    ),
    (
      case when m.status = 'dismissed'
        then (
          (case when a.user_id = auth.uid() then m.item_a_decision else m.item_b_decision end) = 'dismissed'
          or (m.item_a_decision is null and m.item_b_decision is null)
        )
        else true
      end
    )
  from public.matches m
  join public.items a on a.id = m.item_a_id
  join public.items b on b.id = m.item_b_id
  join public.items mine on mine.id = (case when a.user_id = auth.uid() then a.id else b.id end)
  join public.items theirs on theirs.id = (case when a.user_id = auth.uid() then b.id else a.id end)
  where (a.user_id = auth.uid() or b.user_id = auth.uid())
    and a.deleted_at is null
    and b.deleted_at is null
    and a.status <> 'resolved'
    and b.status <> 'resolved'
    and not exists (
      select 1 from public.user_blocks ub
      where ub.blocker_id = auth.uid() and ub.blocked_id = theirs.user_id
    )
    and (p_item_id is null or mine.id = p_item_id or theirs.id = p_item_id)
    and (
      case coalesce(p_section, 'all')
        when 'pending' then m.status = 'pending'
          and (case when a.user_id = auth.uid() then m.item_a_decision else m.item_b_decision end) is distinct from 'confirmed'
        when 'waiting' then m.status = 'pending'
          and (case when a.user_id = auth.uid() then m.item_a_decision else m.item_b_decision end) = 'confirmed'
        when 'decided' then m.status <> 'pending'
        when 'confirmed' then m.status = 'confirmed'
        else true
      end
    )
    and (
      coalesce(p_filter, 'all') = 'all'
      or (p_filter = 'image'
          and coalesce(m.image_similarity >= 0.60::real, false)
          and not coalesce(m.text_similarity >= 0.50::real, false))
      or (p_filter = 'text'
          and coalesce(m.text_similarity >= 0.50::real, false)
          and not coalesce(m.image_similarity >= 0.60::real, false))
      or (p_filter = 'both'
          and coalesce(m.image_similarity >= 0.60::real, false)
          and coalesce(m.text_similarity >= 0.50::real, false))
      or (p_filter = 'nearby'
          and m.distance_meters is not null and m.distance_meters <= 5000)
      or (p_filter = 'time'
          and m.time_proximity is not null and m.time_proximity >= 0.5)
    )
  order by
    (case when p_section in ('pending', 'waiting') then m.similarity_score end) desc nulls last,
    m.created_at desc,
    m.id desc
  limit greatest(1, least(coalesce(p_limit, 20), 500));
$$;

revoke all on function public.my_matches_page(text, text, uuid, integer) from public, anon;
grant execute on function public.my_matches_page(text, text, uuid, integer) to authenticated;
