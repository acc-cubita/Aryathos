"""Generates the tileable, hand-painted style terrain textures.

Run:  python tools/art/terrain_textures.py
Writes game/art/textures/terrain/{grass,dirt,rock,sand,snow}.png (RGB = color,
A = height used by the terrain shader for natural blending between layers).
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 512
OUT = Path(__file__).resolve().parents[2] / "game" / "art" / "textures" / "terrain"


def fbm(rng, beta=1.4, cutoff=None, size=SIZE):
    """Tileable fractal noise in 0..1 (FFT-filtered white noise wraps seamlessly)."""
    spectrum = np.fft.fft2(rng.standard_normal((size, size)))
    fx = np.fft.fftfreq(size)[:, None]
    fy = np.fft.fftfreq(size)[None, :]
    r = np.sqrt(fx * fx + fy * fy)
    r[0, 0] = 1.0
    spectrum *= 1.0 / r ** beta
    if cutoff:
        spectrum *= np.exp(-(r / cutoff) ** 2)
    spectrum[0, 0] = 0
    out = np.real(np.fft.ifft2(spectrum))
    return (out - out.min()) / (out.max() - out.min())


def voronoi(rng, count, size=SIZE, stretch=1.0):
    """Tileable Voronoi: distance to nearest (f1) and second nearest (f2) point, and the cell id.
    `stretch` > 1 squashes cells vertically into wide slabs."""
    points = rng.random((count, 2)) * size
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    f1 = np.full((size, size), np.inf, np.float32)
    f2 = np.full((size, size), np.inf, np.float32)
    cell = np.zeros((size, size), np.int32)
    for i, (px, py) in enumerate(points):
        for ox in (-size, 0, size):
            for oy in (-size, 0, size):
                d = np.sqrt((xx - px - ox) ** 2 + ((yy - py - oy) * stretch) ** 2)
                closer = d < f1
                f2 = np.where(closer, f1, np.minimum(f2, d))
                cell = np.where(closer, i, cell)
                f1 = np.where(closer, d, f1)
    return f1, f2, cell


def lerp(a, b, t):
    return a + (b - a) * t[..., None]


def color(*rgb):
    return np.array(rgb, np.float32) / 255.0


def wrapped(draw_fn, x, y, margin, size):
    """Draws a shape again on the opposite side when it crosses an edge, so the texture tiles."""
    for ox in (-size, 0, size):
        for oy in (-size, 0, size):
            if -margin < x + ox < size + margin and -margin < y + oy < size + margin:
                draw_fn(x + ox, y + oy)


def strokes(base, rng, count, length, width, brightness, alpha_height=None):
    """Paints short leaf-like strokes on a 2x canvas, colored from the base underneath."""
    big = SIZE * 2
    canvas = Image.fromarray((np.clip(base, 0, 1) * 255).astype(np.uint8)).resize((big, big), Image.BICUBIC)
    height = Image.new("L", (big, big), 90) if alpha_height is not None else None
    draw = ImageDraw.Draw(canvas)
    hdraw = ImageDraw.Draw(height) if height else None
    order = np.sort(rng.uniform(brightness[0], brightness[1], count))  # dark first, highlights on top
    for k in range(count):
        x, y = rng.uniform(0, big, 2)
        angle = rng.uniform(0, np.pi * 2)
        ln = rng.uniform(*length) * 2
        wd = rng.uniform(*width) * 2
        shade = order[k]
        src = base[int(y / 2) % SIZE, int(x / 2) % SIZE]
        fill = tuple(int(c) for c in np.clip(src * shade * 255 + rng.normal(0, 6, 3), 0, 255))
        dx, dy = np.cos(angle) * ln * 0.5, np.sin(angle) * ln * 0.5

        def leaf(cx, cy, fill=fill, dx=dx, dy=dy, wd=wd, shade=shade):
            draw.line([(cx - dx, cy - dy), (cx + dx, cy + dy)], fill=fill, width=max(1, int(wd)))
            draw.ellipse([cx + dx - wd * 0.5, cy + dy - wd * 0.5, cx + dx + wd * 0.5, cy + dy + wd * 0.5], fill=fill)
            if hdraw:
                hdraw.line([(cx - dx, cy - dy), (cx + dx, cy + dy)], fill=int(np.clip(shade * 150, 0, 255)), width=max(1, int(wd)))

        wrapped(leaf, x, y, ln + wd, big)
    rgb = np.asarray(canvas.resize((SIZE, SIZE), Image.LANCZOS), np.float32) / 255.0
    h = np.asarray(height.resize((SIZE, SIZE), Image.LANCZOS), np.float32) / 255.0 if height else None
    return rgb, h


def shade_from_height(h, strength):
    """Fake top-left lighting from a height field (hand-painted bevels)."""
    gx = np.roll(h, -1, 1) - np.roll(h, 1, 1)
    gy = np.roll(h, -1, 0) - np.roll(h, 1, 0)
    return 1.0 + (-gx - gy) * strength


def grass(rng):
    patches = fbm(rng, 2.2)
    spots = fbm(rng, 1.6, cutoff=0.05)
    base = lerp(color(60, 98, 36), color(84, 122, 44), patches)
    base = lerp(base, color(112, 134, 54), np.clip((spots - 0.6) * 1.2, 0, 0.35))
    rgb, h = strokes(base, rng, 14000, (5, 11), (1.6, 2.6), (0.72, 1.32), alpha_height=True)
    rgb = np.asarray(Image.fromarray((rgb * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.5)), np.float32) / 255
    return rgb, h * 0.6 + patches * 0.4


def dirt(rng):
    mottle = fbm(rng, 1.8)
    grain = fbm(rng, 0.6)
    base = lerp(color(108, 82, 54), color(132, 102, 66), mottle)
    base *= (0.92 + grain * 0.16)[..., None]
    img = Image.fromarray((np.clip(base, 0, 1) * 255).astype(np.uint8))
    hmap = Image.fromarray((mottle * 120).astype(np.uint8))
    draw = ImageDraw.Draw(img)
    hdraw = ImageDraw.Draw(hmap)
    for _ in range(110):
        x, y = rng.uniform(0, SIZE, 2)
        rx, ry = rng.uniform(2.5, 7.5), rng.uniform(2.0, 5.5)
        tone = rng.uniform(0.85, 1.1)
        stone = tuple(int(c * tone) for c in (136, 114, 86))
        dark = tuple(int(c * tone * 0.72) for c in (136, 114, 86))
        light = tuple(min(255, int(c * tone * 1.12)) for c in (136, 114, 86))

        def pebble(cx, cy, rx=rx, ry=ry, stone=stone, dark=dark, light=light):
            draw.ellipse([cx - rx + 1, cy - ry + 1, cx + rx + 1, cy + ry + 1], fill=dark)
            draw.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=stone)
            draw.ellipse([cx - rx * 0.6 - 0.5, cy - ry * 0.6 - 0.8, cx + rx * 0.2, cy], fill=light)
            hdraw.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=230)

        wrapped(pebble, x, y, 8, SIZE)
    rgb = np.asarray(img.filter(ImageFilter.GaussianBlur(0.45)), np.float32) / 255
    return rgb, np.asarray(hmap.filter(ImageFilter.GaussianBlur(1.0)), np.float32) / 255


def rock(rng):
    # Wide, flat slabs read as layered cliff rock instead of a cobbled wall.
    f1, f2, cell = voronoi(rng, 34, stretch=2.6)
    edge = f2 - f1
    h = np.clip(edge / 30.0, 0, 1) ** 0.7
    detail = fbm(rng, 1.2)
    h = h * 0.75 + detail * 0.25
    tones = rng.uniform(0.88, 1.1, 34)[cell]
    base = color(118, 116, 124) * tones[..., None]
    base = lerp(base, color(104, 108, 98), np.clip(fbm(rng, 2.0) - 0.45, 0, 1) * 1.4)
    yy = np.mgrid[0:SIZE, 0:SIZE][0] / SIZE
    bands = np.sin((yy + fbm(rng, 2.2) * 0.15) * np.pi * 2 * 9) * 0.5 + 0.5
    base *= (0.94 + bands * 0.08)[..., None]
    base *= np.clip(shade_from_height(h, 5.0), 0.7, 1.3)[..., None]
    crack = np.clip(1.0 - edge / 1.8, 0, 1)
    base = lerp(base, color(70, 68, 78), crack * 0.7)
    base *= (0.92 + detail * 0.16)[..., None]
    return base, h


def sand(rng):
    mottle = fbm(rng, 1.7)
    warp = fbm(rng, 2.4)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE] / SIZE
    ripples = np.sin((yy + warp * 0.25) * np.pi * 2 * 12) * 0.5 + 0.5
    base = lerp(color(176, 156, 108), color(214, 196, 146), mottle)
    base *= (0.94 + ripples * 0.08)[..., None]
    base *= (0.95 + fbm(rng, 0.3) * 0.1)[..., None]
    return base, mottle * 0.5 + ripples * 0.3


def snow(rng):
    drifts = fbm(rng, 2.0)
    base = lerp(color(206, 218, 238), color(242, 246, 252), drifts)
    base *= np.clip(shade_from_height(drifts, 10.0), 0.92, 1.06)[..., None]
    base *= (0.97 + fbm(rng, 0.4) * 0.06)[..., None]
    return base, drifts


def save(name, rgb, height):
    rgba = np.dstack([np.clip(rgb, 0, 1), np.clip(height, 0, 1)])
    Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(OUT / f"{name}.png")
    print("wrote", name)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for i, (name, fn) in enumerate([("grass", grass), ("dirt", dirt), ("rock", rock), ("sand", sand), ("snow", snow)]):
        save(name, *fn(np.random.default_rng(100 + i)))


if __name__ == "__main__":
    main()
