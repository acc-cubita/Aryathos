"""Our own hero animations, keyed pose by pose on the animation library's mannequin (the
UE-style skeleton of game/art/animations/ual1.glb), so Godot retargets them onto every
character like the library's clips.

    blender -b --python tools/art/blender/hero_moves.py -- [--shots <folder>]

Each move is a few key poses written as joint angles (degrees): how far each thigh swings
forward, how much each knee bends, how far each arm swings forward and each elbow bends,
the torso's lean, the hips' rise and fall. A pose sets every bone's direction in the body's
own frame, so the head stays level whatever the spine does. The second half of a cycle is
the first mirrored (left for right). Writes game/art/animations/hero_moves.glb; --shots
renders side views of the key times for comparing with the reference.

Mannequin frame (Blender): it faces -Y, up is +Z, its left is +X.
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[3]
LIBRARY = ROOT / "game" / "art" / "animations" / "ual1.glb"
OUT = ROOT / "game" / "art" / "animations" / "hero_moves.glb"
FPS = 30

## The run: 21 frames a cycle (0.7 s, about 170 steps a minute), studied from a reference
## run (passing, push-off, flight, landing, then the same on the other leg). Per key:
## frame; left leg (thigh forward, knee bend, ankle bend toes down); right leg; left arm (swing
## forward, elbow bend); right arm; torso lean; hips height change (m); hips turn toward
## the left leg (deg). The right half of the cycle mirrors these.
RUN = {
    "length": 21,
    "abduct_arm": 22.0,  # the upper arms held out from the body (broad shoulders and lats)
    "abduct_forearm": 4.0,  # the forearms hang nearly straight down from the elbows
    "across": 18.0,  # and swing in toward the middle as they come forward (fists before the belly)
    "adduct_leg": 4.5,  # the feet land near one line under the body (seen from ahead)
    "keys": [
        # (feet: the ankle's bend from square to the shin, + toes down, - toes up)
        # passing: the left leg under the body, knee well bent, foot flat; the right foot
        # passing behind at the other knee's height, hanging from the ankle; fists at the waist
        {"f": 0.0, "legL": (16, 58, -42), "legR": (-4, 98, 12), "armL": (-12, 74), "armR": (10, 76),
         "lean": 19, "bob": -0.075, "turn": 3},
        # push-off: the left leg driving back off its toes, the right knee forward and up
        {"f": 3.0, "legL": (-28, 16, 0), "legR": (46, 78, 8), "armL": (-36, 66), "armR": (20, 80),
         "lean": 21, "bob": -0.015, "turn": -2},
        # flight: the widest split, the back foot pointed, the front shin reaching, toes up
        {"f": 6.0, "legL": (-40, 38, 22), "legR": (46, 50, -6), "armL": (-42, 64), "armR": (24, 82),
         "lean": 20, "bob": 0.025, "turn": -5},
        # landing: the right heel comes down a little ahead of the hips
        {"f": 8.5, "legL": (-18, 92, 14), "legR": (26, 16, 0), "armL": (-26, 70), "armR": (16, 78),
         "lean": 19, "bob": -0.03, "turn": -4},
    ],
}


## The two-handed weapon held ready (a fighter's stance, studied from a reference): feet
## wide, the left a little ahead, toes out, knees bent and the hips down, the torso a little
## forward, the shoulders turned a little right. Here the legs and body breathe over 2 s; the hands go
## onto the haft in the game (TwoHandGrip), whatever the character's arms. Per key as RUN,
## plus each leg's spread (deg out to the side) and toes turned out (deg).
READY_2H = {
    "length": 60,
    "mirror": False,
    "grounded": True,  # the hips sit as low as the bent legs leave them
    "abduct_arm": 20.0, "abduct_forearm": 0.0, "across": 25.0, "adduct_leg": 0.0,
    "keys": [
        {"f": 0.0, "legL": (14, 32, -18), "legR": (-6, 18, -24), "armL": (30, 70), "armR": (15, 75),
         "spreadL": 12, "spreadR": 12, "toeL": 15, "toeR": 25, "lean": 10, "bob": 0.0, "turn": 0, "shoulders": -22},
        {"f": 30.0, "legL": (15, 35, -20), "legR": (-5, 21, -26), "armL": (30, 72), "armR": (15, 77),
         "spreadL": 12, "spreadR": 12, "toeL": 15, "toeR": 25, "lean": 11.5, "bob": 0.0, "turn": 0, "shoulders": -22},
    ],
}


## A two-handed sweep from the ready stance (studied from a reference): the body coils to
## the right (hips a fifth, shoulders more than half a right angle) as the weapon comes
## up over the right shoulder, the weight back on the right leg; then the hips lead the
## unwinding, the knees drop into the blow and the shoulders come round past square to the
## left (a third of a right angle: the weapon stops at the left side), held, and back. Only the body: the weapon's path, and the arms with it, are
## TwoHandGrip's "sweep" (the same times). 1 s; the blow at 0.31 s.
_READY = READY_2H["keys"][0]
STRIKE_2H = dict(READY_2H, length=30, keys=[
    dict(_READY, f=0.0),
    # coiled: the right knee bent, the left leg long
    dict(_READY, f=7.0, turn=-18, shoulders=-58, lean=10, legL=(12, 24, -12), legR=(-6, 30, -36)),
    # the blow: hips round first, square shoulders, both knees down
    dict(_READY, f=9.3, turn=12, shoulders=-4, lean=17, legL=(16, 40, -24), legR=(-4, 28, -32)),
    # round to the left, the weight onto the left leg
    dict(_READY, f=14.0, turn=22, shoulders=38, lean=15, legL=(16, 38, -22), legR=(-8, 16, -24)),
    dict(_READY, f=21.0, turn=20, shoulders=34, lean=13, legL=(15, 36, -21), legR=(-7, 17, -24)),
])


def mirrored(key, frame):
    """The same key on the other leg, `frame` later."""
    return {"f": key["f"] + frame, "legL": key["legR"], "legR": key["legL"], "armL": key["armR"],
            "armR": key["armL"], "lean": key["lean"], "bob": key["bob"], "turn": -key["turn"]}


def rot(axis, degrees):
    return Matrix.Rotation(math.radians(degrees), 4, axis)


def load_rig():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj)
    bpy.ops.import_scene.gltf(filepath=str(LIBRARY))
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    for obj in [o for o in bpy.data.objects if o.type == "MESH" and o.parent != rig]:
        bpy.data.objects.remove(obj)
    rig.animation_data_clear()  # the library's own clips (and their NLA tracks) stay out
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    rig.animation_data_create()
    return rig


def set_aim(rig, name, turn):
    """The bone's armature-space orientation = `turn` applied to its rest orientation (its
    place follows its parent)."""
    bone = rig.pose.bones[name]
    rest = rig.data.bones[name].matrix_local
    bone.matrix = Matrix.Translation(bone.matrix.to_translation()) @ (turn @ rest.to_3x3().to_4x4())
    bpy.context.view_layer.update()


def pose(rig, key, spec):
    """Every bone for one key (the order runs from the hips out)."""
    abduct = spec["abduct_arm"]
    pelvis = rig.pose.bones["pelvis"]
    pelvis.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    rest = rig.data.bones["pelvis"].matrix_local
    turn = rot("Z", key["turn"]) @ rot("X", key["lean"] * 0.25)
    pelvis.matrix = Matrix.Translation(rest.to_translation() + Vector((0, 0, key["bob"]))) @ (turn @ rest.to_3x3().to_4x4())
    bpy.context.view_layer.update()
    # the spine carries the rest of the lean, the shoulders turning back against the hips
    # the shoulders turn back against the hips (a runner), or, given "shoulders", turn that
    # far (deg, + to the left) with the hips, the spine sharing it out (a swing)
    for name, share in (("spine_01", 0.45), ("spine_02", 0.75), ("spine_03", 1.0)):
        if "shoulders" in key:
            turn_here = key["turn"] + (key["shoulders"] - key["turn"]) * share
        else:
            turn_here = -key["turn"] * share * 0.8
        set_aim(rig, name, rot("Z", turn_here) @ rot("X", key["lean"]))
    set_aim(rig, "neck_01", rot("X", key["lean"] * 0.4))
    set_aim(rig, "Head", Matrix.Identity(4))  # level, looking ahead
    for side, sign in (("l", 1.0), ("r", -1.0)):
        swing, bend = key["armL"] if side == "l" else key["armR"]
        set_aim(rig, "clavicle_" + side, Matrix.Identity(4))
        # down from the T-pose (about Y), out a little, then forward (about X)
        down = rot("Y", sign * (90.0 - abduct))
        set_aim(rig, "upperarm_" + side, rot("X", -swing) @ down)
        # the forearm: its own small lean out, swung forward, then turned in toward the middle
        fore = rot("Z", -sign * spec["across"]) @ rot("X", -swing - bend)
        fore_down = rot("Y", sign * (90.0 - spec["abduct_forearm"]))
        set_aim(rig, "lowerarm_" + side, fore @ fore_down)
        hand = rot("Z", -sign * spec["across"]) @ rot("X", -swing - bend + 10.0) @ fore_down
        set_aim(rig, "hand_" + side, hand)
        # closed fists: each finger joint curls about the hand's own across-the-palm axis
        for finger in ("index", "middle", "ring", "pinky"):
            for joint, curl in ((1, 55.0), (2, 100.0), (3, 140.0)):
                set_aim(rig, "%s_0%d_%s" % (finger, joint, side), hand @ rot("Y", sign * curl))
        for joint, curl in ((2, 25.0), (3, 45.0)):
            set_aim(rig, "thumb_0%d_%s" % (joint, side), hand @ rot("Y", sign * curl))
        thigh, knee, foot = key["legL"] if side == "l" else key["legR"]
        letter = "L" if side == "l" else "R"
        inward = rot("Y", sign * (spec["adduct_leg"] - key.get("spread" + letter, 0.0)))
        set_aim(rig, "thigh_" + side, rot("X", -thigh) @ inward)
        set_aim(rig, "calf_" + side, rot("X", -(thigh - knee)) @ inward)
        # the ankle bends from square to the shin (the rest foot stands square to an upright
        # shin), then the toes turn out
        toes = rot("Z", sign * key.get("toe" + letter, 0.0))
        set_aim(rig, "foot_" + side, toes @ rot("X", -(thigh - knee) + foot))
        set_aim(rig, "ball_" + side, toes @ rot("X", -(thigh - knee) + foot))
    if spec.get("grounded"):
        # the hips lowered until the lower ankle is as high as it stands at rest
        low = min(rig.pose.bones["foot_" + s].head.z for s in ("l", "r"))
        rest_low = min(rig.data.bones["foot_" + s].head_local.z for s in ("l", "r"))
        pelvis.matrix = Matrix.Translation(Vector((0, 0, rest_low - low))) @ pelvis.matrix
        bpy.context.view_layer.update()


def key_all(rig, frame):
    for bone in rig.pose.bones:
        bone.keyframe_insert("location", frame=frame)
        bone.keyframe_insert("rotation_quaternion", frame=frame)


def make_cycle(rig, name, spec):
    action = bpy.data.actions.new(name)
    rig.animation_data.action = action
    for bone in rig.pose.bones:
        bone.rotation_mode = "QUATERNION"
    length = spec["length"]
    keys = list(spec["keys"])
    if spec.get("mirror", True):
        keys += [mirrored(k, length / 2.0) for k in spec["keys"]]
    keys.append(dict(keys[0], f=float(length)))  # the loop closes on its first pose
    for key in keys:
        pose(rig, key, spec)
        key_all(rig, 1 + key["f"])
    for fcurve in _fcurves(action):
        for point in fcurve.keyframe_points:
            point.interpolation = "BEZIER"
            point.handle_left_type = point.handle_right_type = "AUTO_CLAMPED"
    action.use_fake_user = True
    return action


def _fcurves(action):
    if hasattr(action, "fcurves") and len(action.fcurves):
        return list(action.fcurves)
    curves = []
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                curves.extend(bag.fcurves)
    return curves


def ground_speed(rig, action, side, landing, push_off):
    """The speed the cycle is made for: how fast the planted foot (from `landing` to
    `push_off`, frames into the cycle) moves back under the body."""
    rig.animation_data.action = action
    places = []
    for frame in (landing, push_off):
        bpy.context.scene.frame_set(int(1 + frame), subframe=(1 + frame) % 1.0)
        foot = rig.pose.bones["ball_" + side].head
        places.append(foot.y - rig.pose.bones["pelvis"].head.y)
    return (places[1] - places[0]) / ((push_off - landing) / FPS)


def shots(rig, action, folder, frames):
    """Side views of the key times."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x, scene.render.resolution_y = 300, 350
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "SINGLE"
    camera = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.3
    camera.location = (-6.0, -0.15, 0.95)  # from its right: it runs to the right, as the reference does
    camera.rotation_euler = (math.radians(90), 0, math.radians(-90))
    rig.animation_data.action = action
    Path(folder).mkdir(parents=True, exist_ok=True)
    for frame in frames:
        scene.frame_set(frame)
        scene.render.filepath = str(Path(folder) / ("%s_%02d.png" % (action.name, frame)))
        bpy.ops.render.render(write_still=True)


def export(rig, actions):
    rig.animation_data.action = actions[0]
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    for child in rig.children:
        child.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=str(OUT), use_selection=True, export_format="GLB", export_yup=True,
                              export_animations=True, export_animation_mode="ACTIONS",
                              export_force_sampling=True, export_frame_step=1)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    bpy.context.scene.render.fps = FPS
    rig = load_rig()
    run = make_cycle(rig, "Run_Loop", RUN)
    print("moves: Run_Loop made for %.2f m/s on the mannequin" % ground_speed(rig, run, "r", 8.5, 13.5))
    ready = make_cycle(rig, "Ready2H_Loop", READY_2H)
    strike = make_cycle(rig, "Strike2H", STRIKE_2H)
    if "--shots" in args:
        shots(rig, run, args[args.index("--shots") + 1], [1, 4, 7, 10, 12, 15, 18, 21])
    export(rig, [run, ready, strike])
    print("moves: exported", OUT)
