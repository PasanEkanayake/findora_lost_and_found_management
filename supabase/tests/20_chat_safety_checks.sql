-- ============================================================================
-- Findora — checks for 20_chat_safety.sql (alerts, blocking, person reports)
--
-- Run in the Supabase SQL editor against a STAGING project after applying
-- 20_chat_safety.sql. Same approach as 17_policy_checks.sql: throw-away users
-- and posts, acting as each of them, everything rolled back at the end, one
-- PASS/FAIL line per check. NOT run by the author (no database was available).
-- ============================================================================
begin;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000f1', 't20-a@example.test'),
  ('00000000-0000-4000-8000-0000000000f2', 't20-b@example.test'),
  ('00000000-0000-4000-8000-0000000000f3', 't20-c@example.test');

insert into public.items (id, user_id, type, title) values
  ('00000000-0000-4000-8000-0000000000f4',  '00000000-0000-4000-8000-0000000000f1', 'lost',  'zzq alpha'),
  ('00000000-0000-4000-8000-0000000000f5', '00000000-0000-4000-8000-0000000000f2', 'found', 'xkw omega');

delete from public.matches
 where (item_a_id, item_b_id) in (('00000000-0000-4000-8000-0000000000f4','00000000-0000-4000-8000-0000000000f5'), ('00000000-0000-4000-8000-0000000000f5','00000000-0000-4000-8000-0000000000f4'));
insert into public.matches (id, item_a_id, item_b_id, similarity_score, status)
values ('00000000-0000-4000-8000-0000000000f6', '00000000-0000-4000-8000-0000000000f4', '00000000-0000-4000-8000-0000000000f5', 0.9, 'confirmed');

-- ---------- new-message alerts ----------------------------------------------

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000f1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.messages (match_id, sender_id, receiver_id, content) values ('00000000-0000-4000-8000-0000000000f6', '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000f2', 'hi')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: first message goes through (expected allowed)';
  end if;
  raise notice 'PASS: first message goes through';
end
$t$;

do $t$
declare n bigint;
begin
  select (select count(*) from public.notifications where user_id = '00000000-0000-4000-8000-0000000000f2' and type = 'new_message') into n;
  if n is distinct from 1 then
    raise exception 'FAIL: first unread message creates one alert (got % , expected 1)', n;
  end if;
  raise notice 'PASS: first unread message creates one alert';
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
    execute $q$insert into public.messages (match_id, sender_id, receiver_id, content) values ('00000000-0000-4000-8000-0000000000f6', '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000f2', 'hello?')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: second message while the first is unread (expected allowed)';
  end if;
  raise notice 'PASS: second message while the first is unread';
end
$t$;

do $t$
declare n bigint;
begin
  select (select count(*) from public.notifications where user_id = '00000000-0000-4000-8000-0000000000f2' and type = 'new_message') into n;
  if n is distinct from 1 then
    raise exception 'FAIL: ...does NOT create another alert (got % , expected 1)', n;
  end if;
  raise notice 'PASS: ...does NOT create another alert';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000f2","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$update public.messages set read_at = now() where receiver_id = '00000000-0000-4000-8000-0000000000f2' and read_at is null$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: receiver reads the chat (expected allowed)';
  end if;
  raise notice 'PASS: receiver reads the chat';
end
$t$;

do $t$
declare n bigint;
begin
  select (select count(*) from public.notifications where user_id = '00000000-0000-4000-8000-0000000000f2' and type = 'new_message' and read_at is null) into n;
  if n is distinct from 0 then
    raise exception 'FAIL: reading the chat clears its alert (got % , expected 0)', n;
  end if;
  raise notice 'PASS: reading the chat clears its alert';
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
    execute $q$insert into public.messages (match_id, sender_id, receiver_id, content) values ('00000000-0000-4000-8000-0000000000f6', '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000f2', 'again')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: a new message after reading (expected allowed)';
  end if;
  raise notice 'PASS: a new message after reading';
end
$t$;

do $t$
declare n bigint;
begin
  select (select count(*) from public.notifications where user_id = '00000000-0000-4000-8000-0000000000f2' and type = 'new_message') into n;
  if n is distinct from 2 then
    raise exception 'FAIL: ...alerts again (got % , expected 2)', n;
  end if;
  raise notice 'PASS: ...alerts again';
end
$t$;

do $t$
declare n bigint;
begin
  select (select count(*) from public.notifications where type = 'new_message' and (body ilike '%again%' or title ilike '%again%')) into n;
  if n is distinct from 0 then
    raise exception 'FAIL: alert text never contains the message (got % , expected 0)', n;
  end if;
  raise notice 'PASS: alert text never contains the message';
end
$t$;

-- ---------- blocking --------------------------------------------------------

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000f2","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.user_blocks (blocker_id, blocked_id) values ('00000000-0000-4000-8000-0000000000f2', '00000000-0000-4000-8000-0000000000f1')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: person can block someone (expected allowed)';
  end if;
  raise notice 'PASS: person can block someone';
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
    execute $q$insert into public.user_blocks (blocker_id, blocked_id) values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000f3')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: can''t block on someone else''s behalf (expected blocked)';
  end if;
  raise notice 'PASS: can''t block on someone else''s behalf';
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
    execute $q$select count(*) from (select 1 from public.user_blocks) s$q$ into n;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: blocked person can''t see who blocked them (expected blocked)';
  end if;
  raise notice 'PASS: blocked person can''t see who blocked them';
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
    execute $q$insert into public.messages (match_id, sender_id, receiver_id, content) values ('00000000-0000-4000-8000-0000000000f6', '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000f2', 'let me explain')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: blocked person''s messages are refused (expected blocked)';
  end if;
  raise notice 'PASS: blocked person''s messages are refused';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000f2","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.messages (match_id, sender_id, receiver_id, content) values ('00000000-0000-4000-8000-0000000000f6', '00000000-0000-4000-8000-0000000000f2', '00000000-0000-4000-8000-0000000000f1', 'go away')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: the blocker''s messages are refused too (expected blocked)';
  end if;
  raise notice 'PASS: the blocker''s messages are refused too';
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
    execute $q$select public.start_contact_thread('00000000-0000-4000-8000-0000000000f5')$q$;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: blocked person can''t start a direct thread (expected blocked)';
  end if;
  raise notice 'PASS: blocked person can''t start a direct thread';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  set local role anon;
  begin
    execute $q$select count(*) from (select 1 from public.user_blocks) s$q$ into n;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: signed-out callers can''t read blocks (expected blocked)';
  end if;
  raise notice 'PASS: signed-out callers can''t read blocks';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000f2","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$delete from public.user_blocks where blocker_id = '00000000-0000-4000-8000-0000000000f2' and blocked_id = '00000000-0000-4000-8000-0000000000f1'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: person can unblock (expected allowed)';
  end if;
  raise notice 'PASS: person can unblock';
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
    execute $q$insert into public.messages (match_id, sender_id, receiver_id, content) values ('00000000-0000-4000-8000-0000000000f6', '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000f2', 'thanks')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: after unblocking, messages flow again (expected allowed)';
  end if;
  raise notice 'PASS: after unblocking, messages flow again';
end
$t$;

-- ---------- reporting a person -----------------------------------------------

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000f1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$insert into public.user_reports (reporter_id, reported_user_id, match_id, reason) values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000f2', '00000000-0000-4000-8000-0000000000f6', 'Spam or advertising')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: can report the person you''re matched with (expected allowed)';
  end if;
  raise notice 'PASS: can report the person you''re matched with';
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
    execute $q$insert into public.user_reports (reporter_id, reported_user_id, match_id, reason) values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000f2', '00000000-0000-4000-8000-0000000000f6', 'again')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: a second open report about the same person is refused (expected blocked)';
  end if;
  raise notice 'PASS: a second open report about the same person is refused';
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
    execute $q$insert into public.user_reports (reporter_id, reported_user_id, match_id, reason) values ('00000000-0000-4000-8000-0000000000f3', '00000000-0000-4000-8000-0000000000f2', '00000000-0000-4000-8000-0000000000f6', 'x')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: can''t report a stranger you share no conversation with (expected blocked)';
  end if;
  raise notice 'PASS: can''t report a stranger you share no conversation with';
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
    execute $q$insert into public.user_reports (reporter_id, reported_user_id, match_id, reason) values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000f2', '00000000-0000-4000-8000-0000000000f6', 'x')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: can''t report on someone else''s behalf (expected blocked)';
  end if;
  raise notice 'PASS: can''t report on someone else''s behalf';
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
    execute $q$insert into public.user_reports (reporter_id, reported_user_id, match_id, reason, status) values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000f2', '00000000-0000-4000-8000-0000000000f6', 'x', 'dismissed')$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: can''t file a report that starts out ''dismissed'' (expected blocked)';
  end if;
  raise notice 'PASS: can''t file a report that starts out ''dismissed''';
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
    execute $q$select count(*) from (select 1 from public.user_reports) s$q$ into n;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: ordinary users can''t read the report queue (expected blocked)';
  end if;
  raise notice 'PASS: ordinary users can''t read the report queue';
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
    execute $q$update public.user_reports set status = 'dismissed'$q$;
    get diagnostics n = row_count;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: ordinary users can''t resolve reports (expected blocked)';
  end if;
  raise notice 'PASS: ordinary users can''t resolve reports';
end
$t$;

rollback;
-- If you see no FAIL above, every check passed and nothing was saved.
