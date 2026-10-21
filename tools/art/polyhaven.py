"""Downloads CC0 models and textures from Poly Haven (polyhaven.com, all CC0).

    python tools/art/polyhaven.py models <id> [<id> ...]    (1k glTF)
    python tools/art/polyhaven.py textures <id> [<id> ...]  (2k diffuse, normal (GL), ARM)
    python tools/art/polyhaven.py sources <id> [<id> ...]   (1k glTF, vendor folder only)

Models go to art/vendor/polyhaven/models/<id>/ and, for the game's scanned props
(world/props.gd), are copied to game/art/props/<id>/<id>.gltf with their textures
("sources" stop at the vendor folder: Blender scripts make game files from them).
Textures go to art/vendor/polyhaven/textures/<id>/<id>_<map>_2k.jpg, for the Blender
scripts that build with them. Files already there are not fetched again.
"""
import json
import shutil
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VENDOR = ROOT / "art" / "vendor" / "polyhaven"
PROPS = ROOT / "game" / "art" / "props"
API = "https://api.polyhaven.com/files/"
## texture maps fetched (Poly Haven's names) and the names they are saved under
MAPS = {"Diffuse": "diff", "nor_gl": "nor_gl", "arm": "arm"}


def fetch(url, path, tries=4):
    if path.exists():
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "Aryathos-art-tools"})
    for attempt in range(tries):  # (the connection drops now and then)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                data = response.read()
            break
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if attempt == tries - 1:
                raise
    path.write_bytes(data)
    print("polyhaven: got", path.relative_to(ROOT))


def files(asset):
    request = urllib.request.Request(API + asset, headers={"User-Agent": "Aryathos-art-tools"})
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def source(asset, resolution="1k"):
    entry = files(asset)["gltf"][resolution]["gltf"]
    folder = VENDOR / "models" / asset
    gltf = folder / ("%s_%s.gltf" % (asset, resolution))
    fetch(entry["url"], gltf)
    for name, include in entry.get("include", {}).items():
        fetch(include["url"], folder / name)
    return entry, folder, gltf


def model(asset, resolution="1k"):
    entry, folder, gltf = source(asset, resolution)
    # the game's copy: <id>.gltf beside its bin and textures
    out = PROPS / asset
    out.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(gltf, out / (asset + ".gltf"))
    for name in entry.get("include", {}):
        (out / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(folder / name, out / name)


def texture(asset, resolution="2k"):
    found = files(asset)
    for key, short in MAPS.items():
        fetch(found[key][resolution]["jpg"]["url"],
              VENDOR / "textures" / asset / ("%s_%s_%s.jpg" % (asset, short, resolution)))


if __name__ == "__main__":
    kind, assets = sys.argv[1], sys.argv[2:]
    for name in assets:
        {"models": model, "textures": texture, "sources": source}[kind](name)
