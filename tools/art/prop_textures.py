"""Generates the tileable, hand-painted style textures for trees and camp props.

Run:  python tools/art/prop_textures.py
Writes game/art/textures/props/{bark,leaves,wood,canvas}.png
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from terrain_textures import SIZE, color, fbm, lerp, wrapped

OUT = Path(__file__).resolve().parents[2] / "game" / "art" / "textures" / "props"


def streaks(rng, vertical, beta=1.6, low_cut=0.0):
    """Tileable noise stretched along one axis: vertical fibers (bark) or horizontal grain (wood)."""
    spectrum = np.fft.fft2(rng.standard_normal((SIZE, SIZE)))
    fx = np.fft.fftfreq(SIZE)[None, :]
    fy = np.fft.fftfreq(SIZE)[:, None]
    # Damping the frequencies along one axis keeps the noise smooth in that direction.
    r = np.sqrt(fx ** 2 + (fy * 8) ** 2) if vertical else np.sqrt((fx * 8) ** 2 + fy ** 2)
    r[0, 0] = 1.0
    spectrum *= 1.0 / r ** beta
    if low_cut:
        spectrum *= 1.0 - np.exp(-(r / low_cut) ** 2)
    spectrum[0, 0] = 0
    out = np.real(np.fft.ifft2(spectrum))
    return (out - out.min()) / (out.max() - out.min())


def bark(rng):
    fibers = streaks(rng, True, beta=1.3, low_cut=0.012)
    fine = streaks(rng, True, beta=0.9)
    patches = fbm(rng, 2.0)
    base = lerp(color(64, 46, 34), color(118, 92, 66), fibers)
    base = lerp(base, color(96, 98, 70), np.clip(patches - 0.6, 0, 1) * 1.5)  # a little lichen
    low, high = np.percentile(fibers, [14, 80])
    cracks = np.clip((low - fibers) * 12.0 + 0.4, 0, 1)
    base = lerp(base, color(34, 24, 18), cracks)
    ridge = np.clip((fibers - high) * 6.0, 0, 1)
    base = lerp(base, color(150, 122, 92), ridge * 0.5)
    base *= (0.9 + fine * 0.2)[..., None]
    return base


def leaves(rng):
    """Grey leaf clusters; the foliage shader tints them with each tree's color."""
    canvas = Image.new("L", (SIZE * 2, SIZE * 2), 60)
    draw = ImageDraw.Draw(canvas)
    big = SIZE * 2
    clumps = fbm(rng, 2.2)
    leaves_xy = rng.uniform(0, big, (2400, 2))
    # Leaves in sunlit clumps are brighter; dark leaves are drawn first so bright ones sit on top.
    lit = clumps[(leaves_xy[:, 1] / 2).astype(int) % SIZE, (leaves_xy[:, 0] / 2).astype(int) % SIZE]
    tone_of = np.clip(60 + lit * 150 + rng.normal(0, 22, 2400), 50, 240)
    order = np.argsort(tone_of)
    tones = tone_of[order]
    leaves_xy = leaves_xy[order]
    for k in range(2400):
        x, y = leaves_xy[k]
        angle = rng.uniform(0, np.pi * 2)
        ln = rng.uniform(34, 60)
        wd = ln * rng.uniform(0.45, 0.6)
        tone = int(tones[k])
        ca, sa = np.cos(angle), np.sin(angle)

        def leaf(cx, cy, ca=ca, sa=sa, ln=ln, wd=wd, tone=tone):
            pts = []
            for t in np.linspace(0, np.pi * 2, 12, endpoint=False):
                # pointed leaf outline
                lx = np.cos(t) * ln * 0.5
                ly = np.sin(t) * wd * 0.5 * (1 - 0.35 * np.cos(t))
                pts.append((cx + lx * ca - ly * sa, cy + lx * sa + ly * ca))
            draw.polygon(pts, fill=max(0, tone - 40))
            inner = [(cx + (px - cx) * 0.78 - 1.5, cy + (py - cy) * 0.78 - 1.5) for px, py in pts]
            draw.polygon(inner, fill=tone)

        wrapped(leaf, x, y, 64, big)
    img = canvas.resize((SIZE, SIZE), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.4))
    gray = np.asarray(img, np.float32) / 255.0
    gray = gray * (0.85 + fbm(rng, 1.8) * 0.3)
    return np.dstack([gray * 0.98, gray, gray * 0.9])


def wood(rng):
    """Four horizontal planks with grain, dark seams and nails."""
    grain = streaks(rng, False)
    fine = streaks(rng, False, beta=0.8)
    rows = np.arange(SIZE)[:, None] * np.ones((1, SIZE))
    plank = (rows // (SIZE // 4)).astype(int)
    tone = rng.uniform(0.85, 1.12, 4)[plank]
    base = lerp(color(104, 74, 46), color(158, 118, 76), grain) * tone[..., None]
    base *= (0.9 + fine * 0.2)[..., None]
    seam_pos = rows % (SIZE // 4)
    seam = np.clip(1.0 - np.minimum(seam_pos, SIZE // 4 - seam_pos) / 3.0, 0, 1)
    base = lerp(base, color(40, 28, 18), seam * 0.9)
    edge_light = np.clip(1.0 - np.abs(seam_pos - 5) / 3.0, 0, 1)
    base = lerp(base, color(190, 150, 104), edge_light * 0.25)
    img = Image.fromarray((np.clip(base, 0, 1) * 255).astype(np.uint8))
    draw = ImageDraw.Draw(img)
    for row in range(4):
        y = row * (SIZE // 4) + SIZE // 8
        for x in (18, SIZE - 18):
            draw.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(52, 50, 52))
            draw.ellipse([x - 3, y - 3, x + 1, y + 1], fill=(120, 118, 116))
    return np.asarray(img, np.float32) / 255.0


def canvas_cloth(rng):
    """Light cloth; tents tint it. Weave, stains and a few stitched seams."""
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    weave = (np.sin(xx * np.pi * 2 / 4) * np.sin(yy * np.pi * 2 / 4)) * 0.5 + 0.5
    stains = fbm(rng, 1.9)
    base = np.full((SIZE, SIZE, 3), 0.88, np.float32) * np.array([1.0, 0.97, 0.9])
    base *= (0.93 + weave * 0.07)[..., None]
    base *= (0.8 + stains * 0.25)[..., None]
    for seam in (SIZE // 3, SIZE * 2 // 3):
        band = np.clip(1.0 - np.abs(yy - seam) / 2.5, 0, 1)
        stitches = ((xx // 6) % 2) * band
        base *= (1.0 - band * 0.25 + stitches * 0.12)[..., None]
    return base


def save(name, rgb):
    Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB").save(OUT / f"{name}.png")
    print("wrote", name)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for i, (name, fn) in enumerate([("bark", bark), ("leaves", leaves), ("wood", wood), ("canvas", canvas_cloth)]):
        save(name, fn(np.random.default_rng(200 + i)))


if __name__ == "__main__":
    main()
