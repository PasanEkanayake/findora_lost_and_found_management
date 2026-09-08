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
4. `match_items()` in Postgres compares the new embedding against all
   *opposite-type*, *open*, optionally *same-category* items using
   pgvector's cosine distance operator (`<=>`), returning ranked candidates.
5. Candidates above a similarity threshold get written to `matches`, which
   both item owners can see per the RLS policy.

## 6. A few things to double-check before Phase 5+

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
- **Google Maps**: `google_maps_flutter` needs an API key added to
  `android/app/src/main/AndroidManifest.xml` (and the iOS equivalent) —
  see the package's own setup docs, which change per platform.
- **Firebase**: `firebase_messaging` needs a Firebase project and one run
  of `flutterfire configure`, which generates `firebase_options.dart`.

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
    widgets/        MainShell (bottom nav + FAB)
  features/
    splash/         shows the pin glyph on brand teal
    auth/           login, signup, forgot-password — wired to Supabase Auth
    home/           the browse/feed tab, reading real items from Supabase
    items/
      data/          CategoryModel, ItemModel, ItemsRepository, providers
      post_item_screen.dart   photo picking, location, AI tagging, upload
    matches/        AI-suggested matches tab (empty state for now)
    chat/           messaging tab (empty state for now)
    profile/        account screen, shows the real signed-in user
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
