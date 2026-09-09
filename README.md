# Findora — Flutter + Supabase starter

Findora is a lost & found app: report a lost or found item, and on-device
AI compares its photo against everyone else's to suggest a match. This is
Phases 1–4 of the build: theme, navigation, auth, real item posting with
photo upload, and on-device recognition. Screens are visually complete but
wired with `// TODO(phase-N)` comments marking where anything still left
plugs in.

## 1. Generate the Flutter project shell

This code was written without a live Flutter SDK attached, so it doesn't
include the auto-generated `android/`, `ios/`, `web/`, etc. platform folders.
Generate those yourself, then drop these files in on top:

```bash
flutter create findora
cd findora
# copy this pubspec.yaml over the generated one (merge in your own
# name/description if you changed them), then copy the lib/, supabase/,
# scripts/, assets/, and .env.example into place
flutter pub get
```

## 2. Create the Supabase project

1. Create a project at https://supabase.com/dashboard.
2. Open the SQL editor and run the four files in `supabase/` **in order**:
   `01_extensions_and_tables.sql` → `02_functions_and_triggers.sql` →
   `03_rls_policies.sql` → `04_storage_setup.sql`.
3. Go to Project Settings → API Keys and copy your project URL and
   **publishable key**. Supabase is retiring the old `anon`/`service_role`
   naming in favor of `publishable`/`secret` keys — grab the publishable
   one (`sb_publishable_...`) for use in the app; never put a secret key
   in client code.

## 3. Configure environment variables

```bash
cp .env.example .env
```

Then fill in your real `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`.
`.env` is already listed under `assets` in `pubspec.yaml` so it gets bundled
at build time — add it to `.gitignore` so it's never committed.

## 4. Run it

```bash
flutter run
```

You should land on the splash screen, then get redirected to the login
screen (no session yet), and the theme/navigation should already feel
complete even though the on-device model isn't in place yet (see Phase 4
below) — posting still works fine without it, just without AI matching.

## App icon and branding

`assets/images/` has the full Findora mark: a white location pin with an
amber "found" dot, in the brand teal (`#0F6E56`) and amber (`#E8A33D`)
used throughout `AppColors`.

- `app_icon.svg` / `app_icon.png` — the full square mark (SVG source and
  a ready-to-use 1024×1024 PNG).
- `app_icon_foreground.png` — pin + dot only, transparent background,
  sized with the extra padding Android's adaptive icon mask needs.
- `logo_lockup.svg` — icon + wordmark, used on the login screen (light
  background).
- `pin_glyph_white.svg` — just the pin + dot, no square, used on the
  splash screen (teal background, where the square would blend in).
- `scripts/generate_icon_pngs.py` — regenerates both PNGs (redraws the
  mark directly with Pillow rather than rasterizing the SVG, since this
  sandbox has no SVG renderer available) if you ever tweak the design.

The PNGs are already in place, so generating launcher icons is one command:

```bash
dart run flutter_launcher_icons
```

The config in `pubspec.yaml` already points at both files and sets up a
proper Android adaptive icon (teal background + pin foreground).

## Google sign-in setup (Phase 2)

The "Continue with Google" button calls `signInWithOAuth`, but the redirect
back into the app needs two things configured outside of Dart code:

1. **Supabase Dashboard** → Authentication → Providers → enable Google, and
   add your OAuth client ID/secret from Google Cloud Console.
2. **Supabase Dashboard** → Authentication → URL Configuration → add
   `io.supabase.findora://login-callback` as a redirect URL (this exact
   string is what `login_screen.dart` passes as `redirectTo`).
3. **Android**: add an intent filter for that scheme inside the `<activity>`
   block of `android/app/src/main/AndroidManifest.xml`:

   ```xml
   <intent-filter android:autoVerify="true">
       <action android:name="android.intent.action.VIEW" />
       <category android:name="android.intent.category.DEFAULT" />
       <category android:name="android.intent.category.BROWSABLE" />
       <data android:scheme="io.supabase.findora" />
   </intent-filter>
   ```

Skip all three and the email/password flow still works fine — the Google
button will just fail gracefully with an error message.

## Auth state and routing (Phase 2)

`core/router/app_router.dart` now gates navigation for real:

- `GoRouterRefreshStream` turns `supabase.auth.onAuthStateChange` into
  something go_router can listen to, so the router re-checks its
  `redirect` callback on every sign-in, sign-out, and token refresh.
- Signed-out users get bounced to `/login` from anywhere else in the app;
  signed-in users get bounced away from `/login`/`/signup` to `/feed`.
- Screens never navigate manually after a successful auth call — they just
  await the Supabase call and let the redirect react to the resulting
  state change. This is also why a session that expires mid-use (e.g. the
  refresh token gets revoked) sends the user back to `/login` on its own.

`core/providers/auth_providers.dart` exposes `currentUserProvider` for any
screen that wants to read the signed-in user reactively — `ProfileScreen`
already uses it for the display name.

## Photo, location, and storage permissions (Phase 3)

`image_picker` and `geolocator` need platform permissions declared before
the OS will grant them at runtime. Add these once `android/` exists:

**`android/app/src/main/AndroidManifest.xml`** (inside `<manifest>`, above
`<application>`):

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<!-- Android 13+ (API 33+) uses granular media permissions instead of
     READ_EXTERNAL_STORAGE for picking from the gallery -->
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
```

No Dart-side permission-request package is needed for the camera/gallery
picker itself — `image_picker` triggers the OS prompt automatically the
first time it's used. `geolocator`'s `requestPermission()` call in
`post_item_screen.dart` does the same for location.

## How posting an item works (Phase 3 recap)

1. `PostItemScreen` picks photos with `image_picker` (camera or gallery,
   multiple photos supported) and keeps them as local `File`s until submit.
2. "Add current location" calls `Geolocator.getCurrentPosition()`, then
   `geocoding`'s `placemarkFromCoordinates()` turns the coordinates into a
   readable label like "Galle Road, Negombo" — falling back gracefully if
   reverse geocoding fails.
3. On submit, `ItemsRepository.createItem()` inserts the `items` row first
   (so it has an id), then uploads each photo to the `item-images` bucket
   under `{user_id}/{item_id}/...`, then inserts one `item_images` row per
   photo with its public URL — plus that photo's AI classification, if
   the model was available (see Phase 4).
4. `ItemFeedScreen` reads real rows via `itemsFeedProvider`, joined with
   category name and photo URLs in a single query. It's a plain
   `FutureProvider` refreshed with pull-to-refresh or invalidated after a
   successful post — not a live Realtime subscription, since Supabase's
   `.stream()` API doesn't support the embedded joins this screen needs.
   Phase 6's messaging work is a more natural place to bring in full
   Realtime plumbing.

## Generating the on-device model (Phase 4)

`assets/models/` needs two files this repo can't ship — `tensorflow` isn't
something this sandbox can download, since it requires network access to
Google's servers. Generate them yourself:

```bash
cd scripts
pip install -r requirements.txt
python export_tflite_model.py
```

This downloads pretrained MobileNetV2 (ImageNet) weights, wraps them so a
single forward pass returns both a 1280-d embedding and a 1000-way
classification, converts to TFLite with dynamic-range quantization, and
writes `imagenet_labels.txt` directly from Keras's own class index file
(not hand-typed, so it can't drift out of sync with the model). Copy both
output files into `assets/models/`.

**Before trusting it on-device**, check the script's printed output tensor
order against the indices `tflite_classifier.dart`'s `classify()` method
assumes (0 = embedding, 1 = classification). The converter should preserve
Keras's output order, but this hasn't been verified against a live TFLite
runtime in this sandbox — swap the indices in `classify()` if predictions
come back scrambled.

Until you run this script, the app degrades gracefully: `PostItemScreen`
catches the missing-model error and posts without AI matching rather than
crashing (see `_classifyAllPhotos()`).

## How the AI matching actually works

1. On-device: the exported MobileNetV2 model runs on each photo, producing
   a predicted ImageNet label and a 1280-d embedding vector, entirely on
   the phone.
2. A heuristic in `core/ml/category_mapper.dart` maps that fine-grained
   label (e.g. "Labrador_retriever") onto one of Findora's categories
   (e.g. "Pets") to pre-fill the post form — this is keyword matching, not
   a trained classifier, so expect to refine the keyword lists once you
   see real predictions on real photos.
3. Only the embedding, label, and photo get uploaded — never used for
   comparison on-device, since matching needs everyone else's items too.
4. A trigger (`record_matches_for_image`, see Phase 5 below) fires the
   moment a photo with an embedding is inserted, comparing it against all
   *opposite-type*, *open*, same-category items using pgvector's cosine
   distance operator (`<=>`), and writes any candidates above the
   similarity threshold straight into `matches`.
5. `MatchesScreen` reads those via `my_matches()`, which resolves each row
   into "my item" vs "the matched item" from the caller's perspective —
   both item owners can see the match per the RLS policy, and either can
   confirm or dismiss it.

## The matching engine, end to end (Phase 5)

The pieces built in earlier phases (the `embedding` column, `match_items()`)
were only half the story — nothing was actually calling that function or
writing to `matches` yet. Phase 5 closes that loop, entirely at the
database layer:

- **`record_matches_for_image`**: an `after insert` trigger on
  `item_images` that runs whenever a row has a non-null `embedding`. It
  calls `match_items()` for that photo and inserts any results into
  `matches`, `on conflict do nothing` so re-processing never creates
  duplicates. This runs as part of the same transaction as the photo
  insert, so by the time `ItemsRepository.createItem()` returns, any
  matches already exist — no polling or delay needed.
- **`match_items()` got one correctness fix**: it now also excludes items
  posted by the *same user* as the source item, so someone testing with
  both a "lost" and "found" report of their own doesn't match themselves.
- **`my_matches()`**: a read function that resolves the ambiguous
  `item_a_id`/`item_b_id` columns into "my item" vs "the matched item"
  from `auth.uid()`'s perspective, plus the matched item's title, type,
  and first photo — one round trip instead of the client doing that join
  itself.
- **A new RLS policy**: item owners can now `update` their own matches
  (only `select` existed before), which is what lets "Not a match" /
  "This is it!" in the app actually persist.

If you already ran the Phase 1 SQL files against a live project, re-run
`02_functions_and_triggers.sql` and `03_rls_policies.sql` — both use
`create or replace function` / `create policy` guarded appropriately, so
re-running them is safe.

What's still deliberately missing: confirming a match doesn't do anything
beyond flip its status yet — no chat opens, no contact info is shared.
That's Phases 7 (messaging) and 8 (claims), which give "confirmed" an
actual next step.

## Google Maps setup (Phase 6)

The map view in `ItemsMapView` needs a Google Maps API key configured
natively — it won't render without one, even though the Dart code is
already correct.

1. Get an API key from Google Cloud Console with the **Maps SDK for
   Android** enabled.
2. Add it to `android/app/src/main/AndroidManifest.xml`, inside the
   `<application>` tag:

   ```xml
   <meta-data
       android:name="com.google.android.geo.API_KEY"
       android:value="YOUR_API_KEY_HERE" />
   ```

Until this is set up, tapping the map toggle will show a blank or greyed
map rather than crashing — the widget itself doesn't require the key to
build, only to render tiles.

## Search, filters, and the map (Phase 6)

- `ItemFeedScreen`'s search box and category chips are no longer client-side
  filters over an already-fetched list — they're real query parameters.
  `ItemsRepository.fetchOpenItems()` applies `.eq('category_id', ...)` and
  an `.or('title.ilike...,description.ilike...')` search server-side, and
  `itemsFeedProvider` is now a `.family` provider keyed on
  `ItemsFilter(categoryId, searchQuery)` so Riverpod fetches and caches per
  filter combination automatically. The search box debounces for 400ms
  before refetching, so typing doesn't fire a query per keystroke.
- The map toggle (top-right of the app bar) swaps the list for
  `ItemsMapView`, which centers on the device's current location (via the
  same `getCurrentPositionOrNull()` helper the post-item form uses, now
  shared from `core/location/`) and plots open items within 5km using the
  `nearby_items()` RPC — red pins for lost, green for found.
- `nearby_items()` got a shape change: it used to return raw `items` rows,
  which meant the PostGIS `location` column would serialize unpredictably
  over PostgREST. It now returns plain `latitude`/`longitude` doubles (via
  `st_y`/`st_x`) plus category name and first photo, so the client never
  has to parse a geography value directly. **This changes the function's
  return type**, so the SQL file drops the old version before recreating
  it — straightforward if you're re-running against a database that
  already had Phase 1's version installed.
- Deliberately out of scope for now: the map view doesn't share the list's
  category/search filters, and there's no distance or date filter yet
  beyond the map's fixed 5km radius. Both are natural follow-ups once this
  is in daily use rather than blind guesses about what filtering people
  actually want.

## Firebase setup for push notifications (Phase 7)

Push notifications need a real Firebase project — something this sandbox
can't create. Once you have one:

1. In the Firebase Console, add an Android app with your package name,
   download `google-services.json`, and place it at
   `android/app/google-services.json`.
2. Add the Google Services Gradle plugin — in
   `android/build.gradle.kts` (project-level):
   ```kotlin
   plugins {
       id("com.google.gms.google-services") version "4.4.2" apply false
   }
   ```
   and in `android/app/build.gradle.kts` (module-level):
   ```kotlin
   plugins {
       id("com.google.gms.google-services")
   }
   ```
3. Add the notification permission to
   `android/app/src/main/AndroidManifest.xml`:
   ```xml
   <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
   ```

With that in place, `Firebase.initializeApp()` in `main.dart` — called
with no explicit options, which works fine for an Android-only app without
needing a generated `firebase_options.dart` — will succeed, and
`initializePushNotifications()` requests permission, registers this
device's FCM token to the signed-in user's `profiles` row, and shows
foreground messages as local notifications. Skip all of this and the app
still runs fine; it's wrapped in a try/catch specifically so a missing
Firebase project degrades to "no push notifications" rather than a crash.

**What's still missing, honestly**: nothing in this codebase actually
*sends* a push notification when a match or message happens. That's a
server-side piece — a Supabase Edge Function (calling the FCM HTTP v1 API)
triggered by a Database Webhook on inserts into `matches`/`messages` —
which needs a Firebase service account key. That's a real secret this
sandbox has no way to hold or test against, so it's a natural next step
to build once you're ready to wire it up rather than something guessed at
here.

## In-app chat (Phase 7)

- **`messages` changed shape**: it used to be scoped by `item_id`, but a
  conversation is fundamentally between the two people on either side of
  a match, not about one item in isolation — so it's now scoped by
  `match_id`. If you already ran the Phase 1 SQL and have existing message
  rows, run `truncate table public.messages;` before re-running
  `01_extensions_and_tables.sql`; there's no production data at stake this
  early in the build.
- **Chat is gated behind a confirmed match**, not available the moment a
  candidate appears — tapping "This is it!" on a match is what makes a
  "Message" button (and a `ChatListScreen` entry) appear, via the new
  `my_conversations()` RPC.
- **Messages use real Supabase Realtime**, unlike the joined queries
  elsewhere in this app (`itemsFeedProvider`, `matchesProvider`), which
  refetch rather than stream, since `.stream()` doesn't support embedded
  joins. A plain message list has no such join, so `ChatScreen` gets live
  updates via `messagesStreamProvider`, a genuine `StreamProvider`.
- Marking messages read only touches the *current user's own* incoming
  messages (enforced by the existing RLS policy, not just app logic), so
  there's no way to mark the other person's messages as read on their
  behalf even with a buggy client.

## Claims, trust, and moderation (Phase 8)

This is the last phase in the original roadmap — it closes the loop that
Phase 5 opened ("confirming a match doesn't do anything beyond flip its
status yet") and Phase 7 continued (chat, but no next step once you'd
found the right person).

**The claim → return → rating lifecycle**, all inside `ChatScreen`:

1. Claims are always filed against whichever item in the match has type
   `'found'` — you claim something someone *found*, to prove you're the
   one who *lost* it. `ChatScreenArgs.foundItemId` / `.iAmClaimant` work
   this out from the two items' types so the UI doesn't need to ask.
2. The claimant writes a verification answer (a detail only the real
   owner would know) via a "File a claim" button; the finder sees it and
   can Approve or Reject.
3. Approving runs a trigger (`handle_claim_approved`) that moves the item
   to `'claimed'` automatically — the client never writes that status
   directly, so it can't drift out of sync with the claim's actual state.
4. Once claimed, the finder gets a "Mark as returned" button, moving the
   item to `'resolved'`.
5. Resolving surfaces a star-rating prompt for the other person. Ratings
   write to a new `ratings` table (one row per return, for an audit
   trail), and a trigger (`handle_new_rating`) recomputes
   `profiles.rating`/`rating_count` from it — those columns are a
   fast-read cache, never written to directly.

All of this state (claim, item status, whether you've already rated) is
fetched together by `chatLifecycleProvider`, so the banner at the top of
the chat doesn't flicker through multiple loading states as you scroll.

**A real item detail screen**, which turned out to be a genuine gap
before this phase — there was no way to see an item's full description,
every photo, or take any action beyond what the feed card already showed.
Tapping a card now opens `ItemDetailScreen`, which is also where
"Report this item" lives (a reason picker that inserts into `reports`).

**Basic moderation**: `profiles.is_admin` gates a "Flagged reports" entry
in `ProfileScreen`, opening `AdminReportsScreen` — a list of open reports
with Dismiss / Remove item actions. This is backed by RLS, not just a
hidden UI element: the "admins can view all reports" and "admins can
delete any item" policies mean a non-admin who somehow navigated there
would just see an empty list. There's no UI to grant someone admin —
that's a one-off `update profiles set is_admin = true where id = '...';`
in the Supabase SQL editor for now, which is reasonable for a single
trusted moderator and a natural thing to build a proper flow around later.

## 9. A few things to double-check before shipping

- **Package versions**: everything in `pubspec.yaml` was current as of the
  research done alongside this scaffold, but this ecosystem moves fast —
  run `flutter pub outdated` before your first real build and bump
  anything stale.
- **TFLite plugin**: the original `tflite_flutter` package's upstream
  development has been slow. Before relying on it, check pub.dev/
  fluttergems.dev for whichever fork or successor is currently
  best-maintained (sort by "last updated" and check open issues) rather
  than assuming the pinned version here is still the right one.
- **pgvector inserts**: `ItemsRepository.createItem()` inserts a Dart
  `List<double>` straight into the `embedding` column. This works in the
  common case because a JSON array's text form matches pgvector's own
  input format, but it's untested against a live project in this sandbox
  — verify it once you have a real device, model, and Supabase project.
- **Google Maps**: needs an API key in the Android manifest — see the
  "Google Maps setup" section above.
- **Firebase**: needs a real project and `google-services.json` — see the
  "Firebase setup for push notifications" section above. No push is
  actually *sent* yet without an Edge Function; that's flagged there too.
- **Ratings aren't tightly restricted**: the RLS policy lets any signed-in
  user insert a rating as themselves, not strictly only for an item they
  actually completed a return on — the app only ever shows the rating
  dialog after "mark as returned", so this is a reasonable trust boundary
  for a first version, not a hard guarantee worth over-engineering yet.
- **Granting admin access**: there's no in-app flow for it — run
  `update public.profiles set is_admin = true where id = '<user-uuid>';`
  in the Supabase SQL editor for your first moderator.

## Project structure

```
lib/
  core/
    theme/         AppColors + AppTheme (Material 3, light & dark)
    router/         go_router config with a StatefulShellRoute bottom nav
    constants/      table names, bucket names, RPC function names
    providers/      currentUserProvider, authStateChangesProvider
    supabase/       shared Supabase client accessor
    ml/             TfliteClassifier, its provider, category_mapper
    location/       shared getCurrentPositionOrNull() helper
    notifications/  FCM setup + push token registration
    widgets/        MainShell (bottom nav + FAB)
  features/
    splash/         shows the pin glyph on brand teal
    auth/           login, signup, forgot-password — wired to Supabase Auth
    home/           browse tab: real search/filters, plus items_map_view.dart
    items/
      data/          CategoryModel, ItemModel, NearbyItemModel, ClaimModel,
                      ItemsRepository, ClaimsRepository, providers
      post_item_screen.dart   photo picking, location, AI tagging, upload
      item_detail_screen.dart  full detail, photo gallery, report action
    matches/
      data/          MatchModel, MatchesRepository, providers
      matches_screen.dart   real matches, confirm/dismiss, message action
    chat/
      data/          ConversationModel, MessageModel, MessagesRepository
      chat_list_screen.dart   real conversations, unread badges
      chat_screen.dart        live messages + claim/return/rate lifecycle
    profile/
      data/          ProfileModel, AdminRepository, ReportModel, providers
      profile_screen.dart      real rating, conditional admin entry
      admin_reports_screen.dart  moderation: dismiss / remove item
supabase/
  01_extensions_and_tables.sql
  02_functions_and_triggers.sql
  03_rls_policies.sql
  04_storage_setup.sql
scripts/
  export_tflite_model.py   generates the on-device model + labels
  requirements.txt
assets/
  models/           drop the exported .tflite + labels file here
  images/           app_icon.svg, logo_lockup.svg, pin_glyph_white.svg
```
