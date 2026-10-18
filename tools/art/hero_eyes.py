"""The heroes' eye colours (character creation): MakeHuman's CC0 eye textures from the MPFB
data folder, halved to 512 px (an eye is small on screen) into game/art/characters/arkanor/eyes.
MakeHuman's "brown" iris is nearly red under game light; its hue is turned to a dark brown.

    python tools/art/hero_eyes.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art/vendor/makehuman/blender_env/extensions/.user/user_default/mpfb/data/eyes/materials"
OUT = ROOT / "game/art/characters/arkanor/eyes"
COLOURS = ["ice", "lightblue", "blue", "deepblue", "bluegreen", "green", "grey", "brownlight", "brown"]
SIZE = 512


def browner(image):
    """Reds (the iris) turned to brown (hue ~27 degrees), a little less saturated."""
    alpha = image.getchannel("A")
    hsv = np.asarray(image.convert("RGB").convert("HSV")).astype(float)
    red = (hsv[..., 1] > 60) & ((hsv[..., 0] < 22) | (hsv[..., 0] > 240))
    hsv[..., 0] = np.where(red, 19.0, hsv[..., 0])
    hsv[..., 1] = np.where(red, hsv[..., 1] * 0.85, hsv[..., 1])
    out = Image.fromarray(hsv.astype(np.uint8), "HSV").convert("RGB")
    out.putalpha(alpha)
    return out


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for colour in COLOURS:
        image = Image.open(SOURCE / ("%s_eye.png" % colour)).convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)
        if colour == "brown":
            image = browner(image)
        image.save(OUT / ("%s.png" % colour), optimize=True)
        print("eyes:", colour)
