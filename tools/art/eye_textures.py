"""Hand-painted glowing eye textures for the Arkanor (blue + gold heterochromia).

Eyes are UV-projected from the front (iris at the texture center, projected
iris radius IRIS of the half-width), see arkanor_head.eye_uv().
Writes <name>_color.png and <name>_glow.png into art/characters/arkanor/tex.
"""
import os

import numpy as np
from PIL import Image, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "art", "characters", "arkanor", "tex")
SIZE = 512
IRIS = 0.5 / 1.1  # eye_uv maps +-1.1 radius to the texture edges; iris = half the eye radius
PUPIL = 0.32      # of the iris radius

PALETTES = {
    # center glow, mid, rim, limbal ring
    "eye_blue": ((0.80, 0.97, 1.00), (0.35, 0.78, 1.00), (0.10, 0.36, 0.78), (0.03, 0.08, 0.22)),
    "eye_gold": ((1.00, 0.97, 0.70), (1.00, 0.74, 0.18), (0.80, 0.38, 0.05), (0.25, 0.10, 0.02)),
}


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    return a + (np.asarray(b) - a) * t[..., None]


def paint(name, pal):
    rng = np.random.default_rng(7)
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    u = (x + 0.5) / SIZE * 2 - 1
    v = (y + 0.5) / SIZE * 2 - 1
    r = np.hypot(u, v) / IRIS          # 1.0 at the iris edge
    a = np.arctan2(v, u)

    # radial fibres: sum of a few angular sine bands with random phases
    fib = np.zeros_like(r)
    for k, w in ((23, 0.5), (41, 0.3), (67, 0.2)):
        fib += w * np.sin(a * k + rng.uniform(0, 6.28) + 2.0 * np.sin(r * 5 + rng.uniform(0, 6.28)))
    fib = 0.5 + 0.5 * fib

    sclera = np.ones(r.shape + (3,)) * np.array((0.93, 0.91, 0.89))
    sclera = mix(sclera, (0.86, 0.72, 0.72), smooth(1.4, 2.4, r) * 0.6)  # warm toward the corners

    iris = mix(np.zeros(r.shape + (3,)) + pal[0], pal[1], smooth(0.25, 0.65, r))
    iris = mix(iris, pal[2], smooth(0.6, 0.95, r))
    iris = iris * (0.82 + 0.3 * fib[..., None])
    pupil = smooth(PUPIL * 1.15, PUPIL * 0.85, r)
    iris = mix(iris, np.asarray(pal[1]) * 0.6, pupil * 0.4)  # glowing eyes: pupil barely shows
    ring = smooth(0.82, 1.0, r) * smooth(1.08, 0.98, r)
    iris = mix(iris, pal[3], ring)

    inside = smooth(1.03, 0.98, r)
    color = mix(sclera, (0, 0, 0), inside)
    color = color + iris * inside[..., None]
    # painted catch-light (upper left), WoW style
    hl = smooth(0.2, 0.0, np.hypot(u + 0.38 * IRIS, v + 0.38 * IRIS) / IRIS)
    color = mix(color, (1, 1, 1), hl * 0.9)

    glow = np.asarray(pal[0]) * smooth(1.0, 0.4, r)[..., None] + np.asarray(pal[1]) * (smooth(1.0, 0.7, r) * 0.6)[..., None]
    glow = glow * (1 - pupil * 0.5)[..., None]

    def save(img, suffix):
        im = Image.fromarray((np.clip(img, 0, 1) ** (1 / 1.0) * 255).astype(np.uint8))
        im.filter(ImageFilter.GaussianBlur(0.6)).save(os.path.join(OUT, "%s_%s.png" % (name, suffix)))

    save(color, "color")
    save(glow, "glow")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for n, p in PALETTES.items():
        paint(n, p)
    print("ok", os.path.abspath(OUT))
