"""Builds the Arkanor (male) character in Blender and paints it in a hand-painted style.

Run (no Blender window needed):
  blender --background --factory-startup --python tools/art/blender/arkanor.py -- <out_dir>

1. Grows the body from a skin-modifier skeleton (heroic proportions, separate fingers)
   and adds the face, hair, braided beard and clothing details from the modeling sheet.
2. Joins everything into one mesh and unwraps it.
3. Bakes a painted texture in Cycles, the way WoW characters are painted: base colors
   with fabric folds, hair strands and glowing rune tattoos, darkened in crevices by
   ambient occlusion, lit from above and with highlighted edges. A second glow map
   holds the eyes and tattoos.
Saves <out_dir>/arkanor.blend, arkanor_paint.png, arkanor_glow.png and preview renders.
"""
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

OUT = Path(sys.argv[sys.argv.index("--") + 1]) if "--" in sys.argv else Path.cwd()
PAINT_SIZE = 2048
GLOW_SIZE = 1024

# Linear base colors before painting.
BASE = {
    "skin": (0.52, 0.32, 0.23),
    "tunic": (0.26, 0.23, 0.17),
    "trousers": (0.2, 0.19, 0.15),
    "sash": (0.17, 0.13, 0.09),
    "boots": (0.17, 0.09, 0.045),
    "sole": (0.06, 0.04, 0.03),
    "hair": (0.68, 0.68, 0.7),
    "trim": (0.48, 0.5, 0.55),
    "eye_blue": (0.3, 0.75, 1.0),
    "eye_amber": (1.0, 0.6, 0.15),
}
RUNE_GLOW = (0.3, 0.8, 1.0)


# ---------------------------------------------------------------- geometry

def material(name):
    if name not in bpy.data.materials:
        bpy.data.materials.new(name)
    return bpy.data.materials[name]


def bake_modifiers(obj):
    """Replaces the object's mesh with its evaluated (modified) mesh."""
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = bpy.data.meshes.new_from_object(evaluated)
    obj.modifiers.clear()
    old = obj.data
    obj.data = mesh
    bpy.data.meshes.remove(old)
    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


def skin_object(name, nodes, edges, mat=None, subdivisions=2, paint=None):
    """A smooth mesh grown around a graph: nodes = {key: (position, (radius_x, radius_y))}.
    `paint(obj)` may assign materials to the coarse mesh before it is smoothed, so the
    borders between materials follow its edge loops."""
    keys = list(nodes)
    mesh = bpy.data.meshes.new(name + "Graph")
    mesh.from_pydata([nodes[k][0] for k in keys], [(keys.index(a), keys.index(b)) for a, b in edges], [])
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.modifiers.new("Skin", "SKIN")
    skin = mesh.skin_vertices[0].data
    for i, k in enumerate(keys):
        radius = nodes[k][1]
        skin[i].radius = (radius, radius) if isinstance(radius, float) else radius
    skin[0].use_root = True
    bake_modifiers(obj)
    if mat:
        obj.data.materials.append(material(mat))
    if paint:
        paint(obj)
    sub = obj.modifiers.new("Smooth", "SUBSURF")
    sub.levels = subdivisions
    sub.render_levels = subdivisions
    return bake_modifiers(obj)


def chain(name, points, mat, subdivisions=1):
    """A skin tube through points [(position, radius), ...]."""
    nodes = {str(i): (p, (r, r) if isinstance(r, float) else r) for i, (p, r) in enumerate(points)}
    edges = [(str(i), str(i + 1)) for i in range(len(points) - 1)]
    return skin_object(name, nodes, edges, mat, subdivisions)


def sphere(name, mat, radius, location, scale=(1, 1, 1), rotation=(0, 0, 0), segments=16, rings=10):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=location, segments=segments, ring_count=rings)
    return finish(name, mat, scale, rotation)


def torus(name, mat, major, minor, location, scale=(1, 1, 1), rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=location, major_segments=32, minor_segments=8)
    return finish(name, mat, scale, rotation)


def box(name, mat, location, scale, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = finish(name, mat, scale, rotation)
    bevel = obj.modifiers.new("Soft", "BEVEL")
    bevel.width = min(scale) * 0.3
    bevel.segments = 2
    return bake_modifiers(obj)


def finish(name, mat, scale, rotation):
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    obj.rotation_euler = [math.radians(a) for a in rotation]
    obj.data.materials.append(material(mat))
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def mirror_x(p):
    return (-p[0], p[1], p[2])


def body():
    # Front faces -Y. Heights in meters; the top of the head is about 1.93 m.
    nodes = {
        "pelvis": ((0, 0.0, 1.0), (0.2, 0.15)),
        "belly": ((0, -0.015, 1.14), (0.225, 0.17)),
        "chest": ((0, -0.025, 1.31), (0.27, 0.18)),
        "upper_chest": ((0, -0.005, 1.45), (0.31, 0.17)),
        "trapezius": ((0, 0.01, 1.525), (0.2, 0.13)),
        "neck": ((0, 0.015, 1.59), (0.1, 0.1)),
        "jaw": ((0, -0.01, 1.66), (0.112, 0.118)),
        "head": ((0, 0.0, 1.765), (0.12, 0.13)),
        "crown": ((0, 0.012, 1.86), (0.098, 0.108)),
    }
    right = {
        "shoulder": ((0.3, 0.0, 1.49), (0.135, 0.125)),
        "bicep": ((0.39, 0.0, 1.375), (0.105, 0.1)),
        "elbow": ((0.475, 0.0, 1.26), (0.08, 0.08)),
        "forearm": ((0.54, -0.01, 1.165), (0.092, 0.082)),
        "wrist": ((0.62, -0.02, 1.055), (0.056, 0.046)),
        "palm": ((0.665, -0.025, 0.99), (0.05, 0.05)),
        "palm_end": ((0.695, -0.028, 0.95), (0.045, 0.045)),
        "hip": ((0.12, 0.0, 0.95), (0.13, 0.13)),
        "thigh": ((0.135, 0.0, 0.76), (0.122, 0.122)),
        "knee": ((0.145, -0.012, 0.55), (0.093, 0.095)),
        "calf": ((0.15, 0.012, 0.37), (0.11, 0.115)),
        "ankle": ((0.155, 0.0, 0.13), (0.095, 0.1)),
        "heel": ((0.155, 0.03, 0.05), (0.08, 0.075)),
        "toe": ((0.16, -0.2, 0.055), (0.082, 0.055)),
    }
    for key, (pos, radius) in right.items():
        nodes["r_" + key] = (pos, radius)
        nodes["l_" + key] = (mirror_x(pos), radius)
    edges = [("pelvis", "belly"), ("belly", "chest"), ("chest", "upper_chest"), ("upper_chest", "trapezius"), ("trapezius", "neck"),
             ("neck", "jaw"), ("jaw", "head"), ("head", "crown")]
    for side in ("r_", "l_"):
        for a, b in [("upper_chest", "shoulder"), ("shoulder", "bicep"), ("bicep", "elbow"), ("elbow", "forearm"),
                     ("forearm", "wrist"), ("wrist", "palm"), ("palm", "palm_end"), ("pelvis", "hip"),
                     ("hip", "thigh"), ("thigh", "knee"), ("knee", "calf"), ("calf", "ankle"), ("ankle", "heel"),
                     ("ankle", "toe")]:
            edges.append((a if a in nodes else side + a, side + b))
    return skin_object("Arkanor", nodes, edges, paint=assign_regions)


def assign_regions(obj):
    """Colors the coarse body: skin, tunic with short sleeves, sash, trousers, boots."""
    names = ["skin", "tunic", "trousers", "sash", "boots"]
    for name in names:
        obj.data.materials.append(material(name))
    for poly in obj.data.polygons:
        c = poly.center
        side = abs(c.x)
        region = "skin"
        if c.z < 0.46:
            region = "boots"
        elif c.z < 0.98:
            region = "trousers" if side < 0.3 else "skin"
        elif c.z < 1.09 and side < 0.3:
            region = "sash"
        elif c.z < 1.575 and side < 0.415:
            region = "tunic"
        poly.material_index = names.index(region)


def hands():
    """Four fingers and a thumb per hand, relaxed and slightly curled toward the legs."""
    down = Vector((0.555, 0.0, -0.832))
    curl = Vector((-1.0, 0.0, 0.0))
    knuckles = Vector((0.7, -0.028, 0.945))
    for mirror in (False, True):
        for i, (offset, length) in enumerate([(-0.04, 0.085), (-0.013, 0.095), (0.013, 0.09), (0.038, 0.075)]):
            start = knuckles + Vector((0, offset, 0))
            points = [(start, 0.019), (start + down * length * 0.5 + curl * 0.012, 0.017), (start + down * length + curl * 0.032, 0.014)]
            finger(f"Finger{i}", points, mirror)
        finger("Thumb", [(Vector((0.655, -0.055, 1.0)), 0.023), (Vector((0.668, -0.087, 0.965)), 0.019), (Vector((0.676, -0.1, 0.935)), 0.015)], mirror)


def finger(name, points, mirror):
    if mirror:
        points = [(Vector((-p.x, p.y, p.z)), r) for p, r in points]
    chain(name, [(tuple(p), r) for p, r in points], "skin")


def face():
    sphere("BrowRidge", "skin", 1.0, (0, -0.103, 1.812), scale=(0.105, 0.04, 0.03))
    for x in (0.068, -0.068):
        sphere("Cheek", "skin", 1.0, (x * 0.95, -0.1, 1.758), scale=(0.028, 0.018, 0.02))
        sphere("Ear", "skin", 1.0, (x * 1.9, 0.0, 1.775), scale=(0.014, 0.027, 0.04), rotation=(0, 0, 12 if x > 0 else -12))
        sphere("Brow", "hair", 1.0, (x * 0.68, -0.137, 1.824), scale=(0.046, 0.016, 0.011), rotation=(0, -18 if x > 0 else 18, 0))
    chain("Nose", [((0, -0.135, 1.8), 0.017), ((0, -0.165, 1.752), 0.024), ((0, -0.148, 1.733), (0.03, 0.02))], "skin")
    sphere("EyeLeft", "eye_blue", 0.013, (-0.045, -0.121, 1.794), scale=(1.25, 0.7, 0.62), segments=12, rings=8)
    sphere("EyeRight", "eye_amber", 0.013, (0.045, -0.121, 1.794), scale=(1.25, 0.7, 0.62), segments=12, rings=8)


def hair():
    sphere("HairCap", "hair", 0.132, (0, 0.022, 1.805), scale=(1.03, 1.02, 0.95), segments=24, rings=14)
    sphere("Bun", "hair", 0.066, (0, 0.055, 1.935))
    torus("BunBand", "trim", 0.05, 0.012, (0, 0.055, 1.905))
    # Braids from each temple back to the bun.
    for x in (1, -1):
        braid("SideBraid", [(x * 0.118, -0.04, 1.83), (x * 0.1, 0.02, 1.9), (x * 0.04, 0.05, 1.93)], 0.016)
    # The beard: sideburns into a full beard that narrows into one long braid.
    nodes = {
        "chin": ((0, -0.115, 1.68), (0.12, 0.07)),
        "r_side": ((0.118, -0.02, 1.75), (0.03, 0.03)),
        "r_cheek": ((0.095, -0.085, 1.69), (0.05, 0.05)),
        "l_side": ((-0.118, -0.02, 1.75), (0.03, 0.03)),
        "l_cheek": ((-0.095, -0.085, 1.69), (0.05, 0.05)),
        "mid": ((0, -0.158, 1.6), (0.115, 0.07)),
        "low": ((0, -0.182, 1.52), (0.08, 0.055)),
        "braid": ((0, -0.192, 1.47), (0.045, 0.04)),
    }
    edges = [("chin", "r_cheek"), ("r_cheek", "r_side"), ("chin", "l_cheek"), ("l_cheek", "l_side"),
             ("chin", "mid"), ("mid", "low"), ("low", "braid")]
    skin_object("Beard", nodes, edges, "hair")
    braid("BeardBraid", [(0, -0.192, 1.47), (0, -0.194, 1.4), (0, -0.19, 1.35)], 0.032)
    sphere("BeardBead", "trim", 0.034, (0, -0.19, 1.345))
    chain("BeardTip", [((0, -0.19, 1.32), 0.025), ((0, -0.188, 1.27), 0.01)], "hair")
    moustache = [((0, -0.15, 1.728), (0.036, 0.024))]
    for x in (1, -1):
        moustache += [((x * 0.065, -0.132, 1.702), 0.026), ((x * 0.078, -0.12, 1.655), 0.017)]
    skin_object("Moustache", {
        "c": moustache[0], "r1": moustache[1], "r2": moustache[2], "l1": moustache[3], "l2": moustache[4],
    }, [("c", "r1"), ("r1", "r2"), ("c", "l1"), ("l1", "l2")], "hair", subdivisions=1)


def braid(name, path, radius):
    """Plaited hair: overlapping beads that zig-zag along the path."""
    points = [Vector(p) for p in path]
    steps = []
    for a, b in zip(points, points[1:]):
        count = max(2, int((b - a).length / (radius * 0.75)))
        steps += [a.lerp(b, i / count) for i in range(count)]
    steps.append(points[-1])
    for i, p in enumerate(steps):
        side = Vector((radius * 0.3 * (1 if i % 2 else -1), 0, 0))
        sphere(name, "hair", radius, p + side, scale=(1.0, 0.8, 0.62), segments=10, rings=6)


def clothes():
    bpy.ops.mesh.primitive_cone_add(vertices=28, radius1=0.3, radius2=0.235, depth=0.32, end_fill_type="NOTHING", location=(0, 0, 0.875))
    skirt = finish("TunicSkirt", "tunic", (1.0, 0.82, 1.0), (0, 0, 0))
    solid = skirt.modifiers.new("Thickness", "SOLIDIFY")
    solid.thickness = 0.015
    bake_modifiers(skirt)
    torus("SkirtHem", "trim", 0.3, 0.012, (0, 0, 0.716), scale=(1.0, 0.82, 1.0))
    box("FrontPanel", "tunic", (0, -0.222, 0.83), (0.2, 0.02, 0.36), (-9.5, 0, 0))
    box("PanelTrim", "trim", (0, -0.257, 0.672), (0.2, 0.014, 0.03), (-9.5, 0, 0))
    box("PanelRune", "trim", (0, -0.245, 0.78), (0.05, 0.012, 0.05), (-9.5, 45, 0))
    torus("Collar", "trim", 0.13, 0.018, (0, 0.0, 1.535), scale=(1.15, 1.0, 1.0), rotation=(-12, 0, 0))
    torus("SashWrap", "sash", 0.218, 0.045, (0, -0.005, 1.035), scale=(1.0, 0.8, 1.0))
    sphere("SashKnot", "sash", 0.05, (0.08, -0.17, 1.03), scale=(1.3, 0.6, 0.85))
    for i, x in enumerate((0.07, 0.105)):
        box("SashEnd", "sash", (x, -0.18, 0.93), (0.045, 0.012, 0.14), (-6, 0, 8 - i * 14))
    for x in (1, -1):
        torus("SleeveHem", "trim", 0.104, 0.012, (x * 0.415, 0.0, 1.345), rotation=(0, -37 * x, 0))
        torus("BootCuff", "boots", 0.118, 0.032, (x * 0.15, 0.006, 0.465))
        torus("LegWrap", "sash", 0.1, 0.014, (x * 0.148, -0.004, 0.525))


def build():
    body()
    hands()
    face()
    hair()
    clothes()
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    character = bpy.data.objects["Arkanor"]
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = character
    bpy.ops.object.join()
    print("triangles:", sum(len(p.vertices) - 2 for p in character.data.polygons))
    return character


def unwrap(obj):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")


# ---------------------------------------------------------------- painting

class Nodes:
    """Shorthand for building shader math. Values may be constants or node sockets."""

    def __init__(self, mat):
        self.tree = mat.node_tree
        self.tree.nodes.clear()
        self.coords = self.new("ShaderNodeTexCoord").outputs["Object"]
        position = self.new("ShaderNodeSeparateXYZ")
        self.feed(position.inputs[0], self.coords)
        self.x, self.y, self.z = position.outputs["X"], position.outputs["Y"], position.outputs["Z"]
        geometry = self.new("ShaderNodeNewGeometry")
        normal = self.new("ShaderNodeSeparateXYZ")
        self.feed(normal.inputs[0], geometry.outputs["Normal"])
        self.normal_z = normal.outputs["Z"]
        self.pointiness = geometry.outputs["Pointiness"]
        ao = self.new("ShaderNodeAmbientOcclusion", samples=16)
        ao.inputs["Distance"].default_value = 0.15
        self.ao = ao.outputs["AO"]

    def new(self, kind, **props):
        node = self.tree.nodes.new(kind)
        for key, value in props.items():
            setattr(node, key, value)
        return node

    def feed(self, socket, value):
        if isinstance(value, bpy.types.NodeSocket):
            self.tree.links.new(value, socket)
        elif socket.type == "RGBA" and len(value) == 3:
            socket.default_value = (*value, 1.0)
        else:
            socket.default_value = value

    def math(self, op, a, b=0.0):
        node = self.new("ShaderNodeMath", operation=op)
        self.feed(node.inputs[0], a)
        self.feed(node.inputs[1], b)
        return node.outputs[0]

    def vec(self, op, a, b):
        node = self.new("ShaderNodeVectorMath", operation=op)
        self.feed(node.inputs[0], a)
        self.feed(node.inputs[1], b)
        return node.outputs[0]

    def scale(self, a, factor):
        node = self.new("ShaderNodeVectorMath", operation="SCALE")
        self.feed(node.inputs[0], a)
        self.feed(node.inputs[3], factor)
        return node.outputs[0]

    def remap(self, value, from_a, from_b, to_a, to_b, smooth=False):
        node = self.new("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP" if smooth else "LINEAR", clamp=True)
        self.feed(node.inputs[0], value)
        for index, number in zip((1, 2, 3, 4), (from_a, from_b, to_a, to_b)):
            node.inputs[index].default_value = number
        return node.outputs[0]

    def lerp(self, a, b, t):
        return self.vec("ADD", a, self.scale(self.vec("SUBTRACT", b, a), t))

    def noise(self, scale, detail=3.0, distortion=0.0):
        node = self.new("ShaderNodeTexNoise")
        self.feed(node.inputs["Vector"], self.coords)
        node.inputs["Scale"].default_value = scale
        node.inputs["Detail"].default_value = detail
        node.inputs["Distortion"].default_value = distortion
        return node.outputs["Fac"]

    def wave(self, scale, direction, distortion, detail=2.0):
        node = self.new("ShaderNodeTexWave", wave_type="BANDS", bands_direction=direction)
        self.feed(node.inputs["Vector"], self.coords)
        node.inputs["Scale"].default_value = scale
        node.inputs["Distortion"].default_value = distortion
        node.inputs["Detail"].default_value = detail
        return node.outputs["Fac"]

    def grooves(self, scale):
        node = self.new("ShaderNodeTexVoronoi", feature="DISTANCE_TO_EDGE")
        self.feed(node.inputs["Vector"], self.coords)
        node.inputs["Scale"].default_value = scale
        return node.outputs["Distance"]


def pattern(name, n):
    """Material-specific painting: returns (color, glow)."""
    base = BASE[name]
    black = (0.0, 0.0, 0.0)
    if name == "skin":
        color = n.lerp(base, (0.58, 0.24, 0.17), n.remap(n.noise(7.0), 0.4, 0.7, 0.0, 0.35))
        for eye_x in (0.045, -0.045):
            dx = n.math("SUBTRACT", n.x, eye_x)
            dz = n.math("SUBTRACT", n.z, 1.794)
            reach = n.math("SQRT", n.math("ADD", n.math("MULTIPLY", dx, dx), n.math("MULTIPLY", n.math("MULTIPLY", dz, dz), 2.2)))
            socket = n.remap(reach, 0.012, 0.034, 0.45, 1.0, smooth=True)
            # Only the front of the face: further back the factor is 1.
            color = n.scale(color, n.math("MAXIMUM", socket, n.remap(n.y, -0.1, -0.08, 0.0, 1.0)))
        # Rune tattoos: thin wavy lines on the forearms and below the sleeves.
        arms = n.math("MULTIPLY", n.remap(n.math("ABSOLUTE", n.x), 0.43, 0.46, 0, 1), n.remap(n.z, 1.05, 1.08, 0, 1))
        arms = n.math("MULTIPLY", arms, n.remap(n.z, 1.3, 1.33, 1, 0))
        lines = n.remap(n.math("ABSOLUTE", n.math("SUBTRACT", n.wave(5.0, "DIAGONAL", 7.0), 0.5)), 0.0, 0.05, 1, 0)
        tattoo = n.math("MULTIPLY", arms, lines)
        return n.lerp(color, (0.45, 0.85, 1.0), n.math("MULTIPLY", tattoo, 0.85)), n.scale(RUNE_GLOW, tattoo)
    if name == "hair":
        strands = n.remap(n.wave(16.0, "X", 2.5, 1.0), 0.0, 1.0, 0.62, 1.15)
        clumps = n.remap(n.noise(5.0, 2.0), 0.35, 0.65, 0.82, 1.1)
        return n.scale(n.scale(base, strands), clumps), black
    if name == "tunic":
        folds = n.remap(n.wave(4.5, "X", 5.0), 0.0, 1.0, 0.84, 1.1)
        grain = n.remap(n.noise(30.0), 0.3, 0.7, 0.94, 1.06)
        return n.scale(n.scale(base, folds), grain), black
    if name == "trousers":
        return n.scale(base, n.remap(n.wave(10.0, "Z", 6.0), 0.0, 1.0, 0.86, 1.08)), black
    if name == "sash":
        return n.scale(base, n.remap(n.wave(25.0, "Z", 2.0), 0.0, 1.0, 0.82, 1.12)), black
    if name == "boots":
        leather = n.remap(n.noise(12.0, 4.0), 0.3, 0.7, 0.82, 1.12)
        scuffed = n.remap(n.z, 0.0, 0.25, 0.7, 1.0)
        boot = n.scale(n.scale(base, leather), scuffed)
        return n.lerp(BASE["sole"], boot, n.remap(n.z, 0.03, 0.045, 0.0, 1.0)), black
    if name == "trim":
        etched = n.remap(n.grooves(40.0), 0.0, 0.05, 0.5, 1.0)
        return n.scale(base, etched), black
    if name.startswith("eye"):
        return base, base
    return base, black


def setup_painting(mat):
    """Node tree with two outputs to bake: the painted color and the glow."""
    n = Nodes(mat)
    color, glow = pattern(mat.name, n)
    shade = n.math("POWER", n.remap(n.ao, 0.0, 1.0, 0.25, 1.0), 1.4)
    top_light = n.remap(n.normal_z, -1.0, 1.0, 0.68, 1.2)
    lit = n.scale(n.scale(color, shade), top_light)
    edge_strength = 0.6 if mat.name == "trim" else 0.3
    edges = n.math("ADD", 1.0, n.remap(n.pointiness, 0.5, 0.58, 0.0, edge_strength))
    creases = n.remap(n.pointiness, 0.4, 0.5, 0.7, 1.0)
    painted = n.scale(n.scale(lit, edges), creases)
    for node_name, value in (("PaintEmit", painted), ("GlowEmit", glow)):
        emit = n.new("ShaderNodeEmission")
        emit.name = node_name
        n.feed(emit.inputs["Color"], value)
    output = n.new("ShaderNodeOutputMaterial")
    output.name = "Output"
    target = n.new("ShaderNodeTexImage")
    target.name = "BakeTarget"
    n.tree.nodes.active = target


def bake(obj, image, emit_node):
    for mat in obj.data.materials:
        tree = mat.node_tree
        tree.links.new(tree.nodes[emit_node].outputs[0], tree.nodes["Output"].inputs["Surface"])
        tree.nodes["BakeTarget"].image = image
        tree.nodes.active = tree.nodes["BakeTarget"]
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.bake(type="EMIT", margin=16)
    soften(image)
    image.filepath_raw = str(OUT / f"{image.name}.png")
    image.file_format = "PNG"
    image.save()
    print("baked", image.name)


def soften(image):
    """A light blur hides the bake noise, like soft brush strokes."""
    width, height = image.size
    pixels = np.empty(width * height * 4, np.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(height, width, 4)
    rgb = pixels[..., :3]
    pixels[..., :3] = (rgb * 2 + np.roll(rgb, 1, 0) + np.roll(rgb, -1, 0) + np.roll(rgb, 1, 1) + np.roll(rgb, -1, 1)) / 6
    image.pixels.foreach_set(pixels.ravel())


def use_gpu(scene):
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for kind in ("OPTIX", "CUDA"):
            try:
                prefs.compute_device_type = kind
            except TypeError:
                continue
            prefs.get_devices()
            if any(d.type == kind for d in prefs.devices):
                for device in prefs.devices:
                    device.use = device.type == kind
                scene.cycles.device = "GPU"
                print("baking on", kind)
                return
    except Exception as error:  # Any trouble: the CPU bakes too, just slower.
        print("GPU not used:", error)
    scene.cycles.device = "CPU"


def paint(obj):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 48
    use_gpu(scene)
    for mat in obj.data.materials:
        setup_painting(mat)
    paint_image = bpy.data.images.new("arkanor_paint", PAINT_SIZE, PAINT_SIZE)
    glow_image = bpy.data.images.new("arkanor_glow", GLOW_SIZE, GLOW_SIZE)
    bake(obj, paint_image, "PaintEmit")
    bake(obj, glow_image, "GlowEmit")
    # One painted material replaces all the base materials.
    final = bpy.data.materials.new("ArkanorPainted")
    nodes = final.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    color = nodes.new("ShaderNodeTexImage")
    color.image = paint_image
    glow = nodes.new("ShaderNodeTexImage")
    glow.image = glow_image
    final.node_tree.links.new(color.outputs["Color"], bsdf.inputs["Base Color"])
    final.node_tree.links.new(glow.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 2.0
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Specular IOR Level"].default_value = 0.15
    obj.data.materials.clear()
    obj.data.materials.append(final)
    for poly in obj.data.polygons:
        poly.material_index = 0


# ---------------------------------------------------------------- previews

def stage():
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = 700
    scene.render.resolution_y = 900
    world = bpy.data.worlds.new("Studio")
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.53, 0.58, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    scene.world = world
    for name, rotation, energy in (("Key", (50, 0, -35), 2.6), ("Fill", (60, 0, 140), 0.8), ("Rim", (20, 0, 180), 1.6)):
        light = bpy.data.lights.new(name, "SUN")
        light.energy = energy
        obj = bpy.data.objects.new(name, light)
        obj.rotation_euler = [math.radians(a) for a in rotation]
        scene.collection.objects.link(obj)
    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    camera.data.type = "ORTHO"
    scene.collection.objects.link(camera)
    scene.camera = camera
    return camera


def render_views(camera):
    views = (("front", 0, 1.0, 2.25), ("three_quarter", 35, 1.0, 2.25), ("side", 90, 1.0, 2.25), ("portrait", 25, 1.62, 0.75))
    for name, angle, height, size in views:
        a = math.radians(angle)
        camera.data.ortho_scale = size
        camera.location = (6.0 * math.sin(a), -6.0 * math.cos(a), height)
        direction = Vector((0, 0, height)) - camera.location
        camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        bpy.context.scene.render.filepath = str(OUT / f"arkanor_{name}.png")
        bpy.ops.render.render(write_still=True)
        print("rendered", name)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    character = build()
    unwrap(character)
    paint(character)
    camera = stage()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "arkanor.blend"))
    render_views(camera)


main()
