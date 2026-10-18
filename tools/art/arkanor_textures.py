"""Painted pattern sheets for the Arkanor bake (white/colour on black, used as masks).

runes.png        tileable strip of carved runes between two border lines (embroidery, trims)
tattoo.png       forearm rune-circuit tattoo; u = around the limb (0 = front), v = shoulder -> wrist
face_male.png    face marks, front projection: u = (x - cx) / 0.2 + 0.5, v = (z - eye_z) / 0.2 + 0.5
face_female.png  (character's right eye at u ~ 0.29 = blue, left eye at u ~ 0.71 = gold)
ornament.png     silver bodice swirls; u = (x - cx) / 0.4 + 0.5, v = (z - waist) / 0.4
Colour channels of the face sheets: R = cyan mark, G = gold mark.
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "art", "characters", "arkanor", "tex")
SS = 4  # supersampling for smooth strokes


def canvas(w, h):
    im = Image.new("RGB", (w * SS, h * SS), (0, 0, 0))
    return im, ImageDraw.Draw(im)


def finish(im, name, blur=0.0):
    w, h = im.size
    im = im.resize((w // SS, h // SS), Image.LANCZOS)
    if blur:
        im = im.filter(ImageFilter.GaussianBlur(blur))
    im.save(os.path.join(OUT, name))


def glyph(draw, x, y, w, h, rng, width, fill):
    """Elder-futhark-like rune: a stem plus 1-3 straight branches."""
    s = SS
    stems = [(x + w * 0.5, y, x + w * 0.5, y + h)] if rng.random() < 0.8 else [(x + w * 0.2, y, x + w * 0.2, y + h), (x + w * 0.8, y, x + w * 0.8, y + h)]
    for st in stems:
        draw.line([c * s for c in st], fill=fill, width=width * s)
    cx = x + w * 0.5
    for _ in range(rng.randint(1, 3)):
        y0 = y + h * rng.choice((0.0, 0.2, 0.35, 0.5))
        dy = h * rng.choice((0.25, 0.35))
        side = rng.choice((-1, 1))
        kind = rng.random()
        if kind < 0.45:
            pts = [(cx, y0), (cx + side * w * 0.45, y0 + dy)]
        elif kind < 0.75:
            pts = [(cx, y0), (cx + side * w * 0.45, y0 + dy * 0.5), (cx, y0 + dy)]
        else:
            pts = [(cx - w * 0.45, y0), (cx + w * 0.45, y0 + dy)]
        draw.line([(px * s, py * s) for px, py in pts], fill=fill, width=width * s, joint="curve")


def runes():
    w, h = 1024, 128
    im, d = canvas(w, h)
    rng = random.Random(3)
    for yy in (10, h - 10):
        d.line([(0, yy * SS), (w * SS, yy * SS)], fill=(255, 255, 255), width=5 * SS)
    cell = 64
    for i in range(w // cell):
        glyph(d, i * cell + 16, 28, cell - 32, h - 56, rng, 6, (255, 255, 255))
    finish(im, "runes.png", 0.4)


def wavy(d, pts, width, fill):
    d.line([(x * SS, y * SS) for x, y in pts], fill=fill, width=int(width * SS), joint="curve")


def tattoo():
    """Long flowing lines down the forearm with branches, dots and a few runes."""
    w, h = 512, 1024
    im, d = canvas(w, h)
    rng = random.Random(11)
    white = (255, 255, 255)
    for k, (x0, amp, ph) in enumerate(((150, 22, 0.0), (205, 18, 1.7), (250, 14, 3.1))):
        pts = [(x0 + amp * math.sin(y / 120.0 + ph), y) for y in range(330, 980, 6)]
        wavy(d, pts, 4.5 if k == 1 else 3.5, white)
        for y in range(380, 940, 110):  # little branches ending in dots
            x = x0 + amp * math.sin(y / 120.0 + ph)
            side = 1 if (y // 110 + k) % 2 else -1
            br = [(x + side * 3 * i, y + 4 * i) for i in range(0, 12)]
            wavy(d, br, 3, white)
            ex, ey = br[-1]
            d.ellipse([(ex - 5) * SS, (ey - 5) * SS, (ex + 5) * SS, (ey + 5) * SS], fill=white)
    for y in (420, 640, 860):
        glyph(d, 300, y, 34, 60, rng, 4, white)
    # a band of runes where the sleeve ends (top of the bare arm)
    for i in range(6):
        glyph(d, 30 + i * 75, 250, 40, 55, rng, 4, white)
    finish(im, "tattoo.png", 0.6)


def face(name, marks):
    w = h = 512
    im, d = canvas(w, h)
    for color, pts, width in marks:
        wavy(d, [(u * w, (1 - v) * h) for u, v in pts], width, color)
    finish(im, name, 0.8)


CYAN, GOLD, DARK = (255, 0, 0), (0, 255, 0), (0, 0, 255)  # DARK: brows / lash lines


def lash(u, v, half=0.15, lift=0.02):
    """Upper lash line over an eye at (u, v) in face-sheet coords."""
    return [(u - half, v - 0.01), (u - half * 0.5, v + lift * 0.8), (u, v + lift), (u + half * 0.5, v + lift * 0.8), (u + half, v - 0.005)]


def faces():
    face("face_male.png", [
        (CYAN, [(0.27, 0.70), (0.26, 0.78), (0.28, 0.86)], 7),   # forehead strokes over each brow
        (CYAN, [(0.32, 0.71), (0.33, 0.80)], 5),
        (CYAN, [(0.73, 0.70), (0.74, 0.78), (0.72, 0.86)], 7),
        (CYAN, [(0.68, 0.71), (0.67, 0.80)], 5),
        (GOLD, [(0.76, 0.40), (0.79, 0.33)], 7),                  # under the gold eye
        (CYAN, [(0.24, 0.40), (0.21, 0.33)], 7),                  # under the blue eye
        (DARK, lash(0.29, 0.5, 0.14, 0.008), 5),
        (DARK, lash(0.71, 0.5, 0.14, 0.008), 5),
    ])
    face("face_female.png", [
        (CYAN, [(0.30, 0.41), (0.29, 0.33), (0.31, 0.25)], 6),   # streaks below the blue eye
        (CYAN, [(0.25, 0.42), (0.24, 0.35)], 4),
        (GOLD, [(0.70, 0.41), (0.71, 0.34)], 6),                  # below the gold eye
        (GOLD, [(0.75, 0.40), (0.76, 0.36)], 4),
        (CYAN, [(0.46, 0.80), (0.50, 0.75), (0.54, 0.80)], 5),   # small chevron on the forehead
        (DARK, lash(0.29, 0.5, 0.15, 0.03), 10),
        (DARK, lash(0.71, 0.5, 0.15, 0.03), 10),
        (DARK, [(0.40, 0.61), (0.33, 0.635), (0.25, 0.64), (0.19, 0.615)], 9),  # slim straight brows
        (DARK, [(0.60, 0.61), (0.67, 0.635), (0.75, 0.64), (0.81, 0.615)], 9),
    ])


def ornament():
    """Silver bodice: mirrored flame swirls under the collar + princess-seam curves to the waist."""
    w = h = 1024
    im, d = canvas(w, h)
    white = (255, 255, 255)

    def side(sign):
        f = lambda u: 0.5 + sign * u
        # seam from shoulder to the girdle, curving in
        wavy(d, [(f(0.2 + 0.06 * math.cos(t * 1.4)) * w, (1 - (0.95 - t * 0.9)) * h) for t in [i / 40 for i in range(41)]], 6, white)
        # flame swirl beside the collar opening
        pts = []
        for i in range(60):
            t = i / 59
            r = 0.09 * (1 - t) + 0.015
            a = 1.5 + t * 4.2
            pts.append((f(0.07 + r * math.cos(a) * 0.8) * w, (1 - (0.8 - 0.25 * t + r * math.sin(a) * 0.5)) * h))
        wavy(d, pts, 7, white)
        wavy(d, [(f(0.03 + 0.05 * t) * w, (1 - (0.97 - 0.2 * t)) * h) for t in [i / 20 for i in range(21)]], 6, white)

    side(1)
    side(-1)
    finish(im, "ornament.png", 0.6)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    runes()
    tattoo()
    faces()
    ornament()
    print("ok", os.path.abspath(OUT))
