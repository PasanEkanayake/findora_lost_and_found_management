-- ============================================================================
-- Findora — Upgrade: "you're confirmed!" welcome email
-- Run this after 06_contact_messaging.sql.
--
-- Supabase already sends the "Confirm your email" message automatically
-- (Dashboard → Authentication → Email Templates → "Confirm signup" — see
-- supabase/email_templates/confirm_signup.html for the branded version to
-- paste in there). This file adds the *second* email: once someone actually
-- clicks that link, `auth.users.email_confirmed_at` flips from null to a
-- timestamp, and this trigger fires a follow-up "you're verified!" email via
-- an Edge Function (supabase/functions/send-welcome-email) so new users get
-- a clear "signup complete" signal instead of silence after confirming.
--
-- ⚠️ Before running this file:
--   1. Deploy the Edge Function: see
--      supabase/functions/send-welcome-email/README.md.
--   2. Replace the two placeholders below (YOUR_PROJECT_REF,
--      YOUR_SERVICE_ROLE_KEY) with your actual project ref and service
--      role key (Project Settings → API Keys → service_role — NOT the
--      publishable key).
--
-- Embedding the service role key directly in a SQL trigger works but is
-- the least private option available, since anyone with SQL Editor/read
-- access to this function's source can read it back out. If you'd rather
-- not do that, store it in Supabase Vault instead (Dashboard → Project
-- Settings → Vault → "New secret") and swap the hardcoded header below for
-- `(select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')`.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- A public bucket to host web/auth-callback.html — the landing page the
-- confirmation email's link points at (see that file's own header comment
-- for what it does and why it needs to be a real HTTPS page rather than
-- opening the app's custom URL scheme directly). Using Storage for this
-- avoids needing separate web hosting (Firebase Hosting, Netlify, etc.)
-- just for one static file.
--
-- After running this, upload web/auth-callback.html via Dashboard →
-- Storage → site → Upload file, then use its public URL (Dashboard →
-- Storage → site → auth-callback.html → "..." → Get URL) as the
-- `emailRedirectTo` value in signup_screen.dart, and add that same URL
-- under Authentication → URL Configuration → Redirect URLs.
-- ----------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('site', 'site', true)
on conflict (id) do nothing;

drop policy if exists "site files are publicly readable" on storage.objects;
create policy "site files are publicly readable"
  on storage.objects for select
  using (bucket_id = 'site');

create extension if not exists pg_net;

create or replace function public.handle_email_confirmed()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.email_confirmed_at is not null and old.email_confirmed_at is null then
    perform net.http_post(
      url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-welcome-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer YOUR_SERVICE_ROLE_KEY'
      ),
      body := jsonb_build_object(
        'email', new.email,
        'user_id', new.id,
        'full_name', new.raw_user_meta_data ->> 'full_name'
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists on_email_confirmed on auth.users;
create trigger on_email_confirmed
  after update on auth.users
  for each row execute function public.handle_email_confirmed();
