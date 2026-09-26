# Findora — Setup Guide & Reference

Findora is a lost & found app: report a lost or found item, and the AI
compares it against everyone else's — by title and description always,
and by photo too if one's attached — to suggest a match.

This README has two parts. **Part A** is a complete, from-zero, step by
step walkthrough to get the app running on your own Android phone from
VS Code — every step is spelled out, including the ones that feel too
obvious to mention. **Part B** (further down) documents how each part of
the app actually works, organized by build phase, for when you're ready
to extend it.

If you've already been through setup once and just hit a Gradle error,
jump straight to **"Troubleshooting Gradle errors"** in Part A.

---

## What's new since the original build

A later upgrade pass added the following.

⚠️ **`05_multimodal_matching.sql` and `08_soft_delete.sql` are not
optional** — unlike everything else in this section, skipping them
doesn't just mean missing a feature, it **breaks browsing and posting
outright**. `08_soft_delete.sql` adds `items.deleted_at`, and the updated
app code filters every item read (the main feed, My Items, item detail)
on that column existing — run this update's Dart/Flutter code against a
database that hasn't had `08_soft_delete.sql` applied yet, and
`items.deleted_at` doesn't exist, so those queries fail outright and
**the browse feed appears empty** (really: failed to load) even though
your posts are still sitting in the database untouched.
`05_multimodal_matching.sql` similarly adds `items.event_time`, which
posting a new item with a lost/found time set will now try to write —
without that migration, that specific post attempt fails the same way.
If you've pulled this update's code but haven't touched Supabase yet,
**run those two migrations before testing anything**
(`06_contact_messaging.sql` and `07_email_confirmation.sql` are
genuinely optional — see their own rows below).

| Feature | What changed | Setup needed? |
|---|---|---|
| Delete your own posts | Owner-only "Delete post" (item detail's menu, swipe-to-delete in My Items) — now a **soft delete**, see below | **Required:** run `supabase/08_soft_delete.sql` |
| Home screen header | Gradient greeting header with a live lost/found count, replacing the old blank title bar | None |
| CNN photo auto-fill | Now also suggests a **title**, not just category | None |
| Lost/found time | Optional date+time picker when posting | **Required:** run `supabase/05_multimodal_matching.sql` |
| Contact any poster | New "Contact poster" direct-message thread, separate from the confirmed-match chat (Chats tab now has two tabs) | Optional — run `supabase/06_contact_messaging.sql`; skipping it just makes "Contact poster" show an error snackbar, nothing else breaks |
| Multimodal matching | Match score now blends image (CNN), text (NLP), and GPS proximity, not just image | **Required:** run `supabase/05_multimodal_matching.sql`; optionally also deploy `ai_service/` for the text signal |
| App icon | Same logo, white background instead of light blue | None — already regenerated. Re-run `python scripts/generate_icon_pngs.py` only if you change the logo |
| Email confirmation UX | Branded confirm email, opens the app on mobile / closes the tab on desktop, plus a second "you're verified" email | Optional — see "Email confirmation flow" below; skipping it just means Supabase's plain default confirmation email/redirect is used instead |
| Password strength | Live checklist + 5 rules enforced on signup | None |
| Manual location pin | "Adjust pin on map" alongside GPS auto-detect when posting | None |
| Exit confirmation | Back button on the Browse tab's root now asks before closing the app | None |
| Light/dark theme toggle | Profile → Appearance — Light/Dark/System, persisted | None |
| Soft delete | Deleting a post (by its owner or an admin) now hides it instead of removing the row — see "Soft delete: items are hidden, never erased" below | **Required:** run `supabase/08_soft_delete.sql` |
| "NEW" badge | Items posted within the last 3 days show a NEW pill on their card and detail page | None |
| Browse tab always goes home | Tapping "Browse" in the bottom nav now always shows the list, even if the map view was left open | None |
| Google signup confirmation | A first-time Google sign-in now lands on a "You're signed up!" screen before entering the app, instead of silently landing in /feed indistinguishably from a normal login | None — Google sign-in itself still needs its own setup, see "Google sign-in setup (Phase 2)" |
| Edit posts | Owner-only "Edit post" (item detail's menu, next to Delete) — title, description, category, location, event time. Not photos or lost/found type — see `ItemsRepository.updateItem`'s doc for why | None |
| Delete account | Profile → "Delete account" — soft-deletes their items, scrubs their name/photo/phone, blocks future sign-in. See "Account deletion" below for exactly what this does and doesn't do | **Required:** run `supabase/09_account_deletion.sql` |
| Chat flicker fixed | Both message screens (confirmed-match chat and direct messages) no longer flicker mid-conversation — rewritten to update incrementally instead of re-fetching the whole list on every change | None |
| AI matching fixed | Found and fixed the actual bug: photo embeddings were being sent in a format Postgres's `vector` type couldn't reliably parse, so no item ever had a usable embedding and matches could never be created | None — already fixed in code. **But also see "Generating the on-device model (Phase 4)" above** — a still-empty `assets/models/` is an equally common reason matches never appear, and is separate from this bug |
| Matching opened up | Category no longer gates matching — a lost item and a found item in different categories can still match on image/text/GPS/time. Added event-time proximity as a fourth scoring signal, and filter chips (Text match / Nearby / Similar time) on the Matches screen | **Required:** run `supabase/10_open_matching_and_time.sql` |

| Splash tagline | Now reads "The Smart Lost & Found Detective" | None |
| Live chat fixed | Messages (both the confirmed-match chat and direct messages) now show up immediately — the database was never told to broadcast them (`messages` / `contact_messages` were missing from the `supabase_realtime` publication). Also: your own message appears the instant you send it, incoming messages are marked read while the chat is open, a 5-second background sync covers a flaky connection, and the Chats/Matches tabs refetch when opened | **Required:** run `supabase/11_realtime_and_matching_fixes.sql` |
| Exit confirmation fixed | The "Leave Findora?" popup now really appears — the back-button guard moved from `MainShell` into each tab's own route (see "Exit confirmation" below) | None |
| AI matching, second fix | The bundled model's two outputs come out in the opposite order to what the app assumed, so every photo was posted with no embedding and nothing could ever match. The app now detects the order itself. Also: a **scan icon on the Matches tab** (and an automatic scan on opening it) that embeds photos posted before the fix, a visible warning when a photo can't be analyzed, a lower and tunable similarity cut-off, and a trigger so a photo embedded later still gets matched | **Required:** run `supabase/11_realtime_and_matching_fixes.sql`, then follow **A4b** below |

| Photos optional | A post now needs only a **title**. With no photo, the app shows the Findora logo on a neutral tile everywhere a photo would appear (feed, My reported items, matches, chats, post detail). The placeholder is drawn by the app — nothing is uploaded or stored for it. **Note:** it's still matched by title and description either way (see the next row) — a photo only adds a second, independent matching signal on top | None |
| Edit photos | Edit post now handles photos: add more, remove, or tap one to replace it. Changes are held until you press Save. A newly added photo is analysed on-device like at posting, so it can create matches straight away. Removing deletes the photo row and, best-effort, the file in Storage | None (the existing delete policies already cover it) |
| Match by title/description | Posts are now compared by their title and description too, not only their photo — so a post with no photo, or one whose photo failed AI analysis, can still be matched. Runs the moment a post is made or its title/description is edited. Uses a proper meaning-based comparison when the optional `ai_service/` text service is configured and awake, otherwise falls back to comparing the words themselves (no setup needed) | **Required for posts made before this:** run `supabase/12_text_matching.sql`, then `select public.rematch_all_text();` |
| Clearer matches | Each match card shows **your item on the left and the item it matched on the right** (photo, lost/found, title), and tapping either opens that post | None |

| Delete crash fixed | Swiping a post away in "My reported items" could crash with "A dismissed Dismissible widget is still part of the tree" if the server hadn't confirmed the delete by the next frame. The card is now hidden the instant the delete succeeds, instead of waiting on that round trip | None |

| Matches from a post | A post's detail page now has a "View possible matches" row: the owner sees every match found for it (or a note that the AI checks automatically if there are none yet); anyone else sees it only once the post is already matched against one of their own — tapping it opens the same Confirm / Not a match / Message actions as the Matches tab | None |

| Claim status crash + staleness | Filing/approving a claim could crash with a framework tree-consistency error ("_owner != null" / "_children.contains(child)"), because match cards in a list had no stable identity for Flutter to track when a match moved from pending to decided. Separately, the claim/return status banner in a chat only ever loaded once, so the other person's already-open chat never showed a claim was filed, approved, etc. until they left and reopened it | None |

New/changed SQL files, run **in order** after `04_storage_setup.sql` —
`05` and `08` are required, `06`/`07` are optional but harmless to run
anyway:
`05_multimodal_matching.sql`, `06_contact_messaging.sql`,
`07_email_confirmation.sql` (the last one has manual placeholders to fill
in — see its header comment and "Email confirmation flow" below),
`08_soft_delete.sql`, `09_account_deletion.sql`,
`10_open_matching_and_time.sql`,
`11_realtime_and_matching_fixes.sql` (live chat + AI matching fixes —
required), and finally `12_text_matching.sql` (matching by title/
description, independent of photos — required).

---

# Part A — Setup, step by step

## A1. Install the prerequisites (once per machine)

Skip anything you've already got installed — `flutter doctor` (step A1.5)
will tell you what's still missing either way.

### A1.1 Install the Flutter SDK

1. Go to https://docs.flutter.dev/get-started/install and download the
   Flutter SDK for your operating system (Windows/macOS/Linux).
2. Extract/install it somewhere permanent — not a Downloads folder you
   might clear out. A common choice is `C:\src\flutter` on Windows or
   `~/development/flutter` on macOS/Linux.
3. Add Flutter's `bin` folder to your system `PATH`:
   - **Windows**: Search "Environment Variables" in the Start menu → Edit
     the system environment variables → Environment Variables → under
     "User variables", select `Path` → Edit → New → add the full path to
     the `flutter\bin` folder → OK on every dialog.
   - **macOS/Linux**: open your shell profile (`~/.zshrc`, `~/.bashrc`, or
     `~/.bash_profile`) in a text editor and add a line:
     `export PATH="$PATH:/full/path/to/flutter/bin"`, save, then run
     `source ~/.zshrc` (or whichever file you edited) or just open a new
     terminal window.
4. Close and reopen every terminal/VS Code window so the new `PATH` takes
   effect, then confirm it worked:
   ```bash
   flutter --version
   ```
   This should print a Flutter and Dart version, not "command not found".

### A1.2 Install Android Studio (for the Android SDK — you won't write code in it)

Even though you're developing in VS Code, Android Studio is the easiest
way to install and manage the Android SDK, platform tools, and an
emulator.

1. Download and install Android Studio from
   https://developer.android.com/studio.
2. Open it once. On first launch it runs a "Setup Wizard" — accept the
   defaults and let it download the Android SDK, SDK Platform-Tools, and
   a recent Android SDK Platform. This can take a while on a slow
   connection.
3. Once it's open, go to **More Actions → SDK Manager** (or **Settings →
   Languages & Frameworks → Android SDK** if a project is already open).
   Under the **SDK Tools** tab, make sure these are checked, then click
   **Apply**:
   - Android SDK Command-line Tools (latest)
   - Android SDK Platform-Tools
   - Android SDK Build-Tools (latest)
4. Accept the Android SDK licenses from a terminal:
   ```bash
   flutter doctor --android-licenses
   ```
   Press `y` and Enter to accept each one.

### A1.3 Make sure Gradle will use Java 17

This project's Android build is configured for Java 17 specifically (see
"Troubleshooting Gradle errors" below for why). Android Studio ships its
own bundled JDK that's new enough, so the simplest fix is pointing
`JAVA_HOME` at it.

1. Find Android Studio's bundled JDK folder:
   - **Windows**: usually
     `C:\Program Files\Android\Android Studio\jbr`
   - **macOS**: usually
     `/Applications/Android Studio.app/Contents/jbr/Contents/Home`
   - **Linux**: usually
     `/usr/local/android-studio/jbr` or wherever you installed it, under
     a `jbr` folder
2. Set `JAVA_HOME` to that path:
   - **Windows**: Environment Variables (same dialog as step A1.1) → under
     "User variables" → New → Variable name `JAVA_HOME`, Variable value =
     the path from step 1 above.
   - **macOS/Linux**: add to the same shell profile file as step A1.1:
     `export JAVA_HOME="/path/from/step/1"`, save, and reload the shell.
3. Open a **new** terminal window and confirm:
   ```bash
   java -version
   ```
   This should report version `17.x`.

### A1.4 Install VS Code + the Flutter extension

1. Download VS Code from https://code.visualstudio.com if you don't have
   it already.
2. Open VS Code → Extensions icon in the left sidebar (or `Ctrl+Shift+X` /
   `Cmd+Shift+X`) → search for **"Flutter"** → install the official one
   published by Dart Code. This automatically installs the **Dart**
   extension too.

### A1.5 Verify everything with flutter doctor

```bash
flutter doctor -v
```

Look for a checkmark next to "Flutter", "Android toolchain", and "VS
Code". Fix anything marked with `✗` before moving on — the tool
usually tells you exactly what command to run. It's normal to see
warnings about Chrome or Xcode if you don't plan to build for web/iOS.

## A2. Get the project open in VS Code

1. Unzip the project folder you were given, anywhere you like (e.g.
   `Documents/findora`).
2. Open VS Code → **File → Open Folder…** → select the unzipped `findora`
   folder (the one that directly contains `pubspec.yaml`, `lib/`,
   `android/`, etc.).
3. VS Code will likely show a popup "This workspace contains a Flutter
   project — get the Dart/Flutter extensions?" — since you already
   installed them in A1.4, you can dismiss this.
4. Open a terminal inside VS Code (**Terminal → New Terminal**) and run:
   ```bash
   flutter pub get
   ```
   This downloads every Dart package listed in `pubspec.yaml`. It should
   finish with no red error text.

## A3. Set up the Supabase backend

1. Create a free project at https://supabase.com/dashboard (sign up if
   you don't have an account, then **New Project**).
2. Wait for the project to finish provisioning (a minute or two).
3. In the left sidebar, click **SQL Editor**, then **New query**.
4. Open `supabase/01_extensions_and_tables.sql` from the project folder
   in VS Code, select all the text (`Ctrl+A`/`Cmd+A`), copy it, paste it
   into the Supabase SQL editor, and click **Run** (or `Ctrl+Enter`).
   Confirm it says "Success. No rows returned" and not an error.
5. Repeat step 4 for `02_functions_and_triggers.sql`.
6. Repeat step 4 for `03_rls_policies.sql`.
7. Repeat step 4 for `04_storage_setup.sql`.
   ⚠️ **Run these four in this exact order** — each one depends on
   tables/functions the previous one created.
7b. Same again for `05_multimodal_matching.sql`, then
   `06_contact_messaging.sql`, then `07_email_confirmation.sql` (also in
   order) — these add event time, multimodal (image+text+GPS) matching,
   direct contact messaging, and the welcome-email trigger. The app runs
   without them too (older columns/functions these `create or replace`
   just won't exist yet), but My Items' delete, Contact poster, and the
   richer match scoring all depend on them. `07_email_confirmation.sql`
   specifically has two placeholders to edit before running it — see
   "Email confirmation flow" further down.
7c. Then `08_soft_delete.sql`, `09_account_deletion.sql`,
   `10_open_matching_and_time.sql`, `11_realtime_and_matching_fixes.sql`
   and `12_text_matching.sql`, in that order. Each is safe to re-run.
   `08`, `10`, `11` and `12` are needed for the current app code to work
   properly (see the top of this file).
8. In the left sidebar, click the gear icon (**Project Settings**) →
   **API Keys**. Copy two values, you'll need them in the next step:
   - **Project URL** (looks like `https://xxxxx.supabase.co`)
   - **Publishable key** (starts with `sb_publishable_...`) — Supabase is
     retiring the old "anon" key naming in favor of this; make sure you
     copy the *publishable* one, not the *secret* one.

## A4. Configure your environment variables

1. In VS Code's file explorer, find `.env.example` in the project root.
2. Make a copy of it in the same folder named exactly `.env` (no `.example`).
   You can right-click → Copy, then right-click → Paste, then rename, or
   from the terminal:
   ```bash
   cp .env.example .env
   ```
3. Open `.env` and replace the placeholder values with the real ones from
   step A3.8:
   ```
   SUPABASE_URL=https://your-actual-project-ref.supabase.co
   SUPABASE_PUBLISHABLE_KEY=sb_publishable_your_actual_key
   ```
   Two more keys exist below those and can stay blank for now —
   `AUTH_CALLBACK_URL` (see "Email confirmation flow") and
   `AI_SERVICE_URL` (see `ai_service/README.md`) — both are optional and
   the app degrades gracefully without them.
4. Save the file. `.env` is already listed under `assets` in
   `pubspec.yaml`, so Flutter bundles it automatically — you don't need
   to do anything else for it to be picked up. It's also already excluded
   from `.gitignore` conventions for this kind of file; if you put this
   project under version control, double check `.env` isn't committed.

## A4b. Set up AI matching — start to finish (do this before `flutter run`)

Everything AI-related, in order. Nothing here needs Python or TensorFlow
on your machine: the project already ships the model files.

**Step 1 — Make sure all 12 migrations have been run.**
In the Supabase SQL Editor, run the migrations from A3 in numeric order
(`01` … `12`). Skipping ahead is the usual cause of confusing errors, so if
you're not sure which ones you ran, just run any you're unsure of again —
they are all safe to re-run.

**Step 2 — Confirm migrations 11 and 12 took effect.**
Run each of these on its own:
```sql
-- both chat tables should be listed (this is what makes chat live):
select tablename from pg_publication_tables
where pubname = 'supabase_realtime' and schemaname = 'public';

-- should return 0.6:
select public.matching_threshold();

-- should return 0.3:
select public.text_matching_threshold();

-- should list BOTH item_images_record_matches and
-- item_images_record_matches_on_embedding:
select tgname from pg_trigger
where tgrelid = 'public.item_images'::regclass and not tgisinternal;

-- should list BOTH items_record_text_matches_insert and
-- items_record_text_matches_update:
select tgname from pg_trigger
where tgrelid = 'public.items'::regclass and not tgisinternal;
```
Or run query 4 in `supabase/diagnostics_matching.sql` — every column in its
result should say `true`.

**Step 3 — Confirm the model files are in place.** From the project root
(PowerShell or Command Prompt):
```powershell
dir assets\models
```
You should see `mobilenet_v2_embedder.tflite` (about 3.8 MB) and
`imagenet_labels.txt`. Both ship with the project. Only if either is
missing, generate them with the steps under "Generating the on-device
model (Phase 4)" in Part B.

**Step 4 — (Optional) text matching service.**
Photo matching works without it. It only adds the "📝 text similarity"
signal. If `AI_SERVICE_URL` in `.env` points at your deployed
`ai_service/` (see `ai_service/README.md`), nothing else to do. Free hosts
put idle services to sleep and take 30–60 seconds to wake, so the app now
pings the service the moment the "Report item" form opens, giving it time
to wake while you fill in the form. If the service still isn't ready when
you tap Post, the item is posted without a text signal — photo matching is
unaffected.

**Step 5 — Do a full restart (not hot reload).**
Asset and model changes are only picked up by a fresh build:
```powershell
flutter pub get
flutter run
```
If a run was already going, stop it first.

**Step 6 — Check the model loaded correctly.**
Open **Report item** (or the **Matches** tab). In the `flutter run` console
you should see lines like:
```
TFLite output 0: shape=[1, 1000]
TFLite output 1: shape=[1, 1280]
TFLite ready: embedding=output 1, classes=output 0 (1000), 1000 labels
```
The exact indices depend on the model file; what matters is that one
output is `1280` wide and the "ready" line appears. If instead you see an
error mentioning "no 1280-wide output", the model file isn't the one this
project expects — regenerate it (Part B, "Generating the on-device model").

**Step 7 — Fix posts made earlier (every account needs this once).**

Title/description matching runs automatically for anything posted **after**
migration 12 — nothing to do for those. For posts made *before* it, run
this once in the SQL Editor (safe to re-run):
```sql
select public.rematch_all_text();
```

Photos are separate — see the next step.

**Step 8 — Fix photos posted earlier (every account needs this once).**
Photos posted before this fix have no AI data, so they can't be matched.
The app now analyses them automatically **as soon as it launches** (the
console prints `Embedding backfill: …`), and the Matches tab's scan icon
does the same on demand.

The catch: a photo can only be analysed on its **owner's** phone. A match
needs *both* photos of the pair analysed, so if account A hasn't opened the
updated app yet, nobody sees matches against A's items — even though their
own photos are fine. When testing with several accounts, sign in to **each**
one once on the updated build and wait a few seconds (the Matches tab's
scan icon shows a progress bar while it works). Matches then appear for
everyone involved without any further action.

**Step 9 — Test it properly, with two accounts.**
Matching deliberately never pairs two items from the *same* account, and
only pairs a **lost** item with a **found** one. So:
1. Account A: report a **Lost** item with a clear photo.
2. Account B (another phone/emulator, or sign out and sign in as someone
   else): report a **Found** item with a photo of the same — or a very
   similar — object.
3. Open **Matches** as either account. Even with no photo on either side,
   similar enough titles/descriptions should already show a match.

If nothing appears, run `supabase/diagnostics_matching.sql` in the SQL
Editor, one query at a time. **Start with 2b** — it lists every item with
its owner, type and `has_embedding`. A Lost and a Found item from different
owners that are both `true` should have matched by photo; regardless of
that column, they should also have matched by text unless their wording is
genuinely dissimilar. A `false` `has_embedding` just means that owner still
needs to open the updated app for photo matching specifically (Step 8).
Then:
- **3d** — the real text similarity of each cross-account pair. If your
  test pair scores below `0.3`, the words themselves don't overlap enough
  — try more similar wording, or lower the number in
  `text_matching_threshold()` (edit that function in migration 12, re-run
  it, then run `select public.rematch_all_text();`).
- **3c** — does each account have photos *with* an embedding? Any
  `without_embedding` above 0 means open that account's Matches tab (Step 8).
- **3b** — the real image similarity of each cross-account pair. If your
  test pair scores below `0.60`, the model doesn't consider the photos
  alike. Either use a clearer photo or lower the number in
  `matching_threshold()` (edit that function in migration 11, re-run it,
  then run `select public.rematch_all_images();`).
- **5** — the `matches` table itself.

**What to do if a post says "the AI could not analyze N photos".**
The item is posted, but those photos can't be matched yet. Open Matches
and tap the scan icon to retry. If it fails again, the error text shown
there says why — a model that failed to load (Step 6), no internet, or
migration 11 missing.

## A5. Android configuration — what's already done, and what's left

To save you a step, the Android manifest and Gradle files in this project
already have the following applied:

- ✅ Camera, location, media, and notification permissions
  (`android/app/src/main/AndroidManifest.xml`)
- ✅ Core library desugaring, Java 17, and `minSdk 24`
  (`android/app/build.gradle.kts`) — required by
  `flutter_local_notifications` 22+; see "Troubleshooting Gradle errors"
  for why this matters.
- ✅ App icon PNGs already generated in `assets/images/`

Two things are placeholders you can fill in when you're ready — the app
runs fine on a device without either of them, just with reduced features:

### A5.1 (Optional) Google Maps

The map view will show a blank/grey map until you add a real API key.

1. Go to https://console.cloud.google.com/, create or select a project.
2. Enable the **"Maps SDK for Android"** API (search for it in the API
   Library).
3. Create an API key under **APIs & Services → Credentials → Create
   Credentials → API key**.
4. Open `android/app/src/main/AndroidManifest.xml` and replace
   `YOUR_GOOGLE_MAPS_API_KEY_HERE` with your real key.

### A5.2 (Optional) Google Sign-In and push notifications

These need more setup (a Firebase project, Supabase provider config) and
are documented in Part B under "Google sign-in setup" and "Firebase setup
for push notifications". Skip them for now — email/password login and
the rest of the app work without them.

### A5.3 Regenerate the app icon (only if you change the design)

The launcher icon PNGs are already generated (white background, logo from
`assets/images/logo.png`) and referenced from `pubspec.yaml`. If you ever
redesign `assets/images/logo.png` and want to regenerate every launcher
icon (Android, adaptive icon foreground, web/PWA, favicon) from it:

```bash
python scripts/generate_icon_pngs.py
```

(Every Python command in this README uses `python` — that's what
Windows' official installer registers. On macOS/Linux, `python` is
sometimes missing or points to Python 2, so use `python3` there instead
if `python` doesn't work.)

or, equivalently for just the Android files, the standard Flutter tool:

```bash
dart run flutter_launcher_icons
```

See `assets/images/README.md` for what each generated file is for.

## A6. Connect your physical Android device

### A6.1 Enable Developer options and USB debugging on the phone

1. Open **Settings** on your Android phone.
2. Go to **About phone** (exact wording varies slightly by manufacturer).
3. Find **Build number** and tap it **7 times** in a row. You'll see a
   countdown toast like "You are now 3 steps away from being a
   developer." After the 7th tap, it'll say "You are now a developer!"
4. Go back to the main **Settings** screen → **System** → **Developer
   options** (on some phones this is its own top-level entry in Settings
   instead of under System).
5. Turn on **Developer options** if it's not already on, then scroll down
   and enable **USB debugging**.

### A6.2 Plug in the phone and authorize your computer

1. Connect the phone to your computer with a USB cable that supports data
   transfer (not a charge-only cable).
2. If your phone shows a popup asking about the USB connection mode,
   choose **File Transfer** or **PTP** (not "Charging only").
3. A dialog should appear on the phone: **"Allow USB debugging?"** with
   your computer's RSA key fingerprint. Check **"Always allow from this
   computer"** and tap **Allow**. If you don't see this dialog, unplug and
   replug the cable.
4. Verify your computer sees the device:
   ```bash
   flutter devices
   ```
   You should see your phone listed by name. If it shows "no devices
   detected" or "unauthorized", see "Device not showing up" in the
   troubleshooting section below.

### A6.3 Run the app

In VS Code:

1. Look at the bottom-right status bar — there should be a device name
   shown (or "No Device"). Click it and select your phone from the list.
2. Press **F5**, or open the **Run and Debug** panel (left sidebar) and
   click the green play button, or from the terminal:
   ```bash
   flutter run
   ```
3. The first build will take a few minutes (Gradle has to download
   dependencies and compile everything). Subsequent runs are much faster.
4. If it builds successfully, the app installs and opens on your phone,
   landing on the splash screen and then the login screen.

If step 3 fails with a Gradle-related error, continue to the next section.

**A note on AI features specifically**: `assets/models/` ships with the
model file and label list, so photo auto-tagging and image matching work
once the database side is set up. **Follow "A4b. Set up AI matching" above
before your first run** — it covers the SQL migration, checking the model
loads, and testing with two accounts. If the model is ever missing or
broken, the app doesn't crash: posting still works, but it now warns you
that the photo couldn't be analyzed (see `core/ml/tflite_provider.dart`).

## A7. Troubleshooting Gradle errors

### "Timeout waiting to lock build logic queue" / a second Gradle instance

This means two Gradle processes are fighting over the same project — most
commonly VS Code's Java extension trying to auto-import `android/` as a
standalone Gradle project in the background, using its own Gradle
version and JDK, completely separately from Flutter's own build. Add
this to `.vscode/settings.json` (already done in this project) to stop
it happening:
```json
{
    "java.import.gradle.enabled": false,
    "java.import.exclusions": ["**/android/**"]
}
```
Then close VS Code, kill any lingering `java.exe` processes in Task
Manager, delete `android/.gradle`, and reopen.

### "Could not close incremental caches" / `BuildToolsApiCompilationWork` failures

If you see this for one or more plugins (commonly
`firebase_core`, `geocoding_android`, `image_picker_android`,
`google_maps_flutter_android`, or similar), it's **not a bug in this
project** — it's a currently-active Flutter ecosystem migration issue.
Flutter is transitioning Android builds to a new "Built-in Kotlin" model
required by AGP 9+ (which this project's `flutter create` selected), and
as of this writing, many widely-used plugins haven't finished migrating
to it yet. Their old-style Kotlin compilation is hitting a cache-closing
bug under this newer toolchain. This is being tracked upstream at
flutter/flutter#173456, #187225, and #185121 — it isn't unique to this
project or something specific to Findora's code.

**First**, this project's `android/gradle.properties` already has
`kotlin.incremental=false`, a documented, low-risk workaround that
avoids the buggy code path (slightly slower rebuilds, no other effect).
If you're seeing this error, do a clean rebuild first to make sure that
setting actually takes effect:
```bash
flutter clean
cd android
./gradlew clean          # on Windows: gradlew.bat clean
cd ..
flutter pub get
flutter run
```

**If it still fails after a clean rebuild**, this is an active upstream
issue and the most reliable fix available to an app developer (rather
than waiting on each plugin's maintainers) is dropping to a slightly
older, more mature Flutter release that predates this migration push:
```bash
flutter downgrade
```
This walks you through installing the previous stable release. Check
https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin
for the current state of the migration before deciding how far back to
go — plugin authors are actively updating, so this may resolve itself
with a `flutter pub upgrade` in the near future without downgrading at all.

### "Out of memory" / `allocation.cc: error: Out of memory` during the build

If the crash trace mentions `kernel_snapshot_program` or points into the
Dart VM's own allocation code, this is happening in the **Dart compiler
running on your development machine**, not the Android device — the
device name in the "Launching..." line is a red herring here. It means
your PC ran out of available RAM while compiling the app, usually from
too much running at once: the Gradle daemon (which by default reserves a
large heap — already turned down in this project's `gradle.properties`
from 8GB to 3GB), a separate Kotlin daemon, the Dart compiler itself, and
whatever else is open (Android Studio, browser tabs, VS Code extensions).

If you hit this:
1. Stop any lingering Gradle/Kotlin daemons before retrying — repeated
   failed builds can leave several idling in memory simultaneously:
   ```bash
   cd android
   ./gradlew --stop          # on Windows: gradlew.bat --stop
   cd ..
   ```
2. Close other memory-heavy applications (Android Studio if it's open
   separately, browser windows, etc.) before running `flutter run` again.
3. If it still happens on a machine with 16GB or less, the `-Xmx3G` in
   `gradle.properties` can be turned down further (e.g. `-Xmx2G`) — Gradle
   will just run a bit slower, which is a better trade than failing outright.

### "Inconsistent JVM Target Compatibility Between Java and Kotlin Tasks"

This shows up as something like:
```
Inconsistent JVM-target compatibility detected for tasks 'compileDebugJavaWithJavac' (11) and 'compileDebugKotlin' (21).
```
for a specific plugin (`tflite_flutter` and others are known to hit this).
It means that plugin's own bundled Android build config — which lives in
the pub cache, not this project, so it can't be edited directly — sets a
Java target that doesn't match the Kotlin target Gradle resolves for it.

This project's root `android/build.gradle.kts` fixes this by reading
each module's own Java target (set by that plugin's own build file,
never touched by this project) and pointing that module's Kotlin target
at the same value — via a `gradle.taskGraph.whenReady` hook, since that's
the only point at which every module's configuration (including AGP's
own internal wiring) is guaranteed to have already finished.

This took three attempts to get right, and it's worth knowing the
history in case you ever touch this block:
1. A plain `subprojects { tasks.withType<JavaCompile>().configureEach {} }`
   only partially worked — it fixed Kotlin but not Java, since AGP sets
   each plugin's own `compileOptions` on its `JavaCompile` task during
   that plugin's own configuration, which can run *after* an ordinary
   configuration block's action fires.
2. Forcing `JavaCompile`'s `sourceCompatibility`/`targetCompatibility` to
   17 directly via `taskGraph.whenReady` did fix the mismatch, but broke
   something worse: it interfered with AGP's own classpath wiring for
   that task, and `android.jar` (Android's own SDK classes) silently
   vanished from the compile classpath entirely — surfacing as
   `package android.app does not exist` and similar errors for basic
   Android classes, for a module that had nothing wrong with its actual
   code.
3. The current version never touches `JavaCompile` at all — it only
   *reads* each module's already-correct Java target and aligns Kotlin
   to match it, leaving AGP's classpath wiring completely undisturbed.

If you add a new plugin and hit this again, no action should be needed —
the override reads each module's target dynamically rather than assuming
a fixed value. If it somehow persists, a `flutter clean` followed by a
rebuild clears any stale per-module build cache that might be masking
the fix taking effect.

### "Dependency ':flutter_local_notifications' requires core library desugaring to be enabled"

This is already fixed in this project's `android/app/build.gradle.kts`
(`isCoreLibraryDesugaringEnabled = true` plus the matching
`coreLibraryDesugaring` dependency). If you still see this exact error,
double-check you're running the version of `build.gradle.kts` from this
project and haven't accidentally reverted it, then run a clean rebuild
(see below).

### "Manifest merger failed" mentioning minSdkVersion

`flutter_local_notifications` 22+ requires `minSdk 24` or higher, which
is also already set in `build.gradle.kts`. If a different plugin you add
later demands an even higher minimum, the error message will name the
exact number to use — update the `minSdk` line to match.

### "Your project is configured with Android NDK [X], but the following plugin(s) depend on a different Android NDK version"

This project has several plugins with native code (`google_maps_flutter`,
`tflite_flutter`, `geolocator`, `image`), and it's common for them to
disagree slightly on which NDK version they were built against. The
error message tells you exactly which version to use — copy it and add
(or edit) this line inside the `android { }` block of
`android/app/build.gradle.kts`:

```kotlin
android {
    ndkVersion = "27.0.12077973"  // use the exact version from your error message
    // ... rest of the block
}
```

### "Unsupported class file major version" or Java version errors

This means Gradle is using a Java version other than 17. Double check:

1. `java -version` in your terminal shows `17.x` (see step A1.3).
2. In VS Code, if you have the **Gradle for Java** extension installed,
   check its settings for a `java.home` or `java.import.gradle.java.home`
   override that might be pointing somewhere else.
3. As a last resort, you can point Gradle at a specific JDK regardless of
   `JAVA_HOME` by adding a line to `android/gradle.properties`:
   ```
   org.gradle.java.home=/full/path/to/a/jdk-17
   ```

### "SDK location not found" / "flutter.sdk not set in local.properties"

`android/local.properties` (auto-generated, not committed to version
control) needs to point at both your Flutter SDK and Android SDK. Delete
it and let Flutter regenerate it:

```bash
flutter clean
flutter pub get
```

### Device not showing up in `flutter devices`

- Make sure USB debugging is on (step A6.1) and you tapped "Allow" on the
  phone's dialog (step A6.2).
- Try a different USB cable or port — some cables are charge-only.
- Run `flutter doctor -v` and check the "Android toolchain" and any
  device-related lines for a more specific error.
- On Windows, you may need the phone manufacturer's USB driver installed.

### Clean rebuild (fixes a surprising number of stale-cache issues)

```bash
flutter clean
cd android
./gradlew clean          # on Windows: gradlew.bat clean
cd ..
flutter pub get
flutter run
```

### Still stuck?

Copy the **full** error text from VS Code's terminal (scroll up — the
first red line usually isn't the actual cause, the real error is often
further up) and share it. "Gradle error" alone can mean dozens of
different things; the exact message is what actually pins it down.

---

# Part B — Reference: how the app is built

This part documents what each phase of the build added and why, for when
you're ready to extend the app. It assumes you've completed Part A.

## App icon and branding

`assets/images/` has the Findora logo — a blue magnifying glass with a
cyan lens and an orange location pin, with circuit-style accents. This is
a real PNG asset (not hand-drawn vector shapes), composited into launcher
icons with Pillow.

- `logo.png` — the logo itself, transparent background, used directly via
  `Image.asset()` on the splash screen and login screen.
- `app_icon.png` — the logo composited onto a rounded **white** square
  (changed from the original light-blue background), the flat launcher
  icon source for `flutter_launcher_icons`.
- `app_icon_foreground.png` — the logo alone on transparent, padded for
  Android's adaptive icon safe zone. Its background color is set
  separately to white in `android/app/src/main/res/values/colors.xml`
  (`ic_launcher_background`) and `pubspec.yaml`
  (`flutter_launcher_icons.adaptive_icon_background`).

The app's whole color theme (`core/theme/app_colors.dart`) sources its
primary/secondary colors from this logo — vivid blue primary, cyan
accent, orange secondary — via `ColorScheme.fromSeed`, so the brand color
carries through every screen's buttons, chips, and selected states
automatically rather than needing per-screen updates.

To regenerate every launcher/PWA icon after changing the logo:

```bash
python scripts/generate_icon_pngs.py
```

See `assets/images/README.md` for details on what each output is used
for, and the equivalent `flutter_launcher_icons` command for just the
Android files.

## Profile sub-screens

Everything under Profile is wired to real functionality, not placeholder
taps:

- **Edit profile** (pencil icon next to the avatar) — updates
  `full_name`/`phone` on the `profiles` row, and uploads a new avatar to
  the `avatars` Storage bucket (already set up back in Phase 1).
- **My reported items** — every item you've posted, any status, with a
  status badge (open/matched/claimed/resolved) — unlike the main feed,
  which only shows open items. Swipe a card left, or tap its trailing
  delete icon, to remove a post from the app (`ItemsRepository.deleteItem`
  — a soft delete, see "Soft delete: items are hidden, never erased"
  below for what that actually does).
- **Appearance** — Light/Dark/System, persisted via `shared_preferences`
  (`core/theme/theme_mode_controller.dart`). Overrides the OS setting
  until switched back to "System default".
- **Notification settings** — reads the actual OS-level permission via
  `FirebaseMessaging.getNotificationSettings()`, and a toggle that
  registers or clears this device's push token on your profile. Real
  state, not a decorative switch.
- **Privacy & safety** — meetup safety guidance and a plain explanation
  of what's shared with other users vs. kept private.
- **Help & support** — an FAQ plus a "Contact support" button that opens
  a pre-filled `mailto:` email. This needed a new direct dependency
  (`url_launcher`) and a manifest `<queries>` entry for the `mailto:`
  scheme — Android 11+ hides apps from `canLaunchUrl`/`launchUrl` unless
  you declare you're looking for them.

## The "Report item" button (Home and Matches only)

The floating "Report item" button used to show on all four tabs,
center-docked. It now only appears on Browse and Matches
(`MainShell._branchesWithReportFab`), and floats at the bottom-right
(`FloatingActionButtonLocation.endFloat`) instead of center-docked —
reporting an item isn't a relevant action while reading chats or looking
at your own profile.

## Splash screen

Rebuilt to match a provided reference design: a soft white-to-light-blue
gradient background, the logo at a larger size, "Findora" in bold blue
alongside an "AI-Powered Lost & Found" tagline, and a custom animated
loading ring (a rotating `CustomPainter`, not a stock
`CircularProgressIndicator`) with "Initializing AI Engine..." beneath it.
The actual session-check logic (redirecting to `/login` or `/feed`) is
unchanged — only the visual presentation changed.

## Google sign-in setup (Phase 2)

The "Continue with Google" button calls `signInWithOAuth`, but the
redirect back into the app needs setup outside of Dart code — in two
different places, for two different hops, easy to mix up:

1. **Google Cloud Console** → APIs & Services → Credentials → your OAuth
   2.0 Client ID (Web application type) → **Authorized redirect URIs** →
   add:
   ```
   https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback
   ```
   This is the one people get wrong — **not** the app's custom scheme.
   The actual flow is app → Supabase → Google → back to Supabase → back
   to the app, and this URI is what Google redirects to (Supabase's own
   callback endpoint), not where the app ends up. Getting this wrong
   looks like Google's own error page: "Access blocked: this app's
   request is invalid" / "Error 400: redirect_uri_mismatch" — if you see
   that, it's this URI, not anything in Supabase's dashboard or in code.
2. **Supabase Dashboard** → Authentication → Providers → enable Google,
   and paste in that same OAuth client's ID/secret.
3. **Supabase Dashboard** → Authentication → URL Configuration → add
   `io.supabase.findora://login-callback` as a redirect URL — this one
   *is* the custom scheme, for the second hop (Supabase → app), which is
   entirely separate from step 1's URI and doesn't get registered with
   Google at all.
4. **Android**: the intent filter for this scheme is already in
   `android/app/src/main/AndroidManifest.xml` — nothing to add there.

Skip all of this and the email/password flow still works fine — the
Google button will just fail with an error page instead (which one
depends on exactly what's missing — "provider is not enabled" means step
2 hasn't been done yet at all; "redirect_uri_mismatch" means step 2 is
done but step 1 wasn't, or was entered with a typo).

## Item detail screen: carousel, map preview, delete, and contact

- The photo `PageView` now has animated dot indicators instead of no way
  to tell there's more than one photo, plus a rounded "sheet" content
  layout that overlaps the carousel slightly (`_ItemDetailBody`).
- A small non-interactive map preview (`google_maps_flutter` in
  `liteModeEnabled`) shows under the description when the item has a
  location — backed by a new `get_item_coordinates()` RPC, since a raw
  PostGIS geography value doesn't serialize predictably over PostgREST
  (same reasoning as `nearby_items()` back in Phase 6).
- **Owner**: an overflow menu (`_OwnerMenu`) with "Delete post" — a soft
  delete (see "Soft delete: items are hidden, never erased" below), not a
  real `delete`; RLS no longer permits the latter at all.
- **Everyone else**: two separate paths, kept deliberately apart rather
  than merged into one generic "message" button:
  - A confirmed AI match connecting one of *your* items to this one
    opens the verified claim/chat flow (`ChatScreen`) — still gated
    behind a confirmed match on purpose (Phase 5/7), so contact info
    isn't shared before ownership looks plausible.
  - Otherwise, a **"Contact poster"** button opens a lighter, separate
    direct-message thread (`contact_threads`/`contact_messages` — see
    `supabase/06_contact_messaging.sql` and the "Direct contact
    messaging" section below) — for a quick question before you're sure
    it's a match, without needing an AI match to exist first. The old
    "report your own matching item" shortcut is still there underneath
    it.

## Direct contact messaging

A second, parallel messaging system alongside the confirmed-match chat
from Phase 7 — added because item detail's old "no generic contact
button, on purpose" design (see above) was too strict for "quick
question before I'm sure it's mine" cases. Deliberately kept as a
*separate* table/flow rather than folding into `matches`/`messages`, so
the claim-verification lifecycle (`claims`, ratings, "mark returned")
stays exclusively reachable through a real AI match — direct contact is
just messaging, nothing more.

- `contact_threads` — one row per (item, person who reached out);
  `start_contact_thread()` is idempotent, so tapping "Contact poster"
  again just reopens the same thread.
- `contact_messages` — the messages themselves, RLS-restricted to the
  thread's two participants.
- `lib/features/contact/` — `ContactRepository`, `ContactChatScreen`
  (a deliberately plain bubble UI, no claim-lifecycle banner).
- `ChatListScreen` now has two tabs: **Matches** (unchanged) and
  **Direct messages** (new), so both conversation types stay visible
  from one place.

## Loading skeletons

`core/widgets/shimmer_list.dart` has two reusable shimmer placeholders —
`ShimmerCardList` (matches the image+title+subtitle card shape used by
the feed, matches, and my-items lists) and `ShimmerTileList` (matches the
chat list's avatar rows) — now shown during loading instead of a bare
`CircularProgressIndicator` that gives no sense of what's about to
appear. The `shimmer` package was already in `pubspec.yaml` from Phase 1
but had never actually been used until now.

## Onboarding

A 3-page carousel (`features/onboarding/onboarding_screen.dart`) explains
reporting an item, AI matching, and the verify-then-reunite flow before
first login. It's shown once per *device*, not per account — persisted
via `shared_preferences` (`core/onboarding/onboarding_prefs.dart`), added
as a direct dependency since it was previously only present transitively
through `supabase_flutter`. The splash screen's redirect logic now checks
this flag: signed out + onboarding not seen → `/onboarding`; signed out +
already seen → `/login`. `/onboarding` also had to be added to the
router's `isAuthRoute` set, or the redirect logic built in Phase 2 would
immediately bounce a signed-out user away from it back to `/login`.

## Accessibility pass

- Every icon-only button now has a `tooltip` (which also sets its
  screen-reader label in Flutter) — the password visibility toggle, send
  button, star-rating buttons, and the post-item form's close button were
  missing one.
- Two small overlay buttons (remove-photo on a thumbnail, change-avatar
  badge) had tap targets as small as 24dp — well under the 48dp minimum.
  Both are now wrapped with `Semantics` labels and padded hit areas; the
  photo-remove button only reaches ~40dp rather than the full 48dp, since
  the thumbnails sit only 12px apart and a full-size target would overlap
  the next photo.
- Replaced a hardcoded brand-blue hex color on the login screen with
  `theme.colorScheme.primary`. Material 3's `ColorScheme.fromSeed`
  generates a lighter, higher-contrast tone of the brand color
  specifically for dark mode — a fixed hex value skips that and could end
  up low-contrast against a dark background. (The splash screen's fixed
  light design is left as-is; splash screens commonly show a constant
  brand look regardless of system theme.)

## Auth state and routing (Phase 2)

**Profile data fix**: the signup form's "Full name" field used to be sent
as `username` — a column that had a `unique` constraint. Two users
signing up with the same name would make the *second* signup fail
outright with a database constraint violation, since the
`handle_new_user` trigger runs inside the same transaction as account
creation. Fixed by: dropping the unique constraint (there's no "pick a
unique handle" UX in this app, so it was never enforceable correctly
anyway), having signup send `full_name` instead, and having the trigger
derive `username` safely from the email prefix instead of user input.
`ProfileScreen` now reads the display name from the `profiles` table
(`full_name`, falling back to `username`, then email) instead of reading
raw Supabase Auth metadata directly, consistent with how rating and admin
status are already sourced. If you already ran `01_extensions_and_tables.sql`
and `02_functions_and_triggers.sql` before this fix, just re-run both —
both changes are written to be safely re-run.

`core/router/app_router.dart` gates navigation for real:

- `GoRouterRefreshStream` turns `supabase.auth.onAuthStateChange` into
  something go_router can listen to, so the router re-checks its
  `redirect` callback on every sign-in, sign-out, and token refresh.
- Signed-out users get bounced to `/login` from anywhere else in the app;
  signed-in users get bounced away from `/login`/`/signup` to `/feed`.
- Screens never navigate manually after a successful auth call — they
  just await the Supabase call and let the redirect react to the
  resulting state change. This is also why a session that expires
  mid-use sends the user back to `/login` on its own.

`core/providers/auth_providers.dart` exposes `currentUserProvider` for
any screen that wants to read the signed-in user reactively.

## Photo, location, and storage permissions (Phase 3)

`image_picker` and `geolocator` need the platform permissions already
declared in `android/app/src/main/AndroidManifest.xml` (camera, fine and
coarse location, media images). No Dart-side permission-request package
is needed beyond that — `image_picker` and `geolocator`'s
`requestPermission()` trigger the OS prompt automatically.

## How posting an item works (Phase 3 recap)

1. `PostItemScreen` picks photos with `image_picker` (camera or gallery,
   multiple photos supported) and keeps them as local `File`s until submit.
2. "Add current location" calls `Geolocator.getCurrentPosition()`, then
   `geocoding`'s `placemarkFromCoordinates()` (an instance method — see
   the version note at the top of `pubspec.yaml`) turns the coordinates
   into a readable label like "Galle Road, Negombo".
3. On submit, `ItemsRepository.createItem()` inserts the `items` row
   first (so it has an id), then uploads each photo to the `item-images`
   bucket under `{user_id}/{item_id}/...`, then inserts one `item_images`
   row per photo with its public URL plus that photo's AI classification.
4. `ItemFeedScreen` reads real rows via `itemsFeedProvider`, joined with
   category name and photo URLs in a single query — a plain
   `FutureProvider`, refreshed with pull-to-refresh or invalidated after
   a successful post, not a live Realtime subscription (Supabase's
   `.stream()` API doesn't support the embedded joins this screen needs).

## Generating the on-device model (Phase 4)

`assets/models/` needs two files. **This project already ships them**
— you only need this section if they're missing or you want to
regenerate them. Producing them requires downloading pretrained weights
from Google's servers:

```bash
cd scripts
pip install -r requirements.txt
python export_tflite_model.py
```

`tensorflow`'s wheel is large (~350–400MB) — on a slow or throttled
connection, pip's install can time out partway through. If it does,
retry with a longer timeout (pip resumes from its cache rather than
re-downloading from scratch): `pip install --default-timeout=1000 -r requirements.txt`.

This downloads pretrained MobileNetV2 (ImageNet) weights, wraps them so a
single forward pass returns both a 1280-d embedding and a 1000-way
classification, converts to TFLite with dynamic-range quantization, and
writes `imagenet_labels.txt` directly from Keras's own class index file
— both files go **directly into `assets/models/`**, no separate copy
step. (If you're working from a checkout old enough that the script's
own printout says "copy both into assets/models/" instead, update
`scripts/export_tflite_model.py` first — earlier versions wrote both
files into `scripts/` itself and left the copy as a manual last step,
which was very easy to skip without any error telling you so: the script
finishes cleanly, `assets/models/` silently stays empty, and AI
matching/auto-tagging just never do anything with no indication why.)

**Verify it actually landed in the right place** — this exact "ran fine
but the files ended up in the wrong folder" mistake is the single most
common reason AI matching doesn't seem to work:
```bash
dir ..\assets\models
```
```bash
# macOS/Linux
ls ../assets/models
```
You should see `mobilenet_v2_embedder.tflite` (a few MB) and
`imagenet_labels.txt` alongside the folder's own `README.md`. If those
two are missing, the app has nothing to run on-device classification
with, silently — see the next paragraph.

**Output order is detected automatically.** The TFLite converter doesn't
guarantee the two outputs stay in the order the script declares them
(the model shipped here has the classification as output 0 and the
embedding as output 1). `TfliteClassifier.load()` reads each output's
shape (1280 wide = embedding) and prints the mapping to the console, so
there's nothing to check or swap by hand. An earlier version hardcoded the
order, which made every classification fail silently — see the Phase 5
notes and `supabase/11_realtime_and_matching_fixes.sql`.

Until you run this script (and it's in `assets/models/`), the app
degrades gracefully rather than crashing: `PostItemScreen` catches the
missing-model error and posts without AI tagging — but that also means
**no image embedding ever gets stored, so posted items can never be AI
matched against anything**, silently, with no error surfaced anywhere in
the app. If matches never appear no matter what you post, this — not a
matching-logic bug — is the first thing to rule out. A quick way to
confirm either way, run in the Supabase SQL Editor:
```sql
select id, item_id, embedding is not null as has_embedding, created_at
from item_images
order by created_at desc
limit 10;
```
If `has_embedding` is `false` for items posted *after* you ran the
export script and rebuilt the app, the model still isn't being found at
runtime — double check the two files are really in `assets/models/`
(not `assets/models/models/` or similar) and do a full `flutter run`
again (not just hot reload — asset bundle changes need a full restart).

## How the AI matching actually works

1. On-device: the exported MobileNetV2 model runs on each photo,
   producing a predicted ImageNet label and a 1280-d embedding vector —
   this is the CNN half of matching, and it runs **entirely on the
   phone**, using the `.tflite` file bundled into the app itself. See
   "Does matching need my laptop connected?" below for what that means
   in practice.
2. A heuristic in `core/ml/category_mapper.dart` maps that fine-grained
   label (e.g. "Labrador_retriever") onto one of Findora's categories
   (e.g. "Pets") to pre-fill the post form. The label also pre-fills the
   **title** field (title-cased — `PostItemScreen._titleCaseFromLabel`),
   as long as the person hasn't already typed one themselves. This
   category is just a starting suggestion for the post form now, not a
   gate on matching — see point 5.
3. Only the embedding, label, and photo get uploaded — matching needs
   everyone else's items too, so it can't happen purely on-device.
4. Separately, if `AI_SERVICE_URL` is configured (see `ai_service/`),
   the title + description are sent there for a **text/NLP** embedding
   (Sentence-Transformers, with NLTK doing tokenization/stopword/
   lemmatization cleanup first — the "N" and "S" of the documented
   TensorFlow/OpenCV/Sentence-Transformers/NLTK stack) — best-effort,
   skipped entirely if unset, slow, or unreachable.
5. A trigger (`record_matches_for_image`, which now just calls
   `match_image()` — see `supabase/11_realtime_and_matching_fixes.sql`)
   fires the moment a photo with an embedding is inserted **or an
   existing photo gets its embedding filled in later** (the Matches tab's
   scan), comparing it against every opposite-type,
   open item via pgvector's cosine distance operator (`<=>`) to get an
   image-similarity candidate list (photos scoring at least
   `matching_threshold()`, currently 0.60) — **category is not part of this
   filter** (see "Why category doesn't gate matching" below) — then, for
   each candidate, blends in text similarity (if both sides have a text
   embedding), GPS proximity (if both sides have a location), and event
   time proximity (if both sides set one) into one **combined score**,
   written to `matches` (see
   `supabase/10_open_matching_and_time.sql`'s `combined_match_score()`).
6. Separately from all of that — and needing no photo at all —
   **title/description matching** runs the moment an item is posted, and
   again whenever its title or description is edited (triggers
   `items_record_text_matches_insert`/`_update`, `match_item_by_text()`,
   `supabase/12_text_matching.sql`). It compares text the same way point 4
   would, if that text embedding is available for both items; if not (no
   `ai_service/` configured, or it didn't respond before posting), it
   falls back to `pg_trgm`'s word/substring similarity on the raw title +
   description — always available, no setup, but literal (it helps when
   the words genuinely overlap; "wallet" vs "purse" won't score well
   without the semantic embedding). Either way the result lands in the
   same `matches` row a photo comparison would use — see
   `upsert_match_score()`, which lets whichever signal (photo or text)
   finds a pair first, and whichever finds it second enrich the same row
   rather than duplicate it or get silently dropped.
7. `MatchesScreen` reads those via `my_matches()`, which resolves each
   row into "my item" vs "the matched item" from the caller's
   perspective — either owner can confirm or dismiss it, sees the score
   breakdown ("📷 92% · 📝 78% · 📍 1.2 km · 🕐 6h apart"), and can filter
   the list down to matches that have a strong text/location/time signal
   via the chips at the top of the screen (client-side filtering over
   the already-fetched list — the dataset is just one person's matches,
   not worth a server round-trip per filter tap).

### Why category doesn't gate matching

Originally, `match_items()` only compared items within the same
category, on the theory that a lost wallet shouldn't be compared against
a found bicycle. In practice this caused real matches to be missed: the
on-device model's category guess is just a heuristic (an ImageNet label
mapped through `category_mapper.dart`'s rules), and two photos of the
literal same object can easily land in different guessed categories,
especially if one person's photo confuses the classifier and the other
person's doesn't — at which point those two items are silently never
compared *at all*, regardless of how visually identical the photos
actually are. Category is still collected and shown (useful for
browsing/filtering the main feed), it just no longer excludes a
candidate from being scored in `match_items()`.

### Does matching need my laptop connected?

No — once the app is running on your phone, the whole matching pipeline
is independent of the laptop:

- **On-device classification/embedding** (`tflite_classifier.dart`) runs
  using the `.tflite` file bundled into the installed app — this is
  local computation on the phone's own CPU, identical whether the phone
  is tethered to a laptop or sitting on the other side of the room.
- **Everything else** (storing the embedding, the `matches` trigger,
  fetching results) talks to **Supabase**, a cloud service — this needs
  *internet on the phone* (Wi-Fi or mobile data), which has nothing to
  do with the laptop being nearby.
- `flutter run`'s USB/wireless connection is a **development
  convenience only** — hot reload and streaming console logs back to
  your terminal. It's not something the running app depends on to
  function. Unplugging the cable is fine for using the app; the caveat
  is that on some devices, physically disconnecting *while* a debug
  session is actively attached can kill that debug session (and
  sometimes the app process along with it, depending on the device's USB
  debugging behavior) — annoying for testing, but a debug-tooling
  quirk, not evidence the app secretly needs the laptop. If you want to
  be completely sure there's no dependency at all, `flutter build apk
  --release` and install that APK normally — a release build has zero
  runtime connection to the development machine, ever.

## The matching engine, end to end (Phase 5, extended)

- **`record_matches_for_image`**: an `after insert` trigger on
  `item_images` for rows with a non-null `embedding`. Runs
  `match_items()` for the image-similarity **candidate list** (this is
  the fast ANN "recall" step — see the multimodal note below), computes
  text similarity + GPS proximity + time proximity for each candidate,
  and inserts the blended result into `matches`, `on conflict do
  nothing` so re-processing never duplicates. Runs inside the same
  transaction as the photo insert.
- **`match_items()` excludes same-user matches** — posting both a "lost"
  and "found" report yourself won't match against yourself. It still
  *accepts* an optional category filter parameter (unused by the
  trigger, which now passes `null` — see "Why category doesn't gate
  matching" above), kept in case a future caller wants it.
- **Multimodal scoring** (`supabase/10_open_matching_and_time.sql`):
  `match_items()` stays a pure image-similarity ANN search on purpose —
  it's the one step that can actually use `item_images.embedding`'s
  HNSW index, so it's what keeps matching fast as the table grows.
  Everything past that (text similarity via `items.text_embedding`, GPS
  proximity via `gps_proximity_score()`, time proximity via
  `time_proximity_score()`) only ever runs over the already-small
  candidate list `match_items()` returns, then `combined_match_score()`
  blends all four with weights 0.4 image / 0.25 text / 0.2 GPS / 0.15
  time, re-normalized over whichever signals are actually present for
  that pair (not every item has a location, a text embedding, or an
  event time set). `rescore_matches_for_item()` exists because the text
  embedding often arrives *after* the item row is first inserted (an
  async HTTP call to `ai_service/`, not guaranteed to finish before the
  first photo upload) — call it once that embedding lands to backfill
  `text_similarity`/`similarity_score` on that item's existing matches.
- **`my_matches()`**: resolves `item_a_id`/`item_b_id` into "my item" vs
  "the matched item" from `auth.uid()`'s perspective in one query, now
  including the `image_similarity`/`text_similarity`/`distance_meters`/
  `time_proximity` breakdown alongside the blended `similarity_score`.
- Item owners can `update` their own matches (confirm/dismiss), not just
  read them.
- **Title/description matching** (`supabase/12_text_matching.sql`) is a
  second, independent way a pair gets into `matches`, needing no photo:
  - `items_record_text_matches_insert`/`_update` — `after insert`, and
    `after update of title, description` (guarded by a `when` clause so it
    only actually re-runs when one of those values changed, since the
    app's edit form always sends both columns) — call
    `match_item_by_text()`.
  - `match_items_by_text()` is the text-matching analogue of
    `match_items()`: same opposite-type/different-owner/open/not-deleted
    filters, ordered by `text_similarity_between()` instead of vector
    distance, cut off by `text_matching_threshold()` (0.30) instead of
    `matching_threshold()`.
  - `text_similarity_between(a_id, b_id)` picks semantic similarity via
    `items.text_embedding` when both sides have one, else `pg_trgm`'s
    `similarity()` on the lowercased title (weighted 0.7) and description
    (0.3, skipped when either side has none) — see the function's own
    comment for why title outweighs description.
  - `upsert_match_score(item_a, item_b, image_similarity, text_similarity)`
    is what both `match_image()` and `match_item_by_text()` actually write
    through: it looks for an existing row for the pair **in either
    column order** (the unique constraint is on the ordered pair, but two
    items only ever describe one relationship) and updates it — keeping
    whichever of image/text similarity it already had for any signal the
    current call doesn't supply — instead of inserting a second row or
    silently discarding the new signal. GPS/time proximity are recomputed
    fresh from the two items' current data on every call, cheap enough not
    to bother caching.
  - `rematch_all_text()` — the text-matching equivalent of
    `rematch_all_images()`, for items posted before this migration.

## Google Maps setup (Phase 6)

Covered in Part A5.1. The map view builds and opens without a key, it
just renders a blank/grey map until one is added.

## Search, filters, and the map (Phase 6)

- Search and category filters are real server-side query parameters
  (`.eq('category_id', ...)`, `.or('title.ilike...,description.ilike...')`),
  not client-side filtering — `itemsFeedProvider` is a `.family` provider
  keyed on `ItemsFilter(categoryId, searchQuery)`. The search box
  debounces 400ms before refetching.
- The map toggle swaps the list for `ItemsMapView`, centering on the
  device's location and plotting open items within 5km via `nearby_items()`
  — red pins for lost, green for found.
- `nearby_items()` returns plain `latitude`/`longitude` doubles (via
  `st_y`/`st_x`) rather than a raw PostGIS geography value, which doesn't
  serialize predictably over PostgREST.
- Not yet built: the map doesn't share the list's filters, and there's no
  date filter beyond the map's fixed radius.

## Firebase setup for push notifications (Phase 7)

Push notifications need a real Firebase project:

1. In the Firebase Console, add an Android app with package name
   `com.example.findora`, download `google-services.json`, and place it
   at `android/app/google-services.json`.
2. Add the Google Services Gradle plugin — in `android/build.gradle.kts`
   (project-level, inside the `plugins { }` block if one exists, or add
   one):
   ```kotlin
   plugins {
       id("com.google.gms.google-services") version "4.4.2" apply false
   }
   ```
   and in `android/app/build.gradle.kts` (module-level, inside the
   existing `plugins { }` block at the top):
   ```kotlin
   plugins {
       id("com.google.gms.google-services")
   }
   ```

The `POST_NOTIFICATIONS` permission is already in the manifest. With the
above in place, `Firebase.initializeApp()` in `main.dart` (called with no
explicit options, which works fine for an Android-only app without a
generated `firebase_options.dart`) will succeed, and
`initializePushNotifications()` requests permission, registers this
device's FCM token to the signed-in user's `profiles` row, and shows
foreground messages as local notifications. Skip this and the app still
runs fine — it's wrapped in a try/catch specifically so a missing
Firebase project degrades to "no push notifications" rather than a crash.

**What's still missing, honestly**: nothing in this codebase actually
*sends* a push notification when a match or message happens. That needs
a server-side piece — a Supabase Edge Function (calling the FCM HTTP v1
API) triggered by a Database Webhook on inserts into `matches`/`messages`
— which needs a Firebase service account key, a real secret that has to
be set up against your own project.

## In-app chat (Phase 7)

- `messages` is scoped by `match_id`, not `item_id` — a conversation is
  between the two people on either side of a match, not about one item
  in isolation.
- Chat is gated behind a confirmed match — tapping "This is it!" on a
  match is what makes a "Message" button (and a `ChatListScreen` entry)
  appear, via `my_conversations()`.
- Messages use real Supabase Realtime (`messagesStreamProvider`), unlike
  the refetch-on-demand pattern used for the items feed and matches list,
  since a plain message list doesn't need the joins that block
  `.stream()` elsewhere in this app.
- Marking messages read only touches the current user's own incoming
  messages, enforced by RLS, not just app logic.

## Claims, trust, and moderation (Phase 8)

**The claim → return → rating lifecycle**, all inside `ChatScreen`:

1. Claims are always filed against whichever item in the match has type
   `'found'` — you claim something someone *found*, to prove you're the
   one who *lost* it.
2. The claimant writes a verification answer; the finder can Approve or
   Reject it.
3. Approving runs a trigger (`handle_claim_approved`) that moves the item
   to `'claimed'` automatically.
4. Once claimed, the finder gets a "Mark as returned" button, moving the
   item to `'resolved'`.
5. Resolving surfaces a star-rating prompt. Ratings write to a `ratings`
   table, and a trigger (`handle_new_rating`) recomputes
   `profiles.rating`/`rating_count` from it.

**Item detail screen**: tapping a feed/map card opens `ItemDetailScreen`
— full description, every photo, and a "Report this item" action.

**Basic moderation**: `profiles.is_admin` gates a "Flagged reports" entry
in `ProfileScreen`, opening `AdminReportsScreen` (dismiss / remove item),
backed by RLS so a non-admin who found the route would just see nothing.
There's no in-app flow to grant admin — run this once in the Supabase SQL
editor for your first moderator:
```sql
update public.profiles set is_admin = true where id = '<user-uuid>';
```

## Event time and manual location adjustment (posting an item)

Two additions to `PostItemScreen`, both optional:

- **When it was lost/found** — a date+time picker (`_pickEventTime`),
  stored in `items.event_time`, separate from `created_at` (when the
  *report* was posted). Shown on the item detail screen alongside
  "Reported [date]" when set.
- **Adjust pin on map** — `LocationPickerScreen`
  (`core/location/location_picker_screen.dart`) fine-tunes whatever
  "Add current location" auto-detected, using a fixed center pin over a
  draggable map (not a draggable `Marker` — see that file's doc for why)
  plus a reverse-geocoded label on confirm.

## Password strength (signup)

`core/widgets/password_strength.dart` defines five rules (8+ characters,
upper/lowercase, a number, a special character) as data
(`List<PasswordRule>`) rather than inlined validator logic, so the same
rules back both the `TextFormField` validator and a live
`PasswordStrengthIndicator` (a progress bar + a checklist that lights up
each rule as it's satisfied) shown under the field as the person types.

## Exit confirmation (Browse tab)

Android's back button on a bottom-nav tab is handled by `TabBackGuard`
(`lib/core/widgets/tab_back_guard.dart`), a `PopScope` that wraps each
tab's root screen inside its route in `core/router/app_router.dart`:

- On **Matches / Chats / Profile**: back goes to Browse.
- On **Browse** with the map open: back returns to the list.
- On **Browse**'s list (the home page): back shows the "Leave Findora?"
  dialog (`showConfirmDialog`) and only calls `SystemNavigator.pop()` if
  you confirm.

**Why it lives in each route and not in `MainShell`.** The first version
put one `PopScope` in `MainShell` and the dialog never appeared: go_router
sends a back press to the *active tab's own nested navigator*, which has
just one route and no guard of its own, so it reported "nothing to pop"
and the OS closed the app without `MainShell` being consulted. The guard
has to be inside the route of the navigator that actually receives the
press. `MainShell` keeps a fallback `PopScope` that runs the same logic.

Also in `MainShell`: the bottom nav's `onDestinationSelected` resets
`feedShowsMapProvider` to `false` whenever Browse (index 0) is selected —
so tapping Browse always lands you on the list, even if you'd left the
map view open. This has to happen from `MainShell` rather than from
`ItemFeedScreen` resetting its own state, because go_router's
`StatefulShellRoute` keeps `ItemFeedScreen` mounted (just offscreen, in an
`IndexedStack`) while another tab is showing — nothing re-initializes it
on a tab switch, so its map/list choice had to move out of local `State`
and into that provider before anything outside the screen could reach it.

## Soft delete: items are hidden, never erased

Deleting a post — by its own owner (item detail's menu, My Items) or by
an admin removing a flagged item (Flagged reports) — no longer runs an
actual `delete` against the database. `08_soft_delete.sql` adds
`items.deleted_at` (nullable; null means active) and both delete paths
now just set it:

```dart
await supabase.from('items').update({'deleted_at': DateTime.now().toIso8601String()}).eq('id', itemId);
```

That same migration also **drops** the `items` table's `delete` RLS
policies entirely (both the owner one and the admin one) — so this isn't
just an app-code convention; a real `delete` against `items` fails at the
database level even for someone calling the Supabase client directly with
a valid session, bypassing the app. Every read this repository does
(`fetchOpenItems`, `fetchMyItems`, `fetchItemById`) filters
`deleted_at is null`, so a soft-deleted item disappears from the app
exactly as if it had been hard-deleted — the difference only shows up if
you go looking for it directly in the database (which is the point: an
accidental delete, or a moderation call worth revisiting, is one
`update ... set deleted_at = null` away from being undone).

Matching follows the same idea but with one deliberate exception:
`match_items()` and `my_matches()` (Phase 5) both exclude deleted items,
so a removed item stops being surfaced as a *candidate* match going
forward and any still-*pending* match against it disappears — but
`my_conversations()` (Phase 7, confirmed-match chat) is left unfiltered
on purpose, so an existing conversation about an item stays reachable
even after that item is later deleted. Chat history is worth keeping;
dangling "confirm or dismiss?" prompts about a removed item aren't.

Admin's `removeItem()` also updates any other still-open reports against
that item to `dismissed` — with a real delete, `reports.item_id`'s
cascade used to make them disappear from the moderation queue for free;
a soft delete leaves `reports` rows untouched unless this does it
explicitly, so without it they'd sit in the open queue forever pointing
at an item that's already been taken down.

## Account deletion

Profile → "Delete account" calls the `request_account_deletion()` RPC
(`supabase/09_account_deletion.sql`), which — for the same reason item
deletion is a soft delete (see above) — doesn't run a real `delete from
auth.users`: `profiles.id references auth.users(id) on delete cascade`,
so that would cascade-delete their profile and leave every *other*
user's matches/chats/reports referencing that id pointing at nothing.

Instead it, all in one `security definer` function:
1. Soft-deletes every item the account posted (same `items.deleted_at`
   flag as a regular per-item delete).
2. Clears `profiles.full_name`/`username`/`avatar_url`/`phone`/
   `fcm_token` and sets a new `profiles.deleted_at` — the row survives,
   but with nothing personal left on it. Existing chats/matches
   referencing this user now just show "Findora user" wherever a name
   would have appeared, via the `coalesce(full_name, username, 'Findora
   user')` fallback already used in `my_contact_threads()` and similar.
3. Sets `auth.users.banned_until` to 100 years out — the same column the
   Admin API's "ban user" endpoint sets, reachable directly here because
   `security definer` runs as the function's *owner* (the `postgres`
   role, in a normal SQL-Editor-run migration), which has full access to
   the `auth` schema — no service-role key or Edge Function needed, only
   `security definer` plus deriving the target strictly from `auth.uid()`
   (never a parameter, so there's no "ban someone else" version of this
   to accidentally expose).

The Flutter side calls `supabase.auth.signOut()` immediately after the
RPC returns — banning blocks *future* sign-ins/token refreshes, but
doesn't retroactively invalidate a JWT that's already been issued for
the current session, so the explicit sign-out is what actually ends
*this* session right away rather than leaving it valid until it happens
to expire.

## "NEW" badge

`core/widgets/new_badge.dart` defines `isRecentlyPosted(DateTime)` (true
for `newPostWindow`, currently 3 days, after `created_at`) and a small
`NewBadge` pill widget, shown on feed cards and the item detail screen's
badge row whenever that check passes. There's no timer or scheduled job
behind this — every build just re-checks the item's age against
`newPostWindow`, so the badge stops appearing on its own the next time
that part of the UI happens to rebuild (pull-to-refresh, reopening the
item, reopening the app) after the window has elapsed. Change how long
"new" lasts by editing `newPostWindow` in that one file.

## Email confirmation flow

Three pieces, all independently optional (skip any of them and Supabase's
own default confirmation email/redirect still works, just without this
project's mobile-handoff/auto-close/welcome-email additions):

1. **Branded confirmation email** — paste
   `supabase/email_templates/confirm_signup.html` into Supabase Dashboard
   → Authentication → Email Templates → "Confirm signup" (Message body),
   and set its Subject to `Confirm your email for Findora`.
2. **`web/auth-callback.html`** — a self-contained static page (no
   Flutter build needed) that `{{ .ConfirmationURL }}` redirects the
   browser to after confirming. On mobile it hands off into the app via
   the same `io.supabase.findora://` custom scheme already used for
   Google sign-in (supabase_flutter's built-in deep-link handling picks
   up the auth data automatically — no extra Dart code needed); on
   desktop it shows success and closes the tab (best-effort — see the
   file's comment on why `window.close()` can't be guaranteed).

   **Hosting it — don't use Supabase Storage for this.** Storage is
   built for arbitrary file/CDN delivery, not guaranteed HTML rendering,
   and in practice it can serve an uploaded `.html` file with a
   content-type that makes browsers display the raw source code as text
   instead of rendering it as a page — confusing since the upload itself
   "succeeds" with no error. Use a real static host instead — free,
   and a couple of minutes each:

   **Cloudflare Pages** (no git/account-linking needed, just a file):
   1. https://pages.cloudflare.com → sign in (or create a free account)
      → **Create a project** → **Upload assets**.
   2. Drag in `web/auth-callback.html`. Rename it to `index.html` during
      upload (drag-and-drop lets you rename before confirming) so it
      serves at your project's root URL rather than a
      `/auth-callback.html` sub-path — simpler to reference later,
      though either works.
   3. Deploy — you get a URL like `https://findora-auth.pages.dev`.
   4. Use that URL as `AUTH_CALLBACK_URL` (see step 4 below).

   Netlify Drop (https://app.netlify.com/drop) and GitHub Pages work
   the same way if you'd rather use one of those.

   **Prefer to keep this inside Supabase anyway?** It's possible, but
   only via the Storage REST API with an explicit content-type — the
   Dashboard's drag-and-drop uploader doesn't expose that control, which
   is exactly what goes wrong:
   ```powershell
   # PowerShell — replace YOUR_PROJECT_REF and YOUR_SERVICE_ROLE_KEY
   # (Project Settings → API Keys → service_role). Run
   # supabase/07_email_confirmation.sql first if you haven't — it
   # creates the public `site` bucket this targets.
   $headers = @{
     Authorization = "Bearer YOUR_SERVICE_ROLE_KEY"
     "Content-Type" = "text/html"
   }
   Invoke-WebRequest `
     -Uri "https://YOUR_PROJECT_REF.supabase.co/storage/v1/object/site/auth-callback.html?upsert=true" `
     -Method Post -Headers $headers -InFile "web\auth-callback.html"
   ```
   Whichever host you use, open the resulting URL in a browser before
   moving on — you should see a rendered "Confirming your email…" page,
   not visible HTML markup. If you see markup (like the screenshot), the
   content-type is still wrong.

   Once you have a working URL:
   1. Dashboard → **Authentication** → **URL Configuration** →
      **Redirect URLs** → add it (Supabase rejects an `emailRedirectTo`
      that isn't on this allow-list).
   2. Paste the same URL as `AUTH_CALLBACK_URL` in `.env`.
3. **Follow-up "you're confirmed!" email** — `07_email_confirmation.sql`
   adds a trigger that fires the moment `auth.users.email_confirmed_at`
   is first set, calling the `send-welcome-email` Edge Function (Resend
   API) — see `supabase/functions/send-welcome-email/README.md` for
   deployment. That SQL file has two placeholders
   (`YOUR_PROJECT_REF`, `YOUR_SERVICE_ROLE_KEY`) to fill in before
   running it.

## A few things to double-check before shipping

- **pgvector inserts**: `ItemsRepository.createItem()` inserts a Dart
  `List<double>` straight into the `embedding` column, which works
  because a JSON array's text form matches pgvector's own input format —
  verify this once you have a real device, model, and Supabase project.
- **Ratings aren't tightly restricted**: the RLS policy lets any
  signed-in user insert a rating as themselves, not strictly only for an
  item they completed a return on — a reasonable trust boundary for a
  first version, not a hard guarantee.
- **TFLite plugin**: check pub.dev/fluttergems.dev periodically for
  whichever `tflite_flutter` release is currently best-maintained.

## Project structure

```
lib/
  core/
    theme/         AppColors + AppTheme (Material 3, light & dark),
                    ThemeModeController (persisted light/dark/system)
    router/         go_router config with a StatefulShellRoute bottom nav
    constants/      table names, bucket names, RPC function names
    providers/      currentUserProvider, authStateChangesProvider
    supabase/       shared Supabase client accessor
    ml/             TfliteClassifier, its provider, category_mapper,
                    TextEmbeddingService (optional ai_service/ client)
    location/       getCurrentPositionOrNull(), LocationPickerScreen
    notifications/  FCM setup + push token registration
    widgets/        MainShell (bottom nav + FAB + exit confirmation),
                    showConfirmDialog, PasswordStrengthIndicator
  features/
    splash/         shows the pin glyph on brand teal
    auth/           login, signup (+ password strength), forgot-password
    home/           browse tab: hero header, search/filters, items_map_view.dart
    items/
      data/          CategoryModel, ItemModel, NearbyItemModel, ClaimModel,
                      ItemsRepository, ClaimsRepository, providers
      post_item_screen.dart   photo picking, location (+ manual adjust),
                               event time, AI tagging, upload
      item_detail_screen.dart  full detail, delete (owner), contact (others)
    matches/
      data/          MatchModel, MatchesRepository, providers
      matches_screen.dart   real matches, confirm/dismiss, score breakdown
    chat/
      data/          ConversationModel, MessageModel, MessagesRepository
      chat_list_screen.dart   tabbed: confirmed matches + direct messages
      chat_screen.dart        live messages + claim/return/rate lifecycle
    contact/
      data/          ContactThreadModel, ContactMessageModel, ContactRepository
      contact_chat_screen.dart  plain messaging, no claim lifecycle
    profile/
      data/          ProfileModel, AdminRepository, ReportModel, providers
      profile_screen.dart      real rating, appearance picker, admin entry
      my_items_screen.dart     swipe/tap to delete
      admin_reports_screen.dart  moderation: dismiss / remove item
supabase/
  01_extensions_and_tables.sql
  02_functions_and_triggers.sql
  03_rls_policies.sql
  04_storage_setup.sql
  05_multimodal_matching.sql   event_time, text embeddings, image+text+GPS scoring
  06_contact_messaging.sql     direct "Contact poster" threads
  07_email_confirmation.sql    welcome-email trigger + public site bucket
  email_templates/             confirm_signup.html, welcome_email.html
  functions/send-welcome-email/  Deno Edge Function (Resend API)
ai_service/            optional FastAPI microservice — see its README.md
  requirements.txt            core: text embeddings (Sentence-Transformers + NLTK)
  requirements-image.txt      optional: image embeddings (TensorFlow/Keras + OpenCV)
  Dockerfile                  full build (both tiers)
  Dockerfile.text-only        smaller build, text tier only
scripts/
  export_tflite_model.py   generates the on-device model + labels
  generate_icon_pngs.py    regenerates every launcher/PWA icon PNG
  requirements.txt
assets/
  models/           drop the exported .tflite + labels file here
  images/           app_icon.svg/.png, logo_lockup.svg, pin_glyph_white.svg
web/
  auth-callback.html   email confirmation landing page (mobile handoff /
                       desktop auto-close) — see "Email confirmation flow"
```
