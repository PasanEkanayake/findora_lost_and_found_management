-- ============================================================================
-- Findora — Match outcome log (for tuning) and "download my data"
-- Run this after 24_proof_questions.sql. Safe to re-run.
--
-- 1. MATCH OUTCOMES. Every time someone confirms, dismisses or undoes a match
--    the scores it had at that moment are recorded (scores and the decision
--    only — no names, messages or post text). Confirmed vs dismissed matches
--    are free training labels: they show where the "Strong / Likely / Possible"
--    cut-offs and the signal weights in 18_calibrated_match_score.sql should
--    really sit. Only admins can read the log.
-- 2. DATA EXPORT. export_my_data() returns everything Findora holds about the
--    signed-in person as one JSON document — the in-app "Download my data"
--    button calls it. (Other people's messages to you are included because
--    they are in your conversations; their identities are not — only ids.)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Match outcomes
-- ----------------------------------------------------------------------------
create table if not exists public.match_outcomes (
  id uuid primary key default gen_random_uuid(),
  match_id uuid references public.matches (id) on delete set null,
  decision text not null check (decision in ('confirmed', 'dismissed', 'reopened')),
  similarity_score real,
  image_similarity real,
  text_similarity real,
  distance_meters real,
  time_proximity real,
  decided_at timestamptz not null default now()
);

create index if not exists match_outcomes_decided_idx
  on public.match_outcomes (decided_at desc);

alter table public.match_outcomes enable row level security;
revoke all on public.match_outcomes from anon, authenticated;
grant select on public.match_outcomes to authenticated;

drop policy if exists "admins can read match outcomes" on public.match_outcomes;
create policy "admins can read match outcomes"
  on public.match_outcomes for select to authenticated
  using ((select public.is_admin()));

create or replace function public.log_match_outcome()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.match_outcomes (
    match_id, decision, similarity_score, image_similarity, text_similarity,
    distance_meters, time_proximity
  ) values (
    new.id,
    case new.status when 'confirmed' then 'confirmed'
                    when 'dismissed' then 'dismissed'
                    else 'reopened' end,
    new.similarity_score, new.image_similarity, new.text_similarity,
    new.distance_meters, new.time_proximity
  );
  return new;
end;
$$;

drop trigger if exists matches_log_outcome on public.matches;
create trigger matches_log_outcome
  after update of status on public.matches
  for each row
  when (old.status is distinct from new.status)
  execute function public.log_match_outcome();

revoke all on function public.log_match_outcome() from public, anon, authenticated;

-- How the decisions fall across score bands — the table to read when asking
-- "is 80% really Strong?". security_invoker: the admin-only rule above still
-- applies to whoever queries it.
create or replace view public.match_outcome_summary
with (security_invoker = true) as
select
  width_bucket(coalesce(similarity_score, 0), 0, 1, 10) as score_band,  -- 1 = 0-10% ... 10 = 90-100%
  count(*) filter (where decision = 'confirmed') as confirmed,
  count(*) filter (where decision = 'dismissed') as dismissed,
  count(*) filter (where decision = 'reopened') as reopened,
  round(avg(image_similarity)::numeric, 2) as avg_image,
  round(avg(text_similarity)::numeric, 2) as avg_text
from public.match_outcomes
group by 1
order by 1;

grant select on public.match_outcome_summary to authenticated;

-- ----------------------------------------------------------------------------
-- 2. export_my_data
-- ----------------------------------------------------------------------------
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
             'latitude', case when i.location is null then null else st_y(i.location::geometry) end,
             'longitude', case when i.location is null then null else st_x(i.location::geometry) end,
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

revoke all on function public.export_my_data() from public, anon;
grant execute on function public.export_my_data() to authenticated;

-- ============================================================================
-- Verify (optional):
--   -- as an admin, after some matches have been decided:
--   select * from public.match_outcome_summary;
--   -- as any signed-in user (in the app: Profile -> Download my data):
--   select public.export_my_data();
-- ============================================================================
