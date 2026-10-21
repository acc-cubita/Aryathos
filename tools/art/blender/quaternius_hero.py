"""The heroes from Quaternius' CC0 kits (art/vendor/quaternius, free Standard versions):
a Universal Base Characters "Superhero" head (face, eyes, brows) on a Modular Character
Outfits - Fantasy body (Ranger for Runeknights, Peasant for Aethermancers), with the kits'
hairstyles and beard as meshes the game shows or hides (character creation).

    blender -b --factory-startup --python tools/art/blender/quaternius_hero.py [-- male female] [--shots <folder>]

The kits share one 65-bone skeleton with the Universal Animation Library, so the game's
clips play on them as they were made. Bones get the Godot humanoid names and grip markers
(arkanor_game.rename_bones / grip_markers); the head is moved onto the outfit body's neck
(the outfits are cut for the "Regular" body, the free heads come on "Superhero" bodies) and
everything below the neck is dropped from it. Hair textures (grey, made for tinting) are
brightened: the game tints them (CharacterModel.HAIR_COLORS). The limbs' skin (the
outfits' own, Regular body) is matched to the head's. Exports
game/art/characters/hero/hero_<gender>.glb: the head mesh hero_<gender> and the parts
hero_<gender>_<part> (ranger, peasant, hood, the hairstyles, beard).
"""
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import arkanor_game as game  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
KITS = ROOT / "art" / "vendor" / "quaternius"
BASE = KITS / "ubc" / "Universal Base Characters[Standard]"
BODIES = BASE / "Base Characters" / "Godot - UE"
TEXTURES = BASE / "Base Characters" / "Textures"
HAIRS = BASE / "Hairstyles" / "Rigged to Head Bone" / "glTF (Godot -Unreal)"
OUTFITS = KITS / "outfits" / "Modular Character Outfits - Fantasy[Standard]" / "Exports" / "glTF (Godot-Unreal)" / "Outfits"
OUT = ROOT / "game" / "art" / "characters" / "hero"

HEROES = {
    "male": {"body": "Superhero_Male_FullBody", "skin": "T_Superhero_Male_Ligh.png",
             "outfits": {"ranger": "Male_Ranger", "peasant": "Male_Peasant"},
             "brows": "Eyebrows_Regular", "hair": ["Hair_Long", "Hair_SimpleParted", "Hair_Buzzed", "Hair_Beard"]},
    "female": {"body": "Superhero_Female_FullBody", "skin": "T_Superhero_Female_Light_BaseColor.png",
               "outfits": {"ranger": "Female_Ranger", "peasant": "Female_Peasant"},
               "brows": "Eyebrows_Female", "hair": ["Hair_Buns", "Hair_Long", "Hair_BuzzedFemale"]},
}
## The head keeps the body's faces whose vertices all hang this much on the head and neck.
HEAD_WEIGHT = 0.5
## Mean brightness the grey hair textures are raised to (the game tints them down).
HAIR_LEVEL = 0.82
## Textures are cut down to this size (px).
TEXTURE_SIZE = 1024


def imported(path):
    """Imports a glTF; returns (armature, meshes)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    new = [o for o in bpy.data.objects if o not in before]
    rig = next(o for o in new if o.type == "ARMATURE")
    skinned = [o for o in new if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)]
    for obj in new:
        if obj.type == "MESH" and obj not in skinned:
            bpy.data.objects.remove(obj)  # (bone display shapes)
    return rig, skinned


def onto(meshes, source, rig, offset=Vector()):
    """Moves skinned meshes from `source`'s skeleton onto `rig` (same bone names), shifted
    by `offset` (rest pose, world)."""
    assert rig.matrix_world == Matrix.Identity(4) and source.matrix_world == Matrix.Identity(4)
    for obj in meshes:
        obj.data.transform(Matrix.Translation(offset) @ obj.matrix_world)
        obj.parent = rig
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.matrix_basis = Matrix.Identity(4)
        for mod in obj.modifiers:
            if mod.type == "ARMATURE":
                mod.object = rig
    bpy.data.objects.remove(source)


def material_name(obj):
    return obj.data.materials[0].name if obj.data.materials and obj.data.materials[0] else ""


def head_point(rig):
    return rig.matrix_world @ rig.data.bones["Head"].head_local


def keep_head(obj):
    """Deletes the faces of a full body below the neck."""
    import bmesh
    groups = {g.index for g in obj.vertex_groups if g.name in ("Head", "neck_01")}
    keep = []
    for v in obj.data.vertices:
        keep.append(sum(g.weight for g in v.groups if g.group in groups) >= HEAD_WEIGHT)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    doomed = [f for f in bm.faces if not all(keep[v.index] for v in f.verts)]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()


def images_of(obj):
    for slot in obj.material_slots:
        if slot.material and slot.material.use_nodes:
            for node in slot.material.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image is not None:
                    yield slot.material, node


def pixels(image):
    w, h = image.size
    px = np.empty(w * h * 4, np.float32)
    image.pixels.foreach_get(px)
    return px.reshape(h, w, 4)


def repaint(image, name, change):
    """A copy of `image` whose RGB `change` maps (alpha kept), saved beside the export."""
    px = pixels(image)
    out = bpy.data.images.new(name, image.size[0], image.size[1], alpha=True)
    out.pixels.foreach_set(np.dstack([np.clip(change(px[..., :3]), 0, 1), px[..., 3:]]).astype(np.float32).ravel())
    out.pack()
    return out


def build(gender):
    spec = HEROES[gender]
    name = "hero_" + gender
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj)
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    outfits = {}
    rig = None
    for part, file in spec["outfits"].items():
        other, meshes = imported(OUTFITS / (file + ".gltf"))
        if rig is None:
            rig = other
        else:
            onto(meshes, other, rig)
        outfits[part] = meshes
    rig.name = rig.data.name = name + "_rig"
    # the hood comes off the ranger: a part of its own
    hood = [o for o in outfits["ranger"] if "Hood" in o.name]
    outfits["ranger"] = [o for o in outfits["ranger"] if o not in hood]
    outfits["hood"] = hood
    # the head, its eyes and brows from the Superhero body, onto the outfit body's neck
    body_rig, body = imported(BODIES / (spec["body"] + ".gltf"))
    offset = head_point(rig) - head_point(body_rig)
    for obj in [o for o in body if material_name(o).startswith("MI_Hair")]:
        body.remove(obj)
        bpy.data.objects.remove(obj)  # the kit's default brows: the chosen ones follow
    skin = next(o for o in body if material_name(o).startswith("MI_Superhero"))
    keep_head(skin)
    onto(body, body_rig, rig, offset)
    parts = {}
    for file in [spec["brows"]] + spec["hair"]:
        hair_rig, meshes = imported(HAIRS / (file + ".gltf"))
        onto(meshes, hair_rig, rig, head_point(rig) - head_point(hair_rig))
        parts[file] = meshes
    # one mesh per part, named for the game
    def join(objs, new_name):
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        obj = bpy.context.view_layer.objects.active
        obj.name = obj.data.name = new_name
        return obj
    head = join(body + parts.pop(spec["brows"]), name)
    for part, objs in outfits.items():
        join(objs, "%s_%s" % (name, part))
    for file, objs in parts.items():
        join(objs, "%s_%s" % (name, file.lower().replace("hair_", "")))
    # textures: skin to the light tone (the outfits' limbs to match), hair raised to tint,
    # everything at most TEXTURE_SIZE; materials named for the game (CharacterModel)
    light = bpy.data.images.load(str(TEXTURES / spec["skin"]))
    light_mean = pixels(light)[..., :3].reshape(-1, 3).mean(0)
    done = {}
    for obj in rig.children:
        for material, node in list(images_of(obj)):
            image = node.image
            key = image.name
            if key not in done:
                if key.startswith("T_Superhero") and "Normal" not in key and "Roughness" not in key:
                    done[key] = light
                elif key.startswith("T_Regular") and "BaseColor" in key:
                    mean = pixels(image)[..., :3].reshape(-1, 3).mean(0)
                    done[key] = repaint(image, "%s_limbs" % name, lambda rgb, m=mean: rgb * (light_mean / m))
                elif key.startswith("T_Hair") and "BaseColor" in key:
                    mean = pixels(image)[..., :3].mean()
                    done[key] = repaint(image, "%s_%s" % (name, key), lambda rgb, m=mean: rgb * (HAIR_LEVEL / m))
                else:
                    done[key] = image
                if max(done[key].size) > TEXTURE_SIZE:
                    done[key].scale(TEXTURE_SIZE, TEXTURE_SIZE)
            node.image = done[key]
        for slot in obj.material_slots:
            mat = slot.material
            for prefix, new_name in (("MI_Superhero", "body"), ("MI_Regular", "body_limbs"), ("MI_Hair", "hair"),
                                     ("MI_Eyes", "eyes"), ("MI_Ranger", "ranger"), ("MI_Peasant", "peasant")):
                if mat is not None and mat.name.startswith(prefix):
                    mat.name = "eyebrow" if new_name == "hair" and obj.name == name else new_name
    # bone names for Godot's humanoid profile, the root dropped, grip markers in the fists
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    eb = rig.data.edit_bones
    if "root" in eb:
        eb["pelvis"].parent = None
        eb.remove(eb["root"])
    bpy.ops.object.mode_set(mode="OBJECT")
    game.rename_bones(rig)
    game.grip_markers(rig)
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in rig.children)
    print("%s: %d bones, %d tris, parts %s" % (name, len(rig.data.bones), tris, sorted(o.name for o in rig.children)))
    return rig


def shots(rig, folder):
    """Front and side renders with every part but the hood, peasant and spare hair hidden."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 900, 1100
    name = rig.name[:-4]
    shown = {name, name + "_ranger", name + "_long" if name.endswith("male") and not name.endswith("female") else name + "_buns"}
    if name == "hero_male":
        shown.add(name + "_beard")
    for obj in rig.children:
        obj.hide_render = obj.name not in shown
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.57, 0.62, 1.0)
    scene.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (0.9, 0.2, 0.6)
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    Path(folder).mkdir(parents=True, exist_ok=True)
    top = max((rig.matrix_world @ v.co).z for v in bpy.data.objects[name].data.vertices)
    for view, place in (("front", Vector((0.0, -3.4, 1.0))), ("side", Vector((3.4, 0.0, 1.0))),
                        ("face", Vector((0.25, -0.75, top - 0.12)))):
        cam.location = place
        aim = Vector((0.0, 0.0, 0.95 if view != "face" else top - 0.14))
        cam.rotation_euler = (aim - place).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = 50 if view != "face" else 85
        bpy.context.view_layer.update()
        scene.render.filepath = str(Path(folder) / ("%s_%s.png" % (name, view)))
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for gender in [a for a in args if a in HEROES] or list(HEROES):
        hero = build(gender)
        print("-> %s" % game.export(hero.name[:-4], OUT))
        if "--shots" in args:
            shots(hero, args[args.index("--shots") + 1])
