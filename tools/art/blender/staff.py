"""The Aethermancer's crystal staff, modelled and exported for Godot.

    blender -b --python tools/art/blender/staff.py

A gnarled shaft of dark wood (the props' wood texture, grain along the shaft) with a
leather grip, silver bands and ferrule, and a three-pronged silver claw holding an
azure Aether crystal that glows. Frame (Blender): grip at the origin, haft along +Z
(out of the thumb side of the fist), like the rune axe; glTF turns it into +Y up.
Exports game/art/weapons/crystal_staff.glb.
"""
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector, noise

ROOT = Path(__file__).resolve().parents[3]
WOOD = ROOT / "game" / "art" / "textures" / "props_pbr" / "wood_albedo.png"
OUT = ROOT / "game" / "art" / "weapons" / "crystal_staff.glb"

BOTTOM, TOP = -0.72, 0.9  # the shaft, metres from the grip
SIDES = 12
WOOD_REPEAT = 1.6  # texture lengths per metre of shaft
WOOD_INDEX, SILVER, LEATHER, CRYSTAL = range(4)


def material(name, colour, rough, metal=0.0, image=None, glow=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*colour, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if image is not None:
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = image
        links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if glow is not None:
        bsdf.inputs["Emission Color"].default_value = (*glow, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 0.9
    return mat


def wobble(z, seed, amount):
    return noise.noise(Vector((seed, 0.0, z * 2.5))) * amount


def tube(bm, uv, z0, z1, radius, rings, index, gnarl=0.0, caps=(False, False)):
    """A ring-stacked tube from z0 to z1, radius(t) for t 0..1; gnarl bends and knots it.
    UV: u along the length (WOOD_REPEAT per metre), v around."""
    loops = []
    for i in range(rings + 1):
        t = i / rings
        z = z0 + (z1 - z0) * t
        centre = Vector((wobble(z, 1.0, gnarl), wobble(z, 7.0, gnarl), z))
        ring = []
        for j in range(SIDES):
            a = j / SIDES * math.tau
            knot = 1.0 + (0.12 * noise.noise(Vector((math.cos(a) * 1.5, math.sin(a) * 1.5, z * 9.0))) if gnarl else 0.0)
            r = radius(t) * knot
            ring.append(bm.verts.new(centre + Vector((math.cos(a) * r, math.sin(a) * r, 0.0))))
        loops.append(ring)
    for i in range(rings):
        for j in range(SIDES):
            k = (j + 1) % SIDES
            face = bm.faces.new((loops[i][j], loops[i][k], loops[i + 1][k], loops[i + 1][j]))
            face.material_index = index
            face.smooth = True
            for loop, (a, b) in zip(face.loops, ((j, i), (j + 1, i), (j + 1, i + 1), (j, i + 1))):
                loop[uv].uv = ((z0 + (z1 - z0) * b / rings) * WOOD_REPEAT, a / SIDES)
    if caps[0]:
        bm.faces.new(loops[0][::-1]).material_index = index
    if caps[1]:
        bm.faces.new(loops[-1]).material_index = index
    return loops


def sweep(bm, points, radii, index, sides=6):
    """A thin tube along a polyline (the claw's prongs), tapering by radii, tip closed."""
    rings = []
    for i, p in enumerate(points):
        ahead = points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]
        ahead.normalize()
        side = ahead.cross(Vector((0, 0, 1)) if abs(ahead.z) < 0.9 else Vector((1, 0, 0))).normalized()
        up = side.cross(ahead).normalized()
        rings.append([bm.verts.new(p + (side * math.cos(a) + up * math.sin(a)) * radii[i])
                      for a in (s / sides * math.tau for s in range(sides))])
    for i in range(len(rings) - 1):
        for j in range(sides):
            k = (j + 1) % sides
            face = bm.faces.new((rings[i][j], rings[i + 1][j], rings[i + 1][k], rings[i][k]))
            face.material_index = index
            face.smooth = True
    tip = bm.verts.new(points[-1] + (points[-1] - points[-2]).normalized() * radii[-1] * 2.0)
    for j in range(sides):
        face = bm.faces.new((rings[-1][j], tip, rings[-1][(j + 1) % sides]))
        face.material_index = index
        face.smooth = True


def crystal(bm, z0, z1, radius, index):
    """An elongated six-sided crystal (bipyramid with a prism waist), flat-shaded."""
    length = z1 - z0
    rings = []
    for z, r in ((z0 + length * 0.25, radius), (z0 + length * 0.62, radius * 0.92)):
        rings.append([bm.verts.new((math.cos(a) * r, math.sin(a) * r, z))
                      for a in (s / 6 * math.tau + 0.3 for s in range(6))])
    bottom, top = bm.verts.new((0, 0, z0)), bm.verts.new((0, 0, z1))
    for j in range(6):
        k = (j + 1) % 6
        faces = [bm.faces.new((rings[0][k], rings[0][j], bottom)),
                 bm.faces.new((rings[0][j], rings[0][k], rings[1][k], rings[1][j])),
                 bm.faces.new((rings[1][j], rings[1][k], top))]
        for face in faces:
            face.material_index = index


def build():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj)
    wood_image = bpy.data.images.load(str(WOOD))
    wood_image.scale(1024, 1024)  # plenty for a staff
    mats = [material("staff_wood", (1.0, 1.0, 1.0), 0.75, image=wood_image),
            material("staff_silver", (0.8, 0.82, 0.86), 0.3, metal=1.0),
            material("staff_leather", (0.2, 0.13, 0.09), 0.8),
            material("staff_crystal", (0.3, 0.6, 1.0), 0.1, glow=(0.25, 0.55, 1.0))]
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    # the shaft swells a little toward the head and the foot, gnarled along its length
    tube(bm, uv, BOTTOM, TOP, lambda t: 0.0145 + 0.004 * t ** 2 + 0.002 * (1 - t) ** 4, 64, WOOD_INDEX,
         gnarl=0.004, caps=(True, True))
    tube(bm, uv, -0.09, 0.13, lambda t: 0.0175, 6, LEATHER)                      # the grip wrap
    tube(bm, uv, BOTTOM - 0.012, BOTTOM + 0.05, lambda t: 0.0165 - 0.004 * (1 - t) ** 2, 4, SILVER,
         caps=(True, False))                                                     # ferrule
    for z in (0.16, 0.52, 0.8):                                                  # bands
        tube(bm, uv, z - 0.012, z + 0.012, lambda t: 0.0205 + 0.002 * math.sin(t * math.pi), 3, SILVER)
    tube(bm, uv, TOP - 0.05, TOP + 0.01, lambda t: 0.019 + 0.011 * t, 4, SILVER, caps=(False, True))  # collar
    for prong in range(3):                                                       # the claw
        a = prong / 3 * math.tau
        out = Vector((math.cos(a), math.sin(a), 0.0))
        path = [out * r + Vector((0, 0, z)) for r, z in ((0.022, TOP), (0.045, TOP + 0.05), (0.052, TOP + 0.11),
                                                        (0.042, TOP + 0.17), (0.026, TOP + 0.21))]
        sweep(bm, path, (0.007, 0.0065, 0.0055, 0.004, 0.0025), SILVER)
    crystal(bm, TOP + 0.02, TOP + 0.27, 0.034, CRYSTAL)
    mesh = bpy.data.meshes.new("crystal_staff")
    bm.to_mesh(mesh)
    bm.free()
    for mat in mats:
        mesh.materials.append(mat)
    obj = bpy.data.objects.new("crystal_staff", mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def export(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT), use_selection=True, export_format="GLB", export_yup=True,
                              export_apply=True, export_image_format="JPEG")
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print("staff: %d tris, %.2f m long -> %s" % (tris, TOP + 0.27 - BOTTOM + 0.012, OUT))


if __name__ == "__main__":
    export(build())
