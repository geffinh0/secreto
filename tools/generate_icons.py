"""Regenerates the app icons/favicon/hero image from the fox mascot photo.

Run from the repo root after replacing assets/images/fox_mascot_source.webp:

    python tools/generate_icons.py

Requires Pillow (``pip install pillow``), not otherwise a project dependency.
"""
from PIL import Image, ImageFilter

SRC = "assets/images/fox_mascot_source.webp"
BG = (27, 20, 15, 255)  # AppTheme.bgDark #1B140F

# Square crop centered on the face, tuned by eye for the current source photo.
# Re-tune these four numbers if the source photo changes framing.
CROP_BOX = (20, 0, 1020, 1000)


def _clean_cutout(im: Image.Image) -> Image.Image:
    """Erodes + softens the alpha mask to strip the colour-fringe halo a
    background-removal cutout usually leaves behind."""
    r, g, b, a = im.split()
    a = a.filter(ImageFilter.MinFilter(5))
    a = a.filter(ImageFilter.MinFilter(3))
    a = a.filter(ImageFilter.GaussianBlur(1.2))
    return Image.merge("RGBA", (r, g, b, a))


def make_icon(face: Image.Image, path: str, size: int, fox_fraction: float,
              square_bg: bool = True) -> None:
    canvas = Image.new("RGBA", (size, size), BG if square_bg else (0, 0, 0, 0))
    fox_size = int(size * fox_fraction)
    fox = face.resize((fox_size, fox_size), Image.LANCZOS)
    offset = ((size - fox_size) // 2, (size - fox_size) // 2 + int(size * 0.03))
    canvas.alpha_composite(fox, offset)
    canvas.convert("RGB" if square_bg else "RGBA").save(path)
    print("wrote", path, canvas.size)


def main() -> None:
    im = Image.open(SRC).convert("RGBA")
    face = _clean_cutout(im).crop(CROP_BOX)

    # Standard icons: fox fills most of the frame, solid background.
    make_icon(face, "web/icons/Icon-192.png", 192, 0.92)
    make_icon(face, "web/icons/Icon-512.png", 512, 0.92)
    make_icon(face, "web/favicon.png", 32, 0.92)

    # Maskable icons: keep the fox within the ~80% safe zone, full-bleed background.
    make_icon(face, "web/icons/Icon-maskable-192.png", 192, 0.68)
    make_icon(face, "web/icons/Icon-maskable-512.png", 512, 0.68)

    # Hero art for the login/register screens (photo, not the flat vector icon).
    hero = face.resize((640, 640), Image.LANCZOS)
    hero.save("assets/images/fox_hero.webp", "WEBP", quality=92, method=6)
    print("wrote assets/images/fox_hero.webp", hero.size)


if __name__ == "__main__":
    main()
