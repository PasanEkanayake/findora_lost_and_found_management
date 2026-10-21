-- ============================================================================
-- Findora — checks for 28_saved_searches.sql
-- Run in the Supabase SQL editor against a STAGING project after applying 28.
-- Throw-away users, rolled back at the end. NOT run by the author.
-- ============================================================================
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-4000-8000-000000000a01', 't28-a@example.test', '{"country_code": "LK"}'),
  ('00000000-0000-4000-8000-000000000a02', 't28-b@example.test', '{"country_code": "LK"}');

-- ---------- saving searches --------------------------------------------------

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000a01","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.saved_searches (user_id, query, country_code) values ('00000000-0000-4000-8000-000000000a01', 'zzsaved wallet', 'LK')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: a person can save a search (expected allowed)';
  end if;
  raise notice 'PASS: a person can save a search';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000a01","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.saved_searches (user_id, country_code) values ('00000000-0000-4000-8000-000000000a01', 'LK')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: a search with no words and no category is refused (expected blocked)';
  end if;
  raise notice 'PASS: a search with no words and no category is refused';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000a01","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.saved_searches (user_id, query, country_code) values ('00000000-0000-4000-8000-000000000a01', 'ZZSAVED WALLET', 'LK')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: saving the same search twice is refused (expected blocked)';
  end if;
  raise notice 'PASS: saving the same search twice is refused';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000a01","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.saved_searches (user_id, query, country_code) values ('00000000-0000-4000-8000-000000000a01', 'zzsaved keys', 'LKA')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: a bad country is refused (expected blocked)';
  end if;
  raise notice 'PASS: a bad country is refused';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000a02","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.saved_searches (user_id, query, country_code) values ('00000000-0000-4000-8000-000000000a01', 'zzsaved spy', 'LK')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: nobody can save a search for someone else (expected blocked)';
  end if;
  raise notice 'PASS: nobody can save a search for someone else';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000a02","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select count(*) from (select 1 from public.saved_searches) s$q$ into n;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: other people can''t see my saved searches (expected blocked)';
  end if;
  raise notice 'PASS: other people can''t see my saved searches';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000a01","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select count(*) from (select 1 from public.saved_searches) s$q$ into n;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: I can see my own (expected allowed)';
  end if;
  raise notice 'PASS: I can see my own';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000a01","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.saved_searches set query = 'changed'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: only the on/off switch can be edited (expected blocked)';
  end if;
  raise notice 'PASS: only the on/off switch can be edited';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000a01","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.saved_searches (user_id, query, country_code) select '00000000-0000-4000-8000-000000000a01', 'zzsaved ' || g, 'LK' from generate_series(1, 10) g$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: more than 10 saved searches is refused (expected blocked)';
  end if;
  raise notice 'PASS: more than 10 saved searches is refused';
end
$t$;

-- ---------- alerts --------------------------------------------------------------

insert into public.items (user_id, type, title, country_code)
values ('00000000-0000-4000-8000-000000000a02', 'found', 'zzsaved wallet black leather', 'LK');

do $t$
declare n bigint;
begin
  select (select count(*) from public.notifications where user_id = '00000000-0000-4000-8000-000000000a01' and type = 'saved_search' and item_id is not null) into n;
  if n is distinct from 1 then
    raise exception 'FAIL: a matching new post alerts the person (got % , expected 1)', n;
  end if;
  raise notice 'PASS: a matching new post alerts the person';
end
$t$;

insert into public.items (user_id, type, title, country_code)
values ('00000000-0000-4000-8000-000000000a02', 'found', 'zzsaved wallet brown', 'LK');

do $t$
declare n bigint;
begin
  select (select count(*) from public.notifications where user_id = '00000000-0000-4000-8000-000000000a01' and type = 'saved_search') into n;
  if n is distinct from 1 then
    raise exception 'FAIL: a second matching post right after does not alert again (30-minute limit) (got % , expected 1)', n;
  end if;
  raise notice 'PASS: a second matching post right after does not alert again (30-minute limit)';
end
$t$;

update public.saved_searches set last_notified_at = null where user_id = '00000000-0000-4000-8000-000000000a01';
insert into public.items (user_id, type, title, country_code)
values ('00000000-0000-4000-8000-000000000a02', 'found', 'zzsaved wallet in another country', 'US');

do $t$
declare n bigint;
begin
  select (select count(*) from public.notifications where user_id = '00000000-0000-4000-8000-000000000a01' and type = 'saved_search') into n;
  if n is distinct from 1 then
    raise exception 'FAIL: a post in another country does not alert (got % , expected 1)', n;
  end if;
  raise notice 'PASS: a post in another country does not alert';
end
$t$;

insert into public.items (user_id, type, title, country_code)
values ('00000000-0000-4000-8000-000000000a01', 'lost', 'zzsaved wallet my own', 'LK');

do $t$
declare n bigint;
begin
  select (select count(*) from public.notifications where user_id = '00000000-0000-4000-8000-000000000a01' and type = 'saved_search') into n;
  if n is distinct from 1 then
    raise exception 'FAIL: your own post does not alert you (got % , expected 1)', n;
  end if;
  raise notice 'PASS: your own post does not alert you';
end
$t$;

update public.saved_searches set active = false where user_id = '00000000-0000-4000-8000-000000000a01';
insert into public.items (user_id, type, title, country_code)
values ('00000000-0000-4000-8000-000000000a02', 'found', 'zzsaved wallet while switched off', 'LK');

do $t$
declare n bigint;
begin
  select (select count(*) from public.notifications where user_id = '00000000-0000-4000-8000-000000000a01' and type = 'saved_search') into n;
  if n is distinct from 1 then
    raise exception 'FAIL: a switched-off search does not alert (got % , expected 1)', n;
  end if;
  raise notice 'PASS: a switched-off search does not alert';
end
$t$;

update public.saved_searches set active = true where user_id = '00000000-0000-4000-8000-000000000a01';
insert into public.user_blocks (blocker_id, blocked_id) values ('00000000-0000-4000-8000-000000000a01', '00000000-0000-4000-8000-000000000a02');
insert into public.items (user_id, type, title, country_code)
values ('00000000-0000-4000-8000-000000000a02', 'found', 'zzsaved wallet from a blocked person', 'LK');

do $t$
declare n bigint;
begin
  select (select count(*) from public.notifications where user_id = '00000000-0000-4000-8000-000000000a01' and type = 'saved_search') into n;
  if n is distinct from 1 then
    raise exception 'FAIL: posts by someone you blocked do not alert (got % , expected 1)', n;
  end if;
  raise notice 'PASS: posts by someone you blocked do not alert';
end
$t$;

-- ---------- Browse: counts window and nearest-first ----------------------------

do $t$
declare n bigint;
begin
  select (select found_count from public.feed_counts(null, 'zzsaved', 'LK', now() + interval '1 day')) into n;
  if n is distinct from 0 then
    raise exception 'FAIL: feed_counts honours the ''posted within'' window (got % , expected 0)', n;
  end if;
  raise notice 'PASS: feed_counts honours the ''posted within'' window';
end
$t$;

insert into public.items (id, user_id, type, title, country_code, location) values
  ('00000000-0000-4000-8000-000000000b01', '00000000-0000-4000-8000-000000000a02', 'found', 'zznear one',   'LK', st_setsrid(st_makepoint(80.00, 7.00), 4326)::geography),
  ('00000000-0000-4000-8000-000000000b02', '00000000-0000-4000-8000-000000000a02', 'found', 'zznear two',   'LK', st_setsrid(st_makepoint(80.50, 7.50), 4326)::geography),
  ('00000000-0000-4000-8000-000000000b03', '00000000-0000-4000-8000-000000000a02', 'found', 'zznear three', 'LK', null);

do $t$
declare ids uuid[];
begin
  select array_agg(id order by ord) into ids
  from (select id, row_number() over () as ord
        from public.feed_nearest_ids(7.0, 80.0, 'LK', null, 'zznear', null, null, 10, 0)) s;
  if ids is distinct from array['00000000-0000-4000-8000-000000000b01', '00000000-0000-4000-8000-000000000b02', '00000000-0000-4000-8000-000000000b03']::uuid[] then
    raise exception 'FAIL: nearest-first order was % (expected near, far, no-location)', ids;
  end if;
  raise notice 'PASS: nearest-first orders near, far, then posts without a location';
end
$t$;

-- ---------- data export --------------------------------------------------------

do $t$
declare doc jsonb;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000a01","role":"authenticated"}', true);
  set local role authenticated;
  doc := public.export_my_data();
  reset role;
  if jsonb_array_length(doc -> 'saved_searches') < 1 then
    raise exception 'FAIL: export should include saved searches';
  end if;
  raise notice 'PASS: export includes saved searches';
end
$t$;

rollback;
-- If you see no FAIL above, every check passed and nothing was saved.
