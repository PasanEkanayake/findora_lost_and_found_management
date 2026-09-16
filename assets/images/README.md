# Image assets

- `logo.png` — the Findora mark (magnifying glass, AI/circuit accents,
  location pin), used directly via `Image.asset()` on the splash screen
  and login screen.
- `app_icon.png` — the same logo composited onto a rounded light-blue
  square, used as the flat launcher icon source for
  `flutter_launcher_icons`.
- `app_icon_foreground.png` — the logo alone on a transparent background,
  sized with the extra padding Android's adaptive icon mask needs, used
  as the adaptive icon foreground.

To regenerate the launcher icons after changing any of the above:

```bash
dart run flutter_launcher_icons
```

If you redesign the logo itself, replace `logo.png` (used in-app) and
regenerate `app_icon.png`/`app_icon_foreground.png` from the new source —
any image editor works, or Pillow: composite the new logo onto a rounded
square for `app_icon.png`, and onto a transparent canvas at roughly 55%
scale (centered) for `app_icon_foreground.png` to stay within the
adaptive icon safe zone.
