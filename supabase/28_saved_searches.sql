-- ============================================================================
-- Findora — Saved searches with alerts, and date / sort filters on Browse
-- Run this after 27_country_settings.sql. Safe to re-run.
--
-- 1. SAVED SEARCHES. Someone looking for a lost black wallet can save that
--    search (words, category, lost/found, in their country). When a NEW post
--    that fits is made, they get an alert (in the app, and a push through the
--    existing webhook) that opens the post. Details:
--      * up to 10 saved searches per person;
--      * only posts from the SAME country as the search, made after it was saved;
--      * never for your own posts, or posts by people you've blocked or who
--        blocked you;
--      * one alert per person per post, and a given search alerts at most once
--        every 30 minutes (a burst of matching posts is one alert, not twenty);
--      * a search can be switched off without deleting it.
-- 2. BROWSE FILTERS.
--      * feed_counts() learns the "posted within" window, so the header totals
--        match the filtered list;
--      * feed_nearest_ids() returns posts ordered by distance from the person
--        (posts without a location last), for the "Nearest to me" sort.
-- 3. Saved searches are included in "Download my data" and removed when an
--    account is deleted.
-- ============================================================================

create table if not exists public.saved_searches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  -- Words that must appear in the title or description (null = any).
  query text,
  category_id uuid references public.categories (id) on delete set null,
  -- 'lost' | 'found' | null for both.
  type text check (type in ('lost', 'found')),
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),
  active boolean not null default true,
  last_notified_at timestamptz,
  created_at timestamptz not null default now(),
  constraint saved_searches_query_len check (query is null or char_length(query) between 1 and 60),
  -- A search with no words and no category would alert on every post.
  constraint saved_searches_not_empty check (query is not null or category_id is not null)
);

create index if not exists saved_searches_user_idx on public.saved_searches (user_id);
create index if not exists saved_searches_alert_idx
  on public.saved_searches (country_code) where active;

-- The same search can't be saved twice.
create unique index if not exists saved_searches_unique_idx
  on public.saved_searches (
    user_id, country_code, coalesce(type, ''), coalesce(category_id::text, ''), lower(coalesce(query, ''))
  );

alter table public.saved_searches enable row level security;
revoke all on public.saved_searches from anon;

drop policy if exists "people can see their saved searches" on public.saved_searches;
create policy "people can see their saved searches"
  on public.saved_searches for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "people can save searches" on public.saved_searches;
create policy "people can save searches"
  on public.saved_searches for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "people can switch their saved searches on and off" on public.saved_searches;
create policy "people can switch their saved searches on and off"
  on public.saved_searches for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "people can delete their saved searches" on public.saved_searches;
create policy "people can delete their saved searches"
  on public.saved_searches for delete to authenticated
  using ((select auth.uid()) = user_id);

-- Only the on/off switch is editable; to change a search, delete and re-save.
revoke update on public.saved_searches from anon, authenticated;
grant update (active) on public.saved_searches to authenticated;

-- At most 10 per person.
create or replace function public.limit_saved_searches()
returns trigger
language plpgsql
as $$
declare
  existing bigint;
begin
  if not public.is_api_caller() then
    return new;
  end if;
  select count(*) into existing from public.saved_searches where user_id = new.user_id;
  if existing >= 10 then
    raise exception 'You can save up to 10 searches. Delete one to save another.'
      using errcode = '22023';
  end if;
  return new;
end;
$$;

drop trigger if exists saved_searches_limit on public.saved_searches;
create trigger saved_searches_limit
  before insert on public.saved_searches
  for each row execute function public.limit_saved_searches();

-- ----------------------------------------------------------------------------
-- Alerts: a new open post -> everyone with a matching saved search
-- ----------------------------------------------------------------------------
create or replace function public.notify_saved_searches()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  s record;
begin
  -- Older posts have no country and can't be matched to a country-bound search.
  if new.status <> 'open' or new.deleted_at is not null or new.country_code is null then
    return new;
  end if;

  for s in
    select distinct on (ss.user_id) ss.id, ss.user_id, ss.query
    from public.saved_searches ss
    where ss.active
      and ss.country_code = new.country_code
      and ss.user_id <> new.user_id
      and (ss.type is null or ss.type = new.type::text)
      and (ss.category_id is null or ss.category_id = new.category_id)
      and (
        ss.query is null
        or new.title ilike '%' || replace(replace(replace(ss.query, '\', '\\'), '%', '\%'), '_', '\_') || '%'
        or coalesce(new.description, '') ilike '%' || replace(replace(replace(ss.query, '\', '\\'), '%', '\%'), '_', '\_') || '%'
      )
      and (ss.last_notified_at is null or ss.last_notified_at < now() - interval '30 minutes')
      and not public.is_blocked_between(ss.user_id, new.user_id)
    order by ss.user_id, ss.created_at
  loop
    perform public.create_notification(
      s.user_id,
      'saved_search',
      'New ' || new.type::text || ' post: "' || left(new.title, 60) || '"',
      case when s.query is null then 'Matches one of your saved searches.'
           else 'Matches your saved search "' || s.query || '".' end,
      new.id,
      null
    );
    update public.saved_searches set last_notified_at = now() where id = s.id;
  end loop;

  return new;
end;
$$;

drop trigger if exists items_notify_saved_searches on public.items;
create trigger items_notify_saved_searches
  after insert on public.items
  for each row execute function public.notify_saved_searches();

revoke all on function public.notify_saved_searches() from public, anon, authenticated;

-- Deleting an account removes its saved searches.
create or replace function public.clear_saved_searches_on_deletion()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  delete from public.saved_searches where user_id = new.id;
  return new;
end;
$$;

drop trigger if exists profiles_clear_saved_searches on public.profiles;
create trigger profiles_clear_saved_searches
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.clear_saved_searches_on_deletion();

revoke all on function public.clear_saved_searches_on_deletion() from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- Browse: counts that follow the "posted within" window
-- ----------------------------------------------------------------------------
drop function if exists public.feed_counts(uuid, text, text);

create or replace function public.feed_counts(
  p_category_id uuid default null,
  p_search text default null,
  p_country text default null,
  p_since timestamptz default null
)
returns table (lost_count bigint, found_count bigint)
language sql
stable
as $$
  select
    count(*) filter (where i.type = 'lost'),
    count(*) filter (where i.type = 'found')
  from public.items i
  where i.status = 'open'
    and i.deleted_at is null
    and (p_country is null or i.country_code = upper(p_country))
    and (p_category_id is null or i.category_id = p_category_id)
    and (p_since is null or i.created_at >= p_since)
    and (
      nullif(btrim(coalesce(p_search, '')), '') is null
      or i.title ilike '%' || replace(replace(replace(btrim(p_search), '\', '\\'), '%', '\%'), '_', '\_') || '%'
      or i.description ilike '%' || replace(replace(replace(btrim(p_search), '\', '\\'), '%', '\%'), '_', '\_') || '%'
    );
$$;

revoke all on function public.feed_counts(uuid, text, text, timestamptz) from public, anon;
grant execute on function public.feed_counts(uuid, text, text, timestamptz) to authenticated;

-- ----------------------------------------------------------------------------
-- Browse: "Nearest to me". Returns post ids in order of distance (metres) from
-- the given point, those with no location last, with the same filters as the
-- feed. SECURITY INVOKER: row-level security applies as usual.
-- ----------------------------------------------------------------------------
create or replace function public.feed_nearest_ids(
  p_lat double precision,
  p_lng double precision,
  p_country text default null,
  p_category_id uuid default null,
  p_search text default null,
  p_type text default null,
  p_since timestamptz default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (id uuid, distance_m real)
language sql
stable
as $$
  select
    i.id,
    case when i.location is null then null
         else st_distance(i.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography)::real
    end
  from public.items i
  where i.status = 'open'
    and i.deleted_at is null
    and (p_country is null or i.country_code = upper(p_country))
    and (p_category_id is null or i.category_id = p_category_id)
    and (p_type is null or i.type::text = p_type)
    and (p_since is null or i.created_at >= p_since)
    and (
      nullif(btrim(coalesce(p_search, '')), '') is null
      or i.title ilike '%' || replace(replace(replace(btrim(p_search), '\', '\\'), '%', '\%'), '_', '\_') || '%'
      or i.description ilike '%' || replace(replace(replace(btrim(p_search), '\', '\\'), '%', '\%'), '_', '\_') || '%'
    )
  order by
    (i.location is null),
    i.location <-> st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
    i.created_at desc,
    i.id
  limit greatest(1, least(p_limit, 50))
  offset greatest(0, p_offset);
$$;

revoke all on function public.feed_nearest_ids(
  double precision, double precision, text, uuid, text, text, timestamptz, integer, integer
) from public, anon;
grant execute on function public.feed_nearest_ids(
  double precision, double precision, text, uuid, text, text, timestamptz, integer, integer
) to authenticated;

-- ----------------------------------------------------------------------------
-- "Download my data" (from 25) — now includes saved searches.
-- ----------------------------------------------------------------------------
create or replace function public.export_my_data()
returns jsonb
language plpgsql
stable
security definer set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'exported_at', now(),
    'note', 'Everything Findora holds about this account. Other people appear only as ids.',
    'account', (
      select jsonb_build_object('id', u.id, 'email', u.email, 'created_at', u.created_at)
      from auth.users u where u.id = me
    ),
    'profile', (select to_jsonb(p) - 'is_admin' from public.profiles p where p.id = me),
    'private_profile', (select to_jsonb(pp) from public.profile_private pp where pp.id = me),
    'devices', (select count(*) from public.device_tokens d where d.user_id = me),
    'items', coalesce((
      select jsonb_agg(
        (to_jsonb(i) - 'text_embedding' - 'location')
        || jsonb_build_object(
             'latitude', case when i.location is null then null else st_y(i.location::geometry) end,
             'longitude', case when i.location is null then null else st_x(i.location::geometry) end,
             'proof_answer', (select ip.proof_answer from public.item_private ip where ip.item_id = i.id),
             'photos', coalesce((select jsonb_agg(im.image_url order by im.created_at)
                                 from public.item_images im where im.item_id = i.id), '[]'::jsonb)
           )
        order by i.created_at)
      from public.items i where i.user_id = me
    ), '[]'::jsonb),
    'matches', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.created_at)
      from public.matches m
      join public.items a on a.id = m.item_a_id
      join public.items b on b.id = m.item_b_id
      where a.user_id = me or b.user_id = me
    ), '[]'::jsonb),
    'messages', coalesce((
      select jsonb_agg(to_jsonb(ms) order by ms.created_at)
      from public.messages ms where ms.sender_id = me or ms.receiver_id = me
    ), '[]'::jsonb),
    'direct_threads', coalesce((
      select jsonb_agg(to_jsonb(t) order by t.created_at)
      from public.contact_threads t where t.item_owner_id = me or t.contacter_id = me
    ), '[]'::jsonb),
    'direct_messages', coalesce((
      select jsonb_agg(to_jsonb(cm) order by cm.created_at)
      from public.contact_messages cm
      join public.contact_threads t on t.id = cm.thread_id
      where t.item_owner_id = me or t.contacter_id = me
    ), '[]'::jsonb),
    'claims', coalesce((
      select jsonb_agg(to_jsonb(c) order by c.created_at)
      from public.claims c
      left join public.items i on i.id = c.item_id
      where c.claimant_id = me or i.user_id = me
    ), '[]'::jsonb),
    'ratings_given', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.created_at) from public.ratings r where r.rater_id = me
    ), '[]'::jsonb),
    'ratings_received', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.created_at) from public.ratings r where r.ratee_id = me
    ), '[]'::jsonb),
    'notifications', coalesce((
      select jsonb_agg(to_jsonb(n) order by n.created_at) from public.notifications n where n.user_id = me
    ), '[]'::jsonb),
    'saved_searches', coalesce((
      select jsonb_agg(to_jsonb(ss) order by ss.created_at)
      from public.saved_searches ss where ss.user_id = me
    ), '[]'::jsonb),
    'blocked_people', coalesce((
      select jsonb_agg(b.blocked_id) from public.user_blocks b where b.blocker_id = me
    ), '[]'::jsonb),
    'reports_filed', jsonb_build_object(
      'posts', coalesce((select jsonb_agg(to_jsonb(r)) from public.reports r where r.reporter_id = me), '[]'::jsonb),
      'people', coalesce((select jsonb_agg(to_jsonb(r)) from public.user_reports r where r.reporter_id = me), '[]'::jsonb)
    )
  );
end;
$$;

-- ============================================================================
-- Verify (optional): supabase/tests/28_checks.sql
-- Also redeploy the push function so alerts open the post:
--   supabase functions deploy send-push-notification
-- ============================================================================
