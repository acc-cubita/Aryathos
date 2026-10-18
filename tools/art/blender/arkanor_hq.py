"""High-quality Arkanor male + female, built in the live Blender session.

Run inside Blender (MCP execute or Text editor):
    exec(open(r"D:/my game/tools/art/blender/arkanor_hq.py").read())
    setup()            # fresh scene: base bodies + reference images

Bases are Blender Studio's CC0 "Human Base Meshes" (stylized male/female),
reshaped to the concept sheet art/characters/arkanor/ref_sheet_male_female.jpg.
"""
import math

import bpy
import mathutils

ROOT = "D:/my game"
BUNDLE = ROOT + "/art/vendor/human-base-meshes/extracted/human-base-meshes-bundle-v1.4.1/human_base_meshes_bundle.blend"
REF_DIR = ROOT + "/art/characters/arkanor"

# name: (base collection, body object, x offset, height incl. hair bun)
CHARACTERS = {
    "male": ("Body Male - Stylized", "GEO-body_male_stylized", -0.6, 1.95),
    "female": ("Body Female - Stylized", "GEO-body_female_stylized", 0.6, 1.85),
}


def clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for d in list(block):
            if d.users == 0:
                block.remove(d)


def collection(name):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
    return c


def append_body(key):
    base, body_name, x, _ = CHARACTERS[key]
    with bpy.data.libraries.load(BUNDLE, link=False) as (src, dst):
        dst.collections = [base]
    c = dst.collections[0]
    c.name = "Arkanor " + key.title()
    bpy.context.scene.collection.children.link(c)
    body = bpy.data.objects[body_name]
    body.name = "arkanor_%s_body" % key
    body.location = (x, 0, 0)
    body.data.shade_smooth()
    for child in body.children:
        side = child.name[-1]
        child.name = "arkanor_%s_eye.%s" % (key, side)
    return body


def reference(name, image, location, rotation, height, alpha=0.45):
    img = bpy.data.images.load(REF_DIR + "/" + image, check_existing=True)
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = 'IMAGE'
    e.data = img
    e.empty_display_size = height
    e.empty_image_offset = (-0.5, 0.0)
    e.empty_image_depth = 'FRONT'
    e.use_empty_image_alpha = True
    e.color[3] = alpha
    e.show_empty_image_only_axis_aligned = True
    e.location = location
    e.rotation_euler = rotation
    e.hide_select = True
    collection("References").objects.link(e)
    return e


def setup():
    clear_scene()
    for key, (_, _, x, height) in CHARACTERS.items():
        append_body(key)
        # Front sheet faces the -Y front view; side sheet faces the +X right view.
        reference("ref_%s_front" % key, "ref_%s_front.png" % key, (x, 0.5, 0), (math.pi / 2, 0, 0), height)
        reference("ref_%s_side" % key, "ref_%s_side.png" % key, (x - 0.5, 0, 0), (math.pi / 2, 0, math.pi / 2), height)
    return {"objects": [o.name for o in bpy.context.scene.objects]}


def body_pass(key, bake=False):
    """Base body -> scaled, rigged, morphed to the concept (bake=True applies it)."""
    prepare(key, UNIFORM[key])
    rig(key, ARM_HEIGHTS[key])
    morph(key, MORPHS[key])
    if bake:
        apply_morph(key)


def reshape_pass(key, bake=False):
    """Finished character -> WoW-like heroic proportions, a little more realistic.

    Runs after hands_pass, on the rig and everything bound to it, so it needs no
    re-modelling; anim_pass must run again afterwards (and arkanor_hands.left_grip)."""
    _, _, rig = objects(key)
    if rig.animation_data:
        rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.matrix_basis = mathutils.Matrix()
    bpy.context.view_layer.update()
    ground = rig.data.bones["LeftFoot"].head_local.z
    morph(key, RESHAPE[key])
    hips = rig.pose.bones["Hips"]  # longer legs reach below the floor: lift the whole body
    hips.matrix = mathutils.Matrix.Translation((0, 0, ground - rig.pose.bones["LeftFoot"].head.z)) @ hips.matrix
    bpy.context.view_layer.update()
    if bake:
        apply_morph(key)


def seat_weights(key, keep=0.2):
    """The base mesh lets the thighs carry ~93% of the buttocks, so every stride swung the
    seat 7-13 cm against the pelvis: a swaying, feminine walk. Hand the buttocks and the
    back of the hips to the Hips bone, fading back to the thighs at the gluteal fold
    (the thighs keep `keep` of their share on top so the cheeks still flex a little).
    Runs on every mesh bound to the rig, after paint_pass (which rebuilds the game mesh)."""
    def smoothstep_f(e0, e1, x):  # arkanor_head's smoothstep, for one float
        t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
        return t * t * (3 - 2 * t)

    _, _, rig = objects(key)
    hip = rig.data.bones["LeftUpperLeg"].head_local
    fold = hip.z - 0.14  # gluteal fold, a little below the crotch
    for o in bpy.data.objects:
        if o.type != 'MESH' or not any(m.type == 'ARMATURE' and m.object == rig for m in o.modifiers):
            continue
        legs = {o.vertex_groups[n].index for n in ("LeftUpperLeg", "RightUpperLeg") if n in o.vertex_groups}
        if not legs:
            continue
        hips = o.vertex_groups.get("Hips") or o.vertex_groups.new(name="Hips")
        to_rig = rig.matrix_world.inverted() @ o.matrix_world
        for v in o.data.vertices:
            p = to_rig @ v.co
            t = (1 - keep) * smoothstep_f(fold, fold + 0.12, p.z) * smoothstep_f(hip.y - 0.02, hip.y + 0.07, p.y)
            if t <= 0:
                continue
            moved = 0.0
            for g in v.groups:
                if g.group in legs and g.weight > 0:
                    moved += g.weight * t
                    o.vertex_groups[g.group].add([v.index], g.weight * (1 - t), 'REPLACE')
            if moved:
                now = next((g.weight for g in v.groups if g.group == hips.index), 0.0)
                hips.add([v.index], now + moved, 'REPLACE')


# Second pass, from a WoW human reference: a 7.5-head figure (the stylized base
# is ~5.4), arms reaching mid-thigh with normal-size hands, narrower shoulders
# and stance. Factors are relative to the finished MORPHS shape.
RESHAPE = {
    "male": {
        "Hips": {"scale": (0.9, 1, 0.95)},
        "Spine": {"scale": (0.86, 1.1, 0.92)},
        "Chest": {"scale": (0.93, 1, 0.94)},
        "UpperChest": {"scale": (0.9, 1, 0.94)},
        "Neck": {"scale": (0.92, 0.9, 0.92)},
        "Head": {"scale": (0.735, 0.735, 0.735)},
        "Shoulder": {"scale": (1, 0.6, 1)},
        "UpperArm": {"scale": (0.97, 1.08, 0.97)},
        "LowerArm": {"scale": (0.97, 1.3, 0.97)},
        "Hand": {"scale": (0.86, 0.86, 0.86)},
        "UpperLeg": {"scale": (0.92, 1.08, 0.92), "abduct": -5},
        "LowerLeg": {"scale": (0.95, 1.08, 0.95)},
        "Foot": {"scale": (0.95, 0.95, 0.95), "abduct": 5},
    },
    "female": {
        "Neck": {"scale": (1, 0.95, 1)},
        "Head": {"scale": (0.75, 0.75, 0.75)},
        "UpperArm": {"scale": (1, 1.3, 1)},
        "LowerArm": {"scale": (1, 1.17, 1)},
        "Hand": {"scale": (0.9, 0.9, 0.9)},
        "UpperLeg": {"scale": (1, 1.07, 1), "abduct": -3},
        "LowerLeg": {"scale": (1, 1.07, 1)},
        "Foot": {"abduct": 3},
    },
}


# Proportions measured from the concept sheet (see morph()).
UNIFORM = {"male": 1.03, "female": 1.08}
ARM_HEIGHTS = {"male": (0.765, 0.62, 0.505), "female": (0.755, 0.64, 0.535)}  # shoulder, elbow, wrist / height
MORPHS = {
    # Hulking warrior: barrel torso, huge arms and hands, wide stance.
    "male": {
        "Hips": {"scale": (1.3, 1, 1.15)},
        "Spine": {"scale": (1.4, 1, 1.3)},
        "Chest": {"scale": (1.35, 1, 1.35)},
        "UpperChest": {"scale": (1.35, 1, 1.3)},
        "Neck": {"scale": (1.35, 1, 1.3)},
        "Shoulder": {"scale": (1.35, 1.6, 1.35)},
        "UpperArm": {"scale": (1.55, 1, 1.5), "abduct": 16},
        "LowerArm": {"scale": (1.45, 0.88, 1.4)},
        "Hand": {"scale": (1.35, 1.25, 1.35)},
        "UpperLeg": {"scale": (1.3, 1, 1.25), "abduct": 8},
        "LowerLeg": {"scale": (1.3, 1, 1.25)},
        "Foot": {"scale": (1.2, 1.15, 1.2), "abduct": -8},
        "Toes": {"scale": (1.2, 1, 1.2)},
    },
    # Athletic: thicker waist and limbs than the slim base, bigger hands.
    "female": {
        "Hips": {"scale": (1.18, 1, 1.1)},
        "Spine": {"scale": (1.3, 1, 1.15)},
        "Chest": {"scale": (1.18, 1, 1.1)},
        "UpperChest": {"scale": (1.12, 1, 1.05)},
        "Neck": {"scale": (1.05, 1, 1.05)},
        "Shoulder": {"scale": (1.1, 1.15, 1.1)},
        "UpperArm": {"scale": (1.15, 1, 1.15), "abduct": 10},
        "LowerArm": {"scale": (1.15, 1, 1.15)},
        "Hand": {"scale": (1.2, 1.2, 1.2)},
        "UpperLeg": {"scale": (1.2, 1, 1.15), "abduct": 6.5},
        "LowerLeg": {"scale": (1.12, 1, 1.1)},
        "Foot": {"scale": (1.1, 1.1, 1.1), "abduct": -6.5},
    },
}


# ---------------------------------------------------------------- skeleton

def mesh_coords(obj):
    import numpy as np
    me = obj.data
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    return co.reshape(-1, 3)


def slice_center(co, z, xmin, xmax, band=0.01):
    """Centroid (x, y) and y-depth of the verts in a horizontal band."""
    s = co[(abs(co[:, 2] - z) < band) & (co[:, 0] >= xmin) & (co[:, 0] <= xmax)]
    return s[:, 0].mean(), s[:, 1].mean(), s[:, 1].min(), s[:, 1].max()


def estimate_joints(obj, shoulder_n, elbow_n, wrist_n):
    """Joint positions (object space, left side = +X) from landmarks + ratios.

    The arm heights are passed in (fractions of height) because the A-pose
    arm merges with the torso near the shoulder and is hard to slice."""
    import numpy as np
    co = mesh_coords(obj)
    H = co[:, 2].max()
    mid = co[(abs(co[:, 0]) < 0.006) & (co[:, 2] > 0.3 * H)]
    crotch = mid[:, 2].min()
    j = {}

    def spine(z, back=0.2):
        x, y, y0, y1 = slice_center(co, z, -0.09, 0.09)
        return (0.0, y + back * (y1 - y0), z)

    j["Hips"] = spine(crotch + 0.07 * H)
    j["Spine"] = spine(crotch + 0.13 * H)
    j["Chest"] = spine(0.66 * H)
    j["UpperChest"] = spine(0.73 * H)
    j["Neck"] = spine(0.815 * H, 0.15)
    # skull base sits under the ear, not over the jaw: keep the neck's depth
    j["Head"] = (0.0, j["Neck"][1] - 0.01, 0.87 * H)
    j["HeadTop"] = (0.0, j["Head"][1], H)

    # Legs: centroid of the left leg slice at each height.
    def leg(z, front=0.0):
        x, y, y0, y1 = slice_center(co, z, 0.005, 0.1 * H)  # inside the hands
        return (x, y - front * (y1 - y0), z)

    hip = leg(crotch - 0.05 * H)
    j["UpperLeg"] = (hip[0], hip[1], crotch + 0.04 * H)
    j["LowerLeg"] = leg(0.275 * H, 0.08)
    j["Foot"] = leg(0.055 * H)
    foot = co[(co[:, 2] < 0.04 * H) & (co[:, 0] > 0)]
    toe_y, heel_y = foot[:, 1].min(), foot[:, 1].max()
    ball_y = toe_y + 0.3 * (heel_y - toe_y)
    ball = foot[abs(foot[:, 1] - ball_y) < 0.01]
    j["Toes"] = (ball[:, 0].mean(), ball_y, 0.022 * H)
    j["ToesEnd"] = (ball[:, 0].mean(), toe_y, 0.02 * H)

    # Arms: centroid of the outermost (arm) run of each horizontal slice.
    def arm(zn):
        z = zn * H
        s = co[(abs(co[:, 2] - z) < 0.008) & (co[:, 0] > 0)]
        s = s[np.argsort(s[:, 0])]
        gaps = np.where(np.diff(s[:, 0]) > 0.025)[0]
        run = s[gaps[-1] + 1:] if len(gaps) else s[s[:, 0] > s[:, 0].max() - 0.07]
        return np.array((run[:, 0].mean(), run[:, 1].mean(), z))

    hand = co[(co[:, 0] > 0.15 * H) & (co[:, 2] < 0.6 * H)]
    tip = hand[hand[:, 2].argmin()]
    wrist, elbow = arm(wrist_n), arm(elbow_n)
    sh = np.array((0.0, 0.0, shoulder_n * H))
    # shoulder joint on the elbow line, extended up to the shoulder height
    d = (elbow - wrist) / (elbow - wrist)[2]
    sh = elbow + d * (sh[2] - elbow[2])
    sh[0] = min(sh[0], 0.82 * co[abs(co[:, 2] - sh[2]) < 0.01][:, 0].max())
    sh[1] = j["UpperChest"][1] - 0.01
    j["UpperArm"], j["LowerArm"], j["Hand"] = tuple(sh), tuple(elbow), tuple(wrist)
    j["HandEnd"] = tuple(wrist + 0.55 * (tip - wrist))
    j["Shoulder"] = (0.03 * H, j["UpperChest"][1] - 0.04, sh[2] + 0.01 * H)
    return {k: tuple(round(float(c), 4) for c in v) for k, v in j.items()}


# bone: (head joint, tail joint, parent, mirrored)
BONES = [
    ("Hips", "Hips", "Spine", None, False),
    ("Spine", "Spine", "Chest", "Hips", False),
    ("Chest", "Chest", "UpperChest", "Spine", False),
    ("UpperChest", "UpperChest", "Neck", "Chest", False),
    ("Neck", "Neck", "Head", "UpperChest", False),
    ("Head", "Head", "HeadTop", "Neck", False),
    ("Shoulder", "Shoulder", "UpperArm", "UpperChest", True),
    ("UpperArm", "UpperArm", "LowerArm", "Shoulder", True),
    ("LowerArm", "LowerArm", "Hand", "UpperArm", True),
    ("Hand", "Hand", "HandEnd", "LowerArm", True),
    ("UpperLeg", "UpperLeg", "LowerLeg", "Hips", True),
    ("LowerLeg", "LowerLeg", "Foot", "UpperLeg", True),
    ("Foot", "Foot", "Toes", "LowerLeg", True),
    ("Toes", "Toes", "ToesEnd", "Foot", True),
]


def build_armature(key, joints):
    """Godot-humanoid bone names (LeftUpperArm, ...) so animations retarget."""
    body = bpy.data.objects["arkanor_%s_body" % key]
    arm = bpy.data.armatures.new("arkanor_%s_rig" % key)
    rig = bpy.data.objects.new("arkanor_%s_rig" % key, arm)
    body.users_collection[0].objects.link(rig)
    rig.location = body.location
    rig.show_in_front = True
    arm.display_type = 'STICK'
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    for name, head, tail, parent, mirrored in BONES:
        for side, sx in ((("Left", 1), ("Right", -1)) if mirrored else (("", 1),)):
            b = arm.edit_bones.new(side + name)
            b.head = (joints[head][0] * sx, joints[head][1], joints[head][2])
            b.tail = (joints[tail][0] * sx, joints[tail][1], joints[tail][2])
            if parent:
                mirrored_parent = parent not in ("Hips", "Spine", "Chest", "UpperChest", "Neck", "Head")
                b.parent = arm.edit_bones[(side if mirrored_parent else "") + parent]
                b.use_connect = name in ("Spine", "Chest", "UpperChest", "Neck", "Head", "LowerArm", "Hand", "LowerLeg", "Foot", "Toes")
    bpy.ops.object.mode_set(mode='OBJECT')
    return rig


def objects(key):
    body = bpy.data.objects["arkanor_%s_body" % key]
    eyes = [bpy.data.objects["arkanor_%s_eye.%s" % (key, s)] for s in "LR"]
    return body, eyes, bpy.data.objects.get("arkanor_%s_rig" % key)


def prepare(key, scale):
    """Detach the eyes and scale the base body uniformly about its feet."""
    body, eyes, _ = objects(key)
    bpy.context.view_layer.update()  # freshly appended objects have stale world matrices
    pivot = mathutils.Matrix.Translation(body.location)
    s = pivot @ mathutils.Matrix.Scale(scale, 4) @ pivot.inverted()
    for e in eyes:
        mw = e.matrix_world.copy()
        e.parent = None
        e.matrix_world = s @ mw
    body.data.transform(mathutils.Matrix.Scale(scale, 4))
    body.data.update()


def rig(key, arm_n):
    body, eyes, old = objects(key)
    if old:
        bpy.data.objects.remove(old)
    rig = build_armature(key, estimate_joints(body, *arm_n))
    bpy.ops.object.select_all(action='DESELECT')
    body.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    for e in eyes:
        mw = e.matrix_world.copy()
        e.parent, e.parent_type, e.parent_bone = rig, 'BONE', "Head"
        e.matrix_world = mw
    return rig


def morph(key, spec):
    """Pose the rig like character-creator sliders.

    spec: bone -> dict(scale=(width, length, depth), abduct=degrees). Mirrored
    bones are named without the side prefix. Abduction swings a limb outward
    around the front axis (and is used negatively to keep the feet flat)."""
    _, _, rig = objects(key)
    main = {s + name for name, _, _, _, mirrored in BONES for s in (("Left", "Right") if mirrored else ("",))}
    for b in rig.data.bones:
        # thickness sliders must not stack down the chain; fingers and grip markers follow the hand
        b.inherit_scale = 'NONE' if b.name in main else 'FULL'
    for name, _, _, _, mirrored in BONES:  # parents first
        if name not in spec:
            continue
        s = spec[name]
        for side, sign in ((("Left", -1), ("Right", 1)) if mirrored else (("", 0),)):
            pb = rig.pose.bones[side + name]
            pb.scale = s.get("scale", (1, 1, 1))
            if s.get("abduct"):
                bpy.context.view_layer.update()
                head = pb.head.copy()
                r = mathutils.Matrix.Rotation(math.radians(s["abduct"] * sign), 4, 'Y')
                pb.matrix = mathutils.Matrix.Translation(head) @ r @ mathutils.Matrix.Translation(-head) @ pb.matrix
            bpy.context.view_layer.update()


def apply_morph(key):
    """Bake the morph into every mesh bound to the rig and make the morphed pose the new rest.

    Only the armature deformation is baked (other modifiers stay live); objects
    parented to a bone keep where the pose put them."""
    import numpy as np
    _, _, rig = objects(key)
    bound = [o for o in bpy.data.objects if o.type == 'MESH'
             and any(m.type == 'ARMATURE' and m.object == rig for m in o.modifiers)]
    attached = [(o, o.matrix_world.copy()) for o in bpy.data.objects if o.parent == rig and o.parent_type == 'BONE']
    hidden = [(o, o.hide_viewport, o.hide_get()) for o in bound + [rig]]
    for o, _, _ in hidden:  # hidden objects are not evaluated and cannot enter pose mode
        o.hide_viewport = False
        o.hide_set(False)
    others = [(m, m.show_viewport) for o in bound for m in o.modifiers if m.type != 'ARMATURE']
    for m, _ in others:
        m.show_viewport = False
    deps = bpy.context.evaluated_depsgraph_get()
    for o in bound:
        ev = o.evaluated_get(deps).data
        co = np.empty(len(ev.vertices) * 3)
        ev.vertices.foreach_get("co", co)
        o.data.vertices.foreach_set("co", co)
        o.data.update()
    for m, shown in others:
        m.show_viewport = shown
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.pose.select_all(action='SELECT')
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    for b in rig.data.bones:
        b.inherit_scale = 'FULL'
    for o, mw in attached:
        o.matrix_world = mw
    for o, hv, hs in hidden:
        o.hide_viewport = hv
        o.hide_set(hs)


def solo(key=None, refs=False):
    """Show one character (or both with key=None); references on/off."""
    for o in bpy.context.scene.objects:
        if o.name.startswith("ref_"):
            o.hide_viewport = not refs or (key is not None and o.name.split("_")[1] != key)
        elif o.name.startswith("arkanor_"):
            o.hide_viewport = key is not None and o.name.split("_")[1] != key


def view(axis="FRONT", center=(0, 0, 0.95), distance=2.6):
    """Point every 3D viewport down an axis (orthographic, solid shading)."""
    rot = {"FRONT": (math.pi / 2, 0, 0), "RIGHT": (math.pi / 2, 0, math.pi / 2)}[axis]
    for area in bpy.context.screen.areas:
        if area.type == 'VIEW_3D':
            space = area.spaces.active
            space.shading.type = 'SOLID'
            space.shading.color_type = 'SINGLE'
            space.shading.single_color = (1.0, 0.35, 0.08)  # reads through the references
            space.overlay.show_relationship_lines = False
            r = space.region_3d
            r.view_perspective = 'ORTHO'
            r.view_rotation = mathutils.Euler(rot).to_quaternion()
            r.view_location = center
            r.view_distance = distance
