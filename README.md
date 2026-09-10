# Findora — Setup Guide & Reference

Findora is a lost & found app: report a lost or found item, and on-device
AI compares its photo against everyone else's to suggest a match.

This README has two parts. **Part A** is a complete, from-zero, step by
step walkthrough to get the app running on your own Android phone from
VS Code — every step is spelled out, including the ones that feel too
obvious to mention. **Part B** (further down) documents how each part of
the app actually works, organized by build phase, for when you're ready
to extend it.

If you've already been through setup once and just hit a Gradle error,
jump straight to **"Troubleshooting Gradle errors"** in Part A.

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
4. Save the file. `.env` is already listed under `assets` in
   `pubspec.yaml`, so Flutter bundles it automatically — you don't need
   to do anything else for it to be picked up. It's also already excluded
   from `.gitignore` conventions for this kind of file; if you put this
   project under version control, double check `.env` isn't committed.

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

The launcher icon PNGs are already generated and referenced from
`pubspec.yaml`. If you ever redesign `assets/images/app_icon.svg` and
want to regenerate the launcher icons from a fresh PNG, run:

```bash
dart run flutter_launcher_icons
```

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

This project's root `android/build.gradle.kts` already has a `subprojects`
block that forces every module, including third-party plugin modules, onto
Java/Kotlin target 17 uniformly, which is the standard fix for this class
of error. If you added a new plugin and hit this again, no action should
be needed — the override already applies build-wide — but if it somehow
persists, a `flutter clean` followed by a rebuild clears any stale
per-module build cache that might be masking the fix taking effect.

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
  mark directly with Pillow rather than rasterizing the SVG) if you ever
  tweak the design.

## Google sign-in setup (Phase 2)

The "Continue with Google" button calls `signInWithOAuth`, but the
redirect back into the app needs setup outside of Dart code:

1. **Supabase Dashboard** → Authentication → Providers → enable Google,
   and add your OAuth client ID/secret from Google Cloud Console.
2. **Supabase Dashboard** → Authentication → URL Configuration → add
   `io.supabase.findora://login-callback` as a redirect URL (this exact
   string is what `login_screen.dart` passes as `redirectTo`).
3. **Android**: the intent filter for this scheme is already in
   `android/app/src/main/AndroidManifest.xml` — nothing to add there.

Skip this and the email/password flow still works fine — the Google
button will just fail gracefully with an error message.

## Auth state and routing (Phase 2)

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

`assets/models/` needs two files this project doesn't ship, since
producing them requires downloading pretrained weights from Google's
servers:

```bash
cd scripts
pip install -r requirements.txt
python export_tflite_model.py
```

This downloads pretrained MobileNetV2 (ImageNet) weights, wraps them so a
single forward pass returns both a 1280-d embedding and a 1000-way
classification, converts to TFLite with dynamic-range quantization, and
writes `imagenet_labels.txt` directly from Keras's own class index file.
Copy both output files into `assets/models/`.

**Before trusting it on-device**, check the script's printed output
tensor order against the indices `tflite_classifier.dart`'s `classify()`
method assumes (0 = embedding, 1 = classification) — swap them if
predictions come back scrambled.

Until you run this script, the app degrades gracefully: `PostItemScreen`
catches the missing-model error and posts without AI matching rather
than crashing.

## How the AI matching actually works

1. On-device: the exported MobileNetV2 model runs on each photo,
   producing a predicted ImageNet label and a 1280-d embedding vector.
2. A heuristic in `core/ml/category_mapper.dart` maps that fine-grained
   label (e.g. "Labrador_retriever") onto one of Findora's categories
   (e.g. "Pets") to pre-fill the post form.
3. Only the embedding, label, and photo get uploaded — matching needs
   everyone else's items too, so it can't happen purely on-device.
4. A trigger (`record_matches_for_image`) fires the moment a photo with
   an embedding is inserted, comparing it against all opposite-type,
   open, same-category items via pgvector's cosine distance operator
   (`<=>`), writing candidates above the similarity threshold into
   `matches`.
5. `MatchesScreen` reads those via `my_matches()`, which resolves each
   row into "my item" vs "the matched item" from the caller's
   perspective — either owner can confirm or dismiss it.

## The matching engine, end to end (Phase 5)

- **`record_matches_for_image`**: an `after insert` trigger on
  `item_images` for rows with a non-null `embedding`. Runs
  `match_items()` and inserts results into `matches`,
  `on conflict do nothing` so re-processing never duplicates. Runs inside
  the same transaction as the photo insert.
- **`match_items()` excludes same-user matches** — posting both a "lost"
  and "found" report yourself won't match against yourself.
- **`my_matches()`**: resolves `item_a_id`/`item_b_id` into "my item" vs
  "the matched item" from `auth.uid()`'s perspective in one query.
- Item owners can `update` their own matches (confirm/dismiss), not just
  read them.

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
  generate_icon_pngs.py    regenerates the launcher icon PNGs
  requirements.txt
assets/
  models/           drop the exported .tflite + labels file here
  images/           app_icon.svg/.png, logo_lockup.svg, pin_glyph_white.svg
```
