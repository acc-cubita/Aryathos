"""Game-ready rocks and cliffs from scanned CC0 models (Poly Haven, art/vendor/polyhaven/models).

    blender -b --factory-startup --python tools/art/blender/rocks.py

Per set in SETS:
  * every piece is decimated to a game budget and its scan detail baked back into a
    tangent-space normal map (Cycles, selected to active, from the full-detail scan);
  * cliff faces are open shells, so their rim gets a skirt pushed back into the hill
    (UV2.x = 1 on the skirt: rock.gdshader draws terrain rock there instead of the scan);
  * pieces go to game/art/rocks/<set>.glb as meshes piece_0, piece_1, ... with the
    origin on the scan's ground (boulders: under the middle; cliffs: at the front foot,
    facing +Z in Godot);
  * textures: <set>_albedo.jpg (the scan's colour) and <set>_nrao.png
    (RG = baked normal xy, B = roughness, A = ambient occlusion), like the terrain layers.
"""
import shutil
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
VENDOR = ROOT / "art" / "vendor" / "polyhaven" / "models"
OUT = ROOT / "game" / "art" / "rocks"
SIZE = 2048

# set: (scan, triangles per piece, kind, bake ray distance in m)
SETS = {
    "cliff_a": ("rock_face_01", 5000, "cliff", 0.12),
    "cliff_b": ("rock_face_02", 6000, "cliff", 0.12),
    "cliff_c": ("mountainside", 12000, "cliff", 0.25),
    "boulders_a": ("rock_moss_set_01", 2200, "boulder", 0.06),
    "boulders_b": ("rock_moss_set_02", 1600, "boulder", 0.05),
}
SKIRT_DEPTH = 2.0


def gpu():
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for kind in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = kind
            prefs.get_devices()
            for device in prefs.devices:
                device.use = True
            bpy.context.scene.cycles.device = "GPU"
            return kind
        except TypeError:
            continue
    return "CPU"


def weld(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(obj.data)
    bm.free()


def decimated(obj, tris, piece):
    """A decimated copy of obj, its faces tagged with the piece index."""
    count = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    mod = obj.modifiers.new("decimate", "DECIMATE")
    mod.ratio = min(1.0, tris / count)
    mod.use_collapse_triangulate = True
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    obj.modifiers.remove(mod)
    low = bpy.data.objects.new(obj.name + "_low", mesh)
    bpy.context.scene.collection.objects.link(low)
    attr = mesh.attributes.new("piece", "INT", "FACE")
    attr.data.foreach_set("value", [piece] * len(mesh.polygons))
    return low


def select(objects, active):
    for o in bpy.context.scene.objects:
        o.select_set(o in objects)
    bpy.context.view_layer.objects.active = active


def bake_normals(lows, highs, ray, name):
    select(lows, lows[0])
    with bpy.context.temp_override(active_object=lows[0], selected_editable_objects=lows):
        bpy.ops.object.join()
    low = lows[0]
    image = bpy.data.images.new(name + "_normal", SIZE, SIZE)
    image.colorspace_settings.name = "Non-Color"
    mat = bpy.data.materials.new(name + "_bake")
    mat.use_nodes = True
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = image
    mat.node_tree.nodes.active = node
    low.data.materials.clear()
    low.data.materials.append(mat)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 4
    scene.render.bake.margin = 16
    select(highs + [low], low)
    bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", use_selected_to_active=True,
                        cage_extrusion=ray * 0.5, max_ray_distance=ray, margin=16)
    pixels = np.empty(SIZE * SIZE * 4, np.float32)
    image.pixels.foreach_get(pixels)
    return low, pixels.reshape(SIZE, SIZE, 4)


def skirt(obj):
    """Pushes the open rim of a scanned face back into the hill so no edge shows."""
    mesh = obj.data
    flag = mesh.uv_layers.new(name="skirt")
    bm = bmesh.new()
    bm.from_mesh(mesh)
    back = Vector()
    for f in bm.faces:
        back -= f.normal * f.calc_area()
    back.z = min(back.z, 0.0)
    back = back.normalized() * SKIRT_DEPTH
    rim = [e for e in bm.edges if e.is_boundary]
    made = bmesh.ops.extrude_edge_only(bm, edges=rim)
    new_verts = [v for v in made["geom"] if isinstance(v, bmesh.types.BMVert)]
    for v in new_verts:
        v.co += back
    skirt_layer = bm.loops.layers.uv["skirt"]
    fresh = set(new_verts)
    for f in bm.faces:
        for loop in f.loops:
            loop[skirt_layer].uv = (1.0 if loop.vert in fresh else 0.0, 0.0)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    # the extruded quads face outward if the rim winds like the faces next to it
    mesh.validate()


def split(low, count, kind):
    """One object per piece, origin on the scan's ground."""
    pieces = []
    for i in range(count):
        mesh = low.data.copy()
        bm = bmesh.new()
        bm.from_mesh(mesh)
        layer = bm.faces.layers.int["piece"]
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f[layer] != i], context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        co = [v.co for v in bm.verts]
        lo = Vector((min(c.x for c in co), min(c.y for c in co), 0.0))
        hi = Vector((max(c.x for c in co), max(c.y for c in co), 0.0))
        origin = Vector(((lo.x + hi.x) / 2, lo.y if kind == "cliff" else (lo.y + hi.y) / 2, 0.0))
        bmesh.ops.translate(bm, verts=bm.verts, vec=-origin)
        bm.to_mesh(mesh)
        bm.free()
        mesh.attributes.remove(mesh.attributes["piece"])
        obj = bpy.data.objects.new("piece_%d" % i, mesh)
        bpy.context.scene.collection.objects.link(obj)
        if kind == "cliff":
            skirt(obj)
        pieces.append(obj)
    return pieces


def gray(path):
    image = bpy.data.images.load(str(path))
    image.colorspace_settings.name = "Non-Color"
    if tuple(image.size) != (SIZE, SIZE):
        image.scale(SIZE, SIZE)
    pixels = np.empty(SIZE * SIZE * 4, np.float32)
    image.pixels.foreach_get(pixels)
    return pixels.reshape(SIZE, SIZE, 4)


def pack(name, scan, normal):
    textures = VENDOR / scan / "textures"
    arm = textures / ("%s_arm_2k.jpg" % scan)
    if arm.exists():
        maps = gray(arm)
        rough, ao = maps[..., 1], maps[..., 0]
    else:
        rough = gray(textures / ("%s_rough_2k.jpg" % scan))[..., 0]
        ao = np.ones_like(rough)
    out = np.dstack([normal[..., 0], normal[..., 1], rough, ao]).astype(np.float32)
    image = bpy.data.images.new(name + "_nrao", SIZE, SIZE, alpha=True)
    image.colorspace_settings.name = "Non-Color"
    image.pixels.foreach_set(out.ravel())
    image.filepath_raw = str(OUT / ("%s_nrao.png" % name))
    image.file_format = "PNG"
    image.save()
    shutil.copyfile(textures / ("%s_diff_2k.jpg" % scan), OUT / ("%s_albedo.jpg" % name))


def build(name, scan, tris, kind, ray):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    device = gpu()
    bpy.ops.import_scene.gltf(filepath=str(VENDOR / scan / (scan + ".gltf")))
    highs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    highs.sort(key=lambda o: o.name)
    lows = []
    for i, high in enumerate(highs):
        world = high.matrix_world.copy()
        high.parent = None
        high.data.transform(world)
        high.matrix_world.identity()
        weld(high)
        lows.append(decimated(high, tris, i))
    low, normal = bake_normals(lows, highs, ray, name)
    pieces = split(low, len(highs), kind)
    for o in highs + [low]:
        bpy.data.objects.remove(o)
    select(pieces, pieces[0])
    bpy.ops.export_scene.gltf(filepath=str(OUT / (name + ".glb")), export_format="GLB", use_selection=True,
                              export_materials="NONE", export_tangents=True, export_yup=True)
    pack(name, scan, normal)
    print("rocks: %s from %s, %d pieces, %s tris, baked on %s" % (
        name, scan, len(pieces), [sum(len(p.vertices) - 2 for p in o.data.polygons) for o in pieces], device))


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for set_name, spec in SETS.items():
        build(set_name, *spec)
