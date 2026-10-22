-- ============================================================================
-- Findora — exact "try again on <date>" message for Google sign-up (OPTIONAL)
-- Run after 36_security_hardening.sql, then switch the hook on (below). Safe to
-- re-run. Changes no data.
--
-- THE SITUATION. An address that belonged to a recently deleted account can't
-- sign up for a while (supabase/16_release_email_on_delete.sql). Signing up with
-- an email and password checks that up front and says "...you can sign up with
-- it again on <date>". Signing up with GOOGLE can't: the app only learns the
-- address after Google gives it to Supabase, at which point the database's
-- refusal comes back as a generic "Database error saving new user". The app
-- already turns that into a helpful message WITHOUT the date. This hook adds the
-- date.
--
-- WHAT IT IS. A Supabase Auth "Before User Created" hook: a function Supabase
-- calls just before it creates any new account (email, Google, anything). If the
-- address is blocked, the function returns an error WITH the sentence to show,
-- and Supabase hands that sentence back to the app. The existing database
-- trigger (a_enforce_email_reuse_block) stays as the real enforcement; this only
-- improves what the person is told.
--
-- TO SWITCH IT ON (one dashboard step; nothing changes until you do it):
--   Authentication -> Auth Hooks -> "Before User Created" -> Add hook ->
--   type "Postgres function" -> schema public -> function
--   hook_before_user_created -> Create.
-- Then try signing up with Google using an address you deleted a few minutes ago.
-- If the message doesn't show the date, switch the hook off again: the generic
-- wording keeps working without it. (The hook's error format is Supabase's and
-- was written here from its documentation, not run against your project.)
-- ============================================================================

create or replace function public.hook_before_user_created(event jsonb)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_email text := event -> 'user' ->> 'email';
  v_until timestamptz;
  v_blocked boolean := false;
begin
  if v_email is not null then
    select true, b.blocked_until
      into v_blocked, v_until
    from public.email_reuse_blocks b
    where b.email_hash = public.email_fingerprint(v_email)
      and (b.blocked_until is null or b.blocked_until > now())
    limit 1;
  end if;

  if coalesce(v_blocked, false) then
    -- The same sentences the sign-up screen shows (lib/core/auth/signup_block_messages.dart).
    return jsonb_build_object(
      'error', jsonb_build_object(
        'http_code', 400,
        'message',
          case when v_until is null
            then 'This email can''t be used to create an account.'
            else 'An account with this email was recently deleted. You can sign up with it again on '
                 || to_char(v_until at time zone 'UTC', 'FMMon FMDD, YYYY') || '.'
          end
      )
    );
  end if;

  return '{}'::jsonb;
end;
$$;

-- Only Supabase's auth service may call it.
grant execute on function public.hook_before_user_created(jsonb) to supabase_auth_admin;
revoke execute on function public.hook_before_user_created(jsonb) from authenticated, anon, public;
