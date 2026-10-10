-- ============================================================================
-- Findora — checks for 26_country.sql
-- Run in the Supabase SQL editor against a STAGING project after applying 26.
-- Throw-away users, rolled back at the end. NOT run by the author.
-- ============================================================================
begin;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000e1', 't26-a@example.test'),
  ('00000000-0000-4000-8000-0000000000e2', 't26-b@example.test');

insert into public.items (id, user_id, type, title, country_code) values
  ('00000000-0000-4000-8000-0000000000e4', '00000000-0000-4000-8000-0000000000e1', 'lost',  'zzcountry umbrella', 'LK'),
  ('00000000-0000-4000-8000-0000000000e5', '00000000-0000-4000-8000-0000000000e2', 'found', 'zzcountry umbrella', 'US'),
  ('00000000-0000-4000-8000-0000000000e6', '00000000-0000-4000-8000-0000000000e2', 'found', 'zzcountry umbrella', 'LK');


do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.items (user_id, type, title) values ('00000000-0000-4000-8000-0000000000e1', 'lost', 'no country')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: a new post from the app without a country is refused (expected blocked)';
  end if;
  raise notice 'PASS: a new post from the app without a country is refused';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.items (user_id, type, title, country_code) values ('00000000-0000-4000-8000-0000000000e1', 'lost', 'zzcountry wallet', 'lk')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: a lower-case country is accepted (expected allowed)';
  end if;
  raise notice 'PASS: a lower-case country is accepted';
end
$t$;

do $t$
declare n bigint;
begin
  select (select count(*) from public.items where title = 'zzcountry wallet' and country_code = 'LK') into n;
  if n is distinct from 1 then
    raise exception 'FAIL: ...and stored upper-case (got % , expected 1)', n;
  end if;
  raise notice 'PASS: ...and stored upper-case';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.items (user_id, type, title, country_code) values ('00000000-0000-4000-8000-0000000000e1', 'lost', 'bad code', 'LKA')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: a code that isn''t two letters is refused (expected blocked)';
  end if;
  raise notice 'PASS: a code that isn''t two letters is refused';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.items set country_code = null where title = 'zzcountry wallet'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: a post can''t lose its country later (expected blocked)';
  end if;
  raise notice 'PASS: a post can''t lose its country later';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.profiles set country_code = 'lk' where id = '00000000-0000-4000-8000-0000000000e1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: a person can set their own country (expected allowed)';
  end if;
  raise notice 'PASS: a person can set their own country';
end
$t$;

do $t$
declare n bigint;
begin
  select (select count(*) from public.profiles where id = '00000000-0000-4000-8000-0000000000e1' and country_code = 'LK') into n;
  if n is distinct from 1 then
    raise exception 'FAIL: ...stored upper-case (got % , expected 1)', n;
  end if;
  raise notice 'PASS: ...stored upper-case';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.profiles set country_code = 'L1' where id = '00000000-0000-4000-8000-0000000000e1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: a bad profile country is refused (expected blocked)';
  end if;
  raise notice 'PASS: a bad profile country is refused';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.profiles set country_code = 'US' where id = '00000000-0000-4000-8000-0000000000e2'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: nobody can set someone else''s country (expected blocked)';
  end if;
  raise notice 'PASS: nobody can set someone else''s country';
end
$t$;

-- ---------- matching never crosses countries ----------------------------------

select public.upsert_match_score('00000000-0000-4000-8000-0000000000e4', '00000000-0000-4000-8000-0000000000e5', 0.9, 0.9);
select public.upsert_match_score('00000000-0000-4000-8000-0000000000e4', '00000000-0000-4000-8000-0000000000e6', 0.9, 0.9);

do $t$
declare n bigint;
begin
  select (select count(*) from public.matches where (item_a_id = '00000000-0000-4000-8000-0000000000e4' and item_b_id = '00000000-0000-4000-8000-0000000000e5') or (item_a_id = '00000000-0000-4000-8000-0000000000e5' and item_b_id = '00000000-0000-4000-8000-0000000000e4')) into n;
  if n is distinct from 0 then
    raise exception 'FAIL: lost (LK) and found (US): no match is made (got % , expected 0)', n;
  end if;
  raise notice 'PASS: lost (LK) and found (US): no match is made';
end
$t$;

do $t$
declare n bigint;
begin
  select (select count(*) from public.matches where (item_a_id = '00000000-0000-4000-8000-0000000000e4' and item_b_id = '00000000-0000-4000-8000-0000000000e6') or (item_a_id = '00000000-0000-4000-8000-0000000000e6' and item_b_id = '00000000-0000-4000-8000-0000000000e4')) into n;
  if n is distinct from 1 then
    raise exception 'FAIL: lost (LK) and found (LK): a match is made (got % , expected 1)', n;
  end if;
  raise notice 'PASS: lost (LK) and found (LK): a match is made';
end
$t$;

-- ---------- feed counts per country --------------------------------------------

do $t$
declare n bigint;
begin
  select (select found_count from public.feed_counts(null, 'zzcountry', 'LK')) into n;
  if n is distinct from 1 then
    raise exception 'FAIL: feed counts: found posts in LK (got % , expected 1)', n;
  end if;
  raise notice 'PASS: feed counts: found posts in LK';
end
$t$;

do $t$
declare n bigint;
begin
  select (select lost_count from public.feed_counts(null, 'zzcountry', 'LK')) into n;
  if n is distinct from 2 then
    raise exception 'FAIL: feed counts: lost posts in LK (got % , expected 2)', n;
  end if;
  raise notice 'PASS: feed counts: lost posts in LK';
end
$t$;

do $t$
declare n bigint;
begin
  select (select found_count from public.feed_counts(null, 'zzcountry', 'US')) into n;
  if n is distinct from 1 then
    raise exception 'FAIL: feed counts: found posts in US (got % , expected 1)', n;
  end if;
  raise notice 'PASS: feed counts: found posts in US';
end
$t$;

do $t$
declare n bigint;
begin
  select (select lost_count from public.feed_counts(null, 'zzcountry', 'US')) into n;
  if n is distinct from 0 then
    raise exception 'FAIL: feed counts: lost posts in US (got % , expected 0)', n;
  end if;
  raise notice 'PASS: feed counts: lost posts in US';
end
$t$;

rollback;
-- If you see no FAIL above, every check passed and nothing was saved.
