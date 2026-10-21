"""Hammerfall Hold, the Orebound hold in the Crystal Canyons: its great gate carved into
the canyon wall, and the forge before it. Built from blocks with scanned CC0 stone, metal
and wood (Poly Haven; python tools/art/polyhaven.py textures ... and models ...).

    blender -b --python tools/art/blender/hammerfall.py -- [--shots <folder>]

Writes game/art/buildings/hammerfall_gate.gltf and hammerfall_forge.gltf (textures in
buildings/textures/). Each faces
Blender -Y (Godot +Z), its foot at the origin. Meshes named "*-col" also give Godot a
solid body (its glTF importer makes a static trimesh body from the suffix); empties named
"Fire*" mark where Godot lights flames.

The gate (studied from dwarven holds in fantasy art, not copied): a stair of three broad
steps up to a deep doorway between two square pillars, a great lintel and a stepped
gable above, the Orebound hammer on it; low crenellated wings either side, all of large
sandstone blocks; braziers before the pillars. The back runs 6 m into the cliff.
"""
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Vector

ROOT = Path(__file__).resolve().parents[3]
TEXTURES = ROOT / "art" / "vendor" / "polyhaven" / "textures"
MODELS = ROOT / "art" / "vendor" / "polyhaven" / "models"
OUT = ROOT / "game" / "art" / "buildings"

## material: (Poly Haven texture, metres one texture repeat covers, colour it is multiplied by)
SURFACES = {
    "stone": ("large_sandstone_blocks", 3.0, (1.0, 0.97, 0.92)),
    "paving": ("red_sandstone_pavement", 2.5, (1.0, 1.0, 1.0)),
    "steps": ("red_sandstone_pavement", 2.5, (1.0, 1.0, 1.0)),  # (not solid: a ramp is)
    "iron": ("rusty_metal_02", 1.5, (0.3, 0.29, 0.28)),  # blackened iron, the rust only a hint
    "wood": ("weathered_planks", 2.0, (0.8, 0.72, 0.62)),
}
## Largest texture side written (the scans come at 2k; the buildings are seen at a distance).
TEXTURE_SIZE = 1024


def clear():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for item in list(block):
            block.remove(item)


def material(name):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    asset, _, tint = SURFACES[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]

    def image(kind, colour):
        node = nodes.new("ShaderNodeTexImage")
        node.image = bpy.data.images.load(str(TEXTURES / asset / ("%s_%s_2k.jpg" % (asset, kind))), check_existing=True)
        if not colour:
            node.image.colorspace_settings.name = "Non-Color"
        return node

    tinted = nodes.new("ShaderNodeMix")
    tinted.data_type = "RGBA"
    tinted.blend_type = "MULTIPLY"
    tinted.inputs["Factor"].default_value = 1.0
    tinted.inputs["B"].default_value = (*tint, 1.0)
    links.new(image("diff", True).outputs["Color"], tinted.inputs["A"])
    links.new(tinted.outputs["Result"], bsdf.inputs["Base Color"])
    arm = image("arm", False)
    split = nodes.new("ShaderNodeSeparateColor")
    links.new(arm.outputs["Color"], split.inputs["Color"])
    links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
    links.new(split.outputs["Blue"], bsdf.inputs["Metallic"])
    normal = nodes.new("ShaderNodeNormalMap")
    links.new(image("nor_gl", False).outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def glow(name, colour, strength):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*colour, 1.0)
    bsdf.inputs["Emission Color"].default_value = (*colour, 1.0)
    bsdf.inputs["Emission Strength"].default_value = strength
    return mat


class Builder:
    """Gathers boxes, prisms and cylinders into one mesh per material, box-mapped UVs at
    each surface's real scale."""

    def __init__(self, name):
        self.name = name
        self.parts = {}  # material -> bmesh

    def _bm(self, mat):
        if mat not in self.parts:
            self.parts[mat] = bmesh.new()
        return self.parts[mat]

    def box(self, mat, lo, hi, bevel=0.04):
        """An axis-aligned block from corner lo to hi (x, y, z), its edges chamfered."""
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        size = Vector(hi) - Vector(lo)
        centre = (Vector(hi) + Vector(lo)) * 0.5
        bmesh.ops.scale(bm, vec=size, verts=bm.verts)
        bmesh.ops.translate(bm, vec=centre, verts=bm.verts)
        if bevel > 0:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * 0.3), segments=1,
                            affect="EDGES", profile=0.5)
        self._merge(mat, bm)

    def cylinder(self, mat, centre, radius_bottom, radius_top, height, sides=16):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=radius_bottom, radius2=radius_top,
                              depth=height)
        bmesh.ops.translate(bm, vec=Vector(centre) + Vector((0, 0, height * 0.5)), verts=bm.verts)
        self._merge(mat, bm)

    def _merge(self, mat, part):
        mesh = bpy.data.meshes.new("part")
        part.to_mesh(mesh)
        part.free()
        self._bm(mat).from_mesh(mesh)
        bpy.data.meshes.remove(mesh)

    def finish(self, solid=True):
        """One object per material, named <name>_<material>[-col], box-mapped."""
        made = []
        for mat, bm in self.parts.items():
            tile = SURFACES.get(mat, (None, 1.0))[1]
            uv = bm.loops.layers.uv.verify()
            bm.normal_update()
            for face in bm.faces:
                n = face.normal
                axis = max(range(3), key=lambda i: abs(n[i]))
                for loop in face.loops:
                    co = loop.vert.co
                    u, v = [(co.y, co.z), (co.x, co.z), (co.x, co.y)][axis]
                    loop[uv].uv = (u / tile, v / tile)
            mesh = bpy.data.meshes.new("%s_%s" % (self.name, mat))
            bm.to_mesh(mesh)
            bm.free()
            obj = bpy.data.objects.new(mesh.name + ("-col" if solid and mat in ("stone", "paving", "wood") else ""), mesh)
            bpy.context.scene.collection.objects.link(obj)
            mesh.materials.append(material(mat) if mat in SURFACES else bpy.data.materials[mat])
            for poly in mesh.polygons:
                poly.use_smooth = False
            made.append(obj)
        return made


def scanned(model, scale, location, rotation=(0, 0, 0)):
    """A Poly Haven model, scaled and placed; its parts joined into one object."""
    before = {o.name for o in bpy.data.objects}
    files = list((MODELS / model).glob("*.gltf"))
    bpy.ops.import_scene.gltf(filepath=str(files[0]))
    new = [o.name for o in bpy.data.objects if o.name not in before]
    meshes = [bpy.data.objects[n] for n in new if bpy.data.objects[n].type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for other in new:
        if other != obj.name and other in bpy.data.objects:
            bpy.data.objects.remove(bpy.data.objects[other])
    obj.parent = None
    obj.scale = (scale, scale, scale)
    obj.rotation_euler = Euler([math.radians(a) for a in rotation])
    obj.location = location
    obj.name = model
    return obj


def marker(name, location):
    empty = bpy.data.objects.new(name, None)
    empty.location = location
    bpy.context.scene.collection.objects.link(empty)
    return empty


## The gate's stair: steps, each STEP_RISE high and STEP_RUN deep, from the ground at the
## stair's foot (the origin) up to the doorway's landing (31 degrees: walkable).
STEPS = 20
STEP_RISE = 0.3
STEP_RUN = 0.5


def gate():
    """The gate set high in a canyon wall: the stair's foot at the origin, the stair rising
    toward +Y to the doorway landing (LIFT up, RUN on), the facade on from there, its back
    deep in the cliff. Faces -Y."""
    lift, run = STEPS * STEP_RISE, STEPS * STEP_RUN
    b = Builder("gate")
    # the stair (seen, not solid: a ramp beneath it carries the walker)
    for i in range(STEPS):
        b.box("steps", (-3.6, i * STEP_RUN, -2.0), (3.6, run + 1.0, (i + 1) * STEP_RISE), bevel=0.02)
    ramp = bmesh.new()
    corners = [(-3.6, 0.0, 0.0), (3.6, 0.0, 0.0), (3.6, run, lift), (-3.6, run, lift),
               (-3.6, 0.0, -1.0), (3.6, 0.0, -1.0), (3.6, run, -1.0), (-3.6, run, -1.0)]
    v = [ramp.verts.new(c) for c in corners]
    for face in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
        ramp.faces.new([v[k] for k in face])
    mesh = bpy.data.meshes.new("gate_ramp")
    ramp.to_mesh(mesh)
    ramp.free()
    bpy.context.scene.collection.objects.link(bpy.data.objects.new("gate_ramp-colonly", mesh))
    # stepped parapets up either side of the stair, braziers on their feet
    for side in (-1, 1):
        lo, hi = sorted((side * 3.6, side * 4.7))
        for k in range(5):
            y0 = k * run / 5
            top = (k + 1) * lift / 5 + 1.0
            b.box("stone", (lo, y0, -2.0), (hi, y0 + run / 5 + 0.05, top))
        x = side * 4.15
        b.cylinder("iron", (x, 0.5, lift / 5 + 1.0), 0.3, 0.55, 0.4, 14)
        marker("Fire" + ("L" if side < 0 else "R"), (x, 0.5, lift / 5 + 1.45))
    # the facade, from the landing (the doorway's floor) up
    f, y = lift, run  # floor height, facade front
    b.box("paving", (-5.6, y - 1.0, f - 2.0), (5.6, y + 7.0, f))
    for side in (-1, 1):
        x = side * 4.0
        b.box("stone", (x - 1.45, y - 1.45, -2.0), (x + 1.45, y + 6.5, f + 0.9))
        b.box("stone", (x - 1.2, y - 1.2, f + 0.9), (x + 1.2, y + 6.5, f + 9.3))
        b.box("stone", (x - 1.5, y - 1.5, f + 9.3), (x + 1.5, y + 6.5, f + 10.1))
        for z in (f + 2.5, f + 6.7):
            b.box("iron", (x - 1.26, y - 1.26, z), (x + 1.26, y + 6.5, z + 0.35), bevel=0.02)
        # wings, crenellated, down into the slope below
        lo, hi = sorted((side * 5.2, side * 9.6))
        b.box("stone", (lo, y - 0.6, -2.0), (hi, y + 6.5, f + 5.5))
        b.box("stone", (lo, y - 0.8, f + 5.1), (hi, y, f + 5.5))
        for k in range(3):
            cx = side * (6.0 + k * 1.45)
            b.box("stone", (cx - 0.45, y - 0.6, f + 5.5), (cx + 0.45, y + 0.4, f + 6.3))
    # the deep doorway: jambs, the door's back wall, the stepped head
    b.box("stone", (-2.8, y - 0.6, f), (-1.5, y + 6.5, f + 5.7))
    b.box("stone", (1.5, y - 0.6, f), (2.8, y + 6.5, f + 5.7))
    b.box("stone", (-2.8, y + 1.8, f), (2.8, y + 6.5, f + 5.7))
    b.box("stone", (-2.8, y - 0.6, f + 5.7), (2.8, y + 6.5, f + 6.5))
    b.box("stone", (-2.2, y - 0.4, f + 6.5), (2.2, y + 6.5, f + 7.3))
    b.box("stone", (-2.8, y - 0.2, f + 7.3), (2.8, y + 6.5, f + 10.1))
    # lintel and stepped gable
    b.box("stone", (-5.6, y - 1.7, f + 10.1), (5.6, y + 6.5, f + 11.5))
    for k, half in enumerate((4.6, 3.3, 2.0)):
        b.box("stone", (-half, y - 1.3 + k * 0.2, f + 11.5 + k), (half, y + 6.5, f + 12.5 + k))
    made = b.finish()
    # the door (the model stands 2 m by 4 m, its foot 1.13 m below its origin)
    made.append(scanned("large_castle_door", 1.45, (0.0, y + 1.6, f + 1.13 * 1.45)))
    # the Orebound hammer in iron on the gable: haft, head, its faces flared
    e = Builder("emblem")
    g = f + 11.6
    e.box("iron", (-0.2, y - 1.6, g), (0.2, y - 1.25, g + 2.6), bevel=0.05)
    e.box("iron", (-1.3, y - 1.75, g + 2.0), (1.3, y - 1.25, g + 3.0), bevel=0.08)
    for side in (-1, 1):
        x = side * 1.3
        lo, hi = sorted((x, x + side * 0.25))
        e.box("iron", (lo, y - 1.8, g + 1.85), (hi, y - 1.2, g + 3.15), bevel=0.06)
    made += e.finish(solid=False)
    return made


def forge():
    """The forge: hearth with glowing coals, hood and chimney, anvil on its stump, a
    quench trough; front facing -Y, centred on the origin."""
    b = Builder("forge")
    b.box("paving", (-2.6, -2.8, -0.6), (2.6, 1.6, 0.12))
    b.box("stone", (-1.6, -0.9, 0.12), (1.6, 1.1, 1.0))
    b.box("stone", (-1.75, -1.05, 1.0), (1.75, 1.25, 1.15))
    b.box("forge_coals", (-1.2, -0.6, 1.15), (1.2, 0.8, 1.2), bevel=0)
    # hood on four short posts, then the chimney
    for x in (-1.55, 1.55):
        b.box("stone", (x - 0.15, 0.95, 1.15), (x + 0.15, 1.25, 2.3))
    b.box("stone", (-1.7, -0.7, 2.3), (1.7, 1.3, 2.6))
    b.box("stone", (-1.2, -0.3, 2.6), (1.2, 1.3, 3.1))
    b.box("stone", (-0.7, 0.1, 3.1), (0.7, 1.3, 5.6))
    b.box("iron", (-0.75, 0.05, 5.6), (0.75, 1.35, 5.75), bevel=0.01)
    # anvil on a log stump
    b.cylinder("wood", (1.0, -1.9, 0.12), 0.36, 0.33, 0.55, 12)
    b.box("iron", (0.82, -2.02, 0.67), (1.18, -1.78, 0.8), bevel=0.01)
    b.box("iron", (0.9, -1.98, 0.8), (1.1, -1.82, 0.9), bevel=0.01)
    b.box("iron", (0.7, -2.06, 0.9), (1.28, -1.74, 1.02), bevel=0.015)
    horn = bmesh.new()
    bmesh.ops.create_cone(horn, cap_ends=True, segments=10, radius1=0.12, radius2=0.01, depth=0.34)
    bmesh.ops.rotate(horn, verts=horn.verts, cent=(0, 0, 0), matrix=Euler((0, math.radians(-90), 0)).to_matrix())
    bmesh.ops.translate(horn, vec=Vector((0.54, -1.9, 0.97)), verts=horn.verts)
    b._merge("iron", horn)
    # quench trough
    b.box("wood", (-2.2, -2.3, 0.12), (-0.8, -1.6, 0.62), bevel=0.02)
    b.box("forge_water", (-2.1, -2.2, 0.55), (-0.9, -1.7, 0.58), bevel=0)
    made = b.finish()
    marker("FireForge", (0.0, 0.1, 1.25))
    hammer = scanned("sledgehammer_01", 1.0, (1.5, -1.6, 0.6), (0, 18, 0))
    made.append(hammer)
    return made


def export(name, objects):
    """<name>.gltf with its textures in buildings/textures/, shared by the buildings."""
    OUT.mkdir(parents=True, exist_ok=True)
    for image in bpy.data.images:
        if image.size[0] > TEXTURE_SIZE:
            image.scale(TEXTURE_SIZE, int(image.size[1] * TEXTURE_SIZE / image.size[0]))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        obj.select_set(True)
    path = OUT / (name + ".gltf")
    bpy.ops.export_scene.gltf(filepath=str(path), use_selection=True, export_format="GLTF_SEPARATE",
                              export_texture_dir="textures", export_yup=True, export_image_format="JPEG",
                              export_image_quality=88, export_apply=True)
    print("hammerfall: wrote", path)


def shots(folder, name):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in
                                                                         bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 900, 700
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.6, 0.7, 0.85, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    scene.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.lens = 28
    far = 34 if name == "gate" else 9
    aim = Vector((0, 9, 9)) if name == "gate" else Vector((0, 0, 1.8))
    cam.location = aim + Vector((far * 0.45, -far, far * 0.1))
    direction = aim - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    Path(folder).mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(Path(folder) / (name + ".png"))
    bpy.ops.render.render(write_still=True)
    for obj in (sun, cam):
        bpy.data.objects.remove(obj)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for name, build in (("gate", gate), ("forge", forge)):
        clear()
        glow("forge_coals", (1.0, 0.28, 0.05), 2.5)
        water = glow("forge_water", (0.08, 0.12, 0.14), 0.0)
        water.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.05
        build()
        if "--shots" in args:
            shots(args[args.index("--shots") + 1], name)
        export("hammerfall_" + name, None)
