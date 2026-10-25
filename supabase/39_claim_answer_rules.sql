-- ============================================================================
-- Findora — A claim must describe a unique detail
-- Run this after 38_claim_attempt_limit.sql. Safe to re-run. Changes no data.
--
-- THE GAP. The claim form is meant to make the claimant describe something only
-- the real owner would know (or answer the finder's question). But:
--   * the form's Submit button worked with an EMPTY answer — the form simply
--     closed and nothing happened, with no message;
--   * the database accepted a claim with no answer at all (the column allowed
--     null/empty), so any modified app could file a claim with no detail;
--   * a claimant could re-submit the SAME answer the finder had just rejected,
--     wasting one of their limited attempts (migration 38).
--
-- THE RULES NOW (checked by the database, so no app version can skip them):
--   * the answer is trimmed, then must be at least
--       - 2 characters when the finder set a question on the post (short
--         answers like "red" or "Nokia" are legitimate there), or
--       - 15 characters when there is no question (a real description);
--   * it can't repeat an answer this person already submitted for this post.
-- The app shows the same rules before submitting (lib/features/items/data/
-- claim_answer_rules.dart) — keep the two numbers in step.
-- ============================================================================

create or replace function public.claim_min_answer_length(p_item_id uuid)
returns integer
language sql
stable
security definer set search_path = public
as $$
  select case
    when coalesce(btrim((select proof_question from public.items where id = p_item_id)), '') <> ''
      then 2
    else 15
  end;
$$;

revoke all on function public.claim_min_answer_length(uuid) from public, anon;
grant execute on function public.claim_min_answer_length(uuid) to authenticated;

create or replace function public.enforce_claim_answer_rules()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  min_length integer := public.claim_min_answer_length(new.item_id);
begin
  new.verification_answer := btrim(coalesce(new.verification_answer, ''));

  if char_length(new.verification_answer) < min_length then
    if min_length <= 2 then
      raise exception 'Please answer the finder''s question before submitting your claim.'
        using errcode = '22023';
    else
      raise exception 'Describe a unique detail that proves this is yours — at least % characters.', min_length
        using errcode = '22023';
    end if;
  end if;

  if exists (
    select 1 from public.claims c
    where c.item_id = new.item_id
      and c.claimant_id = new.claimant_id
      and lower(btrim(coalesce(c.verification_answer, ''))) = lower(new.verification_answer)
  ) then
    raise exception 'You already submitted that answer for this post. Add more detail, or try a different one.'
      using errcode = '22023';
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_claim_answer_rules() from public, anon, authenticated;

-- Fires before claims_attempt_limit ("claims_an" < "claims_at"), so a blank
-- claim is refused for being blank before anything else is looked at.
drop trigger if exists claims_answer_rules on public.claims;
create trigger claims_answer_rules
  before insert on public.claims
  for each row execute function public.enforce_claim_answer_rules();
