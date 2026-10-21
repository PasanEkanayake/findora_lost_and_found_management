-- ============================================================================
-- Findora — Server-side thumbnails
-- Run this after 33_approximate_locations.sql, and deploy the
-- `make-thumbnails` Edge Function (supabase/functions/make-thumbnails).
-- Safe to re-run.
--
-- THE PROBLEM. Every list (Browse, My posts, Matches, Chats, the map) showed
-- the FULL photo — up to 1600 px, often several hundred KB — in a tile a few
-- hundred pixels wide. The phone decoded it at list size, but still had to
-- DOWNLOAD all of it. A page of 20 cards could be 5-10 MB of mobile data.
--
-- THE CHANGE. Each photo gets a small companion (480 px on the long side, JPEG,
-- about 30-60 KB) made by an Edge Function right after it is uploaded.
--   * item_images.thumb_url holds its public URL (null = not made yet).
--   * Every query that fetches "the first photo" for a LIST now returns
--     coalesce(thumb_url, image_url): the thumbnail when there is one, the
--     full photo otherwise — so nothing breaks before a photo's thumbnail
--     exists (older posts, a failed run, the function not deployed yet).
--   * The post page's gallery and the matching/embedding code keep using the
--     full image_url.
--   * Only the Edge Function (service role) can set thumb_url: a trigger
--     ignores it from the app, and clears it when a photo is replaced.
-- Existing photos are thumbnailed gradually: each person's app asks for the
-- thumbnails of their own photos once per session, and an admin can run the
-- whole backlog (see the function's README).
-- ============================================================================

alter table public.item_images add column if not exists thumb_url text;

-- Lets "which photos still lack a thumbnail?" stay fast as the table grows.
create index if not exists item_images_missing_thumb_idx
  on public.item_images (created_at)
  where thumb_url is null;

-- thumb_url is written by the Edge Function only; a replaced photo's old
-- thumbnail is stale.
create or replace function public.item_images_protect_thumb()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    if public.is_api_caller() then
      new.thumb_url := null;
    end if;
  elsif new.image_url is distinct from old.image_url then
    new.thumb_url := null;
  elsif public.is_api_caller() and new.thumb_url is distinct from old.thumb_url then
    new.thumb_url := old.thumb_url;
  end if;
  return new;
end;
$$;

drop trigger if exists item_images_protect_thumb on public.item_images;
create trigger item_images_protect_thumb
  before insert or update on public.item_images
  for each row execute function public.item_images_protect_thumb();

-- ---- lists use the thumbnail ------------------------------------------------------------
-- The functions below are their latest definitions, unchanged except that the
-- photo they return is coalesce(thumb_url, image_url).

-- from supabase/08_soft_delete.sql
create or replace function public.nearby_items(
  center_lat double precision,
  center_lng double precision,
  radius_meters int default 5000
)
returns table (
  id uuid,
  title text,
  type public.item_type,
  category_name text,
  location_label text,
  latitude double precision,
  longitude double precision,
  image_url text,
  created_at timestamptz
)
language sql
stable
as $$
  select
    i.id,
    i.title,
    i.type,
    c.name as category_name,
    i.location_label,
    st_y(i.location::geometry) as latitude,
    st_x(i.location::geometry) as longitude,
    (
      select coalesce(img.thumb_url, img.image_url) from public.item_images img
      where img.item_id = i.id
      order by img.created_at
      limit 1
    ) as image_url,
    i.created_at
  from public.items i
  left join public.categories c on c.id = i.category_id
  where i.status = 'open'
    and i.deleted_at is null
    and i.location is not null
    and st_dwithin(
      i.location,
      st_setsrid(st_makepoint(center_lng, center_lat), 4326)::geography,
      radius_meters
    );
$$;

-- from supabase/30_chat_photos.sql
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
      select coalesce(img.thumb_url, img.image_url) from public.item_images img
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

-- from supabase/30_chat_photos.sql
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
      select coalesce(img.thumb_url, img.image_url) from public.item_images img
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

-- from supabase/13_returned_items_and_ratings.sql
create or replace function public.my_returned_items()
returns table (
  my_item_id uuid,
  my_item_title text,
  my_item_type public.item_type,
  my_item_image_url text,
  other_item_id uuid,
  other_item_title text,
  other_item_type public.item_type,
  other_item_image_url text,
  other_user_id uuid,
  other_user_name text,
  match_id uuid,
  resolved_at timestamptz,
  stars_i_gave smallint,
  stars_i_received smallint
)
language sql
stable
as $$
  select
    mine.id,
    mine.title,
    mine.type,
    (
      select coalesce(img.thumb_url, img.image_url) from public.item_images img
      where img.item_id = mine.id
      order by img.created_at
      limit 1
    ),
    theirs.id,
    theirs.title,
    theirs.type,
    (
      select coalesce(img.thumb_url, img.image_url) from public.item_images img
      where img.item_id = theirs.id
      order by img.created_at
      limit 1
    ),
    mine.returned_with_user_id,
    coalesce(p.full_name, p.username, 'Findora user'),
    (
      select m.id from public.matches m
      where (m.item_a_id = mine.id and m.item_b_id = theirs.id)
         or (m.item_a_id = theirs.id and m.item_b_id = mine.id)
      order by (m.status = 'confirmed') desc
      limit 1
    ),
    coalesce(mine.resolved_at, mine.updated_at),
    (
      select r.stars from public.ratings r
      where r.item_id = f.found_id and r.rater_id = auth.uid()
    ),
    (
      select r.stars from public.ratings r
      where r.item_id = f.found_id and r.ratee_id = auth.uid()
    )
  from public.items mine
  left join public.items theirs on theirs.id = mine.returned_with_item_id
  left join public.profiles p on p.id = mine.returned_with_user_id
  cross join lateral (
    select case when mine.type = 'found' then mine.id else mine.returned_with_item_id end
      as found_id
  ) f
  where mine.user_id = auth.uid()
    and mine.status = 'resolved'
    and mine.deleted_at is null
  order by coalesce(mine.resolved_at, mine.updated_at) desc;
$$;

-- from supabase/31_two_sided_confirmation.sql
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
