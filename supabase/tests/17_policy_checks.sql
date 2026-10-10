-- ============================================================================
-- Findora — checks for 17_harden_policies.sql
--
-- Run in the Supabase SQL editor against a STAGING project (or any copy) after
-- applying 17_harden_policies.sql. It builds three throw-away users, posts and
-- a match, then acts as each of them (SET LOCAL ROLE + a fake JWT) to confirm
-- that each hole closed in 17 is closed — and that the normal flows still work.
--
-- Everything happens inside one transaction that is ROLLED BACK at the end, so
-- nothing is left behind. Each check prints  PASS: ...  as a NOTICE, and the
-- first failure raises an error and stops. NOT run by the author (no database
-- was available when this was written) — if a check fails, read it before
-- assuming the policy is wrong: it may be a fixture problem.
--
-- If auth.users has extra required columns on your project version, add them
-- to the fixture INSERT below.
-- ============================================================================
begin;

-- ---------- fixtures (run as the SQL editor's privileged role) --------------
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000a1', 't17-a@example.test'),
  ('00000000-0000-4000-8000-0000000000a2', 't17-b@example.test'),
  ('00000000-0000-4000-8000-0000000000a3', 't17-c@example.test');

insert into public.profile_private (id, phone, fcm_token)
values ('00000000-0000-4000-8000-0000000000a1', '+0000000001', 'token-for-a')
on conflict (id) do update set phone = excluded.phone, fcm_token = excluded.fcm_token;

insert into public.items (id, user_id, type, title) values
  ('00000000-0000-4000-8000-0000000000b1',    '00000000-0000-4000-8000-0000000000a1', 'lost',  'zzq alpha'),
  ('00000000-0000-4000-8000-0000000000b2',   '00000000-0000-4000-8000-0000000000a2', 'found', 'xkw omega'),
  ('00000000-0000-4000-8000-0000000000b3', '00000000-0000-4000-8000-0000000000a1', 'lost',  'qpl sigma');

-- The matching triggers may already have paired some of these; make sure the
-- LOST1/FOUND1 pair exists with a known id and starts pending.
delete from public.matches
 where (item_a_id, item_b_id) in (('00000000-0000-4000-8000-0000000000b1','00000000-0000-4000-8000-0000000000b2'), ('00000000-0000-4000-8000-0000000000b2','00000000-0000-4000-8000-0000000000b1'));
insert into public.matches (id, item_a_id, item_b_id, similarity_score, status)
values ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b2', 0.9, 'pending');


do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select public.decide_match('00000000-0000-4000-8000-0000000000c1', 'confirmed')$q$;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: owner can confirm a match via decide_match() (expected allowed)';
  end if;
  raise notice 'PASS: owner can confirm a match via decide_match()';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select public.decide_match('00000000-0000-4000-8000-0000000000c1', 'dismissed')$q$;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: stranger CANNOT decide someone else''s match (expected blocked)';
  end if;
  raise notice 'PASS: stranger CANNOT decide someone else''s match';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.matches set status = 'dismissed' where id = '00000000-0000-4000-8000-0000000000c1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: direct UPDATE on matches is refused (expected blocked)';
  end if;
  raise notice 'PASS: direct UPDATE on matches is refused';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.matches set item_b_id = '00000000-0000-4000-8000-0000000000b3' where id = '00000000-0000-4000-8000-0000000000c1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: direct UPDATE can''t re-point a match at someone else''s item (expected blocked)';
  end if;
  raise notice 'PASS: direct UPDATE can''t re-point a match at someone else''s item';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.messages (id, match_id, sender_id, receiver_id, content) values ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a2', 'hello')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: party can message the other party in a confirmed match (expected allowed)';
  end if;
  raise notice 'PASS: party can message the other party in a confirmed match';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.messages (match_id, sender_id, receiver_id, content) values ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a3', '00000000-0000-4000-8000-0000000000a1', 'spam')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: stranger CANNOT message into someone else''s match (expected blocked)';
  end if;
  raise notice 'PASS: stranger CANNOT message into someone else''s match';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.messages (match_id, sender_id, receiver_id, content) values ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a3', 'hi')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: party can''t message a third person via their own match (expected blocked)';
  end if;
  raise notice 'PASS: party can''t message a third person via their own match';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.messages (match_id, sender_id, receiver_id, content) values ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a2', '')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: empty message is refused (expected blocked)';
  end if;
  raise notice 'PASS: empty message is refused';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.messages set content = 'edited' where id = '00000000-0000-4000-8000-0000000000d1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: receiver CANNOT edit the text of a received message (expected blocked)';
  end if;
  raise notice 'PASS: receiver CANNOT edit the text of a received message';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.messages set read_at = now() where id = '00000000-0000-4000-8000-0000000000d1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: receiver can mark a message read (expected allowed)';
  end if;
  raise notice 'PASS: receiver can mark a message read';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.claims (id, item_id, claimant_id, status) values ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-0000000000a1', 'approved')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: claimant CANNOT insert an already-approved claim (expected blocked)';
  end if;
  raise notice 'PASS: claimant CANNOT insert an already-approved claim';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.claims (item_id, claimant_id) values ('00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-0000000000a3')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: stranger CANNOT file a claim on a post they have no confirmed match with (expected blocked)';
  end if;
  raise notice 'PASS: stranger CANNOT file a claim on a post they have no confirmed match with';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.claims (id, item_id, claimant_id, verification_answer) values ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-0000000000a1', 'scratch on the back')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: matched owner can file a pending claim (expected allowed)';
  end if;
  raise notice 'PASS: matched owner can file a pending claim';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.claims (item_id, claimant_id) values ('00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-0000000000a1')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: second live claim by the same person is refused (expected blocked)';
  end if;
  raise notice 'PASS: second live claim by the same person is refused';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.claims set status = 'approved' where id = '00000000-0000-4000-8000-0000000000e1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: claimant can''t edit the claim afterwards (expected blocked)';
  end if;
  raise notice 'PASS: claimant can''t edit the claim afterwards';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.claims set verification_answer = 'forged' where id = '00000000-0000-4000-8000-0000000000e1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: item owner CANNOT rewrite the claimant''s answer (expected blocked)';
  end if;
  raise notice 'PASS: item owner CANNOT rewrite the claimant''s answer';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.claims set status = 'rejected' where id = '00000000-0000-4000-8000-0000000000e1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: item owner can decide a pending claim (expected allowed)';
  end if;
  raise notice 'PASS: item owner can decide a pending claim';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.claims set status = 'approved' where id = '00000000-0000-4000-8000-0000000000e1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: a decided claim can''t be flipped back (expected blocked)';
  end if;
  raise notice 'PASS: a decided claim can''t be flipped back';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select public.decide_match('00000000-0000-4000-8000-0000000000c1', 'pending')$q$;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: confirmed match can''t be undone once a claim exists (expected blocked)';
  end if;
  raise notice 'PASS: confirmed match can''t be undone once a claim exists';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select public.submit_rating('00000000-0000-4000-8000-0000000000b2', 5, 'great')$q$;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: rating is refused before the item is returned (expected blocked)';
  end if;
  raise notice 'PASS: rating is refused before the item is returned';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.ratings (item_id, rater_id, ratee_id, stars) values ('00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-0000000000a3', '00000000-0000-4000-8000-0000000000a1', 1)$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: direct INSERT into ratings is refused (expected blocked)';
  end if;
  raise notice 'PASS: direct INSERT into ratings is refused';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.profiles set is_admin = true where id = '00000000-0000-4000-8000-0000000000a1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: user CANNOT make themselves admin (expected blocked)';
  end if;
  raise notice 'PASS: user CANNOT make themselves admin';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.profiles set rating = 5, rating_count = 99 where id = '00000000-0000-4000-8000-0000000000a1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: user CANNOT edit their own rating (expected blocked)';
  end if;
  raise notice 'PASS: user CANNOT edit their own rating';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.profiles set full_name = 'Test One' where id = '00000000-0000-4000-8000-0000000000a1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: user can still edit their display name (expected allowed)';
  end if;
  raise notice 'PASS: user can still edit their display name';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select count(*) from (select 1 from public.profile_private where id = '00000000-0000-4000-8000-0000000000a1') s$q$ into n;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: other people CANNOT read someone''s phone/push token (expected blocked)';
  end if;
  raise notice 'PASS: other people CANNOT read someone''s phone/push token';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select count(*) from (select 1 from public.profile_private where id = '00000000-0000-4000-8000-0000000000a1') s$q$ into n;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: owner can read their own private profile (expected allowed)';
  end if;
  raise notice 'PASS: owner can read their own private profile';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  set local role anon;
  begin
    execute $q$select count(*) from (select 1 from public.profiles limit 1) s$q$ into n;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: signed-out callers CANNOT read profiles (expected blocked)';
  end if;
  raise notice 'PASS: signed-out callers CANNOT read profiles';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  set local role anon;
  begin
    execute $q$select count(*) from (select 1 from public.items limit 1) s$q$ into n;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: signed-out callers CANNOT read items (expected blocked)';
  end if;
  raise notice 'PASS: signed-out callers CANNOT read items';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  set local role anon;
  begin
    execute $q$select * from public.signup_email_status('nobody@example.test')$q$;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: signed-out sign-up check still works (expected allowed)';
  end if;
  raise notice 'PASS: signed-out sign-up check still works';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.items set deleted_at = now() where id = '00000000-0000-4000-8000-0000000000b3'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: owner can soft-delete their own post (expected allowed)';
  end if;
  raise notice 'PASS: owner can soft-delete their own post';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.items set deleted_at = null where id = '00000000-0000-4000-8000-0000000000b3'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: owner CANNOT restore a removed post (expected blocked)';
  end if;
  raise notice 'PASS: owner CANNOT restore a removed post';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select count(*) from (select 1 from public.items where id = '00000000-0000-4000-8000-0000000000b3') s$q$ into n;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: other people no longer see a removed post (expected blocked)';
  end if;
  raise notice 'PASS: other people no longer see a removed post';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select count(*) from (select 1 from public.items where id = '00000000-0000-4000-8000-0000000000b3') s$q$ into n;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: owner can still see their own removed post (expected allowed)';
  end if;
  raise notice 'PASS: owner can still see their own removed post';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.items set status = 'resolved' where id = '00000000-0000-4000-8000-0000000000b1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: owner CANNOT set a post''s status directly (expected blocked)';
  end if;
  raise notice 'PASS: owner CANNOT set a post''s status directly';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.items set user_id = '00000000-0000-4000-8000-0000000000a3' where id = '00000000-0000-4000-8000-0000000000b1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: owner CANNOT hand a post to another owner (expected blocked)';
  end if;
  raise notice 'PASS: owner CANNOT hand a post to another owner';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.items (user_id, type, title, status) values ('00000000-0000-4000-8000-0000000000a1', 'lost', 'x', 'claimed')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: new posts can''t start as ''claimed'' (expected blocked)';
  end if;
  raise notice 'PASS: new posts can''t start as ''claimed''';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.items set title = 'zzq alpha edited' where id = '00000000-0000-4000-8000-0000000000b1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: owner can edit a post''s title (expected allowed)';
  end if;
  raise notice 'PASS: owner can edit a post''s title';
end
$t$;

-- ---------- storage limits (privileged role) -------------------------------
do $t$
begin
  if exists (select 1 from storage.buckets
             where id in ('item-images', 'avatars') and file_size_limit is null) then
    raise exception 'FAIL: storage buckets have no size limit';
  end if;
  raise notice 'PASS: storage buckets have size limits';
end
$t$;

rollback;
-- If you see no FAIL above, every check passed and nothing was saved.
