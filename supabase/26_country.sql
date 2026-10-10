-- ============================================================================
-- Findora — Country on every post
-- Run this after 25_outcomes_and_data_export.sql. Safe to re-run.
--
-- Every post now says which COUNTRY the place is in (ISO 3166-1 code, e.g. LK),
-- and it is compulsory: the app won't submit without one and the database
-- refuses a new post from the app without one. Why:
--   * the Browse feed shows each person the posts from THEIR country
--     (profiles.country_code, or the phone's region until they set it), so
--     people in different countries don't wade through each other's posts;
--   * match suggestions are never made between posts in different countries.
--
-- OLDER POSTS have no country. They are left alone and still work, but the
-- feed only shows posts whose country matches the viewer's, so they won't
-- appear in anyone's feed until given one. If your existing posts are all
-- from one country, set them in one go (change LK to yours):
--
--     update public.items set country_code = 'LK' where country_code is null;
--
-- Edits to an older post through the app will ask for the country.
-- ============================================================================

alter table public.profiles add column if not exists country_code text;
alter table public.items add column if not exists country_code text;

do $$ begin
  alter table public.profiles
    add constraint profiles_country_format
    check (country_code is null or country_code ~ '^[A-Z]{2}$');
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.items
    add constraint items_country_format
    check (country_code is null or country_code ~ '^[A-Z]{2}$');
exception when duplicate_object then null; end $$;

-- People can set their own country (the column grants from 17 only allowed
-- name, username and avatar).
grant update (country_code) on public.profiles to authenticated;

-- Feed: open, not removed, newest first — per country.
create index if not exists items_country_feed_idx
  on public.items (country_code, created_at desc, id desc)
  where status = 'open' and deleted_at is null;

-- Upper-case the code, require it on new posts from the app, and don't let a
-- post lose its country later. (Inserts from the SQL editor / our own functions
-- are not forced to supply one — only direct app/API writes are.)
create or replace function public.require_item_country()
returns trigger
language plpgsql
as $$
begin
  if new.country_code is not null then
    new.country_code := upper(btrim(new.country_code));
  end if;

  if tg_op = 'INSERT' then
    if new.country_code is null and public.is_api_caller() then
      raise exception 'Please choose the country where it was lost or found.'
        using errcode = '22023';
    end if;
  elsif new.country_code is null and old.country_code is not null then
    raise exception 'A post must keep its country.' using errcode = '22023';
  end if;
  return new;
end;
$$;

drop trigger if exists items_require_country on public.items;
create trigger items_require_country
  before insert or update on public.items
  for each row execute function public.require_item_country();

create or replace function public.normalise_profile_country()
returns trigger
language plpgsql
as $$
begin
  if new.country_code is not null then
    new.country_code := upper(btrim(new.country_code));
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_normalise_country on public.profiles;
create trigger profiles_normalise_country
  before insert or update of country_code on public.profiles
  for each row execute function public.normalise_profile_country();

-- ----------------------------------------------------------------------------
-- feed_counts: now per country (replaces the 2-argument version from 19).
-- ----------------------------------------------------------------------------
drop function if exists public.feed_counts(uuid, text);

create or replace function public.feed_counts(
  p_category_id uuid default null,
  p_search text default null,
  p_country text default null
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
    and (
      nullif(btrim(coalesce(p_search, '')), '') is null
      or i.title ilike '%' || replace(replace(replace(btrim(p_search), '\', '\\'), '%', '\%'), '_', '\_') || '%'
      or i.description ilike '%' || replace(replace(replace(btrim(p_search), '\', '\\'), '%', '\%'), '_', '\_') || '%'
    );
$$;

revoke all on function public.feed_counts(uuid, text, text) from public, anon;
grant execute on function public.feed_counts(uuid, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- upsert_match_score (from 18): never match across countries.
-- ----------------------------------------------------------------------------
create or replace function public.upsert_match_score(
  p_item_a uuid,
  p_item_b uuid,
  p_image_similarity real,
  p_text_similarity real
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  a public.items%rowtype;
  b public.items%rowtype;
  s record;
  v_image real;
  v_text real;
  v_score real;
  existing_id uuid;
  v_new_id uuid;
begin
  select * into a from public.items where id = p_item_a;
  if not found then return; end if;
  select * into b from public.items where id = p_item_b;
  if not found then return; end if;

  -- Posts in different countries are never proposed as matches (a wallet found
  -- in one country can't be the one lost in another, and the feed is per
  -- country too). Posts with no country yet (older ones) are still compared.
  if a.country_code is not null and b.country_code is not null
     and a.country_code <> b.country_code then
    return;
  end if;

  select * into s from public.pair_match_signals(p_item_a, p_item_b);
  v_image := coalesce(s.image_sim, p_image_similarity);
  v_text := coalesce(s.text_sim, p_text_similarity);
  v_score := coalesce(
    public.calibrated_match_score(
      v_image, v_text, public.text_specificity(p_item_a, p_item_b), s.gps_sim, s.time_sim
    ),
    0
  );

  -- The unique constraint is on the ordered pair, so an existing row could be
  -- stored in either order — check both.
  select id into existing_id from public.matches
  where (item_a_id = p_item_a and item_b_id = p_item_b)
     or (item_a_id = p_item_b and item_b_id = p_item_a)
  limit 1;

  if existing_id is not null then
    update public.matches m
    set
      image_similarity = v_image,
      text_similarity = v_text,
      distance_meters = s.dist,
      time_proximity = s.time_sim,
      similarity_score = v_score
    where m.id = existing_id;
  else
    insert into public.matches (
      item_a_id, item_b_id, image_similarity, text_similarity,
      distance_meters, time_proximity, similarity_score
    ) values (
      p_item_a, p_item_b, v_image, v_text, s.dist, s.time_sim, v_score
    )
    on conflict (item_a_id, item_b_id) do nothing -- race safety only
    returning id into v_new_id;

    if v_new_id is not null then
      perform public.create_notification(
        a.user_id, 'new_match',
        'New match: "' || b.title || '"',
        'Compared with your "' || a.title || '".',
        a.id, v_new_id
      );
      perform public.create_notification(
        b.user_id, 'new_match',
        'New match: "' || a.title || '"',
        'Compared with your "' || b.title || '".',
        b.id, v_new_id
      );
    end if;
  end if;
end;
$$;

revoke all on function public.upsert_match_score(uuid, uuid, real, real) from public, anon, authenticated;

-- Tidy up: a still-undecided match between two posts that are in DIFFERENT
-- countries (possible only for posts that had a country set after being
-- matched) is removed. Matches anyone has confirmed or dismissed are kept.
delete from public.matches m
using public.items a, public.items b
where a.id = m.item_a_id and b.id = m.item_b_id
  and m.status = 'pending'
  and a.country_code is not null and b.country_code is not null
  and a.country_code <> b.country_code;

-- ============================================================================
-- Verify (optional): supabase/tests/26_checks.sql, or by hand:
--   select country_code, count(*) from public.items group by 1 order by 2 desc;
-- ============================================================================
