# send-welcome-email

Sends the "You're confirmed!" welcome email once a new user clicks the
confirmation link in their signup email. Triggered automatically by
Postgres — see `supabase/07_email_confirmation.sql`.

## One-time setup

1. **Install the Supabase CLI**, if you don't have it:
   ```bash
   npm install -g supabase
   ```
2. **Log in and link this project** (from the project root):
   ```bash
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   ```
   Find `YOUR_PROJECT_REF` in Project Settings → General → Reference ID.
3. **Get a Resend API key** (free tier is plenty): sign up at
   https://resend.com, then **API Keys → Create API Key**.
4. **Set the secret**:
   ```bash
   supabase secrets set RESEND_API_KEY=re_your_key_here
   ```
5. **Deploy**:
   ```bash
   supabase functions deploy send-welcome-email
   ```
6. **Wire up the trigger**: open `supabase/07_email_confirmation.sql`,
   replace `YOUR_PROJECT_REF` and `YOUR_SERVICE_ROLE_KEY` (Project Settings
   → API Keys → `service_role`) with your real values, then run the file in
   the SQL Editor.

## Testing it

Sign up a new test account in the app (or via the Supabase Dashboard →
Authentication → Users → Invite), confirm the email, and check that
account's inbox. If nothing arrives, check **Edge Functions → 
send-welcome-email → Logs** in the dashboard for the error.

## Sender domain note

`onboarding@resend.dev` (the default `WELCOME_EMAIL_FROM`) only delivers to
the email address you signed up to Resend with — fine for testing, not for
real users. For production, verify your own domain under **Resend →
Domains**, then set:
```bash
supabase secrets set WELCOME_EMAIL_FROM="Findora <hello@yourdomain.com>"
```
