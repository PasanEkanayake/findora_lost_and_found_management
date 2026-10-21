-- ============================================================================
-- Findora — checks for 33_approximate_locations.sql
-- Run in the Supabase SQL editor against a STAGING project after applying 33.
-- Read-only except where marked. NOT run by the author.
-- ============================================================================

-- 1. The private table exists, is locked down, and clients can't touch it
--    (expect true, false, false, false).
select (select relrowsecurity from pg_class where oid = 'public.item_exact_locations'::regclass),
       has_table_privilege('authenticated', 'public.item_exact_locations', 'select'),
       has_table_privilege('authenticated', 'public.item_exact_locations', 'insert'),
       has_table_privilege('anon', 'public.item_exact_locations', 'select');

-- 2. Every post that has a location also has a private exact one (expect 0).
select count(*) as missing_exact
from public.items i
where i.location is not null
  and not exists (select 1 from public.item_exact_locations e where e.item_id = i.id);

-- 3. Public locations really are snapped: re-snapping changes nothing (expect 0).
select count(*) as not_snapped
from public.items i
where i.location is not null
  and st_astext(public.snap_location_for_public(i.location)) is distinct from st_astext(i.location);

-- 4. No post is the same point as its exact one unless it sits on a grid centre
--    (expect a tiny number — ideally 0 on real data).
select count(*) as public_equals_exact
from public.items i
join public.item_exact_locations e on e.item_id = i.id
where st_astext(i.location) = st_astext(e.location);

-- 5. The public point is never farther than ~400 m from the exact one (expect 0).
select count(*) as too_far
from public.items i
join public.item_exact_locations e on e.item_id = i.id
where st_distance(i.location, e.location) > 420;

-- 6. No public label still contains a comma-separated street part (expect 0).
select count(*) from public.items where location_label like '%,%';

-- 7. Function behaviour (expect 'Singapore', 'Singapore', 'Orchard', 'Pinned location').
select public.coarse_location_label('12 Orchard Rd, Singapore'),
       public.coarse_location_label('Singapore'),
       public.coarse_location_label('Orchard'),
       public.coarse_location_label('Pinned location');

-- 8. get_item_coordinates now has is_exact (expect 3 columns incl. is_exact).
select pg_get_function_result('public.get_item_coordinates(uuid)'::regprocedure);

-- 9. Walk-through (staging, two accounts, a post P by owner O):
--    a. O posts with a pin on a known address. In the SQL editor:
--         select st_astext(location) from items where id = '<P>';                -- approximate
--         select st_astext(location) from item_exact_locations where item_id='<P>'; -- exact
--    b. As O in the app: Edit post -> the map/pin opens on the EXACT spot.
--       As another user: the post page shows a shaded circle, no pin, and the
--       label is a neighbourhood or town; Browse > map shows circles.
--    c. As O, edit only the title: both points are unchanged.
--    d. As O, move the pin: the approximate point moves to the new cell.
--    e. As the other user, run  select * from get_item_coordinates('<P>')  -> is_exact = false.
