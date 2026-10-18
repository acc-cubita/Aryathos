"""The Gloomshard Scavenger: a gaunt, hooded crystal digger (MakeHuman body and CC0 clothes
through MPFB, like the Arkanor bodies) and the dirty pick he fights with (Poly Haven
picke_dirty_01, CC0).

    set BLENDER_USER_RESOURCES=D:/my game/art/vendor/makehuman/blender_env
    blender -b --python tools/art/blender/scavenger.py -- [--shots]

Builds the body (arkanor_mh.build), renders previews with --shots
(art/characters/scavenger/preview), makes it a game character (arkanor_game.convert:
humanoid bone names, one mesh, grip markers) and exports
game/art/characters/scavenger/scavenger.glb. The pick goes to game/art/weapons/pick.glb in
the weapon frame of the rune axe (grip at the origin, haft +Z, point +Y), and the trail
points CharacterModel needs are printed in Godot's frame.
"""
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import arkanor_game as game  # noqa: E402
import arkanor_mh as mh  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "art" / "characters" / "scavenger"
GAME_ART = ROOT / "game" / "art" / "characters" / "scavenger"
PICK_SOURCE = ROOT / "art" / "vendor" / "polyhaven" / "models" / "picke_dirty_01" / "picke_dirty_01_1k.gltf"
PICK = ROOT / "game" / "art" / "weapons" / "pick.glb"
## the scan is 1.12 m long: a little shorter swings with one hand
PICK_SCALE = 0.85
## the fist holds the haft this far (m, after scaling) from its end
PICK_GRIP = 0.12

SCAVENGER = {
    # a lean, wiry man past his prime
    "phenotype": {"gender": 1.0, "age": 0.72, "muscle": 0.45, "weight": 0.32, "proportions": 0.6,
                  "height": 0.5, "cupsize": 0.5, "firmness": 0.5,
                  "race": {"asian": 0.0, "caucasian": 0.85, "african": 0.15}},
    # weathered, unshaven skin
    "skin_mhmat": "jartur69_middleage_slavic_male_with_genitals_and_beard/jartur69_middleage_slavic_male_with_genitals_and_beard.mhmat",
    # hollow cheeks under high cheekbones, a hooked nose, a low suspicious brow
    "targets": {"l-cheek-volume-decr": 0.6, "r-cheek-volume-decr": 0.6, "l-cheek-bones-incr": 0.4,
                "r-cheek-bones-incr": 0.4, "eyebrows-trans-down": 0.3, "eyebrows-angle-down": 0.25,
                "nose-hump-incr": 0.45, "chin-prominent-incr": 0.2},
    "eyebrows": "eyebrow006/eyebrow006.mhclo",
    "eyes": "brown",
    "hair": "",  # the hood covers the head
    "clothes": ["elvs_scruffy_beard1/elvs_scruffy_beard1.mhclo",  # CC-BY Elvaerwyn, see game/CREDITS.md
                "donitz_monk_robe/donitz_monk_robe.mhclo",
                "donitz_monk_robe_hood/donitz_monk_robe_hood.mhclo",
                "culturalibre_male_boots/culturalibre_male_boots.mhclo"],
    "silver": False,
    "x": 0.0,
}
# the robe and hood turn a grimy, faded olive-brown (sRGB), stained by weeks of digging;
# the (ginger) beard a dull dark brown
GRIME = {"donitz_monk_robe": ((0.25, 0.23, 0.17), True), "donitz_monk_robe_hood": ((0.19, 0.18, 0.14), True),
         "elvs_scruffy_beard1": ((0.17, 0.13, 0.1), False)}
# share of triangles kept: the boots (30k triangles) hide under the robe
DECIMATE = {"culturalibre_male_boots": 0.1}


def part(rig, asset):
    return next(o for o in rig.children_recursive if o.type == "MESH" and o.name.endswith(asset))


def stains(h, w, cells=24, seed=7):
    """Soft blotches (about 1 +- 0.5): coarse noise blown up and box-blurred."""
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w), np.float32)
    for scale, weight in ((cells, 0.6), (cells * 3, 0.4)):
        grid = rng.random((scale, scale)).astype(np.float32)
        big = np.repeat(np.repeat(grid, -(-h // scale), axis=0), -(-w // scale), axis=1)[:h, :w]
        k = max(h // scale, 1)
        for axis in (0, 1):
            c = np.cumsum(np.pad(big, [(k, k) if a == axis else (0, 0) for a in (0, 1)], mode="edge"), axis=axis)
            big = (np.take(c, range(2 * k, c.shape[axis]), axis=axis) - np.take(c, range(0, c.shape[axis] - 2 * k), axis=axis)) / (2 * k)
        out += weight * big[:h, :w]
    return 0.5 + (out - out.min()) / max(float(out.max() - out.min()), 1e-6)


def grime(rig, asset, tint, stained):
    """Repaints a texture in `tint` (keeping its weave, folds or strands), stained or not;
    saved to art/characters/scavenger/tex/<asset>.png."""
    for slot in part(rig, asset).material_slots:
        node = next(n for n in slot.material.node_tree.nodes if n.type == "TEX_IMAGE" and n.name == "diffuseTexture")
        w, h = node.image.size
        px = np.empty(w * h * 4, np.float32)
        node.image.pixels.foreach_get(px)
        px = px.reshape(h, w, 4)
        luma = px[..., :3] @ np.array([0.3, 0.59, 0.11], np.float32)
        shade = luma / mh.mean_brightness(node.image) * (stains(h, w) if stained else 1.0)
        colour = np.array(tint, np.float32) * shade[..., None]
        out = bpy.data.images.new(asset, w, h, alpha=True)
        out.pixels.foreach_set(np.dstack([np.clip(colour, 0, 1), px[..., 3:]]).astype(np.float32).ravel())
        (OUT / "tex").mkdir(parents=True, exist_ok=True)
        out.filepath_raw = str(OUT / "tex" / (asset + ".png"))
        out.file_format = "PNG"
        out.save()
        node.image = out


def pick():
    """Imports the scanned pick, puts it in the weapon frame and exports it alone."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(PICK_SOURCE))
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for other in new:
        if other != obj and other.name in bpy.data.objects:
            bpy.data.objects.remove(other)
    co = np.array([v.co[:] for v in obj.data.vertices])
    low, top = co[:, 2].min(), co[:, 2].max()
    axis = co[co[:, 2] < low + 0.3, :2].mean(axis=0)  # the haft's centre line
    head = co[co[:, 2] > top - 0.15]
    point = head[np.argmax(np.abs(head[:, 0] - axis[0]))]
    turn = np.pi / 2 if point[0] > axis[0] else -np.pi / 2  # the point turns to +Y
    grip = Vector((axis[0], axis[1], low + PICK_GRIP / PICK_SCALE))
    obj.data.transform(Matrix.Rotation(turn, 4, "Z") @ Matrix.Scale(PICK_SCALE, 4) @ Matrix.Translation(-grip))
    obj.data.update()
    obj.name = obj.data.name = "pick"
    co = np.array([v.co[:] for v in obj.data.vertices])
    top = co[:, 2].max()
    tip = co[np.argmax(co[:, 1])]
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    PICK.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(PICK), use_selection=True, export_format="GLB", export_yup=True,
                              export_apply=False, export_animations=False, export_image_format="AUTO")
    # Godot frame: (x, z, -y)
    print("pick: %d tris, %.2f m long; trail root (0, %.2f, 0), edge (%.2f, %.2f, %.2f) -> %s" % (
        sum(len(p.vertices) - 2 for p in obj.data.polygons), top - co[:, 2].min(),
        top - 0.06, tip[0], tip[2], -tip[1], PICK))


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    mh.clear_scene()
    basemesh, rig = mh.build("scavenger", SCAVENGER)
    for asset, (tint, stained) in GRIME.items():
        grime(rig, asset, tint, stained)
    for asset, ratio in DECIMATE.items():
        mod = part(rig, asset).modifiers.new("decimate", "DECIMATE")
        mod.ratio = ratio  # applied with the other modifiers by arkanor_game.bake_mesh
    print("scavenger: tris", mh.stats(basemesh))
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "scavenger_mh.blend"))
    if "--shots" in args:
        mh.shots(str(OUT / "preview"), ["scavenger"])
    rig, body = game.convert("scavenger", "scavenger", silver=False)
    print("scavenger: %d bones, %d tris, materials %s -> %s" % (
        len(rig.data.bones), sum(len(p.vertices) - 2 for p in body.data.polygons),
        [m.name for m in body.data.materials], game.export("scavenger", GAME_ART)))
    pick()
