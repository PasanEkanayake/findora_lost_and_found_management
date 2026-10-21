-- ============================================================================
-- Findora — Approximate public locations
-- Run this after 32_moderation.sql. Safe to re-run.
--
-- THE GAP
-- Every post stored the exact point its owner pinned, and handed it to anyone:
-- the map's nearby_items() returned each post's exact latitude/longitude,
-- get_item_coordinates() returned any post's, the "N m away" on a match card
-- was the exact distance between two posts' exact spots (enough, with a few
-- test posts, to work out where someone's item — often their home or
-- workplace — really is), and the location label was a street address
-- ("12 Orchard Rd, Singapore").
--
-- THE CHANGE
--   * items.location now holds an APPROXIMATE point: the exact one snapped to
--     the centre of a grid cell about 550 m across (public_location_grid_degrees()).
--     Everything that already reads items.location — the map, "Nearest to me",
--     saved-search alerts, matching, the distance on a match card — therefore
--     becomes approximate automatically, with no change to those functions.
--     A grid (rather than random jitter) can't be averaged back to the real
--     spot by asking repeatedly, and needs no secret.
--   * The exact point lives in item_exact_locations, a private table no client
--     can read. Only the post's OWNER gets it back, through
--     get_item_coordinates(), which now also says whether it returned the
--     exact or the approximate spot (is_exact).
--   * items.location_label is reduced to its coarse part (the street is
--     dropped); the original is kept privately with the exact point.
--   * A trigger does this on every insert/edit, whatever app version wrote
--     the row, so an old app can't leak the exact spot or overwrite it with
--     the approximate one.
--   * "Download my data" returns the owner's exact location (and the public one).
--
-- Existing posts are converted below. The approximate location is rewritten,
-- which makes the existing match scores refresh (their distances become
-- approximate too).
-- ============================================================================

-- ---- 1. the approximation ----------------------------------------------------------
-- Cell size in degrees of latitude (0.005 is about 550 m). Larger = more private,
-- less precise. Changing it only affects posts saved afterwards.
create or replace function public.public_location_grid_degrees()
returns double precision language sql immutable as $$ select 0.005::double precision $$;

-- The centre of the grid cell the point falls in. Longitude cells are widened
-- toward the poles so a cell stays about the same size on the ground.
create or replace function public.snap_location_for_public(p_location geography)
returns geography
language plpgsql
immutable
as $$
declare
  step double precision := public.public_location_grid_degrees();
  lat double precision;
  lng double precision;
  lat_snapped double precision;
  lng_step double precision;
begin
  if p_location is null then
    return null;
  end if;
  lat := st_y(p_location::geometry);
  lng := st_x(p_location::geometry);
  lat_snapped := round(lat / step) * step;
  lng_step := step / greatest(cos(radians(lat_snapped)), 0.05);
  return st_setsrid(st_makepoint(round(lng / lng_step) * lng_step, lat_snapped), 4326)::geography;
end;
$$;

-- "12 Orchard Rd, Singapore" -> "Singapore". Labels with a comma lose their
-- first part (the street); single-part labels are already coarse and are kept.
create or replace function public.coarse_location_label(p_label text)
returns text
language sql
immutable
as $$
  select case
    when p_label is null then null
    when position(',' in p_label) > 0
      then coalesce(nullif(btrim(regexp_replace(p_label, '^[^,]*,', '')), ''), 'Pinned location')
    else p_label
  end;
$$;

-- ---- 2. the private exact location ----------------------------------------------------
create table if not exists public.item_exact_locations (
  item_id uuid primary key references public.items (id) on delete cascade
    deferrable initially deferred,
  location geography(point, 4326) not null,
  label text,
  updated_at timestamptz not null default now()
);

alter table public.item_exact_locations enable row level security;
-- No policies and no grants: only the security-definer functions below touch it.
revoke all on public.item_exact_locations from anon, authenticated;

-- ---- 3. keep items.location approximate, whoever writes it -------------------------------
create or replace function public.items_privatize_location()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  exact geography;
  raw_label text;
  location_given boolean;
  label_given boolean;
begin
  location_given := new.location is not null
    and (tg_op = 'INSERT' or st_astext(new.location) is distinct from st_astext(old.location));
  label_given := new.location_label is not null
    and (tg_op = 'INSERT' or new.location_label is distinct from old.location_label);

  if label_given then
    raw_label := new.location_label;
    new.location_label := public.coarse_location_label(new.location_label);
  end if;

  if location_given then
    -- A pinned point arrived: keep it privately, publish only the snapped one.
    exact := new.location;
    new.location := public.snap_location_for_public(exact);
    insert into public.item_exact_locations (item_id, location, label, updated_at)
    values (new.id, exact, raw_label, now())
    on conflict (item_id) do update
      set location = excluded.location,
          label = coalesce(excluded.label, public.item_exact_locations.label),
          updated_at = now();
  elsif tg_op = 'UPDATE' and new.location is null and old.location is not null then
    -- The owner cleared the location.
    delete from public.item_exact_locations where item_id = new.id;
  elsif label_given then
    update public.item_exact_locations
    set label = raw_label, updated_at = now()
    where item_id = new.id;
  end if;

  return new;
end;
$$;

revoke all on function public.items_privatize_location() from public, anon, authenticated;

drop trigger if exists items_privatize_location on public.items;
create trigger items_privatize_location
  before insert or update of location, location_label on public.items
  for each row execute function public.items_privatize_location();

-- ---- 4. convert existing posts ---------------------------------------------------------------
-- Keep the exact point and the street label privately...
insert into public.item_exact_locations (item_id, location, label)
select i.id, i.location, i.location_label
from public.items i
where i.location is not null
  and not exists (select 1 from public.item_exact_locations e where e.item_id = i.id);

-- ...then publish only the approximation. The privatising trigger is paused for
-- this one update (it would mistake the snapped point for a newly pinned one).
alter table public.items disable trigger items_privatize_location;

update public.items i
set location = public.snap_location_for_public(i.location),
    location_label = public.coarse_location_label(i.location_label)
where i.location is not null
  and exists (
    select 1 from public.item_exact_locations e
    where e.item_id = i.id
      and st_astext(e.location) = st_astext(i.location)   -- not yet snapped
  );

alter table public.items enable trigger items_privatize_location;

-- ---- 5. what each caller gets back -------------------------------------------------------------
-- The owner gets the exact spot; everyone else the approximate one. is_exact tells
-- the app which, so it can draw an area instead of a pin.
drop function if exists public.get_item_coordinates(uuid);

create function public.get_item_coordinates(p_item_id uuid)
returns table (latitude double precision, longitude double precision, is_exact boolean)
language sql
stable
security definer set search_path = public
as $$
  select
    st_y(g::geometry),
    st_x(g::geometry),
    exact
  from (
    select
      case when i.user_id = auth.uid() and e.location is not null then e.location else i.location end as g,
      (i.user_id = auth.uid() and e.location is not null) as exact
    from public.items i
    left join public.item_exact_locations e on e.item_id = i.id
    where i.id = p_item_id
      and i.location is not null
      and i.deleted_at is null
  ) s;
$$;

revoke all on function public.get_item_coordinates(uuid) from public, anon;
grant execute on function public.get_item_coordinates(uuid) to authenticated;

-- ---- 6. "Download my data" includes the exact location -------------------------------------------
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
             -- The owner's own data: the EXACT spot they pinned (other people only
             -- ever see the approximate public location, items.location).
             'latitude', case when i.location is null then null else
               st_y(coalesce((select e.location from public.item_exact_locations e where e.item_id = i.id), i.location)::geometry) end,
             'longitude', case when i.location is null then null else
               st_x(coalesce((select e.location from public.item_exact_locations e where e.item_id = i.id), i.location)::geometry) end,
             'exact_location_label', (select e.label from public.item_exact_locations e where e.item_id = i.id),
             'public_latitude', case when i.location is null then null else st_y(i.location::geometry) end,
             'public_longitude', case when i.location is null then null else st_x(i.location::geometry) end,
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
