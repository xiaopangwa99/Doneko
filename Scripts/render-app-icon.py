#!/usr/bin/env python3
"""Render the Doneko app icon (orange squircle + paw) into an iconset and .icns.

The approved concept is a warm orange-to-peach macOS squircle with a centered
paw. Pixels outside the squircle stay fully transparent — no checkerboard.

Requires Pillow. From the repo root:

    python3 Scripts/render-app-icon.py

On a Mac, install.sh also runs `iconutil -c icns` so the installed icon matches
this iconset even if the committed .icns is stale.
"""

from __future__ import annotations

import math
import struct
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

# Normalized icon space, y grows downward. Toes are tall ovals; the outer
# pair tilts out. The main pad is a soft bean, not an ellipse.
# (cx, cy, width, height, rotation degrees)
TOES = (
    (0.40, 0.295, 0.150, 0.220, 10),
    (0.60, 0.295, 0.150, 0.220, -10),
    (0.225, 0.455, 0.138, 0.195, 32),
    (0.775, 0.455, 0.138, 0.195, -32),
)
# Closed outline of the main pad.
PAD_POINTS = (
    (0.50, 0.500),
    (0.62, 0.515),
    (0.72, 0.575),
    (0.765, 0.655),
    (0.70, 0.745),
    (0.58, 0.785),
    (0.50, 0.795),
    (0.42, 0.785),
    (0.30, 0.745),
    (0.235, 0.655),
    (0.28, 0.575),
    (0.38, 0.515),
)

TOP = (254, 148, 78, 255)
BOTTOM = (255, 196, 150, 255)
PAD_TOP = (255, 255, 255, 255)
PAD_BOTTOM = (255, 214, 222, 255)
SHADOW = (150, 64, 32, 80)

ICONSET_FILES = (
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
)

# PNG-backed icns chunk types. Duplicates (16@2x and 32) are what iconutil writes.
ICNS_TYPES = (
    ("icp4", 16),
    ("icp5", 32),
    ("ic11", 32),
    ("icp6", 64),
    ("ic12", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic13", 256),
    ("ic14", 512),
    ("ic09", 512),
    ("ic10", 1024),
)


def squircle_mask(size: int, power: float = 5.0) -> Image.Image:
    """Superellipse mask. Mid-edges reach the canvas; corners fall away."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    half = size / 2.0
    for y in range(size):
        ny = abs((y + 0.5 - half) / half)
        if ny >= 1.0:
            continue
        inner = max(0.0, 1.0 - ny**power)
        nx = inner ** (1.0 / power)
        radius = nx * half
        draw.line([(half - radius, y), (half + radius, y)], fill=255)
    return mask


def vertical_gradient(size: int, top: tuple, bottom: tuple) -> Image.Image:
    image = Image.new("RGBA", (size, size))
    draw = ImageDraw.Draw(image)
    for y in range(size):
        t = y / max(1, size - 1)
        color = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(4))
        draw.line([(0, y), (size, y)], fill=color)
    return image


def catmull_rom(points, samples: int = 18):
    result = []
    count = len(points)
    for i in range(count):
        p0 = points[(i - 1) % count]
        p1 = points[i]
        p2 = points[(i + 1) % count]
        p3 = points[(i + 2) % count]
        for step in range(samples):
            t = step / samples
            t2 = t * t
            t3 = t2 * t
            x = 0.5 * (
                (2 * p1[0])
                + (-p0[0] + p2[0]) * t
                + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3
            )
            y = 0.5 * (
                (2 * p1[1])
                + (-p0[1] + p2[1]) * t
                + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3
            )
            result.append((x, y))
    return result


def ellipse_points(cx, cy, w, h, rotation_deg, samples=48):
    angle = math.radians(rotation_deg)
    cos_a = math.cos(angle)
    sin_a = math.sin(angle)
    points = []
    for i in range(samples):
        t = 2 * math.pi * i / samples
        x = math.cos(t) * w / 2
        y = math.sin(t) * h / 2
        xr = x * cos_a - y * sin_a
        yr = x * sin_a + y * cos_a
        points.append((cx + xr, cy + yr))
    return points


def paw_shapes():
    shapes = [ellipse_points(*toe) for toe in TOES]
    shapes.append(catmull_rom(PAD_POINTS))
    return shapes


def draw_polygon(draw: ImageDraw.ImageDraw, points, size: int, dy: float, fill):
    scaled = [((x) * size, (y + dy) * size) for x, y in points]
    draw.polygon(scaled, fill=fill)


def paw_mask(size: int, dy: float = 0.0) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    for shape in paw_shapes():
        draw_polygon(draw, shape, size, dy, 255)
    return mask


def paint_shapes(size: int, dy: float = 0.0) -> Image.Image:
    """White-to-pink pads with a soft highlight toward the top of each blob."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gradient = vertical_gradient(size, PAD_TOP, PAD_BOTTOM)
    for shape in paw_shapes():
        mask = Image.new("L", (size, size), 0)
        draw_polygon(ImageDraw.Draw(mask), shape, size, dy, 255)
        blob = Image.composite(gradient, Image.new("RGBA", (size, size), (0, 0, 0, 0)), mask)

        xs = [p[0] for p in shape]
        ys = [p[1] for p in shape]
        min_x, max_x = min(xs), max(xs)
        min_y, max_y = min(ys), max(ys)
        highlight_mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(highlight_mask).ellipse(
            [
                (min_x + (max_x - min_x) * 0.22) * size,
                (min_y + dy + (max_y - min_y) * 0.06) * size,
                (max_x - (max_x - min_x) * 0.22) * size,
                (min_y + dy + (max_y - min_y) * 0.48) * size,
            ],
            fill=150,
        )
        highlight_mask = ImageChops.multiply(highlight_mask, mask)
        highlight = Image.new("RGBA", (size, size), (255, 255, 255, 255))
        highlight.putalpha(highlight_mask)
        layer = Image.alpha_composite(layer, blob)
        layer = Image.alpha_composite(layer, highlight)
    return layer


def render(size: int) -> Image.Image:
    ss = 4 if size <= 64 else 2
    canvas = size * ss
    mask = squircle_mask(canvas)
    base = Image.composite(
        vertical_gradient(canvas, TOP, BOTTOM),
        Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0)),
        mask,
    )

    shadow_mask = paw_mask(canvas, dy=0.018)
    shadow = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    shadow.paste(SHADOW, (0, 0), shadow_mask)
    blur = max(1, int(canvas * 0.018))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=blur))
    shadow.putalpha(ImageChops.multiply(shadow.getchannel("A"), mask))
    base = Image.alpha_composite(base, shadow)
    base = Image.alpha_composite(base, paint_shapes(canvas))
    # Clip anything that wandered past the squircle (shadow blur).
    clipped = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    clipped.paste(base, (0, 0), mask)
    return clipped.resize((size, size), Image.Resampling.LANCZOS)


def write_icns(images: dict[int, Image.Image], path: Path) -> None:
    chunks = []
    for ostype, size in ICNS_TYPES:
        buffer = images[size]
        raw = png_bytes(buffer)
        chunks.append(ostype.encode("ascii") + struct.pack(">I", len(raw) + 8) + raw)
    body = b"".join(chunks)
    path.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


def png_bytes(image: Image.Image) -> bytes:
    from io import BytesIO

    out = BytesIO()
    image.save(out, format="PNG")
    return out.getvalue()


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    iconset = root / "Resources" / "AppIcon.iconset"
    iconset.mkdir(parents=True, exist_ok=True)

    cache: dict[int, Image.Image] = {}

    def get(size: int) -> Image.Image:
        if size not in cache:
            cache[size] = render(size)
        return cache[size]

    for name, size in ICONSET_FILES:
        destination = iconset / name
        get(size).save(destination)
        print(f"  {destination.relative_to(root)}")

    icns_path = root / "Resources" / "AppIcon.icns"
    write_icns(cache, icns_path)
    print(f"  {icns_path.relative_to(root)} ({icns_path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
