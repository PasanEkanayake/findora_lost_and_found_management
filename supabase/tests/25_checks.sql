-- ============================================================================
-- Findora — checks for 25_outcomes_and_data_export.sql
-- Run in the Supabase SQL editor against a STAGING project after applying 25.
-- Throw-away users, rolled back at the end. NOT run by the author.
-- ============================================================================
begin;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000d1', 't25-a@example.test'),
  ('00000000-0000-4000-8000-0000000000d2', 't25-b@example.test');
insert into public.items (id, user_id, type, title) values
  ('00000000-0000-4000-8000-0000000000d4',  '00000000-0000-4000-8000-0000000000d1', 'lost',  'zzq alpha'),
  ('00000000-0000-4000-8000-0000000000d5', '00000000-0000-4000-8000-0000000000d2', 'found', 'xkw omega');
delete from public.matches
 where (item_a_id, item_b_id) in (('00000000-0000-4000-8000-0000000000d4','00000000-0000-4000-8000-0000000000d5'), ('00000000-0000-4000-8000-0000000000d5','00000000-0000-4000-8000-0000000000d4'));
insert into public.matches (id, item_a_id, item_b_id, similarity_score, status)
values ('00000000-0000-4000-8000-0000000000d6', '00000000-0000-4000-8000-0000000000d4', '00000000-0000-4000-8000-0000000000d5', 0.7, 'pending');


do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000d1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select public.decide_match('00000000-0000-4000-8000-0000000000d6', 'confirmed')$q$;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: confirming a match works as before (expected allowed)';
  end if;
  raise notice 'PASS: confirming a match works as before';
end
$t$;

do $t$
declare n bigint;
begin
  select (select count(*) from public.match_outcomes where match_id = '00000000-0000-4000-8000-0000000000d6' and decision = 'confirmed' and similarity_score is not null) into n;
  if n is distinct from 1 then
    raise exception 'FAIL: ...and the decision is logged with its score (got % , expected 1)', n;
  end if;
  raise notice 'PASS: ...and the decision is logged with its score';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000d1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select public.decide_match('00000000-0000-4000-8000-0000000000d6', 'pending')$q$;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: undoing it is logged too (expected allowed)';
  end if;
  raise notice 'PASS: undoing it is logged too';
end
$t$;

do $t$
declare n bigint;
begin
  select (select count(*) from public.match_outcomes where match_id = '00000000-0000-4000-8000-0000000000d6' and decision = 'reopened') into n;
  if n is distinct from 1 then
    raise exception 'FAIL: ...as ''reopened'' (got % , expected 1)', n;
  end if;
  raise notice 'PASS: ...as ''reopened''';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000d1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select count(*) from (select 1 from public.match_outcomes) s$q$ into n;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: ordinary users can''t read the outcome log (expected blocked)';
  end if;
  raise notice 'PASS: ordinary users can''t read the outcome log';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000d1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select count(*) from (select 1 from public.match_outcome_summary) s$q$ into n;
    if n = 0 then blocked := true; end if;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: ordinary users can''t read the summary either (expected blocked)';
  end if;
  raise notice 'PASS: ordinary users can''t read the summary either';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000d1","role":"authenticated"}', true);
  set local role authenticated;
  begin
    execute $q$select public.export_my_data()$q$;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from false then
    raise exception 'FAIL: a signed-in person can export their data (expected allowed)';
  end if;
  raise notice 'PASS: a signed-in person can export their data';
end
$t$;

-- the export, as U1, must contain only U1's own post (checked by title)
do $t$
declare doc jsonb;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000d1","role":"authenticated"}', true);
  set local role authenticated;
  doc := public.export_my_data();
  reset role;
  if jsonb_array_length(doc -> 'items') <> 1 or doc -> 'items' -> 0 ->> 'title' <> 'zzq alpha' then
    raise exception 'FAIL: export should contain exactly the signed-in person''s own post';
  end if;
  if doc ? 'text_embedding' or (doc -> 'profile') ? 'is_admin' then
    raise exception 'FAIL: export leaked an internal column';
  end if;
  raise notice 'PASS: export contains only the signed-in person''s own data';
end
$t$;

do $t$
declare
  n bigint;
  blocked boolean := false;
begin
  set local role anon;
  begin
    execute $q$select public.export_my_data()$q$;
  exception when others then
    blocked := true;
  end;
  reset role;
  if blocked is distinct from true then
    raise exception 'FAIL: signed-out callers can''t export (expected blocked)';
  end if;
  raise notice 'PASS: signed-out callers can''t export';
end
$t$;

rollback;
-- If you see no FAIL above, every check passed and nothing was saved.
