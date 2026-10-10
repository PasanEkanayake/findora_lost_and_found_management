-- ============================================================================
-- Findora — Country at sign-up, home country limits, and temporary country
-- Run this after 26_country.sql. Safe to re-run.
--
-- 1. SIGN-UP. The create-account form now asks for the person's country and
--    sends it as sign-up metadata; handle_new_user() saves it on the new
--    profile, so Browse is filtered to it from the first launch.
-- 2. HOME COUNTRY — where someone lives. It can be changed once every 30 days
--    (the first choice, for someone with no country yet, is free). The wait
--    stops people hopping between countries to see or reach other countries'
--    posts. profiles.country_changed_at records the last change; clients can't
--    write it — a trigger does.
-- 3. TEMPORARY COUNTRY — "I'm travelling". Browse another country for 1-30
--    days (temp_country_code + temp_country_until); afterwards the home country
--    applies again by itself (the app ignores an expired one). Must differ from
--    the home country. Posts are unaffected: each keeps the country of the place
--    it was lost or found.
-- ============================================================================

alter table public.profiles add column if not exists temp_country_code text;
alter table public.profiles add column if not exists temp_country_until timestamptz;
alter table public.profiles add column if not exists country_changed_at timestamptz;

do $$ begin
  alter table public.profiles
    add constraint profiles_temp_country_format
    check (temp_country_code is null or temp_country_code ~ '^[A-Z]{2}$');
exception when duplicate_object then null; end $$;

-- Clients may set the temporary country; country_changed_at stays server-only.
grant update (temp_country_code, temp_country_until) on public.profiles to authenticated;

create or replace function public.guard_profile_country()
returns trigger
language plpgsql
as $$
declare
  next_allowed timestamptz;
begin
  -- Home country: once every 30 days. The first choice (no country yet) is free
  -- and starts no wait. Our own functions and the SQL editor aren't held to it.
  if new.country_code is distinct from old.country_code and old.country_code is not null then
    next_allowed := old.country_changed_at + interval '30 days';
    if public.is_api_caller()
       and old.country_changed_at is not null
       and next_allowed > now() then
      raise exception
        'You can change your home country once every 30 days — your next change is possible from %. If you are only travelling, browse another country temporarily instead.',
        to_char(next_allowed at time zone 'UTC', 'DD Mon YYYY')
        using errcode = '22023';
    end if;
    new.country_changed_at := now();
  end if;

  -- Temporary country: only checked when it is being set or changed, so an
  -- expired one never blocks an unrelated edit.
  if new.temp_country_code is distinct from old.temp_country_code
     or new.temp_country_until is distinct from old.temp_country_until then
    if new.temp_country_code is null then
      new.temp_country_until := null;
    else
      new.temp_country_code := upper(btrim(new.temp_country_code));
      if new.temp_country_code !~ '^[A-Z]{2}$' then
        raise exception 'That is not a valid country.' using errcode = '22023';
      end if;
      if new.temp_country_until is null or new.temp_country_until <= now() then
        raise exception 'Choose how long you will be there.' using errcode = '22023';
      end if;
      if new.temp_country_until > now() + interval '30 days 1 hour' then
        raise exception 'A temporary country can last at most 30 days.' using errcode = '22023';
      end if;
      if new.country_code is not null and new.temp_country_code = new.country_code then
        raise exception 'That is already your home country.' using errcode = '22023';
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_guard_country on public.profiles;
create trigger profiles_guard_country
  before update of country_code, temp_country_code, temp_country_until on public.profiles
  for each row execute function public.guard_profile_country();

-- New accounts: take the country from the sign-up form (sent as user metadata).
-- Anything that isn't two letters is ignored, so a bad value can never block
-- account creation.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  signup_country text := upper(btrim(new.raw_user_meta_data ->> 'country_code'));
begin
  insert into public.profiles (id, username, full_name, avatar_url, country_code)
  values (
    new.id,
    split_part(new.email, '@', 1),
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'avatar_url',
    case when signup_country ~ '^[A-Z]{2}$' then signup_country else null end
  );
  return new;
end;
$$;

-- ============================================================================
-- Verify (optional): supabase/tests/27_checks.sql
-- ============================================================================
