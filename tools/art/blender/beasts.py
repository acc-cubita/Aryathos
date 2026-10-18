"""Beasts for the game from Sketchfab glTF downloads (CC-BY, credited in game/CREDITS.md):
the Shardfang wolf ("Animated Wolf Scene" by Roo) and Grimjaw the Shardmaw ("Realistic
Animated Bear 3D Model" by WildMesh 3D).

    blender -b --factory-startup --python tools/art/blender/beasts.py -- [wolf] [bear] [--shots <folder>]

Per beast: imports art/vendor/sketchfab/<beast>/scene.gltf, keeps the clips the game uses
under plain names (idle, walk, run, attack..., hit, death; see CLIPS), and exports
game/art/creatures/<beast>.glb. The wolf comes with idle / walk / run only, so its bite,
flinch and death are keyed here on top of its idle pose (WOLF_KEYS). Prints each gait's
ground speed (m/s at the model's own size: how fast a planted paw slides back), which the
game's BeastModel uses to pace the clips. --shots renders key frames of the clips.
"""
import math
import os
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "art" / "vendor" / "sketchfab"
OUT = ROOT / "game" / "art" / "creatures"

# game clip name -> source action (None: keyed by this script)
CLIPS = {
    "wolf": {"idle": "Wolf_Idle_", "walk": "Wolf_Walk_cycle_", "run": "Wolf_Run_Cycle_",
             "bite": None, "hit": None, "death": None},
    "bear": {"idle": "Stand_Idle_01", "angry": "StandAngry_Breathing_01", "walk": "Walk", "trot": "Trot",
             "run": "Run", "swipe": "Attack_StandAngry_01_High", "swipe2": "Attack_StandAngry_02_High",
             "lunge": "Attack_StandAngry_01_Low", "hit": "Hit_Stand_F01", "death": "Death_Stand_R01",
             "rear": "Trans_Stand_to_StandHind", "rear_hold": "StandHind_Breathing_01"},
}
# paws whose planted slide gives a gait's ground speed
PAWS = {"wolf": ["Vorderpfote_L", "Vorderpfote_R", "Pfote2_L", "Pfote2_R"],
        "bear": ["RigLFLegDigit11_018", "RigRFLegDigit11_033", "RigLBLegDigit11_06", "RigRBLegDigit11_010"]}
GAITS = {"wolf": ["walk", "run"], "bear": ["walk", "trot", "run"]}
# beasts whose clips walk them forward on their own (root motion on this bone)
ROOT_MOTION = {"bear": "RigRoot_01"}

# The wolf's own clips, keyed on its idle pose. World axes: the wolf faces -Y, +X is its
# left, +Z up. Per key frame: bone -> (turns, shift); turns are (axis, degrees) about a
# world axis through the bone's head, applied parent first; shift is a world offset (m).
# "X" turns tip the front of a bone down (nose down, jaw open, leg forward for negative).
X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
EARS_BACK = {"Ohr_L": ([(X, -35)], None), "Ohr_R": ([(X, -35)], None)}
WOLF_KEYS = {
    "bite": (17, {
        5: {"Becken": ([], Vector((0, 0.05, -0.03))), "Brust": ([(X, -4)], None), "Hals": ([(X, -18)], None),
            "Kopf": ([(X, -8)], None), "Unterkiefer": ([(X, 8)], None), **EARS_BACK},
        9: {"Becken": ([], Vector((0, -0.13, -0.02))), "Brust": ([(X, 7)], None), "Hals": ([(X, 32)], None),
            "Kopf": ([(X, -20)], None), "Unterkiefer": ([(X, 40)], None),
            "Oberarm_L": ([(X, -22)], None), "Oberarm_R": ([(X, -16)], None),
            "Oberschenkel_L": ([(X, -8)], None), "Oberschenkel_R": ([(X, -8)], None), **EARS_BACK},
        12: {"Becken": ([], Vector((0, -0.11, -0.02))), "Brust": ([(X, 6)], None), "Hals": ([(X, 28)], None),
             "Kopf": ([(X, -16), (Z, 14)], None), "Unterkiefer": ([(X, 2)], None),
             "Oberarm_L": ([(X, -18)], None), "Oberarm_R": ([(X, -12)], None),
             "Oberschenkel_L": ([(X, -6)], None), "Oberschenkel_R": ([(X, -6)], None), **EARS_BACK},
        14: {"Becken": ([], Vector((0, -0.06, -0.01))), "Hals": ([(X, 14)], None),
             "Kopf": ([(X, -8), (Z, -10)], None), **EARS_BACK},
    }),
    "hit": (10, {
        3: {"Becken": ([(Z, 4)], Vector((0, 0.04, 0.01))), "Hals": ([(X, -14)], None),
            "Kopf": ([(X, -6), (Z, 12)], None), "Unterkiefer": ([(X, 14)], None), **EARS_BACK},
        6: {"Becken": ([(Z, 2)], Vector((0, 0.02, 0))), "Hals": ([(X, -6)], None), "Kopf": ([(Z, 6)], None),
            **EARS_BACK},
    }),
    "death": (30, {
        6: {"Becken": ([], Vector((0, 0.02, -0.08))), "Hals": ([(X, -14)], None), "Unterkiefer": ([(X, 22)], None),
            "Oberarm_L": ([(X, -18)], None), "Oberarm_R": ([(X, -18)], None),
            "Unterarm_L": ([(X, 30)], None), "Unterarm_R": ([(X, 30)], None),
            "Oberschenkel_L": ([(X, 16)], None), "Oberschenkel_R": ([(X, 16)], None),
            "Unterschenkel_L": ([(X, -22)], None), "Unterschenkel_R": ([(X, -22)], None), **EARS_BACK},
        14: {"Becken": ([(Y, 50)], "ground"), "Hals": ([(X, -8)], None), "Unterkiefer": ([(X, 16)], None),
             "Oberarm_L": ([(X, -10)], None), "Oberarm_R": ([(X, -10)], None),
             "Unterarm_L": ([(X, 18)], None), "Unterarm_R": ([(X, 18)], None),
             "Oberschenkel_L": ([(X, 10)], None), "Oberschenkel_R": ([(X, 10)], None),
             "Unterschenkel_L": ([(X, -12)], None), "Unterschenkel_R": ([(X, -12)], None), **EARS_BACK},
        22: {"Becken": ([(Y, 88)], "ground"), "Hals": ([(Y, -10)], None), "Kopf": ([(Y, -12)], None),
             "Unterkiefer": ([(X, 10)], None),
             "Oberarm_L": ([(X, -8), (Y, -12)], None), "Oberarm_R": ([(X, 6), (Y, -18)], None),
             "Unterarm_L": ([(X, 10)], None), "Unterarm_R": ([(X, 16)], None),
             "Oberschenkel_L": ([(X, 14), (Y, -10)], None), "Oberschenkel_R": ([(X, -6), (Y, -16)], None),
             "Unterschenkel_L": ([(X, -10)], None), "Unterschenkel_R": ([(X, -16)], None),
             "Schwanz": ([(Y, -10)], None), **EARS_BACK},
        30: {"Becken": ([(Y, 92)], "ground"), "Hals": ([(Y, -14)], None), "Kopf": ([(Y, -16)], None),
             "Unterkiefer": ([(X, 8)], None),
             "Oberarm_L": ([(X, -8), (Y, -14)], None), "Oberarm_R": ([(X, 6), (Y, -20)], None),
             "Unterarm_L": ([(X, 10)], None), "Unterarm_R": ([(X, 16)], None),
             "Oberschenkel_L": ([(X, 14), (Y, -12)], None), "Oberschenkel_R": ([(X, -6), (Y, -18)], None),
             "Unterschenkel_L": ([(X, -10)], None), "Unterschenkel_R": ([(X, -16)], None),
             "Schwanz": ([(Y, -14)], None), "Schwanz.001": ([(Y, -8)], None)},
    }),
}
FPS = 24


def load(beast):
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE / beast / "scene.gltf"))
    for obj in list(bpy.data.objects):
        if obj.name.startswith("Icosphere"):  # the importer's bone display shape
            bpy.data.objects.remove(obj)
    bpy.context.scene.render.fps = FPS
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    return rig, [o for o in bpy.data.objects if o.type == "MESH"]


def play(rig, action, frame):
    rig.animation_data_create()
    rig.animation_data.action = action
    if action is not None and action.slots:
        rig.animation_data.action_slot = action.slots[0]
    bpy.context.scene.frame_set(int(frame))
    bpy.context.view_layer.update()


def bone(rig, short):
    names = [b.name for b in rig.pose.bones]
    return rig.pose.bones[next(n for n in names if n == short or n.startswith(short + "_"))]


def lowest(meshes):
    deps = bpy.context.evaluated_depsgraph_get()
    low = math.inf
    for obj in meshes:
        ev = obj.evaluated_get(deps)
        mesh = ev.to_mesh()
        low = min(low, min((obj.matrix_world @ v.co).z for v in mesh.vertices))
        ev.to_mesh_clear()
    return low


def pose_key(rig, meshes, base, changes):
    """Base pose, then each change: turn about world axes through the bone head (parents
    first, as listed), then shift; "ground" lowers that bone until the body rests on z=0.
    Returns {bone: (rotation_quaternion, location)} for every bone."""
    rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.rotation_quaternion, pb.location = base[pb.name]
        pb.scale = (1, 1, 1)
    bpy.context.view_layer.update()
    world = rig.matrix_world
    for short, (turns, shift) in changes.items():
        pb = bone(rig, short)
        m = world @ pb.matrix
        head = m.translation.copy()
        for axis, degrees in turns:
            m = Matrix.Translation(head) @ Matrix.Rotation(math.radians(degrees), 4, axis) @ Matrix.Translation(-head) @ m
        if isinstance(shift, Vector):
            m = Matrix.Translation(shift) @ m
        pb.matrix = world.inverted() @ m
        pb.scale = (1, 1, 1)
        bpy.context.view_layer.update()
        if shift == "ground":
            drop = lowest(meshes) - 0.005
            pb.matrix = world.inverted() @ Matrix.Translation((0, 0, -drop)) @ world @ pb.matrix
            pb.scale = (1, 1, 1)
            bpy.context.view_layer.update()
    return {pb.name: (pb.rotation_quaternion.copy(), pb.location.copy()) for pb in rig.pose.bones}


def key_action(rig, name, poses):
    """An action from {frame: {bone: (quaternion, location)}}."""
    action = bpy.data.actions.new(name)
    rig.animation_data.action = action
    for frame, pose in sorted(poses.items()):
        for bone_name, (quat, loc) in pose.items():
            for path, values in (("rotation_quaternion", quat), ("location", loc)):
                for i, value in enumerate(values):
                    curve = action.fcurve_ensure_for_datablock(rig, 'pose.bones["%s"].%s' % (bone_name, path), index=i)
                    curve.keyframe_points.insert(frame, value, options={"FAST"})
    rig.animation_data.action = None
    return action


def wolf_clips(rig, meshes):
    play(rig, bpy.data.actions["Wolf_Idle_"], 0)
    base = {pb.name: (pb.rotation_quaternion.copy(), pb.location.copy()) for pb in rig.pose.bones}
    made = {}
    for clip, (length, keys) in WOLF_KEYS.items():
        poses = {0: pose_key(rig, meshes, base, {})}
        for frame, changes in keys.items():
            poses[frame] = pose_key(rig, meshes, base, changes)
        if clip != "death":
            poses[length] = poses[0]
        made[clip] = key_action(rig, "wolf_" + clip, poses)
    return made


def gait_speed(rig, action, paws):
    """Ground speed of a cycle: how fast a planted paw moves back (m/s)."""
    start, end = (int(f) for f in action.frame_range)
    world = rig.matrix_world
    tracks = {p: [] for p in paws}
    for frame in range(start, end + 1):
        play(rig, action, frame)
        for p in paws:
            tracks[p].append(world @ bone(rig, p).head)
    speeds = []
    for track in tracks.values():
        low = min(t.z for t in track)
        for a, b in zip(track, track[1:]):
            if a.z < low + 0.015 and b.z < low + 0.015:
                speeds.append(abs(b.y - a.y) * FPS)
    speeds.sort()
    return speeds[len(speeds) // 2] if speeds else 0.0


def strip_root_motion(rig, root):
    """The game moves the unit, so the root's travel comes out of every clip; returns
    each clip's travel speed (m/s) before it was taken out."""
    speeds = {}
    path = 'pose.bones["%s"].location' % root
    world = rig.matrix_world
    for action in bpy.data.actions:
        start, end = (int(f) for f in action.frame_range)
        play(rig, action, start)
        a = world @ rig.pose.bones[root].head
        play(rig, action, end)
        b = world @ rig.pose.bones[root].head
        speeds[action.name] = (b - a).length * FPS / max(end - start, 1)
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for curve in bag.fcurves:
                        if curve.data_path == path:
                            for key in curve.keyframe_points:
                                key.co.y = key.handle_left.y = key.handle_right.y = 0.0
    return speeds


def build(beast, shots=None):
    rig, meshes = load(beast)
    made = wolf_clips(rig, meshes) if beast == "wolf" else {}
    keep = {}
    for clip, source in CLIPS[beast].items():
        action = made[clip] if source is None else bpy.data.actions[source]
        keep[action.name] = clip
    for action in list(bpy.data.actions):
        if action.name not in keep:
            bpy.data.actions.remove(action)
    for action in list(bpy.data.actions):
        action.name = keep[action.name]
        action.use_fake_user = True
    travel = strip_root_motion(rig, ROOT_MOTION[beast]) if beast in ROOT_MOTION else {}
    for gait in GAITS[beast]:
        speed = travel[gait] if gait in travel else gait_speed(rig, bpy.data.actions[gait], PAWS[beast])
        print("beasts: %s %s %.2f m/s" % (beast, gait, speed))
    if shots:
        render(beast, rig, meshes, shots)
    play(rig, None, 0)
    for pb in rig.pose.bones:
        pb.rotation_quaternion, pb.location, pb.scale = (1, 0, 0, 0), (0, 0, 0), (1, 1, 1)
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / (beast + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", export_yup=True, export_apply=False,
                              export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True,
                              export_def_bones=False, export_image_format="AUTO")
    print("beasts: %s clips %s, %d tris -> %s" % (beast, sorted(keep.values()),
                                                   sum(sum(len(p.vertices) - 2 for p in m.data.polygons) for m in meshes), path))


def render(beast, rig, meshes, folder):
    """Side views of each clip at a few moments (Cycles)."""
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
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 400, 260
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.6, 0.68, 1)
    scene.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (0.8, 0.2, -0.7)
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    play(rig, bpy.data.actions["idle"], 0)
    deps = bpy.context.evaluated_depsgraph_get()
    pts = []
    for m in meshes:
        ev = m.evaluated_get(deps)
        pts += [m.matrix_world @ v.co for v in ev.to_mesh().vertices]
        ev.to_mesh_clear()
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    centre, size = (lo + hi) / 2, (hi - lo).length
    cam.location = centre + Vector((1, -0.35, 0.3)).normalized() * size * 2.0
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
    os.makedirs(folder, exist_ok=True)
    for action in bpy.data.actions:
        start, end = (int(f) for f in action.frame_range)
        for i in range(5):
            frame = start + (end - start) * i // 4
            play(rig, action, frame)
            scene.render.filepath = os.path.join(folder, "%s_%s_%d.png" % (beast, action.name, i))
            bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    shots = args[args.index("--shots") + 1] if "--shots" in args else None
    for beast in [a for a in ("wolf", "bear") if a in args] or ["wolf", "bear"]:
        build(beast, shots)
