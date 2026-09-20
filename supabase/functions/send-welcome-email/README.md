# send-welcome-email

Sends the "You're confirmed!" welcome email once a new user clicks the
confirmation link in their signup email. Triggered automatically by
Postgres — see `supabase/07_email_confirmation.sql`.

All commands below run in a regular terminal, in this project's root
folder (the one with `pubspec.yaml` in it) — VS Code's integrated
terminal (`` Ctrl+` ``) is exactly that, so it works fine; there's
nothing Windows cmd/PowerShell-specific here that VS Code's terminal
can't run just as well. If you're not already there:
```bash
cd path\to\findora
```

## One-time setup

1. **Install the Supabase CLI.** `npm install -g supabase` doesn't
   work — Supabase's npm package deliberately blocks a global install
   and errors out if you try (`npm error ... Installing Supabase CLI as
   a global module is not supported`). Two options:

   **Option A — `npx`** (no install step, but depends on your Node.js
   setup being healthy):
   ```bash
   npx supabase --version
   ```
   That first run downloads it (takes a few seconds) and confirms it
   works. Every command below is written as `npx supabase ...` to match.

   If this fails with something like
   `Error: EEXIST: file already exists, mkdir '...'` /
   `command not found: supabase`, that's npm's cache or Node.js
   install getting confused, not a problem with this project. Two
   common causes on Windows, worth trying in order:
   1. A tool like conda auto-activating its own bundled Node.js and
      conflicting with your system one — if your prompt starts with
      `(base)` or another conda env name, run `conda deactivate` first
      and retry in that same window.
   2. A stale/corrupted npx cache: `npm cache clean --force`, then
      retry.

   Still stuck? Use Option B instead — it doesn't touch npm at all.

   **Option B — Scoop** (Windows only; a real standalone install,
   immune to the npm issues above):
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   irm get.scoop.sh | iex
   scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
   scoop install supabase
   ```
   With this option, drop `npx ` from every command below — just
   `supabase login`, `supabase link`, etc. (macOS/Linux equivalents —
   Homebrew, etc. — are at
   https://github.com/supabase/cli#install-the-cli.)

2. **Log in and link this project:**
   ```bash
   npx supabase login
   npx supabase link --project-ref YOUR_PROJECT_REF
   ```
   Find `YOUR_PROJECT_REF` in Project Settings → General → Reference ID.
3. **Get a Resend API key** (free tier is plenty): sign up at
   https://resend.com, then **API Keys → Create API Key**.
4. **Set the secret:**
   ```bash
   npx supabase secrets set RESEND_API_KEY=re_your_key_here
   ```
5. **Deploy:**
   ```bash
   npx supabase functions deploy send-welcome-email
   ```
6. **Wire up the trigger**: open `supabase/07_email_confirmation.sql`,
   replace `YOUR_PROJECT_REF` and `YOUR_SERVICE_ROLE_KEY` (Project Settings
   → API Keys → `service_role`) with your real values, then run the file in
   the SQL Editor (in your browser, not the terminal — Dashboard → SQL
   Editor → paste the file's contents → Run).

## Testing it

Sign up a new test account in the app (or via the Supabase Dashboard →
Authentication → Users → Invite), confirm the email, and check that
account's inbox. If nothing arrives, check **Edge Functions → 
send-welcome-email → Logs** in the dashboard for the error.

## Sender domain note

`onboarding@resend.dev` (the default `WELCOME_EMAIL_FROM`) only delivers to
the email address you signed up to Resend with — fine for testing, not for
real users. For production, verify your own domain under **Resend →
Domains**, then set (same terminal, same project folder):
```bash
npx supabase secrets set WELCOME_EMAIL_FROM="Findora <hello@yourdomain.com>"
```

