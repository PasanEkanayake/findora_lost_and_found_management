-- ============================================================================
-- Findora — checks for 21_device_tokens.sql, 22_limits_and_housekeeping.sql,
-- 23_time_direction.sql and 24_proof_questions.sql
--
-- Run in the Supabase SQL editor against a STAGING project after applying
-- those four files. Same approach as the other check scripts: throw-away
-- users and posts, acting as each of them, everything rolled back at the end,
-- one PASS/FAIL line per check. NOT run by the author (no database available).
-- ============================================================================
begin;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000c1', 't21-a@example.test'),
  ('00000000-0000-4000-8000-0000000000c2', 't21-b@example.test');

insert into public.items (id, user_id, type, title, event_time) values
  ('00000000-0000-4000-8000-0000000000c4',        '00000000-0000-4000-8000-0000000000c1', 'lost',  'zzq alpha',  now()),
  ('00000000-0000-4000-8000-0000000000c5',       '00000000-0000-4000-8000-0000000000c2', 'found', 'xkw omega',  now()),
  -- found two days BEFORE the lost item's time, and one an hour AFTER it
  ('00000000-0000-4000-8000-0000000000c6', '00000000-0000-4000-8000-0000000000c2', 'found', 'qpl sigma',  now() - interval '2 days'),
  ('00000000-0000-4000-8000-0000000000c7',  '00000000-0000-4000-8000-0000000000c2', 'found', 'vrt delta',  now() + interval '1 hour');

-- ---------- device tokens (21) ----------------------------------------------

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000c1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select public.register_device_token('tok_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'android')$q$;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: a person can register a device (expected allowed)';
  end if;
  raise notice 'PASS: a person can register a device';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000c1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select count(*) from (select 1 from public.device_tokens) s$q$ into n;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: they can see their own device (expected allowed)';
  end if;
  raise notice 'PASS: they can see their own device';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000c2","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select count(*) from (select 1 from public.device_tokens) s$q$ into n;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: someone else cannot see it (expected blocked)';
  end if;
  raise notice 'PASS: someone else cannot see it';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000c2","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.device_tokens (token, user_id) values ('tok_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', '00000000-0000-4000-8000-0000000000c2')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: direct inserts into device_tokens are refused (expected blocked)';
  end if;
  raise notice 'PASS: direct inserts into device_tokens are refused';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000c2","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select public.unregister_device_token('tok_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')$q$;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: someone else cannot unregister it (expected allowed)';
  end if;
  raise notice 'PASS: someone else cannot unregister it';
end
$t$;

do $t$
declare n bigint;
begin
  select (select count(*) from public.device_tokens where token = 'tok_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' and user_id = '00000000-0000-4000-8000-0000000000c1') into n;
  if n is distinct from 1 then
    raise exception 'FAIL: ...and it is still there (got % , expected 1)', n;
  end if;
  raise notice 'PASS: ...and it is still there';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000c2","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select public.register_device_token('tok_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'android')$q$;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: signing in on the same phone moves the token (expected allowed)';
  end if;
  raise notice 'PASS: signing in on the same phone moves the token';
end
$t$;

do $t$
declare n bigint;
begin
  select (select count(*) from public.device_tokens where token = 'tok_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' and user_id = '00000000-0000-4000-8000-0000000000c2') into n;
  if n is distinct from 1 then
    raise exception 'FAIL: ...now it belongs to the new person only (got % , expected 1)', n;
  end if;
  raise notice 'PASS: ...now it belongs to the new person only';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000c2","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select public.unregister_device_token('tok_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')$q$;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: the owner can unregister their device (expected allowed)';
  end if;
  raise notice 'PASS: the owner can unregister their device';
end
$t$;

do $t$
declare n bigint;
begin
  select (select count(*) from public.device_tokens where token = 'tok_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa') into n;
  if n is distinct from 0 then
    raise exception 'FAIL: ...and it is gone (got % , expected 0)', n;
  end if;
  raise notice 'PASS: ...and it is gone';
end
$t$;

-- ---------- proof questions (24) ---------------------------------------------

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000c2","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.items set proof_question = 'What is on the lock screen?' where id = '00000000-0000-4000-8000-0000000000c5'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: finder can set a proof question (expected allowed)';
  end if;
  raise notice 'PASS: finder can set a proof question';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000c2","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.item_private (item_id, proof_answer) values ('00000000-0000-4000-8000-0000000000c5', 'a blue wallpaper')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: finder can store the private answer (expected allowed)';
  end if;
  raise notice 'PASS: finder can store the private answer';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000c2","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select count(*) from (select 1 from public.item_private where item_id = '00000000-0000-4000-8000-0000000000c5') s$q$ into n;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: finder can read their own answer (expected allowed)';
  end if;
  raise notice 'PASS: finder can read their own answer';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000c1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select count(*) from (select 1 from public.item_private) s$q$ into n;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: the claimant CANNOT read the answer (expected blocked)';
  end if;
  raise notice 'PASS: the claimant CANNOT read the answer';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000c1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select count(*) from (select 1 from public.items where id = '00000000-0000-4000-8000-0000000000c5' and proof_question is not null) s$q$ into n;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: the claimant CAN read the question (expected allowed)';
  end if;
  raise notice 'PASS: the claimant CAN read the question';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000c1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.item_private (item_id, proof_answer) values ('00000000-0000-4000-8000-0000000000c7', 'x')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: someone else CANNOT write an answer for a post that isn''t theirs (expected blocked)';
  end if;
  raise notice 'PASS: someone else CANNOT write an answer for a post that isn''t theirs';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000c2","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.items set deleted_at = now() where id = '00000000-0000-4000-8000-0000000000c5'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: the finder removes their post (expected allowed)';
  end if;
  raise notice 'PASS: the finder removes their post';
end
$t$;

do $t$
declare n bigint;
begin
  select (select count(*) from public.item_private where item_id = '00000000-0000-4000-8000-0000000000c5') into n;
  if n is distinct from 0 then
    raise exception 'FAIL: ...and the private answer is deleted with it (got % , expected 0)', n;
  end if;
  raise notice 'PASS: ...and the private answer is deleted with it';
end
$t$;

-- ---------- abuse limits (22) ------------------------------------------------

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000c1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.items (user_id, type, title, country_code) select '00000000-0000-4000-8000-0000000000c1', 'lost', 'flood ' || g, 'LK' from generate_series(1, 25) g$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: a flood of posts is stopped (expected blocked)';
  end if;
  raise notice 'PASS: a flood of posts is stopped';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000c1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.items (user_id, type, title, country_code) values ('00000000-0000-4000-8000-0000000000c1', 'lost', 'one more normal post', 'LK')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: normal posting still works (expected allowed)';
  end if;
  raise notice 'PASS: normal posting still works';
end
$t$;

-- ---------- directional time (23) --------------------------------------------

do $t$
declare n bigint;
begin
  select (select ((select time_sim from public.pair_match_signals('00000000-0000-4000-8000-0000000000c4', '00000000-0000-4000-8000-0000000000c6')) < (select time_sim from public.pair_match_signals('00000000-0000-4000-8000-0000000000c4', '00000000-0000-4000-8000-0000000000c7')))::int) into n;
  if n is distinct from 1 then
    raise exception 'FAIL: a found item dated BEFORE the lost one scores worse on time than one dated after (got % , expected 1)', n;
  end if;
  raise notice 'PASS: a found item dated BEFORE the lost one scores worse on time than one dated after';
end
$t$;

-- ---------- faster policies (22) ---------------------------------------------

do $t$
declare n bigint;
begin
  select (select count(*) from pg_policies where schemaname in ('public','storage') and (coalesce(qual,'') ~ '(?<!SELECT )auth\.uid\(\)' or coalesce(with_check,'') ~ '(?<!SELECT )auth\.uid\(\)')) into n;
  if n is distinct from 0 then
    raise exception 'FAIL: no policy still calls auth.uid() once per row (got % , expected 0)', n;
  end if;
  raise notice 'PASS: no policy still calls auth.uid() once per row';
end
$t$;

rollback;
-- If you see no FAIL above, every check passed and nothing was saved.
