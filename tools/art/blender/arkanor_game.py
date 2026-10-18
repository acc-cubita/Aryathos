"""Turns the MakeHuman Arkanor bodies (arkanor_mh.py) into game characters for Godot.

    blender -b --python tools/art/blender/arkanor_game.py

Reads art/characters/arkanor/arkanor_mh.blend and, per body:
  * renames the bones to Godot's humanoid names (Hips, Spine, ..., LeftIndexProximal) and
    drops MakeHuman's Root, so animations retarget onto it in Godot;
  * bakes the shape keys and modifiers, joins every piece into one skinned mesh and gives
    each part a plain glTF material (colour, alpha, normal map) named after the part;
    hair is greyed to silver in its texture (art/characters/arkanor/tex/mh_<key>_*.png);
  * adds grip markers in each fist (RightGrip -> RightGripTip, LeftGrip -> LeftGripTip):
    the weapon's handle runs through them;
  * exports game/art/characters/arkanor/arkanor_<key>.glb (mesh + skeleton, no animation:
    the clips come from a retargeted animation library in Godot).
"""
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
TEX = ROOT / "art" / "characters" / "arkanor" / "tex"
GAME_ART = ROOT / "game" / "art" / "characters" / "arkanor"
SOURCE = ROOT / "art" / "characters" / "arkanor" / "arkanor_mh.blend"

BONES = {"pelvis": "Hips", "spine_01": "Spine", "spine_02": "Chest", "spine_03": "UpperChest",
         "neck_01": "Neck", "head": "Head"}
for _s, _side in (("l", "Left"), ("r", "Right")):
    BONES.update({"clavicle_" + _s: _side + "Shoulder", "upperarm_" + _s: _side + "UpperArm",
                  "lowerarm_" + _s: _side + "LowerArm", "hand_" + _s: _side + "Hand",
                  "thigh_" + _s: _side + "UpperLeg", "calf_" + _s: _side + "LowerLeg",
                  "foot_" + _s: _side + "Foot", "ball_" + _s: _side + "Toes"})
    for _mh, _godot in (("thumb", "Thumb"), ("index", "Index"), ("middle", "Middle"),
                        ("ring", "Ring"), ("pinky", "Little")):
        _segs = ("Metacarpal", "Proximal", "Distal") if _mh == "thumb" else ("Proximal", "Intermediate", "Distal")
        for _i, _seg in enumerate(_segs):
            BONES["%s_%02d_%s" % (_mh, _i + 1, _s)] = _side + _godot + _seg

HAIRY = ("eyebrow", "hair", "braid", "beard", "moustache", "ponytail", "bun", "updo", "short0", "long0", "bob0", "afro")
SILVER_LEVEL = 0.62
SILVER_TINT = np.array([1.0, 0.98, 0.94])
# roughness per part (by name); everything else is cloth
ROUGHNESS = {"body": 0.55, "high-poly": 0.08, "eyelashes": 0.6}


def part_name(obj, key):
    return obj.name.replace("mh_%s." % key, "")


def rename_bones(rig):
    for bone in rig.data.bones:
        if bone.name in BONES:
            bone.name = BONES[bone.name]  # Blender renames the matching vertex groups too
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    eb = rig.data.edit_bones
    if "Root" in eb:
        eb["Hips"].parent = None
        eb.remove(eb["Root"])
    bpy.ops.object.mode_set(mode="OBJECT")


def bake_mesh(obj):
    """Shape keys mixed in, every modifier but the armature applied."""
    obj.data = obj.data.copy()
    bpy.context.view_layer.objects.active = obj
    if obj.data.shape_keys:
        with bpy.context.temp_override(object=obj, active_object=obj):
            bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    for mod in list(obj.modifiers):
        if mod.type != "ARMATURE":
            with bpy.context.temp_override(object=obj, active_object=obj):
                bpy.ops.object.modifier_apply(modifier=mod.name)


def pixels_of(image):
    w, h = image.size
    px = np.empty(w * h * 4, np.float32)
    image.pixels.foreach_get(px)
    return px.reshape(h, w, 4)


def silver_image(image, name):
    """The hair texture greyed and scaled to the silver level (same rule as arkanor_mh)."""
    px = pixels_of(image)
    visible = px[px[..., 3] > 0.5] if (px[..., 3] > 0.5).any() else px.reshape(-1, 4)
    luma = px[..., :3] @ np.array([0.3, 0.59, 0.11], np.float32)
    mean = max(float((visible[:, :3] @ np.array([0.3, 0.59, 0.11], np.float32)).mean()), 0.02)
    grey = np.clip(luma * (SILVER_LEVEL / mean), 0, 1)[..., None] * SILVER_TINT
    out = bpy.data.images.new(name, image.size[0], image.size[1], alpha=True)
    out.pixels.foreach_set(np.dstack([grey, px[..., 3:]]).astype(np.float32).ravel())
    out.filepath_raw = str(TEX / (name + ".png"))
    out.file_format = "PNG"
    out.save()
    return out


def find_texture(tree, *names):
    for node in tree.nodes:
        if node.type == "TEX_IMAGE" and node.image and node.name.lower() in names:
            return node.image
    for node in tree.nodes:
        if node.type == "GROUP" and node.node_tree:
            found = find_texture(node.node_tree, *names)
            if found:
                return found
    return None


def game_material(obj, key, source, silver=True):
    """A plain Principled material glTF can carry: colour (+ alpha) and normal map.
    Hair turns silver (Arkanor) unless silver is False."""
    part = part_name(obj, key)
    tree = source.node_tree
    colour = find_texture(tree, "diffusetexture")
    normal = find_texture(tree, "normalmaptexture")
    hairy = any(word in part for word in HAIRY)
    if colour is not None and hairy and silver:
        colour = silver_image(colour, "mh_%s_%s" % (key, part))
    mat = bpy.data.materials.new(part)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = next((r for k, r in ROUGHNESS.items() if part.startswith(k)), 0.45 if hairy else 0.85)
    if colour is not None:
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = colour
        links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if hairy or part.startswith(("eyelashes", "high-poly")):
            links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    else:
        old = next((n for n in tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if old is not None:
            bsdf.inputs["Base Color"].default_value = old.inputs["Base Color"].default_value
    if normal is not None:
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = normal
        tex.image.colorspace_settings.name = "Non-Color"
        nmap = nodes.new("ShaderNodeNormalMap")
        links.new(tex.outputs["Color"], nmap.inputs["Color"])
        links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def grip_markers(rig):
    """<Side>Grip -> <Side>GripTip inside each fist: just past the knuckles, toward the palm,
    pointing to the thumb side (where a handle leaves a closed hand)."""
    bones = rig.data.bones
    spots = {}
    for pre, s in (("Left", 1.0), ("Right", -1.0)):
        hand = bones[pre + "Hand"]
        knuckles = sum((bones[pre + f + "Proximal"].head_local for f in ("Index", "Middle", "Ring", "Little")), Vector()) / 4
        D = (bones[pre + "MiddleProximal"].head_local - hand.head_local).normalized()
        lat = bones[pre + "IndexProximal"].head_local - bones[pre + "LittleProximal"].head_local
        lat = (lat - D * lat.dot(D)).normalized()  # toward the thumb
        palm = D.cross(lat) * s  # palm side (left hand: D x lat; mirrored for the right)
        thumb_tip = bones[pre + "ThumbDistal"].tail_local
        if (thumb_tip - hand.head_local).dot(palm) < 0:
            palm = -palm  # the thumb sits on the palm side
        L = (bones[pre + "MiddleDistal"].tail_local - hand.head_local).length
        spots[pre] = (knuckles + D * 0.04 * L + palm * 0.11 * L, lat)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    eb = rig.data.edit_bones
    for pre, (grip, lat) in spots.items():
        g = eb.new(pre + "Grip")
        g.head, g.tail = grip, grip + lat * 0.08
        g.parent = eb[pre + "Hand"]
        t = eb.new(pre + "GripTip")
        t.head, t.tail = g.tail, grip + lat * 0.1
        t.parent = g
    bpy.ops.object.mode_set(mode="OBJECT")
    for pre in spots:
        for name in (pre + "Grip", pre + "GripTip"):
            rig.data.bones[name].use_deform = True  # kept by the glTF export (deform bones only)


def convert(key, name=None, silver=True):
    """Body mh_<key> -> one skinned mesh <name> (default arkanor_<key>) on rig <name>_rig."""
    name = name or "arkanor_%s" % key
    rig = bpy.data.objects["mh_%s" % key]
    rename_bones(rig)
    parts = [o for o in rig.children_recursive if o.type == "MESH" and not o.hide_render]
    for obj in parts:
        bake_mesh(obj)
        materials = [game_material(obj, key, slot.material, silver) for slot in obj.material_slots if slot.material]
        obj.data.materials.clear()
        for mat in materials:
            obj.data.materials.append(mat)
    body = next(o for o in parts if o.name.endswith(".body"))
    with bpy.context.temp_override(active_object=body, selected_editable_objects=parts):
        bpy.ops.object.join()
    body.name = body.data.name = name
    rig.name = rig.data.name = name + "_rig"
    grip_markers(rig)
    return rig, body


## Largest texture side exported: 4K cloth and skin scans are wasted on a game character.
MAX_TEXTURE = 2048


def shrink_textures(obj):
    for slot in obj.material_slots:
        if slot.material is None or not slot.material.use_nodes:
            continue
        for node in slot.material.node_tree.nodes:
            image = node.image if node.type == "TEX_IMAGE" else None
            if image is not None and max(image.size) > MAX_TEXTURE:
                factor = MAX_TEXTURE / max(image.size)
                image.scale(int(image.size[0] * factor), int(image.size[1] * factor))


def export(name, folder=GAME_ART):
    """<folder>/<name>.glb: the mesh <name> on its rig <name>_rig, centred on its feet,
    textures no larger than MAX_TEXTURE."""
    rig = bpy.data.objects[name + "_rig"]
    body = bpy.data.objects[name]
    shrink_textures(body)
    x = rig.location.x
    rig.location.x = 0.0  # centred on its feet
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    for obj in (rig, body):
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / (name + ".glb")
    bpy.ops.export_scene.gltf(filepath=str(path), use_selection=True, export_format="GLB", export_yup=True,
                              export_apply=False, export_skins=True, export_animations=False,
                              export_def_bones=True, export_morph=False, export_image_format="AUTO")
    rig.location.x = x
    return path


if __name__ == "__main__":
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    TEX.mkdir(parents=True, exist_ok=True)
    for key in ("male", "female"):
        rig, body = convert(key)
        tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
        print("game: %s %d bones, %d tris, materials %s -> %s" % (
            key, len(rig.data.bones), tris, [m.name for m in body.data.materials], export(body.name)))
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "art" / "characters" / "arkanor" / "arkanor_game.blend"))
