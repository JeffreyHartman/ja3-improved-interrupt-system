#!/usr/bin/env python3
"""Makes the Workshop preview image and shrinks screenshots below the 1 MB upload limit.

Usage:
  tools/images.py preview [SCREENSHOT]   writes release/images/preview.jpg (1024x1024)
  tools/images.py shots FILE...          writes release/images/shot-N.jpg (1920 wide)

The Mod Editor refuses a preview image or a screenshot over 1 MB.
"""
import pathlib
import sys

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "release/images"
LIMIT = 1024 * 1024
FONT_DIR = pathlib.Path("/usr/share/fonts/TTF")
AMBER = (232, 170, 60)
INK = (236, 232, 220)


def font(name, size):
    return ImageFont.truetype(str(FONT_DIR / name), size)


def save_under_limit(img, path):
    for quality in range(92, 40, -4):
        img.save(path, "JPEG", quality=quality, optimize=True)
        if path.stat().st_size <= LIMIT:
            return quality
    sys.exit(f"{path} is still over 1 MB at quality 44")


def background(size, shot):
    if shot:
        img = Image.open(shot).convert("RGB")
        side = min(img.size)
        left, top = (img.width - side) // 2, (img.height - side) // 2
        img = img.crop((left, top, left + side, top + side)).resize((size, size), Image.LANCZOS)
        return ImageEnhance.Brightness(img).enhance(0.45)
    img = Image.new("RGB", (size, size), (24, 27, 24))
    d = ImageDraw.Draw(img)
    for x in range(-size, size, 48):
        d.line([(x, size), (x + size, 0)], fill=(31, 35, 31), width=14)
    return img.filter(ImageFilter.GaussianBlur(1))


def preview(shot=None):
    size = 1024
    img = background(size, shot)
    d = ImageDraw.Draw(img)

    d.rectangle([0, 0, size, 150], fill=(12, 12, 12))
    d.text((size // 2, 78), "INTERRUPT!", font=font("FiraSansCondensed-ExtraBold.ttf", 118), fill=AMBER, anchor="mm")

    title = font("FiraSansCondensed-Bold.ttf", 112)
    for i, line in enumerate(["IMPROVED", "INTERRUPT", "SYSTEM"]):
        d.text((72, 330 + i * 118), line, font=title, fill=INK, anchor="ls")
    d.rectangle([72, 600, 300, 610], fill=AMBER)

    sub = font("FiraSansCondensed-Medium.ttf", 52)
    d.text((72, 690), "JA2 1.13 interrupts", font=sub, fill=INK, anchor="ls")
    d.text((72, 752), "for Jagged Alliance 3", font=sub, fill=INK, anchor="ls")

    small = font("FiraSansCondensed-SemiBold.ttf", 38)
    d.rounded_rectangle([size - 220, size - 110, size - 60, size - 50], radius=8, outline=AMBER, width=4)
    d.text((size - 140, size - 80), "BETA", font=small, fill=AMBER, anchor="mm")

    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / "preview.jpg"
    q = save_under_limit(img, path)
    print(f"{path.relative_to(ROOT)}: {path.stat().st_size // 1024} KB, quality {q}")


def shots(files):
    OUT.mkdir(parents=True, exist_ok=True)
    for i, f in enumerate(files, 1):
        img = Image.open(f).convert("RGB")
        if img.width > 1920:
            img = img.resize((1920, round(img.height * 1920 / img.width)), Image.LANCZOS)
        path = OUT / f"shot-{i}.jpg"
        q = save_under_limit(img, path)
        print(f"{path.relative_to(ROOT)}: {img.width}x{img.height}, {path.stat().st_size // 1024} KB, quality {q}")


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "preview":
        preview(sys.argv[2] if len(sys.argv) > 2 else None)
    elif len(sys.argv) >= 3 and sys.argv[1] == "shots":
        shots(sys.argv[2:])
    else:
        sys.exit(__doc__)
