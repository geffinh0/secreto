"""Regenerates the app icons/favicon/hero image from the fox mascot photo.

Run from the repo root after replacing assets/images/fox_mascot_source.webp:

    python tools/generate_icons.py

Requires Pillow and scipy (``pip install pillow scipy``), not otherwise a
project dependency - scipy's distance transform drives the colour-fringe
cleanup (see _clean_cutout).
"""
from PIL import Image, ImageFilter
import numpy as np
from scipy.ndimage import distance_transform_edt

SRC = "assets/images/fox_mascot_source.webp"
BG = (27, 20, 15, 255)  # AppTheme.bgDark #1B140F

# The whole photo is used, never cropped - icons/hero just fit it into a
# square canvas (letterboxed with BG) so nothing of her gets cut off.
ALPHA_THRESHOLD = 40  # kills the long faint halo tail some cutouts leave


def _clean_cutout(im: Image.Image) -> Image.Image:
    """Removes the colour-fringe halo a background-removal cutout leaves:
    hard-threshold alpha (drops the faint long tail), erode + blur it for a
    crisp edge, then recolour every visible edge pixel from the nearest
    solidly-opaque pixel (plain erosion alone still leaves a tinted ring)."""
    arr = np.array(im.convert("RGBA"))
    alpha = arr[..., 3].astype(np.uint8)

    alpha2 = np.where(alpha > ALPHA_THRESHOLD, alpha, 0).astype(np.uint8)
    a_img = Image.fromarray(alpha2).filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MinFilter(3))
    tight_alpha = np.array(a_img)

    trusted = tight_alpha > 200
    _, (iy, ix) = distance_transform_edt(~trusted, return_indices=True)
    clean_rgb = arr[iy, ix, :3]

    final_alpha = np.array(Image.fromarray(tight_alpha).filter(ImageFilter.GaussianBlur(1.0)))
    visible = final_alpha > 0
    # Zero the RGB wherever nothing is visible - harmless for any correct
    # alpha-compositing viewer, and keeps a stray non-alpha-aware render path
    # from ever showing the recoloured-pixel pattern as a ghost halo.
    out_rgb = np.where(visible[..., None], clean_rgb, 0).astype(np.uint8)
    out = np.dstack([out_rgb, final_alpha]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def _fit_square(face: Image.Image, size: int, fox_fraction: float, bg) -> Image.Image:
    """Scales the *whole* (already-trimmed-to-content) image to fit within
    fox_fraction of a size x size canvas - contain, not crop - centered,
    with `bg` filling the letterboxed margin."""
    canvas = Image.new("RGBA", (size, size), bg)
    w, h = face.size
    scale = (size * fox_fraction) / max(w, h)
    fox = face.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)
    offset = ((size - fox.width) // 2, (size - fox.height) // 2)
    canvas.alpha_composite(fox, offset)
    return canvas


def make_icon(face: Image.Image, path: str, size: int, fox_fraction: float,
              square_bg: bool = True) -> None:
    canvas = _fit_square(face, size, fox_fraction, BG if square_bg else (0, 0, 0, 0))
    canvas.convert("RGB" if square_bg else "RGBA").save(path)
    print("wrote", path, canvas.size)


def main() -> None:
    im = Image.open(SRC)
    cleaned = _clean_cutout(im)
    face = cleaned.crop(cleaned.getbbox())

    # Standard icons: the whole fox, contained (not cropped), solid background.
    make_icon(face, "web/icons/Icon-192.png", 192, 0.96)
    make_icon(face, "web/icons/Icon-512.png", 512, 0.96)
    make_icon(face, "web/favicon.png", 32, 0.96)

    # Maskable icons: keep her within the ~80% safe zone, full-bleed background.
    make_icon(face, "web/icons/Icon-maskable-192.png", 192, 0.72)
    make_icon(face, "web/icons/Icon-maskable-512.png", 512, 0.72)

    # Hero art for the login/register screens: full pose, natural (landscape)
    # aspect ratio, transparent background - no square padding box needed here,
    # unlike the icons above which must be square by platform convention.
    hero_w = 720
    hero_h = round(face.height * hero_w / face.width)
    hero = face.resize((hero_w, hero_h), Image.LANCZOS)
    hero.save("assets/images/fox_hero.webp", "WEBP", quality=92, method=6)
    print("wrote assets/images/fox_hero.webp", hero.size)


if __name__ == "__main__":
    main()
