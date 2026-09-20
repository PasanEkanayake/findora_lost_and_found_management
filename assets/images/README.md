# Image assets

- `logo.png` — the Findora mark (magnifying glass, AI/circuit accents,
  location pin), used directly via `Image.asset()` on the splash screen
  and login screen.
- `app_icon.png` — the same logo composited onto a rounded **white**
  square, used as the flat launcher icon source for
  `flutter_launcher_icons`.
- `app_icon_foreground.png` — the logo alone on a transparent background,
  sized with the extra padding Android's adaptive icon mask needs, used
  as the adaptive icon foreground. The background it sits on is set
  separately (white) in `android/app/src/main/res/values/colors.xml`'s
  `ic_launcher_background` and in `pubspec.yaml`'s
  `flutter_launcher_icons.adaptive_icon_background` — both are `#FFFFFF`.

To regenerate every launcher/PWA icon (Android mipmaps, adaptive icon
foregrounds, web icons, favicon) straight from `logo.png`:

```bash
python scripts/generate_icon_pngs.py
```

This is also what was used to produce the current white-background icon
set — see that script for exactly how each size/variant is composited.
It writes plain PNGs directly, so it works even without the Flutter SDK
installed. If you do have Flutter set up and prefer the standard tool
instead (equivalent result for the Android files, but reads its
config from `pubspec.yaml` rather than being hardcoded):

```bash
dart run flutter_launcher_icons
```

If you redesign the logo itself, replace `logo.png` and re-run
`scripts/generate_icon_pngs.py` (or `flutter_launcher_icons`) to
propagate it everywhere else.
