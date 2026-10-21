"""The heroes' eye colours (character creation): the Quaternius hero eye (CC0, Universal
Base Characters, a brown iris) recoloured per colour into game/art/characters/hero/eyes.
Only the iris (the coloured disc in the middle) changes; its light and dark keep.

    python tools/art/hero_eyes.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art/vendor/quaternius/ubc/Universal Base Characters[Standard]/Base Characters/Textures/T_Eye_Brown.png"
OUT = ROOT / "game/art/characters/hero/eyes"
## iris colours (sRGB), at the iris' mean brightness
COLOURS = {"ice": (0.72, 0.84, 0.92), "lightblue": (0.42, 0.64, 0.9), "blue": (0.2, 0.42, 0.82),
           "deepblue": (0.12, 0.22, 0.58), "bluegreen": (0.2, 0.56, 0.56), "green": (0.32, 0.56, 0.24),
           "grey": (0.56, 0.6, 0.62), "brownlight": (0.72, 0.5, 0.24), "brown": None}
## the iris: this far (share of the texture's width) from its centre
IRIS = 0.125


if __name__ == "__main__":
    image = np.asarray(Image.open(SOURCE).convert("RGB")).astype(float) / 255.0
    h, w = image.shape[:2]
    y, x = np.mgrid[0:h, 0:w]
    r = np.hypot(x - w / 2, y - h / 2) / w
    luma = image @ np.array([0.3, 0.59, 0.11])
    saturation = image.max(-1) - image.min(-1)
    iris = (r < IRIS) & (saturation > 0.12)  # (not the pupil, not the highlight)
    soft = np.clip((IRIS - r) / 0.02, 0.0, 1.0) * iris
    mean = luma[iris].mean()
    OUT.mkdir(parents=True, exist_ok=True)
    for name, colour in COLOURS.items():
        out = image.copy()
        if colour is not None:
            tinted = np.array(colour)[None, None, :] * (luma / mean)[..., None]
            out = out * (1.0 - soft[..., None]) + tinted * soft[..., None]
        Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(OUT / (name + ".png"))
    print("eyes: %d colours -> %s" % (len(COLOURS), OUT))
