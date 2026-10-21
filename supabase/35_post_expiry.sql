-- ============================================================================
-- Findora — Post expiry and "still looking?" reminders
-- Run this after 34_thumbnails.sql. Safe to re-run.
--
-- THE PROBLEM. A post stayed live for ever. Items get found, bought again or
-- forgotten, but their posts kept appearing in Browse and on the map, kept
-- being matched against new posts, and kept sending people to chat with someone
-- who stopped caring weeks ago.
--
-- THE CHANGE.
--   * Every post expires 60 days after it was posted (post_lifetime()).
--   * 7 days before, and again 1 day before, the owner gets a "Still looking
--     for ...?" alert (post_expiry_first_reminder(), post_expiry_final_reminder()).
--   * When the time is up the post's status becomes 'expired': it leaves
--     Browse, the map and matching exactly like a resolved post (all of those
--     already only look at status = 'open'), and its matches stop showing. It is
--     NOT deleted — it stays in the owner's My posts, marked Expired, with a
--     Renew button.
--   * renew_item() puts it back: status 'open', a fresh 60 days, reminders reset,
--     and its photos are matched again against everything open now. An owner
--     may also renew early ("Keep this post up").
--   * A post is NEVER expired while a conversation about it is under way: a
--     confirmed match, or a claim that is pending or approved, holds it open.
--   * Only the database sets expires_at; an app can't change it.
--   * A nightly job (pg_cron, 08:23 UTC) does the reminding and expiring:
--     process_item_expiry(). Without pg_cron, run
--     `select public.process_item_expiry();` once a day yourself.
--
-- Existing posts get a grace period: they expire 60 days after posting, but not
-- sooner than 14 days from now, so nothing disappears the night this runs.
-- ============================================================================

-- A new enum value can't be USED in the same transaction that adds it, so
-- nothing below mentions the literal in SQL that is checked at creation time:
-- the SQL functions compare status::text, and the plpgsql ones only look at it
-- when they run.
alter type public.item_status add value if not exists 'expired';

-- ---- 1. columns and tunables -----------------------------------------------------------
alter table public.items add column if not exists expires_at timestamptz;
alter table public.items add column if not exists expiry_reminders_sent smallint not null default 0;

do $$ begin
  alter table public.items
    add constraint items_expiry_reminders_range check (expiry_reminders_sent between 0 and 2);
exception when duplicate_object then null; end $$;

create index if not exists items_expiry_idx
  on public.items (expires_at)
  where deleted_at is null;

create or replace function public.post_lifetime()
returns interval language sql immutable as $$ select interval '60 days' $$;
create or replace function public.post_expiry_first_reminder()
returns interval language sql immutable as $$ select interval '7 days' $$;
create or replace function public.post_expiry_final_reminder()
returns interval language sql immutable as $$ select interval '1 day' $$;

-- New posts get their expiry; the app can't pick or change one.
create or replace function public.items_expiry_defaults()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    new.expires_at := now() + public.post_lifetime();
    new.expiry_reminders_sent := 0;
  elsif public.is_api_caller() then
    new.expires_at := old.expires_at;
    new.expiry_reminders_sent := old.expiry_reminders_sent;
  end if;
  return new;
end;
$$;

drop trigger if exists items_expiry_defaults on public.items;
create trigger items_expiry_defaults
  before insert or update on public.items
  for each row execute function public.items_expiry_defaults();

-- Grace period for posts that already exist.
update public.items
set expires_at = greatest(created_at + public.post_lifetime(), now() + interval '14 days')
where expires_at is null;

-- ---- 2. renewing -------------------------------------------------------------------------------
-- The owner keeps a post up (or brings back an expired one) for another full
-- lifetime. Returns the new expiry.
create or replace function public.renew_item(p_item_id uuid)
returns timestamptz
language plpgsql
security definer set search_path = public
as $$
declare
  me uuid := auth.uid();
  it public.items%rowtype;
  was_expired boolean;
  new_expiry timestamptz := now() + public.post_lifetime();
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  select * into it from public.items where id = p_item_id for update;
  if not found or it.user_id is distinct from me then
    raise exception 'That is not your post.' using errcode = '42501';
  end if;
  if it.deleted_at is not null then
    raise exception 'That post was removed, so it can''t be renewed.' using errcode = '22023';
  end if;
  if it.status::text not in ('open', 'expired') then
    raise exception 'Only an open or expired post can be renewed.' using errcode = '22023';
  end if;

  was_expired := (it.status::text = 'expired');

  update public.items
  set status = 'open', expires_at = new_expiry, expiry_reminders_sent = 0
  where id = p_item_id;

  if was_expired then
    -- While it was expired, new posts could not match it. Match its photos
    -- against everything that is open now (re-saving the embedding is what the
    -- matching trigger listens for), and refresh the matches it already had.
    update public.item_images set embedding = embedding
    where item_id = p_item_id and embedding is not null;
    perform public.refresh_matches_for_item(p_item_id);
  end if;

  return new_expiry;
end;
$$;

revoke all on function public.renew_item(uuid) from public, anon;
grant execute on function public.renew_item(uuid) to authenticated;

-- ---- 3. the nightly job --------------------------------------------------------------------------
create or replace function public.process_item_expiry()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  r record;
  days_left integer;
  reminded integer := 0;
  expired integer := 0;
begin
  -- 1. Time's up: expire (unless a conversation about the post is under way).
  for r in
    select i.id, i.user_id, i.title
    from public.items i
    where i.status::text = 'open'
      and i.deleted_at is null
      and i.expires_at is not null
      and i.expires_at <= now()
      and not exists (
        select 1 from public.matches m
        where (m.item_a_id = i.id or m.item_b_id = i.id) and m.status = 'confirmed'
      )
      and not exists (
        select 1 from public.claims c
        where c.item_id = i.id and c.status in ('pending', 'approved')
      )
    for update of i skip locked
  loop
    update public.items set status = 'expired' where id = r.id;
    perform public.create_notification(
      r.user_id, 'item_expired',
      'Your post expired: "' || r.title || '"',
      'It''s no longer shown to other people. Tap to renew it if you''re still looking.',
      r.id
    );
    expired := expired + 1;
  end loop;

  -- 2. Reminders: one a week before, one the day before.
  for r in
    select i.id, i.user_id, i.title, i.expires_at, i.expiry_reminders_sent
    from public.items i
    where i.status::text = 'open'
      and i.deleted_at is null
      and i.expires_at is not null
      and i.expires_at > now()
      and (
        (i.expiry_reminders_sent = 0 and i.expires_at - now() <= public.post_expiry_first_reminder())
        or (i.expiry_reminders_sent = 1 and i.expires_at - now() <= public.post_expiry_final_reminder())
      )
    for update of i skip locked
  loop
    days_left := greatest(1, ceil(extract(epoch from (r.expires_at - now())) / 86400.0)::integer);

    if r.expires_at - now() <= public.post_expiry_final_reminder() then
      perform public.create_notification(
        r.user_id, 'item_expiring',
        'Last day: still looking for "' || r.title || '"?',
        'Your post expires within a day. Tap to keep it up, or let it go.',
        r.id
      );
      update public.items set expiry_reminders_sent = 2 where id = r.id;
    else
      perform public.create_notification(
        r.user_id, 'item_expiring',
        'Still looking for "' || r.title || '"?',
        'Your post expires in ' || days_left || ' days. Tap to keep it up, or let it go if you''re done.',
        r.id
      );
      update public.items set expiry_reminders_sent = 1 where id = r.id;
    end if;
    reminded := reminded + 1;
  end loop;

  return jsonb_build_object('expired', expired, 'reminded', reminded);
end;
$$;

revoke all on function public.process_item_expiry() from public, anon, authenticated;

-- Run it every day at 08:23 UTC if pg_cron is available (it is not an error if
-- it isn't — call `select public.process_item_expiry();` daily instead).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('findora-item-expiry', '23 8 * * *', 'select public.process_item_expiry()');
    raise notice 'Scheduled findora-item-expiry (daily at 08:23 UTC).';
  else
    raise notice 'pg_cron is not enabled, so nothing was scheduled. Enable it (Database -> Extensions) and re-run this file, or call public.process_item_expiry() by hand each day.';
  end if;
exception when others then
  raise notice 'Could not schedule the job (%). Call public.process_item_expiry() by hand each day.', sqlerrm;
end $$;

-- ---- 4. expired posts can't be contacted, and drop out of the matches list -----------------
create or replace function public.start_contact_thread(p_item_id uuid)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  owner_id uuid;
  item_status text;
  thread_id uuid;
  started_today bigint;
begin
  select user_id, status::text into owner_id, item_status from public.items where id = p_item_id;
  if owner_id is null then
    raise exception 'Item not found';
  end if;
  if item_status = 'expired' then
    raise exception 'This post has expired, so it can''t be contacted any more.' using errcode = '22023';
  end if;
  if owner_id = auth.uid() then
    raise exception 'Cannot start a contact thread with yourself';
  end if;
  if public.is_blocked_between(auth.uid(), owner_id) then
    raise exception 'This person can''t be contacted.' using errcode = '42501';
  end if;

  -- Re-opening a conversation that already exists is always fine; only NEW
  -- conversations count towards the limit.
  select id into thread_id from public.contact_threads
  where item_id = p_item_id and contacter_id = auth.uid();
  if thread_id is not null then
    return thread_id;
  end if;

  select count(*) into started_today from public.contact_threads
  where contacter_id = auth.uid() and created_at > now() - interval '24 hours';
  if started_today >= 15 then
    raise exception 'Chat limit reached: you can start 15 new conversations per day. Please try again tomorrow.'
      using errcode = 'RL001';
  end if;

  insert into public.contact_threads (item_id, item_owner_id, contacter_id)
  values (p_item_id, owner_id, auth.uid())
  on conflict (item_id, contacter_id)
    do update set item_id = excluded.item_id -- no-op, just to allow RETURNING below
  returning id into thread_id;

  return thread_id;
end;
$$;

create or replace function public.my_matches_page(
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
      select coalesce(img.thumb_url, img.image_url) from public.item_images img
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
      select coalesce(img.thumb_url, img.image_url) from public.item_images img
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
    and a.status::text not in ('resolved', 'expired')
    and b.status::text not in ('resolved', 'expired')
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
