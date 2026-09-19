"""Regenerates every launcher/PWA icon asset from the real Findora logo
(assets/images/logo.png), composited onto a WHITE background instead of the
old light-blue one.

This replaces the previous version of this script, which drew a simplified
placeholder pin icon that didn't match the actual in-app logo at all. Now
every output is derived from the same source artwork used on the splash and
login screens, so the launcher icon and the in-app branding finally agree.

Run from the project root:
    python3 scripts/generate_icon_pngs.py

Regenerates:
  - assets/images/app_icon.png            (flat icon source, white bg)
  - assets/images/app_icon_foreground.png (adaptive icon foreground, transparent)
  - android/app/src/main/res/mipmap-*/ic_launcher.png      (all 5 densities)
  - android/app/src/main/res/drawable-*/ic_launcher_foreground.png (all 5 densities)
  - web/icons/Icon-192.png, Icon-512.png, Icon-maskable-192.png, Icon-maskable-512.png
  - web/favicon.png

After running this, on a machine with the Flutter SDK installed you can
also run `dart run flutter_launcher_icons` to have it regenerate the
Android files itself from app_icon.png/app_icon_foreground.png — either
approach produces the same result; this script exists so the icons are
already correct even before Flutter tooling is available.
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
WHITE = (255, 255, 255, 255)
SIZE = 1024

# Mirrors pubspec.yaml's `adaptive_icon_background`.
ANDROID_BG_HEX = "#FFFFFF"


def _load_logo() -> Image.Image:
    logo_path = ROOT / "assets" / "images" / "logo.png"
    return Image.open(logo_path).convert("RGBA")


def _rounded_square(size: int, radius_ratio: float = 0.22) -> Image.Image:
    """A plain white rounded square, same corner radius as the previous
    icon design, so the silhouette Android/iOS crop to stays consistent."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    radius = int(size * radius_ratio)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=WHITE)
    return img


def _paste_centered(base: Image.Image, overlay: Image.Image, scale: float) -> Image.Image:
    """Pastes `overlay` (alpha-composited) centered on `base`, resized so its
    longest side is `scale` * base's size."""
    target = int(base.width * scale)
    ratio = target / max(overlay.width, overlay.height)
    resized = overlay.resize(
        (max(1, int(overlay.width * ratio)), max(1, int(overlay.height * ratio))),
        Image.LANCZOS,
    )
    out = base.copy()
    x = (out.width - resized.width) // 2
    y = (out.height - resized.height) // 2
    out.alpha_composite(resized, (x, y))
    return out


def make_app_icon(logo: Image.Image) -> Image.Image:
    """Flat icon: logo on a white rounded square — used directly on iOS/web
    and as flutter_launcher_icons' source image for Android's legacy icon."""
    base = _rounded_square(SIZE)
    # 78% keeps a little breathing room around the mark, same proportion the
    # previous teal-background icon used.
    return _paste_centered(base, logo, scale=0.78)


def make_adaptive_foreground(logo: Image.Image) -> Image.Image:
    """Adaptive icon foreground: logo alone on a transparent canvas, sized to
    stay within Android's ~66% safe zone so it isn't clipped by the circular/
    squircle/rounded-square masks different OEM launchers apply."""
    base = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    return _paste_centered(base, logo, scale=0.58)


def make_flat_square(logo: Image.Image, size: int) -> Image.Image:
    """A plain (non-rounded) white square with the logo centered — used for
    web/PWA icons and mipmap ic_launcher.png, which are masked by the OS
    itself rather than needing pre-baked rounded corners."""
    base = Image.new("RGBA", (size, size), WHITE)
    return _paste_centered(base, logo, scale=0.72)


def make_maskable(logo: Image.Image, size: int) -> Image.Image:
    """PWA 'maskable' icons need extra padding (~20% safe zone each side) so
    Android/Chrome's own masking never clips the mark."""
    base = Image.new("RGBA", (size, size), WHITE)
    return _paste_centered(base, logo, scale=0.55)


def main() -> None:
    logo = _load_logo()

    # --- Flutter asset sources -------------------------------------------
    images_dir = ROOT / "assets" / "images"
    make_app_icon(logo).save(images_dir / "app_icon.png")
    make_adaptive_foreground(logo).save(images_dir / "app_icon_foreground.png")
    print("Wrote assets/images/app_icon.png and app_icon_foreground.png (white bg)")

    # --- Android mipmap ic_launcher.png (flat/legacy icon, all densities) -
    mipmap_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    android_res = ROOT / "android" / "app" / "src" / "main" / "res"
    for folder, size in mipmap_sizes.items():
        out = android_res / folder / "ic_launcher.png"
        make_flat_square(logo, size).save(out)
        print(f"Wrote {out.relative_to(ROOT)} ({size}x{size})")

    # --- Android adaptive icon foreground (all densities) ------------------
    # Matches the existing 108/162/216/324/432 set already in the project.
    fg_sizes = {
        "drawable-mdpi": 108,
        "drawable-hdpi": 162,
        "drawable-xhdpi": 216,
        "drawable-xxhdpi": 324,
        "drawable-xxxhdpi": 432,
    }
    fg_master = make_adaptive_foreground(logo)
    for folder, size in fg_sizes.items():
        out = android_res / folder / "ic_launcher_foreground.png"
        fg_master.resize((size, size), Image.LANCZOS).save(out)
        print(f"Wrote {out.relative_to(ROOT)} ({size}x{size})")

    # --- Web / PWA icons -----------------------------------------------------
    web_icons = ROOT / "web" / "icons"
    make_flat_square(logo, 192).convert("RGB").save(web_icons / "Icon-192.png")
    make_flat_square(logo, 512).convert("RGB").save(web_icons / "Icon-512.png")
    make_maskable(logo, 192).save(web_icons / "Icon-maskable-192.png")
    make_maskable(logo, 512).save(web_icons / "Icon-maskable-512.png")
    make_flat_square(logo, 16).save(ROOT / "web" / "favicon.png")
    print("Wrote web/icons/*.png and web/favicon.png")

    print(f"\nDone. Adaptive icon background should be set to {ANDROID_BG_HEX} in:")
    print("  - android/app/src/main/res/values/colors.xml (ic_launcher_background)")
    print("  - pubspec.yaml (flutter_launcher_icons.adaptive_icon_background)")


if __name__ == "__main__":
    main()
