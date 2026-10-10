-- ============================================================================
-- Findora — checks for 27_country_settings.sql
-- Run in the Supabase SQL editor against a STAGING project after applying 27.
-- Throw-away users, rolled back at the end. NOT run by the author.
-- ============================================================================
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-4000-8000-0000000000f1', 't27-a@example.test', '{"country_code": "lk"}'),
  ('00000000-0000-4000-8000-0000000000f2', 't27-b@example.test', '{"country_code": "XYZ"}'),
  ('00000000-0000-4000-8000-0000000000f3', 't27-c@example.test', '{}');


do $t$
declare n bigint;
begin
  select (select count(*) from public.profiles where id = '00000000-0000-4000-8000-0000000000f1' and country_code = 'LK') into n;
  if n is distinct from 1 then
    raise exception 'FAIL: sign-up country is saved upper-case on the profile (got % , expected 1)', n;
  end if;
  raise notice 'PASS: sign-up country is saved upper-case on the profile';
end
$t$;

do $t$
declare n bigint;
begin
  select (select count(*) from public.profiles where id = '00000000-0000-4000-8000-0000000000f2' and country_code is null) into n;
  if n is distinct from 1 then
    raise exception 'FAIL: an invalid sign-up country is ignored, not an error (got % , expected 1)', n;
  end if;
  raise notice 'PASS: an invalid sign-up country is ignored, not an error';
end
$t$;

do $t$
declare n bigint;
begin
  select (select count(*) from public.profiles where id = '00000000-0000-4000-8000-0000000000f3' and country_code is null) into n;
  if n is distinct from 1 then
    raise exception 'FAIL: no sign-up country leaves it empty (got % , expected 1)', n;
  end if;
  raise notice 'PASS: no sign-up country leaves it empty';
end
$t$;

-- ---------- temporary country --------------------------------------------------

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000f1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.profiles set temp_country_code = 'au', temp_country_until = now() + interval '7 days' where id = '00000000-0000-4000-8000-0000000000f1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: a temporary country for a week (expected allowed)';
  end if;
  raise notice 'PASS: a temporary country for a week';
end
$t$;

do $t$
declare n bigint;
begin
  select (select count(*) from public.profiles where id = '00000000-0000-4000-8000-0000000000f1' and temp_country_code = 'AU') into n;
  if n is distinct from 1 then
    raise exception 'FAIL: ...is stored upper-case (got % , expected 1)', n;
  end if;
  raise notice 'PASS: ...is stored upper-case';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000f1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.profiles set temp_country_code = null, temp_country_until = null where id = '00000000-0000-4000-8000-0000000000f1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: it can be ended (expected allowed)';
  end if;
  raise notice 'PASS: it can be ended';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000f1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.profiles set temp_country_code = 'LK', temp_country_until = now() + interval '3 days' where id = '00000000-0000-4000-8000-0000000000f1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: a temporary country can''t be the home country (expected blocked)';
  end if;
  raise notice 'PASS: a temporary country can''t be the home country';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000f1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.profiles set temp_country_code = 'AU', temp_country_until = now() + interval '60 days' where id = '00000000-0000-4000-8000-0000000000f1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: a temporary country can''t last more than 30 days (expected blocked)';
  end if;
  raise notice 'PASS: a temporary country can''t last more than 30 days';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000f1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.profiles set temp_country_code = 'AU', temp_country_until = now() - interval '1 day' where id = '00000000-0000-4000-8000-0000000000f1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: a temporary country needs an end date in the future (expected blocked)';
  end if;
  raise notice 'PASS: a temporary country needs an end date in the future';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000f1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.profiles set temp_country_code = 'AU', temp_country_until = null where id = '00000000-0000-4000-8000-0000000000f1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: a temporary country needs an end date at all (expected blocked)';
  end if;
  raise notice 'PASS: a temporary country needs an end date at all';
end
$t$;

-- ---------- home country: once every 30 days -----------------------------------

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000f3","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.profiles set country_code = 'in' where id = '00000000-0000-4000-8000-0000000000f3'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: someone with no country can choose one freely (expected allowed)';
  end if;
  raise notice 'PASS: someone with no country can choose one freely';
end
$t$;

do $t$
declare n bigint;
begin
  select (select count(*) from public.profiles where id = '00000000-0000-4000-8000-0000000000f3' and country_changed_at is null) into n;
  if n is distinct from 1 then
    raise exception 'FAIL: ...and that starts no waiting period (got % , expected 1)', n;
  end if;
  raise notice 'PASS: ...and that starts no waiting period';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000f3","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.profiles set country_code = 'US' where id = '00000000-0000-4000-8000-0000000000f3'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: the first CHANGE is allowed (expected allowed)';
  end if;
  raise notice 'PASS: the first CHANGE is allowed';
end
$t$;

do $t$
declare n bigint;
begin
  select (select count(*) from public.profiles where id = '00000000-0000-4000-8000-0000000000f3' and country_changed_at is not null) into n;
  if n is distinct from 1 then
    raise exception 'FAIL: ...and starts the 30-day wait (got % , expected 1)', n;
  end if;
  raise notice 'PASS: ...and starts the 30-day wait';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000f3","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.profiles set country_code = 'GB' where id = '00000000-0000-4000-8000-0000000000f3'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: a second change straight away is refused (expected blocked)';
  end if;
  raise notice 'PASS: a second change straight away is refused';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000f3","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.profiles set country_changed_at = null where id = '00000000-0000-4000-8000-0000000000f3'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: country_changed_at can''t be reset by the person (expected blocked)';
  end if;
  raise notice 'PASS: country_changed_at can''t be reset by the person';
end
$t$;

-- after 30 days the change is possible again (simulated by moving the date back)
update public.profiles set country_changed_at = now() - interval '31 days' where id = '00000000-0000-4000-8000-0000000000f3';

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000f3","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.profiles set country_code = 'GB' where id = '00000000-0000-4000-8000-0000000000f3'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: ...after the 30 days, changing is allowed again (expected allowed)';
  end if;
  raise notice 'PASS: ...after the 30 days, changing is allowed again';
end
$t$;

rollback;
-- If you see no FAIL above, every check passed and nothing was saved.
