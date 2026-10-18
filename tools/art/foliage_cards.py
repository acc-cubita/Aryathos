"""Leaf-cluster and needle-spray cards for the trees (alpha-tested quads in the crowns).

    python tools/art/foliage_cards.py

Broadleaf cards are real scanned leaves (ambientCG CC0 LeafSet atlases in
art/vendor/ambientcg) arranged along drawn twigs; conifer cards are needle sprays
drawn from scratch. Each output is a 2x2 atlas of different clusters, RGBA (colour +
coverage), with the colour bled into the transparent parts so mipmaps keep no dark
fringe. Herb cards (gather nodes) are two single leaves and two white blooms the shader
dyes. Writes game/art/textures/foliage/{summer,autumn,needles,herbs}.png.
"""
import io
import math
import random
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1].parent
VENDOR = ROOT / "art" / "vendor" / "ambientcg"
OUT = ROOT / "game" / "art" / "textures" / "foliage"
CELL = 1024  # one cluster; the atlas is 2 x 2 cells
TWIG = (78, 60, 42)


def leaf_sprites(asset):
    """Cut the single leaves out of an ambientCG LeafSet atlas (by connected coverage)."""
    with zipfile.ZipFile(VENDOR / ("%s_2K-JPG.zip" % asset)) as z:
        color = Image.open(io.BytesIO(z.read("%s_2K-JPG_Color.jpg" % asset))).convert("RGB")
        alpha = Image.open(io.BytesIO(z.read("%s_2K-JPG_Opacity.jpg" % asset))).convert("L")
    small = np.asarray(alpha.resize((256, 256))) > 100
    seen = np.zeros_like(small)
    boxes = []
    for y0 in range(256):
        for x0 in range(256):
            if small[y0, x0] and not seen[y0, x0]:
                stack, xs, ys = [(y0, x0)], [], []
                seen[y0, x0] = True
                while stack:
                    y, x = stack.pop()
                    xs.append(x)
                    ys.append(y)
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < 256 and 0 <= nx < 256 and small[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            stack.append((ny, nx))
                if len(xs) > 60:
                    k = color.width / 256
                    boxes.append((int(min(xs) * k) - 4, int(min(ys) * k) - 4, int((max(xs) + 1) * k) + 4, int((max(ys) + 1) * k) + 4))
    sprites = []
    for box in boxes:
        leaf = color.crop(box).convert("RGBA")
        leaf.putalpha(alpha.crop(box))
        sprites.append(leaf)
    return sprites


def bezier(p0, p1, p2, t):
    return tuple((1 - t) ** 2 * a + 2 * (1 - t) * t * b + t * t * c for a, b, c in zip(p0, p1, p2))


def stroke(draw, points, w0, w1, color):
    """A tapering line through the points, w0 wide at the start, w1 at the end."""
    for i in range(len(points) - 1):
        w = w0 + (w1 - w0) * i / max(len(points) - 1, 1)
        draw.line([points[i], points[i + 1]], fill=color, width=max(1, int(round(w))))
        draw.ellipse([points[i][0] - w / 2, points[i][1] - w / 2, points[i][0] + w / 2, points[i][1] + w / 2], fill=color)


def jitter(sprite, rng, tone):
    """Per-leaf colour variation: brightness and a little hue (yellower / bluer)."""
    a = np.asarray(sprite).astype(float)
    k = rng.uniform(0.75, 1.15) * tone
    a[..., 0] *= k * rng.uniform(0.92, 1.1)
    a[..., 1] *= k
    a[..., 2] *= k * rng.uniform(0.85, 1.05)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def leaf_cluster(sprites, rng, leaves=42):
    """A twig with side shoots, leaves along them pointing outward; darker leaves behind."""
    card = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(card)
    base = (CELL / 2 + rng.uniform(-40, 40), CELL - 20)
    tip = (CELL / 2 + rng.uniform(-160, 160), rng.uniform(120, 220))
    bend = (CELL / 2 + rng.uniform(-200, 200), CELL * 0.55)
    main = [bezier(base, bend, tip, t / 40) for t in range(41)]
    twigs = [main]
    for _ in range(rng.randint(3, 5)):
        start = main[rng.randint(8, 34)]
        side = rng.choice((-1, 1))
        end = (start[0] + side * rng.uniform(180, 330), start[1] - rng.uniform(80, 260))
        mid = ((start[0] + end[0]) / 2, (start[1] + end[1]) / 2 + rng.uniform(-40, 40))
        twigs.append([bezier(start, mid, end, t / 20) for t in range(21)])
    for i, twig in enumerate(twigs):
        stroke(draw, twig, 16 if i == 0 else 9, 4, TWIG)
    spots = []
    for twig in twigs:
        for j in range(4, len(twig), max(2, len(twig) // 8)):
            spots.append((twig, j))
        spots.append((twig, len(twig) - 1))
    rng.shuffle(spots)
    placed = []
    for twig, j in spots[:leaves]:
        x, y = twig[j]
        a, b = twig[max(j - 1, 0)], twig[min(j + 1, len(twig) - 1)]
        along = math.degrees(math.atan2(-(b[1] - a[1]), b[0] - a[0]))  # twig direction, up = +
        side = rng.choice((-1, 1))
        angle = along - 90 + side * rng.uniform(25, 70)  # leaf tip points away from the twig
        size = rng.uniform(150, 240)
        placed.append((rng.random(), x, y, angle, size))
    placed.sort()  # random depth order; later (front) leaves brighter
    for depth, x, y, angle, size in placed:
        leaf = rng.choice(sprites)
        k = size / max(leaf.size)
        leaf = leaf.resize((max(1, int(leaf.width * k)), max(1, int(leaf.height * k))), Image.LANCZOS)
        leaf = jitter(leaf, rng, 0.8 + 0.3 * depth).rotate(angle, resample=Image.BICUBIC, expand=True)
        # the stem end of an upright leaf sprite is at its bottom: put that on the twig
        r = math.radians(angle)
        off = (math.sin(r) * size / 2, math.cos(r) * size / 2)
        card.alpha_composite(leaf, (int(x - leaf.width / 2 - off[0]), int(y - leaf.height / 2 - off[1])))
    return card


def needle_spray(rng):
    """A conifer shoot: a twig with side shoots, thick with needles; drawn 2x and reduced."""
    s = 2
    size = CELL * s
    card = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(card)
    base = (size / 2, size - 30)
    tip = (size / 2 + rng.uniform(-120, 120), 110)
    main = [bezier(base, (size / 2 + rng.uniform(-150, 150), size / 2), tip, t / 160) for t in range(161)]
    shoots = [(main, 1.0)]
    for _ in range(rng.randint(6, 9)):
        j = rng.randint(25, 140)
        start = main[j]
        side = rng.choice((-1, 1))
        length = rng.uniform(420, 760) * (1.15 - j / 200)
        end = (start[0] + side * length, start[1] - length * rng.uniform(0.3, 0.75))
        mid = ((start[0] + end[0]) / 2, (start[1] + end[1]) / 2 + rng.uniform(10, 50))
        shoots.append(([bezier(start, mid, end, t / 70) for t in range(71)], 0.8))
    for i, (twig, _) in enumerate(shoots):
        stroke(draw, twig, 20 if i == 0 else 11, 5, (72, 54, 38, 255))
    # needles: back layer darker, front layer lighter, all angled toward the shoot's tip
    for layer, (lo, hi) in enumerate(((0.55, 0.85), (0.85, 1.25))):
        for twig, scale in shoots:
            n = len(twig)
            for j in range(1, n):
                x, y = twig[j]
                a = twig[j - 1]
                along = math.atan2(y - a[1], x - a[0])
                taper = 0.45 + 0.55 * min(1.0, (n - j) / (n * 0.35))  # shorter needles toward the tip
                for side in (-1, 1):
                    ang = along + side * rng.uniform(0.55, 1.05)
                    length = rng.uniform(110, 170) * taper * scale
                    shade = rng.uniform(lo, hi)
                    end = (x + math.cos(ang) * length, y + math.sin(ang) * length)
                    draw.line([(x, y), end], fill=(int(30 * shade), int(58 * shade), int(30 * shade), 255), width=6)
                    draw.line([((x * 2 + end[0]) / 3, (y * 2 + end[1]) / 3), end],
                              fill=(int(55 * shade), int(92 * shade), int(45 * shade), 255), width=5)
    return card.resize((CELL, CELL), Image.LANCZOS)


def single_leaf(sprites, index):
    """One scanned leaf upright in a cell, stem at the bottom middle (herb rosettes)."""
    leaf = sorted(sprites, key=lambda s: s.width * s.height)[-1 - index]
    k = CELL * 0.92 / max(leaf.size)
    leaf = leaf.resize((int(leaf.width * k), int(leaf.height * k)), Image.LANCZOS)
    card = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    card.alpha_composite(leaf, ((CELL - leaf.width) // 2, CELL - leaf.height - 8))
    return card


def flower(rng, petals):
    """A bloom seen from above: veined white petals around a disc of stamens; drawn 2x.
    White so the shader can dye it per herb."""
    s = 2
    size = CELL * s
    card = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c = size / 2
    spin = rng.uniform(0, math.tau)
    for i in range(petals):
        petal = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(petal)
        a = spin + i * math.tau / petals + rng.uniform(-0.08, 0.08)
        length = size * rng.uniform(0.4, 0.46)
        width = length * rng.uniform(0.36, 0.44)
        # petal outline: narrow at the base, round at the tip
        outline = []
        for k in range(41):
            t = k / 40
            half = width * math.sin(math.pi * min(t * 1.15, 1.0)) ** 0.8 * 0.5
            outline.append((t, half))
        pts = [(t * length, h) for t, h in outline] + [(t * length, -h) for t, h in reversed(outline)]
        ca, sa = math.cos(a), math.sin(a)
        draw.polygon([(c + x * ca - y * sa, c + x * sa + y * ca) for x, y in pts], fill=(250, 250, 246, 255))
        # veins fanning toward the tip
        for v in range(-3, 4):
            end = (length * 0.92, v * width * 0.09)
            mid = (length * 0.5, v * width * 0.06)
            line = [bezier((length * 0.08, 0), mid, end, t / 12) for t in range(13)]
            draw.line([(c + x * ca - y * sa, c + x * sa + y * ca) for x, y in line], fill=(214, 218, 210, 255), width=3)
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).polygon([(c + x * ca - y * sa, c + x * sa + y * ca) for x, y in pts], fill=255)
        petal.putalpha(mask)  # keep the veins inside the petal
        card.alpha_composite(petal)
    # greenish-yellow base fading into the petals, then the stamens
    shade = np.asarray(card).astype(float)
    yy, xx = np.mgrid[0:size, 0:size]
    r = np.hypot(xx - c, yy - c) / (size * 0.45)
    base = np.clip(1.0 - r / 0.35, 0, 1)[..., None]
    shade[..., :3] = shade[..., :3] * (1 - base * 0.25) + np.array([200, 215, 120]) * base * 0.25
    card = Image.fromarray(shade.astype(np.uint8), "RGBA")
    draw = ImageDraw.Draw(card)
    for _ in range(140):
        rr = abs(rng.gauss(0, size * 0.035))
        a = rng.uniform(0, math.tau)
        x, y = c + math.cos(a) * rr, c + math.sin(a) * rr
        d = rng.uniform(7, 13)
        tone = rng.uniform(0.75, 1.05)
        draw.ellipse([x - d, y - d, x + d, y + d], fill=(int(235 * tone), int(196 * tone), int(70 * tone), 255))
    return card.resize((CELL, CELL), Image.LANCZOS)


def bleed(img, rounds=24):
    """Spread edge colours into the transparent area (alpha untouched)."""
    a = np.asarray(img).astype(float)
    rgb, alpha = a[..., :3], a[..., 3]
    known = alpha > 8
    for _ in range(rounds):
        acc = np.zeros_like(rgb)
        cnt = np.zeros(alpha.shape)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sk = np.roll(known, (dy, dx), (0, 1))
            acc += np.roll(rgb, (dy, dx), (0, 1)) * sk[..., None]
            cnt += sk
        grow = (~known) & (cnt > 0)
        rgb[grow] = acc[grow] / cnt[grow][:, None]
        known = known | grow
    rgb[~known] = rgb[known].mean(0)
    return Image.fromarray(np.dstack([rgb, alpha]).astype(np.uint8), "RGBA")


def atlas(cells):
    out = Image.new("RGBA", (CELL * 2, CELL * 2), (0, 0, 0, 0))
    for i, cell in enumerate(cells):
        out.alpha_composite(cell, ((i % 2) * CELL, (i // 2) * CELL))
    return bleed(out)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    rng = random.Random(3)
    summer = leaf_sprites("LeafSet024")
    autumn = leaf_sprites("LeafSet027")
    print("leaves found:", len(summer), len(autumn))
    atlas([leaf_cluster(summer, rng) for _ in range(4)]).save(OUT / "summer.png")
    atlas([leaf_cluster(autumn, rng, 36) for _ in range(4)]).save(OUT / "autumn.png")
    atlas([needle_spray(rng) for _ in range(4)]).save(OUT / "needles.png")
    atlas([single_leaf(summer, 0), single_leaf(summer, 1), flower(rng, 5), flower(rng, 6)]).save(OUT / "herbs.png")
    print("wrote", OUT)
