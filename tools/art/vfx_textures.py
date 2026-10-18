"""Glow textures for spell and hit effects (white on black + matching alpha; tinted in Godot).

    python tools/art/vfx_textures.py

Writes game/art/vfx/:
  rune_circle.png  casting circle: double ring, rune glyphs between, a hexagram inside
  shockwave.png    soft ring with a bright leading edge (nova, heal pulse)
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "game", "art", "vfx")
SIZE = 512


def glyph(draw, cx, cy, h, rot, rng, width):
    """A rune-like glyph: a stave with two or three angled branches."""
    def p(x, y):
        c, s = math.cos(rot), math.sin(rot)
        return (cx + x * c - y * s, cy + x * s + y * c)

    draw.line([p(0, -h / 2), p(0, h / 2)], fill=255, width=width)
    for _ in range(rng.choice((2, 3))):
        y0 = rng.uniform(-0.45, 0.3) * h
        dx = rng.choice((-1, 1)) * h * rng.uniform(0.25, 0.4)
        dy = rng.choice((-1, 1)) * h * rng.uniform(0.15, 0.3)
        draw.line([p(0, y0), p(dx, y0 + dy)], fill=255, width=width)


def rune_circle():
    s = SIZE * 2  # draw large, then downsample for clean lines
    img = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(img)
    c = s / 2
    w = max(2, s // 170)
    for r in (0.48, 0.44, 0.30, 0.27):
        d.ellipse([c - r * s, c - r * s, c + r * s, c + r * s], outline=255, width=w)
    rng = random.Random(7)
    count = 18
    for i in range(count):
        a = 2 * math.pi * i / count
        glyph(d, c + math.cos(a) * 0.36 * s, c + math.sin(a) * 0.36 * s, 0.09 * s, a + math.pi / 2, rng, w)
    for k in range(2):  # hexagram
        pts = [(c + math.cos(a) * 0.27 * s, c + math.sin(a) * 0.27 * s)
               for a in (2 * math.pi * (j / 3) + k * math.pi / 3 - math.pi / 2 for j in range(4))]
        d.line(pts, fill=255, width=w)
    d.ellipse([c - 0.05 * s, c - 0.05 * s, c + 0.05 * s, c + 0.05 * s], outline=255, width=w)
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    halo = img.filter(ImageFilter.GaussianBlur(6))
    a = np.maximum(np.asarray(img, float), np.asarray(halo, float) * 0.8)
    return a


def shockwave():
    y, x = np.mgrid[0:SIZE, 0:SIZE] / (SIZE - 1) * 2 - 1
    r = np.hypot(x, y)
    edge = np.exp(-((r - 0.9) / 0.035) ** 2)          # bright leading edge
    wake = np.clip((r - 0.45) / 0.45, 0, 1) ** 2 * (r < 0.9)  # soft fill behind it
    return np.clip(edge + 0.45 * wake, 0, 1) * 255


def save(name, alpha):
    # colour = alpha too: Godot decals glow by the emission texture's colour, not its alpha
    a = np.clip(alpha, 0, 255).astype(np.uint8)
    rgba = np.dstack([a] * 3 + [a])
    Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, name))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    save("rune_circle.png", rune_circle())
    save("shockwave.png", shockwave())
    print("wrote", OUT)
