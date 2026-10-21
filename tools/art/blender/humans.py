"""The people of Silverrun Vale who are not Arkanor heroes: MakeHuman bodies with CC0
clothes through MPFB, like the Arkanor bodies (CHARACTERS):
  * scavenger: a gaunt, hooded crystal digger of the Gloomshard gangs, with the dirty pick
    he fights with (Poly Haven picke_dirty_01, CC0);
  * acolyte: a woman of the Eclipse Hand cult in a hood and robe of deep violet;
  * thalos: Warden Thalos, an old Arkanor warden in mail and the Watch's blue;
  * ivren: Magister Ivren, an Arkanor arcanist of the Spire in white and blue robes;
  * bren: Quartermaster Bren, a short, broad Orebound with a braided copper beard;
  * durgan, hilde: Thane Durgan and Hilde Emberhand of Hammerfall Hold (Orebound);
  * zealot: a shaven, tattooed warrior of the Eclipse Hand in violet-black, with an ornate
    mace (Poly Haven ornate_medieval_mace, CC0).

    set BLENDER_USER_RESOURCES=D:/my game/art/vendor/makehuman/blender_env
    blender -b --python tools/art/blender/humans.py -- [scavenger] [acolyte] [mace] [--shots]

Per character: builds the body (arkanor_mh.build), dyes its cloth (grime), thins hidden
parts (decimate), renders previews with --shots (art/characters/<key>/preview), makes it a
game character (arkanor_game.convert: humanoid bone names, one mesh, grip markers) and
exports game/art/characters/<key>/<key>.glb. A character's "weapon" (a WEAPONS key; alone
on the command line it is made by itself) becomes game/art/weapons/<weapon>.glb in the
weapon frame of the rune axe (grip at the origin, haft +Z, point +Y), with the trail points
CharacterModel needs printed in Godot's frame.
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
SCANS = ROOT / "art" / "vendor" / "polyhaven" / "models"
## Scanned weapons (Poly Haven, CC0; tools/art/polyhaven.py sources <id>): the scan, its
## scale, and how far (m, after scaling) from the haft's end the fist holds it.
WEAPONS = {
    # the pick scan is 1.12 m long: a little shorter swings with one hand
    "pick": (SCANS / "picke_dirty_01" / "picke_dirty_01_1k.gltf", 0.85, 0.12),
    "mace": (SCANS / "ornate_medieval_mace" / "ornate_medieval_mace_1k.gltf", 1.0, 0.1),
}

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
    # the robe and hood turn a grimy, faded olive-brown (sRGB), stained by weeks of
    # digging; the (ginger) beard a dull dark brown
    "grime": {"donitz_monk_robe": ((0.25, 0.23, 0.17), True), "donitz_monk_robe_hood": ((0.19, 0.18, 0.14), True),
              "elvs_scruffy_beard1": ((0.17, 0.13, 0.1), False)},
    # share of triangles kept: the boots (30k triangles) hide under the robe
    "decimate": {"culturalibre_male_boots": 0.1},
    "weapon": "pick",
}
ACOLYTE = {
    # a slight, pale young woman with violet paint around the eyes
    "phenotype": {"gender": 0.0, "age": 0.45, "muscle": 0.35, "weight": 0.35, "proportions": 0.75,
                  "height": 0.55, "cupsize": 0.45, "firmness": 0.55,
                  "race": {"asian": 0.1, "caucasian": 0.9, "african": 0.0}},
    "skin_mhmat": "toigo_light_skin_female_with_violet_makeup/toigo_light_skin_female_with_violet_makeup.mhmat",
    # sharp cheekbones, a narrow chin, brows tilted up: the calm of a zealot
    "targets": {"l-cheek-bones-incr": 0.5, "r-cheek-bones-incr": 0.5, "l-cheek-volume-decr": 0.3,
                "r-cheek-volume-decr": 0.3, "eyebrows-angle-up": 0.3, "chin-prominent-incr": 0.15},
    "eyebrows": "eyebrow009/eyebrow009.mhclo",
    "eyes": "grey",
    "hair": "",  # under the hood
    "clothes": ["donitz_monk_robe/donitz_monk_robe.mhclo",
                "donitz_monk_robe_hood/donitz_monk_robe_hood.mhclo",
                "toigo_ankle_boots_female/toigo_ankle_boots_female.mhclo"],
    "silver": False,
    "x": 0.0,
    # deep violet-black robes, the hood darkest (the Eclipse)
    "grime": {"donitz_monk_robe": ((0.15, 0.09, 0.21), False), "donitz_monk_robe_hood": ((0.08, 0.05, 0.11), False),
              "toigo_ankle_boots_female": ((0.09, 0.07, 0.09), False)},
    "decimate": {"toigo_ankle_boots_female": 0.2},
}
THALOS = {
    # a big man grown old on watch: silver hair and beard (Arkanor), heavy brow
    "phenotype": {"gender": 1.0, "age": 0.88, "muscle": 0.75, "weight": 0.65, "proportions": 0.8,
                  "height": 0.6, "cupsize": 0.5, "firmness": 0.5,
                  "race": {"asian": 0.0, "caucasian": 1.0, "african": 0.0}},
    "skin_mhmat": "old_caucasian_male/old_caucasian_male.mhmat",
    "targets": {"head-square": 0.4, "eyebrows-trans-down": 0.35, "eyebrows-angle-down": 0.3,
                "chin-width-incr": 0.35, "nose-width1-incr": 0.25},
    "eyebrows": "eyebrow010/eyebrow010.mhclo",
    "eyes": "grey",
    "hair": "short02/short02.mhclo",
    "clothes": ["grinsegold_full_beard/grinsegold_full_beard.mhclo",  # CC-BY grinsegold, see game/CREDITS.md
                "rehmanpolanski_viking_tunic/rehmanpolanski_viking_tunic.mhclo",
                "rehmanpolanski_viking_pants/rehmanpolanski_viking_pants.mhclo",
                "rehmanpolanski_viking_boots/rehmanpolanski_viking_boots.mhclo"],
    "silver": True,
    "x": 0.0,
    # the beard ships black: silver like his hair
    "grime": {"grinsegold_full_beard": ((0.66, 0.65, 0.62), False)},
    # the Watch's colours: mail and cloth shifted to steel blue (multipliers on the texture)
    "tint": {"rehmanpolanski_viking_tunic": (0.75, 0.9, 1.35), "rehmanpolanski_viking_pants": (0.7, 0.85, 1.3)},
}
IVREN = {
    # a slender woman past her middle years: silver hair (Arkanor), keen face
    "phenotype": {"gender": 0.0, "age": 0.68, "muscle": 0.4, "weight": 0.4, "proportions": 0.8,
                  "height": 0.6, "cupsize": 0.45, "firmness": 0.45,
                  "race": {"asian": 0.0, "caucasian": 1.0, "african": 0.0}},
    "skin_mhmat": "middleage_caucasian_female/middleage_caucasian_female.mhmat",
    "targets": {"l-cheek-bones-incr": 0.3, "r-cheek-bones-incr": 0.3, "chin-prominent-incr": 0.2,
                "nose-point-width-decr": 0.2},
    "eyebrows": "eyebrow002/eyebrow002.mhclo",
    "eyes": "ice",
    "hair": "long01/long01.mhclo",
    "clothes": ["donitz_monk_robe/donitz_monk_robe.mhclo",
                "donitz_monk_robe_hood_off/donitz_monk_robe_hood_off.mhclo",
                "toigo_ankle_boots_female/toigo_ankle_boots_female.mhclo"],
    "silver": True,
    "x": 0.0,
    # the Spire's colours: pale blue-grey robes (pure white glares in the sun), a deep blue
    # hood about the shoulders
    "grime": {"donitz_monk_robe": ((0.5, 0.54, 0.62), False), "donitz_monk_robe_hood_off": ((0.14, 0.22, 0.5), False),
              "toigo_ankle_boots_female": ((0.12, 0.12, 0.16), False)},
    "decimate": {"toigo_ankle_boots_female": 0.2},
}
BREN = {
    # an Orebound: short, broad and heavy-handed, tattooed, a braided copper beard
    "phenotype": {"gender": 1.0, "age": 0.62, "muscle": 0.9, "weight": 0.85, "proportions": 0.25,
                  "height": 0.0, "cupsize": 0.5, "firmness": 0.5,
                  "race": {"asian": 0.0, "caucasian": 1.0, "african": 0.0}},
    "skin_mhmat": "rehmanpolanski_skin_viking_tattoos/rehmanpolanski_skin_viking_tattoos.mhmat",
    "targets": {"head-square": 0.5, "nose-width1-incr": 0.5, "nose-volume-incr": 0.4, "chin-width-incr": 0.5,
                "eyebrows-trans-down": 0.3},
    "eyebrows": "eyebrow007/eyebrow007.mhclo",
    "eyes": "brown",
    "hair": "short02/short02.mhclo",
    "clothes": ["rehmanpolanski_beard_viking/rehmanpolanski_beard_viking.mhclo",
                "rehmanpolanski_viking_tunic/rehmanpolanski_viking_tunic.mhclo",
                "rehmanpolanski_viking_pants/rehmanpolanski_viking_pants.mhclo",
                "rehmanpolanski_viking_boots/rehmanpolanski_viking_boots.mhclo"],
    "silver": False,
    "x": 0.0,
    # copper beard and hair; a merchant's warm browns
    "grime": {"rehmanpolanski_beard_viking": ((0.48, 0.24, 0.12), False), "short02": ((0.36, 0.18, 0.09), False)},
    "tint": {"rehmanpolanski_viking_tunic": (1.25, 1.0, 0.72), "rehmanpolanski_viking_pants": (1.2, 1.0, 0.75)},
}
DURGAN = {
    # Thane of Hammerfall Hold, an old Orebound: short, very broad, bald, a long iron-grey
    # beard, in the Azure Concord's deep blue
    "phenotype": {"gender": 1.0, "age": 0.85, "muscle": 0.95, "weight": 0.9, "proportions": 0.2,
                  "height": 0.0, "cupsize": 0.5, "firmness": 0.5,
                  "race": {"asian": 0.0, "caucasian": 1.0, "african": 0.0}},
    "skin_mhmat": "old_caucasian_male/old_caucasian_male.mhmat",
    "targets": {"head-square": 0.7, "nose-width1-incr": 0.6, "nose-volume-incr": 0.5, "chin-width-incr": 0.5,
                "eyebrows-trans-down": 0.5, "eyebrows-angle-down": 0.4, "head-age-incr": 0.4},
    "eyebrows": "eyebrow010/eyebrow010.mhclo",
    "eyes": "grey",
    "hair": "",
    "clothes": ["grinsegold_full_beard/grinsegold_full_beard.mhclo",  # CC-BY grinsegold, see game/CREDITS.md
                "rehmanpolanski_viking_tunic/rehmanpolanski_viking_tunic.mhclo",
                "rehmanpolanski_viking_pants/rehmanpolanski_viking_pants.mhclo",
                "rehmanpolanski_viking_boots/rehmanpolanski_viking_boots.mhclo"],
    "silver": False,
    "x": 0.0,
    "grime": {"grinsegold_full_beard": ((0.64, 0.63, 0.6), False)},
    "tint": {"rehmanpolanski_viking_tunic": (0.55, 0.75, 1.5), "rehmanpolanski_viking_pants": (0.75, 0.7, 0.75)},
}
HILDE = {
    # Hilde Emberhand, smith of Hammerfall: an Orebound woman, short and strong-armed, copper
    # hair cropped short, in soot-dark working clothes
    "phenotype": {"gender": 0.0, "age": 0.55, "muscle": 0.85, "weight": 0.75, "proportions": 0.3,
                  "height": 0.05, "cupsize": 0.45, "firmness": 0.6,
                  "race": {"asian": 0.0, "caucasian": 1.0, "african": 0.0}},
    "skin_mhmat": "toigo_light_skin_female_freckles/toigo_light_skin_female_freckles.mhmat",
    "targets": {"head-square": 0.4, "nose-width1-incr": 0.3, "chin-width-incr": 0.3},
    "eyebrows": "eyebrow001/eyebrow001.mhclo",
    "eyes": "brown",
    "hair": "short02/short02.mhclo",
    "clothes": ["rehmanpolanski_viking_tunic/rehmanpolanski_viking_tunic.mhclo",
                "rehmanpolanski_viking_pants/rehmanpolanski_viking_pants.mhclo",
                "rehmanpolanski_viking_boots/rehmanpolanski_viking_boots.mhclo"],
    "silver": False,
    "x": 0.0,
    "grime": {"short02": ((0.5, 0.22, 0.1), False)},
    "tint": {"rehmanpolanski_viking_tunic": (0.7, 0.62, 0.55), "rehmanpolanski_viking_pants": (0.6, 0.55, 0.5)},
}
ZEALOT = {
    # a warrior of the Eclipse Hand: a hard man in his prime, head shaven, the cult's
    # tattoos on his arms, a short dark beard, in violet-black
    "phenotype": {"gender": 1.0, "age": 0.5, "muscle": 0.8, "weight": 0.5, "proportions": 0.75,
                  "height": 0.6, "cupsize": 0.5, "firmness": 0.5,
                  "race": {"asian": 0.0, "caucasian": 0.9, "african": 0.1}},
    "skin_mhmat": "rehmanpolanski_skin_viking_tattoos/rehmanpolanski_skin_viking_tattoos.mhmat",
    # gaunt cheeks, a heavy brow pulled down: the stare of the true believer
    "targets": {"l-cheek-volume-decr": 0.4, "r-cheek-volume-decr": 0.4, "l-cheek-bones-incr": 0.4,
                "r-cheek-bones-incr": 0.4, "eyebrows-trans-down": 0.4, "eyebrows-angle-down": 0.45,
                "chin-prominent-incr": 0.3},
    "eyebrows": "eyebrow006/eyebrow006.mhclo",
    "eyes": "grey",
    "hair": "",
    "clothes": ["elvs_scruffy_beard1/elvs_scruffy_beard1.mhclo",  # CC-BY Elvaerwyn, see game/CREDITS.md
                "rehmanpolanski_viking_tunic/rehmanpolanski_viking_tunic.mhclo",
                "rehmanpolanski_viking_pants/rehmanpolanski_viking_pants.mhclo",
                "rehmanpolanski_viking_boots/rehmanpolanski_viking_boots.mhclo"],
    "silver": False,
    "x": 0.0,
    # the tunic violet-black, the pants and boots near black (repainted: the tunic's own
    # embroidery would show through a tint)
    "grime": {"elvs_scruffy_beard1": ((0.08, 0.07, 0.07), False),
              "rehmanpolanski_viking_tunic": ((0.2, 0.12, 0.27), True),
              "rehmanpolanski_viking_pants": ((0.1, 0.085, 0.11), False),
              "rehmanpolanski_viking_boots": ((0.13, 0.1, 0.1), False)},
    "weapon": "mace",
}
CHARACTERS = {"scavenger": SCAVENGER, "acolyte": ACOLYTE, "thalos": THALOS, "ivren": IVREN, "bren": BREN,
              "durgan": DURGAN, "hilde": HILDE, "zealot": ZEALOT}


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


def grime(rig, key, asset, tint, stained):
    """Repaints a texture in `tint` (keeping its weave, folds or strands), stained or not;
    saved to art/characters/<key>/tex/<asset>.png."""
    for slot in part(rig, asset).material_slots:
        node = next(n for n in slot.material.node_tree.nodes if n.type == "TEX_IMAGE" and n.name == "diffuseTexture")
        w, h = node.image.size
        px = np.empty(w * h * 4, np.float32)
        node.image.pixels.foreach_get(px)
        px = px.reshape(h, w, 4)
        luma = px[..., :3] @ np.array([0.3, 0.59, 0.11], np.float32)
        shade = luma / mh.mean_brightness(node.image) * (stains(h, w) if stained else 1.0)
        colour = np.array(tint, np.float32) * shade[..., None]
        out = bpy.data.images.new("%s_%s" % (key, asset), w, h, alpha=True)
        out.pixels.foreach_set(np.dstack([np.clip(colour, 0, 1), px[..., 3:]]).astype(np.float32).ravel())
        folder = ROOT / "art" / "characters" / key / "tex"
        folder.mkdir(parents=True, exist_ok=True)
        out.filepath_raw = str(folder / (asset + ".png"))
        out.file_format = "PNG"
        out.save()
        node.image = out


def tint(rig, key, asset, factors):
    """Shifts a texture's colours by `factors` (per channel) without touching its pattern
    (mail stays mail, cloth stays cloth); saved to art/characters/<key>/tex/<asset>.png."""
    for slot in part(rig, asset).material_slots:
        node = next(n for n in slot.material.node_tree.nodes if n.type == "TEX_IMAGE" and n.name == "diffuseTexture")
        src = node.image
        w, h = src.size
        px = np.empty(w * h * 4, np.float32)
        src.pixels.foreach_get(px)
        px = px.reshape(h, w, 4)
        luma = (px[..., :3] @ np.array([0.3, 0.59, 0.11], np.float32))[..., None]
        colour = px[..., :3] * np.array(factors, np.float32)
        # keep the brightness where it was: the shift changes hue, not light
        colour *= luma / np.maximum(colour @ np.array([0.3, 0.59, 0.11], np.float32), 1e-4)[..., None]
        out = bpy.data.images.new("%s_%s" % (key, asset), w, h, alpha=True)
        out.pixels.foreach_set(np.dstack([np.clip(colour, 0, 1), px[..., 3:]]).astype(np.float32).ravel())
        folder = ROOT / "art" / "characters" / key / "tex"
        folder.mkdir(parents=True, exist_ok=True)
        out.filepath_raw = str(folder / (asset + ".png"))
        out.file_format = "PNG"
        out.save()
        node.image = out


def weapon(name):
    """Imports a scanned weapon, puts it in the weapon frame and exports it alone."""
    source, scale, hold = WEAPONS[name]
    path = ROOT / "game" / "art" / "weapons" / (name + ".glb")
    mh.clear_scene()
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(source))
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
    grip = Vector((axis[0], axis[1], low + hold / scale))
    obj.data.transform(Matrix.Rotation(turn, 4, "Z") @ Matrix.Scale(scale, 4) @ Matrix.Translation(-grip))
    obj.data.update()
    obj.name = obj.data.name = name
    co = np.array([v.co[:] for v in obj.data.vertices])
    top = co[:, 2].max()
    tip = co[np.argmax(co[:, 1])]
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(path), use_selection=True, export_format="GLB", export_yup=True,
                              export_apply=False, export_animations=False, export_image_format="AUTO")
    # Godot frame: (x, z, -y)
    print("%s: %d tris, %.2f m long; trail root (0, %.2f, 0), edge (%.2f, %.2f, %.2f) -> %s" % (
        name, sum(len(p.vertices) - 2 for p in obj.data.polygons), top - co[:, 2].min(),
        top - 0.06, tip[0], tip[2], -tip[1], path))


def make(key, shots):
    spec = CHARACTERS[key]
    out = ROOT / "art" / "characters" / key
    mh.clear_scene()
    bpy.ops.outliner.orphans_purge(do_recursive=True)  # no "body.001": each character starts clean
    basemesh, rig = mh.build(key, spec)
    for asset, (colour, stained) in spec.get("grime", {}).items():
        grime(rig, key, asset, colour, stained)
    for asset, factors in spec.get("tint", {}).items():
        tint(rig, key, asset, factors)
    for asset, ratio in spec.get("decimate", {}).items():
        mod = part(rig, asset).modifiers.new("decimate", "DECIMATE")
        mod.ratio = ratio  # applied with the other modifiers by arkanor_game.bake_mesh
    print("%s: tris %s" % (key, mh.stats(basemesh)))
    out.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out / ("%s_mh.blend" % key)))
    if shots:
        mh.shots(str(out / "preview"), [key])
    rig, body = game.convert(key, key, silver=spec.get("silver", False))
    print("%s: %d bones, %d tris, materials %s -> %s" % (
        key, len(rig.data.bones), sum(len(p.vertices) - 2 for p in body.data.polygons),
        [m.name for m in body.data.materials], game.export(key, ROOT / "game" / "art" / "characters" / key)))
    if "weapon" in spec:
        weapon(spec["weapon"])


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for key in [a for a in args if a in WEAPONS]:
        weapon(key)
    for key in [a for a in args if a in CHARACTERS] or ([] if any(a in WEAPONS for a in args) else list(CHARACTERS)):
        make(key, "--shots" in args)
