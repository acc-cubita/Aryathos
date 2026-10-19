"""Realistic Arkanor bodies from MakeHuman (MPFB2 in Blender; CC0 base mesh, skins,
eyebrows, eyelashes, hair and beards from the MakeHuman asset packs).

MPFB and its asset packs live in a project-local Blender profile, so the user's own
Blender stays untouched:
    set BLENDER_USER_RESOURCES=D:/my game/art/vendor/makehuman/blender_env
    blender -b --python tools/art/blender/arkanor_mh.py -- [--unpack] [--list] [--build [--shots]]

--unpack  extracts the asset pack zips (art/vendor/makehuman/*_cc0.zip) into MPFB's data.
--list    prints the skins, brows, lashes, hair and clothes available.
--build   builds both bodies and saves art/characters/arkanor/arkanor_mh.blend.
--shots   then renders full-body and face views into ARKANOR_SHOTS
          (default: art/characters/arkanor/mh_preview).
"""
import os
import sys
import zipfile
from pathlib import Path

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
VENDOR = ROOT / "art" / "vendor" / "makehuman"
OUT = ROOT / "art" / "characters" / "arkanor"
# CC0 packs, plus hair02 and bodyparts06 (CC-BY: credit Elvaerwyn and grinsegold, see art/CREDITS.md)
PACKS = ["makehuman_system_assets_cc0", "skins02_cc0", "skins01_cc0", "bodyparts05_cc0", "eyebrows01_cc0",
         "suits02_cc0", "shoes01_cc0", "hair02_ccby", "bodyparts06_cc-by"]

from bl_ext.user_default.mpfb.services.assetservice import AssetService  # noqa: E402
from bl_ext.user_default.mpfb.services.clothesservice import ClothesService  # noqa: E402
from bl_ext.user_default.mpfb.services.humanservice import HumanService  # noqa: E402
from bl_ext.user_default.mpfb.services.locationservice import LocationService  # noqa: E402
from bl_ext.user_default.mpfb.services.objectservice import ObjectService  # noqa: E402
from bl_ext.user_default.mpfb.services.targetservice import TargetService  # noqa: E402

# The Aethermancer's robe (CC0 Donitz) with its hood down about the shoulders, dyed in the
# Azure Concord's colours: a deep azure robe and a silver-grey cowl (Magister Ivren, of the
# same order, wears the reverse).
MAGE_ROBES = ["donitz_monk_robe/donitz_monk_robe.mhclo", "donitz_monk_robe_hood_off/donitz_monk_robe_hood_off.mhclo"]
MAGE_DYES = {"donitz_monk_robe": (0.08, 0.14, 0.3), "donitz_monk_robe_hood_off": (0.6, 0.62, 0.68)}
MAGE_DECIMATE = {"donitz_monk_robe": 0.5, "donitz_monk_robe_hood_off": 0.5}  # 20k and 9k triangles as made

# MakeHuman macro sliders (0..1; age 0.5 = 25 years, 1.0 = 90) and the CC0 assets each
# body wears (paths relative to MPFB's data/<kind> folders).
BODIES = {
    "male": {
        "phenotype": {"gender": 1.0, "age": 0.8, "muscle": 1.0, "weight": 0.75, "proportions": 0.9,
                      "height": 0.55, "cupsize": 0.5, "firmness": 0.5,
                      "race": {"asian": 0.0, "caucasian": 1.0, "african": 0.0}},
        # a warrior's build, matched in front, side and back silhouettes to a reference hero
        # (heights in eighths of the body): broad shoulders and lats, a deep chest and a
        # thick waist, heavy arms and calves, big hands and feet, legs a little short
        "physique": {"measure-shoulder-dist-incr": 0.5, "torso-vshape-incr": 0.8, "torso-muscle-pectoral-incr": 1.0,
                     "torso-muscle-dorsi-incr": 1.0, "torso-scale-depth-incr": 1.0, "torso-scale-horiz-incr": 0.5,
                     "measure-waist-circ-incr": 1.0, "measure-hips-circ-incr": 0.4, "stomach-pregnant-incr": 0.1,
                     "measure-neck-circ-incr": 0.6, "neck-scale-horiz-incr": 0.3, "measure-neck-height-decr": 0.5,
                     "measure-upperarm-circ-incr": 0.8, "measure-wrist-circ-incr": 0.6, "measure-calf-circ-incr": 0.8,
                     "upperlegs-height-decr": 0.3, "buttocks-volume-incr": 0.2,
                     **{side + part: value for side in ("l-", "r-") for part, value in (
                         ("upperarm-muscle-incr", 1.0), ("upperarm-shoulder-muscle-incr", 0.6),
                         ("lowerarm-muscle-incr", 1.0), ("lowerarm-scale-horiz-incr", 1.0), ("lowerarm-fat-incr", 0.5),
                         ("upperleg-muscle-incr", 0.2), ("upperleg-scale-depth-incr", 0.5), ("upperleg-fat-decr", 0.5),
                         ("lowerleg-muscle-incr", 1.0), ("hand-scale-incr", 1.0), ("foot-scale-incr", 1.0))}},
        "skin_mhmat": "jartur69_old_slavic_male_with_genitals_and_beard/jartur69_old_slavic_male_with_genitals_and_beard.mhmat",
        # a broad, weathered face: square jaw, heavy brow pulled low, wide nose
        "targets": {"head-square": 0.6, "head-age-incr": 0.4, "forehead-trans-forward": 0.35,
                    "eyebrows-trans-down": 0.45, "eyebrows-angle-down": 0.35, "chin-width-incr": 0.5,
                    "chin-prominent-incr": 0.35, "chin-bones-incr": 0.45, "nose-width1-incr": 0.4,
                    "nose-flaring-incr": 0.3, "nose-hump-incr": 0.35, "nose-volume-incr": 0.3},
        "eyebrows": "eyebrow010/eyebrow010.mhclo",
        "eyes": "lightblue",
        "hair": "ponytail01/ponytail01.mhclo",  # swept back and tied
        "clothes": ["elvs_scruffy_beard1/elvs_scruffy_beard1.mhclo",
                    "rehmanpolanski_moustache_viking/rehmanpolanski_moustache_viking.mhclo",
                    "rehmanpolanski_viking_tunic/rehmanpolanski_viking_tunic.mhclo",
                    "rehmanpolanski_viking_pants/rehmanpolanski_viking_pants.mhclo",
                    "rehmanpolanski_viking_boots/rehmanpolanski_viking_boots.mhclo"],
        "x": -0.55,
        # more looks for character creation, fitted too and hidden in the game until
        # chosen (CharacterModel.LOOKS): hair styles and beards
        "variants": {"hair": ["short02/short02.mhclo", "long01/long01.mhclo", "braid01/braid01.mhclo"],
                     "clothes": ["grinsegold_full_beard/grinsegold_full_beard.mhclo",  # CC-BY grinsegold
                                 "rehmanpolanski_beard_viking/rehmanpolanski_beard_viking.mhclo"] + MAGE_ROBES},
        # parts left as their own meshes so the game can show or hide them (tunic and
        # trousers give way to the robe of the Aethermancer, over the same boots)
        "variant_parts": ["ponytail01", "short02", "long01", "braid01", "elvs_scruffy_beard1",
                          "rehmanpolanski_moustache_viking", "grinsegold_full_beard", "rehmanpolanski_beard_viking",
                          "rehmanpolanski_viking_tunic", "rehmanpolanski_viking_pants", "donitz_monk_robe",
                          "donitz_monk_robe_hood_off"],
        "dye": MAGE_DYES,
        "decimate": MAGE_DECIMATE,
        # the other faces of character creation, as target changes on top of "targets"
        # (the weathered face above is the first)
        "faces": {
            # long and fine: oval head, narrow straight nose, high cheekbones
            "noble": {"head-square": 0.0, "head-oval": 0.8, "nose-width1-incr": 0.0, "nose-width1-decr": 0.5,
                      "nose-flaring-incr": 0.0, "nose-hump-incr": 0.0, "nose-scale-vert-incr": 0.5,
                      "nose-point-width-decr": 0.5, "l-cheek-bones-incr": 0.8, "r-cheek-bones-incr": 0.8,
                      "chin-width-incr": 0.0, "chin-height-incr": 0.4, "chin-bones-incr": 0.2,
                      "eyebrows-trans-down": 0.1, "forehead-trans-forward": 0.1},
            # heavy and hard: jutting brow over narrowed eyes, thin set mouth, big jaw
            "stern": {"head-rectangular": 0.7, "forehead-trans-forward": 1.0, "eyebrows-trans-down": 1.0,
                      "eyebrows-angle-down": 1.0, "l-eye-height2-decr": 0.6, "r-eye-height2-decr": 0.6,
                      "mouth-upperlip-volume-decr": 0.7, "mouth-lowerlip-volume-decr": 0.5, "nose-width1-incr": 0.6,
                      "chin-prominent-incr": 0.9, "chin-width-incr": 1.0, "chin-bones-incr": 1.0},
            # gaunt and sharp: hooked nose, hollow cheeks under hard cheekbones, narrow chin
            "hawk": {"head-square": 0.1, "head-triangular": 0.6, "nose-hump-incr": 1.0, "nose-point-down": 0.8,
                     "nose-curve-convex": 0.8, "nose-width1-incr": 0.0, "nose-scale-vert-incr": 0.6,
                     "nose-scale-depth-incr": 0.5, "l-cheek-volume-decr": 1.0, "r-cheek-volume-decr": 1.0,
                     "l-cheek-bones-incr": 0.9, "r-cheek-bones-incr": 0.9, "chin-width-incr": 0.0,
                     "chin-width-decr": 0.3, "chin-prominent-incr": 0.7, "eyebrows-angle-down": 0.6},
        },
    },
    "female": {
        "phenotype": {"gender": 0.0, "age": 0.55, "muscle": 0.72, "weight": 0.5, "proportions": 0.85,
                      "height": 0.57, "cupsize": 0.5, "firmness": 0.6,
                      "race": {"asian": 0.0, "caucasian": 1.0, "african": 0.0}},
        "skin_mhmat": "toigo_light_skin_female_freckles/toigo_light_skin_female_freckles.mhmat",
        # a lean, determined face
        "targets": {"head-oval": 0.4, "chin-prominent-incr": 0.2,
                    "eyebrows-angle-up": 0.2, "nose-point-width-decr": 0.2},
        "eyebrows": "eyebrow001/eyebrow001.mhclo",
        "eyes": "bluegreen",
        "hair": "elvs_braid_bun/elvs_braid_bun.mhclo",
        "clothes": ["culturalibre_heroine_suit_2/culturalibre_heroine_suit_2.mhclo",
                    "culturalibre_heroine_boots_1/culturalibre_heroine_boots_1.mhclo"],
        # the concept's navy suit with silver trim (the assets ship black and red)
        "recolour": {"culturalibre_heroine_suit_2": ((0.1, 0.17, 0.36), (0.78, 0.8, 0.84)),
                     "culturalibre_heroine_boots_1": ((0.09, 0.14, 0.3), (0.78, 0.8, 0.84))},
        # pieces that must sit over the suit (meters pushed out along their normals)
        "push": {"culturalibre_heroine_boots_1": 0.006},
        "x": 0.55,
        "variants": {"hair": ["long01/long01.mhclo", "braid01/braid01.mhclo",
                              "short03/short03.mhclo"],
                     # over the suit, with ankle boots for the thigh-high ones (which show through)
                     "clothes": MAGE_ROBES + ["toigo_ankle_boots_female/toigo_ankle_boots_female.mhclo"]},
        "variant_parts": ["elvs_braid_bun", "long01", "braid01", "short03", "culturalibre_heroine_boots_1",
                          "donitz_monk_robe", "donitz_monk_robe_hood_off", "toigo_ankle_boots_female"],
        "dye": dict(MAGE_DYES, toigo_ankle_boots_female=(0.1, 0.1, 0.13)),
        "decimate": dict(MAGE_DECIMATE, toigo_ankle_boots_female=0.2),  # 30k triangles as made
        "faces": {
            # fine and high-born: high cheekbones, long straight nose, full upper lip
            "noble": {"head-oval": 0.9, "l-cheek-bones-incr": 0.9, "r-cheek-bones-incr": 0.9,
                      "nose-scale-vert-incr": 0.4, "nose-width1-decr": 0.5, "nose-point-up": 0.3,
                      "nose-scale-depth-incr": 0.3, "mouth-upperlip-volume-incr": 0.5,
                      "mouth-lowerlip-volume-incr": 0.3, "chin-height-incr": 0.4, "chin-width-decr": 0.3,
                      "eyebrows-angle-up": 0.5},
            # sharp and fierce: diamond head, brows pulled down over narrowed eyes, lean cheeks, strong chin
            "fierce": {"head-oval": 0.0, "head-diamond": 0.8, "eyebrows-angle-up": 0.0, "eyebrows-angle-down": 0.9,
                       "eyebrows-trans-down": 0.7, "l-eye-height2-decr": 0.4, "r-eye-height2-decr": 0.4,
                       "l-cheek-bones-incr": 0.9, "r-cheek-bones-incr": 0.9, "l-cheek-volume-decr": 0.7,
                       "r-cheek-volume-decr": 0.7, "chin-prominent-incr": 0.9, "nose-hump-incr": 0.6,
                       "nose-scale-vert-incr": 0.3, "mouth-scale-horiz-decr": 0.3, "mouth-upperlip-volume-decr": 0.3},
            # soft and kind: rounder face, wider eyes, small upturned nose, fuller lips, raised brows
            "gentle": {"head-oval": 0.1, "head-round": 0.8, "l-cheek-volume-incr": 0.8, "r-cheek-volume-incr": 0.8,
                       "l-eye-scale-incr": 0.4, "r-eye-scale-incr": 0.4, "l-eye-height2-incr": 0.3,
                       "r-eye-height2-incr": 0.3, "nose-scale-vert-decr": 0.4, "nose-point-up": 0.7,
                       "nose-point-width-decr": 0.0, "nose-width1-decr": 0.2, "mouth-upperlip-volume-incr": 0.6,
                       "mouth-lowerlip-volume-incr": 0.7, "eyebrows-angle-up": 0.7, "chin-prominent-incr": 0.0,
                       "chin-prominent-decr": 0.3},
        },
    },
}


def user_data(*parts):
    return os.path.join(LocationService.get_user_data(), *parts)


def unpack():
    target = user_data()
    for pack in PACKS:
        zip_path = VENDOR / ("%s.zip" % pack)
        with zipfile.ZipFile(zip_path) as archive:
            archive.extractall(target)
        print("mh: unpacked", pack)


def find(kind, *words):
    """First asset file under user data/<kind> whose path contains every word."""
    base = user_data(kind)
    hits = []
    for folder, _dirs, files in os.walk(base):
        for name in files:
            path = os.path.join(folder, name)
            if all(w.lower() in path.lower() for w in words):
                hits.append(path)
    hits.sort()
    return hits[0] if hits else None


def listing(kind, suffix):
    base = user_data(kind)
    out = []
    for folder, _dirs, files in os.walk(base):
        out += [os.path.relpath(os.path.join(folder, f), base) for f in files if f.endswith(suffix)]
    return sorted(out)


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj)


def build(key, spec=None):
    """One MakeHuman body with skin, eyes, brows, lashes, teeth, hair (and beard) on the
    game_engine rig (UE-style bone names), placed at its x. spec defaults to BODIES[key];
    its hair turns silver unless it says "silver": False."""
    spec = spec or BODIES[key]
    info = HumanService._create_default_human_info_dict()
    info.update({
        "name": "mh_%s" % key,
        "phenotype": spec["phenotype"],
        "rig": "game_engine",
        "eyes": "high-poly/high-poly.mhclo",
        "eyelashes": "eyelashes01/eyelashes01.mhclo",
        "teeth": "",  # the mouth stays closed: 7k triangles saved
        "eyebrows": spec["eyebrows"],
        "hair": spec["hair"],
        "clothes": spec["clothes"],
        "skin_mhmat": spec["skin_mhmat"],
        "skin_material_type": "ENHANCED_SSS",
        "targets": [{"target": name, "value": value}
                    for name, value in dict(spec["targets"], **spec.get("physique", {})).items()],
    })
    settings = HumanService.get_default_deserialization_settings()
    settings["subdiv_levels"] = 0
    basemesh = HumanService.deserialize_from_dict(info, settings)
    rig = basemesh.parent
    base_masks = {m.name for m in basemesh.modifiers}
    for kind, assets in spec.get("variants", {}).items():
        for asset in assets:
            path = AssetService.find_asset_absolute_path(asset, asset_subdir=kind)
            HumanService.add_mhclo_asset(path, basemesh, asset_type=kind, subdiv_levels=0, material_type="MAKESKIN")
    # variants are worn one at a time: only the base clothes hide the skin under them, so
    # taking a robe off shows no holes where it was
    for mod in [m for m in basemesh.modifiers if m.type == "MASK" and m.name not in base_masks]:
        basemesh.modifiers.remove(mod)
    if spec.get("faces"):
        face_moves(basemesh, rig, spec["targets"], spec["faces"])
    rig.location.x = spec["x"]
    if spec.get("silver", True):
        silver(rig)
    eyes(rig, spec["eyes"])
    for name, colours in spec.get("recolour", {}).items():
        recolour(rig, name, *colours)
    for name, colour in spec.get("dye", {}).items():
        dye(rig, key, name, colour)
    for name, ratio in spec.get("decimate", {}).items():
        obj = next(o for o in rig.children_recursive if o.type == "MESH" and o.name.endswith(name))
        obj.modifiers.new("decimate", "DECIMATE").ratio = ratio  # applied by arkanor_game.bake_mesh
    for name, distance in spec.get("push", {}).items():
        obj = next(o for o in rig.children_recursive if o.type == "MESH" and o.name.endswith(name))
        mod = obj.modifiers.new("push out", "DISPLACE")
        mod.strength = distance
        mod.mid_level = 0.0
    return basemesh, rig


def coords(vertices):
    out = np.empty(len(vertices) * 3, np.float32)
    vertices.foreach_get("co", out)
    return out


def face_moves(basemesh, rig, targets, faces):
    """Each of `faces` (target values on top of `targets`) stored on the body and on every
    part fitted to it (eyes, brows, lashes, hair, beards, clothes) as a point attribute
    face_<name>: how far each vertex moves to make that face. arkanor_game turns them into
    shape keys, the face presets of character creation. The parts are refitted for each
    face, so brows, beards and hair follow it; the bones stay where they are."""
    names = set(targets).union(*faces.values())
    TargetService.bulk_load_targets(basemesh, [{"target": n, "value": 0.0} for n in sorted(names - set(targets))])
    parts = [basemesh] + list(ObjectService.find_related_mesh_assets(rig, only_children=True))

    def shape(values):
        for name in names:
            TargetService.set_target_value(basemesh, name, values.get(name, 0.0))
        for part in parts[1:]:
            ClothesService.fit_clothes_to_human(part, basemesh, set_parent=False)
        mix = basemesh.shape_key_add(name="face_mix", from_mix=True)
        out = [coords(mix.data)]
        basemesh.shape_key_remove(mix)
        return out + [coords(part.data.vertices) for part in parts[1:]]

    rest = shape(targets)
    for face, changes in faces.items():
        moved = shape(dict(targets, **changes))
        for part, before, after in zip(parts, rest, moved):
            part.data.attributes.new("face_" + face, "FLOAT_VECTOR", "POINT").data.foreach_set("vector", after - before)
        print("mh: face", face, "moves the body up to %.1f mm" % (np.abs(moved[0] - rest[0]).max() * 1000))
    shape(targets)


FABRIC = ROOT / "game" / "art" / "textures" / "props_pbr" / "canvas_albedo.png"


def recolour(rig, asset, base, accent, repeats=5):
    """Repaints a two-tone clothing texture (dark cloth + red accents): the dark becomes
    `base`, the red `accent` (sRGB 0..1), with scanned linen woven through it so the cloth
    is not flat. Saved to art/characters/arkanor/tex/mh_<asset>.png."""
    obj = next(o for o in rig.children_recursive if o.type == "MESH" and o.name.endswith(asset))
    for slot in obj.material_slots:
        node = next(n for n in slot.material.node_tree.nodes if n.type == "TEX_IMAGE" and n.name == "diffuseTexture")
        src = node.image
        if src is None or not src.has_data:
            # some packs name the texture wrongly in the .mhmat: use the png beside it
            folder = user_data("clothes", asset)
            png = next(f for f in sorted(os.listdir(folder)) if f.endswith(".png"))
            src = bpy.data.images.load(os.path.join(folder, png), check_existing=True)
        w, h = src.size
        pixels = np.empty(w * h * 4, np.float32)
        src.pixels.foreach_get(pixels)
        pixels = pixels.reshape(h, w, 4)
        cloth = bpy.data.images.load(str(FABRIC), check_existing=True)
        cw, ch = cloth.size
        weave = np.empty(cw * ch * 4, np.float32)
        cloth.pixels.foreach_get(weave)
        weave = weave.reshape(ch, cw, 4)[..., :3] @ np.array([0.3, 0.59, 0.11], np.float32)
        ys = (np.arange(h) * repeats * ch // h) % ch
        xs = (np.arange(w) * repeats * cw // w) % cw
        detail = weave[np.ix_(ys, xs)]
        detail = np.clip(0.55 + 0.45 * detail / detail.mean(), 0.6, 1.35)[..., None]
        accent_mask = np.clip((pixels[..., 0] - np.maximum(pixels[..., 1], pixels[..., 2])) * 3.0, 0, 1)[..., None]
        shade = 0.75 + 0.5 * pixels[..., :3].max(axis=2, keepdims=True)  # keep any painted shading
        colour = (np.array(base) * (1 - accent_mask) + np.array(accent) * accent_mask) * detail * np.minimum(shade, 1.1)
        out = bpy.data.images.new("mh_%s" % asset, w, h, alpha=True)
        out.pixels.foreach_set(np.dstack([np.clip(colour, 0, 1), pixels[..., 3:]]).astype(np.float32).ravel())
        out.filepath_raw = str(OUT / "tex" / ("mh_%s.png" % asset))
        out.file_format = "PNG"
        out.save()
        node.image = out


def dye(rig, key, asset, colour):
    """Dyes a cloth texture in `colour` (sRGB 0..1), keeping its folds and weave: each texel
    keeps its brightness against the texture's mean. Saved to tex/mh_<key>_<asset>.png."""
    obj = next(o for o in rig.children_recursive if o.type == "MESH" and o.name.endswith(asset))
    for slot in obj.material_slots:
        slot.material = slot.material.copy()  # robe and cowl share one material as loaded
        node = next(n for n in slot.material.node_tree.nodes if n.type == "TEX_IMAGE" and n.name == "diffuseTexture")
        w, h = node.image.size
        pixels = np.empty(w * h * 4, np.float32)
        node.image.pixels.foreach_get(pixels)
        pixels = pixels.reshape(h, w, 4)
        luma = pixels[..., :3] @ np.array([0.3, 0.59, 0.11], np.float32)
        shade = np.clip(luma / mean_brightness(node.image), 0.0, 1.6)[..., None]
        out = bpy.data.images.new("mh_%s_%s" % (key, asset), w, h, alpha=True)
        out.pixels.foreach_set(np.dstack([np.clip(np.array(colour) * shade, 0, 1), pixels[..., 3:]])
                               .astype(np.float32).ravel())
        out.filepath_raw = str(OUT / "tex" / ("mh_%s_%s.png" % (key, asset)))
        out.file_format = "PNG"
        out.save()
        node.image = out


def eyes(rig, colour):
    """Both eyes in one natural colour from MakeHuman's eye textures (blue, lightblue,
    bluegreen, brown, brownlight, deepblue, green, grey, ice)."""
    obj = next(o for o in rig.children_recursive if o.type == "MESH" and o.name.endswith("high-poly"))
    path = user_data("eyes", "materials", "%s_eye.png" % colour)
    for slot in obj.material_slots:
        tex = next(n for n in slot.material.node_tree.nodes if n.type == "TEX_IMAGE")
        tex.image = bpy.data.images.load(path, check_existing=True)

## Arkanor hair is silver-white whatever colour the asset ships in: the colour texture is
## turned grey and scaled so its average brightness lands on SILVER_LEVEL, which keeps
## the strand and braid pattern; SILVER_TINT warms it slightly.
SILVER_LEVEL = 0.62
SILVER_TINT = (1.0, 0.98, 0.94, 1.0)
HAIRY = ("eyebrows", "hair", "short", "braid", "beard", "moustache", "ponytail", "bob", "long", "updo")


def mean_brightness(image):
    """Average brightness of the visible texels (alpha > 0.5)."""
    if image is None:
        return 0.5
    pixels = np.empty(len(image.pixels), np.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(-1, 4)
    visible = pixels[pixels[:, 3] > 0.5] if (pixels[:, 3] > 0.5).any() else pixels
    return max(float((visible[:, :3] @ np.array([0.3, 0.59, 0.11], np.float32)).mean()), 0.02)


def silver(rig):
    for obj in rig.children_recursive:
        if obj.type != "MESH" or not any(word in obj.name.lower() for word in HAIRY):
            continue
        for slot in obj.material_slots:
            tree = slot.material.node_tree if slot.material and slot.material.use_nodes else None
            if tree is None:
                continue
            # only the colour texture: normal, bump and AO maps keep their data
            textures = [n for n in tree.nodes if n.type == "TEX_IMAGE" and n.name == "diffuseTexture"]
            for node in tree.nodes:
                if node.type == "MIX_RGB" and node.name == "diffuseIntensity":
                    node.inputs["Fac"].default_value = 1.0  # all texture, no flat tint
                if node.type == "BSDF_PRINCIPLED" and not textures:
                    node.inputs["Base Color"].default_value = (0.62, 0.62, 0.6, 1.0)
            for node in textures:
                gain = SILVER_LEVEL / mean_brightness(node.image)
                for link in [l for l in tree.links if l.from_node == node and l.from_socket.name == "Color"]:
                    gray = tree.nodes.new("ShaderNodeRGBToBW")
                    scale = tree.nodes.new("ShaderNodeMath")
                    scale.operation = "MULTIPLY"
                    scale.use_clamp = True
                    scale.inputs[1].default_value = gain
                    tint = tree.nodes.new("ShaderNodeMixRGB")
                    tint.blend_type = "MULTIPLY"
                    tint.inputs["Fac"].default_value = 1.0
                    tint.inputs["Color2"].default_value = SILVER_TINT
                    tree.links.new(node.outputs["Color"], gray.inputs["Color"])
                    tree.links.new(gray.outputs["Val"], scale.inputs[0])
                    tree.links.new(scale.outputs["Value"], tint.inputs["Color1"])
                    tree.links.new(tint.outputs["Color"], link.to_socket)


def stats(basemesh):
    parts = [basemesh] + [o for o in basemesh.parent.children_recursive if o.type == "MESH" and o != basemesh]
    out = {}
    for obj in parts:
        mesh = obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
        out[obj.name] = sum(len(p.vertices) - 2 for p in mesh.polygons)
    return out


def shots(folder, keys=None):
    """Front and side renders of the bodies (default: all BODIES; Cycles, soft key light + sky fill)."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for device in prefs.devices:
            device.use = True
        scene.cycles.device = "GPU"
    except TypeError:
        pass
    scene.cycles.samples = 96
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 900, 1100
    world = bpy.data.worlds.new("mh_world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.62, 0.72, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.7
    scene.world = world
    sun = bpy.data.objects.new("mh_sun", bpy.data.lights.new("mh_sun", "SUN"))
    sun.data.energy = 3.5
    sun.data.angle = 0.2
    sun.rotation_euler = (0.9, 0.1, -0.6)
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("mh_cam", bpy.data.cameras.new("mh_cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.lens = 85
    views = {
        "full_front": ((0, -9.5, 0.95), (1.5708, 0, 0), 900, 1100),
        "full_side": ((9.5, 0, 0.95), (1.5708, 0, 1.5708), 900, 1100),
    }
    for key in keys or BODIES:
        rig = next(o for o in bpy.data.objects if o.type == "ARMATURE" and o.name.startswith("mh_%s" % key))
        head = rig.matrix_world @ rig.data.bones["head"].head_local
        z = head.z + 0.05
        views["face_%s" % key] = ((head.x, head.y - 1.7, z), (1.5708, 0, 0), 700, 800)
        views["face34_%s" % key] = ((head.x + 0.85, head.y - 1.47, z), (1.5708, 0, 0.5236), 700, 800)
        views["back_%s" % key] = ((head.x - 0.85, head.y + 1.47, z), (1.5708, 0, 3.6652), 700, 800)
        views["side_%s" % key] = ((head.x + 1.7, head.y, z), (1.5708, 0, 1.5708), 700, 800)
    for name, (loc, rot, w, h) in views.items():
        cam.location, cam.rotation_euler = loc, rot
        cam.data.lens = 85 if name.startswith("full") else 105
        scene.render.resolution_x, scene.render.resolution_y = w, h
        scene.render.filepath = os.path.join(folder, name + ".png")
        bpy.ops.render.render(write_still=True)
        print("mh: shot", scene.render.filepath)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--unpack" in args:
        unpack()
    if "--list" in args:
        for kind, suffix in (("skins", ".mhmat"), ("eyebrows", ".mhclo"), ("eyelashes", ".mhclo"),
                             ("hair", ".mhclo"), ("clothes", ".mhclo"), ("eyes", ".mhclo"), ("teeth", ".mhclo")):
            print("mh:", kind, listing(kind, suffix))
    if "--build" in args:
        clear_scene()
        for key in BODIES:
            basemesh, rig = build(key)
            print("mh:", key, "rig bones", len(rig.data.bones), "tris", stats(basemesh))
        OUT.mkdir(parents=True, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "arkanor_mh.blend"))
        if "--shots" in args:
            shots(os.environ.get("ARKANOR_SHOTS", str(OUT / "mh_preview")))
