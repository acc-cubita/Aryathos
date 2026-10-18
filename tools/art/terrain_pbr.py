"""Packs scanned CC0 ground and bark materials (ambientCG, art/vendor/ambientcg/*.zip).

    python tools/art/terrain_pbr.py

Per layer writes game/art/textures/terrain_pbr/:
  <layer>_albedo.png  RGB = colour (sRGB), A = height (blends layers at uneven edges)
  <layer>_nrao.png    RG = normal xy (OpenGL), B = roughness, A = ambient occlusion
Two textures per layer keep the terrain shader within the sampler limit.
Barks (tree trunks) go to game/art/textures/bark/ and prop surfaces (camp wood, tent
canvas, carved stone) to game/art/textures/props_pbr/, in the same two-texture layout.
"""
import io
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
VENDOR = ROOT / "art" / "vendor" / "ambientcg"
OUT = ROOT / "game" / "art" / "textures" / "terrain_pbr"
BARK_OUT = ROOT / "game" / "art" / "textures" / "bark"
PROPS_OUT = ROOT / "game" / "art" / "textures" / "props_pbr"
SIZE = 2048

LAYERS = {
    "grass": "Grass004",   # meadow grass with dry patches
    "dirt": "Ground072",   # trodden earth with straw: roads and camps
    "rock": "Rock030",     # grey layered rock: cliffs
    "sand": "Ground033",   # pale sand: lake shores
    "snow": "Snow006",
}
BARKS = {
    "oak": "Bark001",   # grey furrowed bark: broadleaf trees
    "pine": "Bark012",  # red-brown scaly bark: conifers
}
PROPS = {
    "wood": "Wood062",       # grey weathered grain: poles, rails, logs
    "planks": "Planks023A",  # weathered boards: carts, crates
    "canvas": "Fabric066",   # natural linen: tents, banners
    "stone": "Rock020",      # fine grey granite: carved stone
}


def read(archive, asset, map_name, mode):
    data = archive.read("%s_2K-JPG_%s.jpg" % (asset, map_name))
    img = Image.open(io.BytesIO(data)).convert(mode)
    if img.size != (SIZE, SIZE):
        img = img.resize((SIZE, SIZE), Image.LANCZOS)
    return np.asarray(img)


def pack(layer, asset, out=OUT):
    with zipfile.ZipFile(VENDOR / ("%s_2K-JPG.zip" % asset)) as archive:
        color = read(archive, asset, "Color", "RGB")
        height = read(archive, asset, "Displacement", "L").astype(float)
        normal = read(archive, asset, "NormalGL", "RGB")
        rough = read(archive, asset, "Roughness", "L")
        try:
            ao = read(archive, asset, "AmbientOcclusion", "L")
        except KeyError:
            ao = np.full(rough.shape, 255, np.uint8)
    # stretch the height to the full range so every layer blends with the same sharpness
    lo, hi = np.percentile(height, (1, 99))
    height = np.clip((height - lo) / max(hi - lo, 1.0) * 255, 0, 255).astype(np.uint8)
    Image.fromarray(np.dstack([color, height]), "RGBA").save(out / ("%s_albedo.png" % layer))
    Image.fromarray(np.dstack([normal[..., 0], normal[..., 1], rough, ao]), "RGBA").save(out / ("%s_nrao.png" % layer))


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    BARK_OUT.mkdir(parents=True, exist_ok=True)
    for layer, asset in LAYERS.items():
        pack(layer, asset)
        print("packed", layer, "from", asset)
    for bark, asset in BARKS.items():
        pack(bark, asset, BARK_OUT)
        print("packed bark", bark, "from", asset)
    PROPS_OUT.mkdir(parents=True, exist_ok=True)
    for prop, asset in PROPS.items():
        pack(prop, asset, PROPS_OUT)
        print("packed prop", prop, "from", asset)
