"""The Runeknight's sword, modelled and exported for Godot.

    blender -b --factory-startup --python tools/art/blender/sword.py [-- --shots <folder>]

A one-handed arming sword of plain steel: a lenticular blade with a fuller down two thirds
of its length and edges bevelled to an ogive point, a straight crossguard with flared
ends, a grip wrapped in a spiral of brown leather (Poly Haven brown_leather, CC0) and a
wheel pommel. The steel's textures are made here: brushed along the blade, with fine
scratches and a few smudges (colour, roughness, normal). Frame (Blender): the right fist's
centre at the origin, just under the guard, the blade up +Z, the edges toward +-Y (+Y
leads a swing), like the rune axe. Exports game/art/weapons/sword.glb.
"""
import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
LEATHER = ROOT / "art" / "vendor" / "polyhaven" / "textures" / "brown_leather"
SKY = ROOT / "game" / "art" / "sky" / "kloofendal_partly_cloudy_4k_clamped.exr"
OUT = ROOT / "game" / "art" / "weapons" / "sword.glb"

## Metres from the right fist's centre: the guard, the blade, the grip and pommel.
GUARD = 0.062
BLADE = (0.068, 0.84)
GRIP = (-0.085, 0.056)
POMMEL = -0.115
BLADE_WIDTH = (0.05, 0.034)  # at the guard, and where the point begins
BLADE_THICK = (0.0078, 0.0042)
POINT = 0.8  # share of the blade's length before the point curves in
FULLER = (0.6, 0.72)  # the fuller runs full depth to here, fades out by there
STATIONS = 60
SIDES = 24
TEXTURE = 1024
BLADE_INDEX, HILT, GRIP_INDEX = range(3)


def steel_maps(rng, brightness, rough):
    """Brushed steel along v: streaks, scratches, smudges -> colour, ORM, normal images."""
    n = TEXTURE
    u = np.arange(n)
    streak = rng.normal(0.0, 1.0, n)
    streak = np.convolve(streak, np.ones(3) / 3, mode="same")
    streak += np.convolve(rng.normal(0.0, 1.0, n), np.ones(25) / 5, mode="same") * 0.5
    streak = np.tile(streak[None, :], (n, 1))
    streak += rng.normal(0.0, 0.25, (n, n))  # grain
    # long soft smudges (low-frequency noise, upsampled)
    coarse = rng.normal(0.0, 1.0, (8, 8))
    smudge = np.kron(coarse, np.ones((n // 8, n // 8)))
    for axis in (0, 1):
        k = np.ones(n // 8) / (n // 8)
        smudge = np.apply_along_axis(lambda line: np.convolve(np.pad(line, n // 16, mode="wrap"), k, "same")[n // 16:-n // 16], axis, smudge)
    # scratches: short thin lines a few degrees off the length
    scratch = np.zeros((n, n))
    for _ in range(260):
        x, y = rng.integers(0, n, 2)
        length = rng.integers(20, 160)
        slope = rng.normal(0.0, 0.25)
        for t in range(length):
            px, py = int(x + t * slope) % n, (y + t) % n
            scratch[py, px] = max(scratch[py, px], rng.uniform(0.4, 1.0))
    shade = brightness * (1.0 + 0.035 * streak + 0.06 * smudge) + 0.08 * scratch
    colour = np.clip(np.stack([shade * 0.97, shade * 0.985, shade * 1.0], -1), 0.0, 1.0)
    roughness = np.clip(rough + 0.035 * streak + 0.06 * smudge + 0.2 * scratch, 0.05, 1.0)
    # metallic a touch under 1: with no reflection probes about, pure metal mirrors only
    # the dark ground and reads black in the game
    orm = np.stack([np.ones_like(roughness), roughness, np.full_like(roughness, 0.8)], -1)
    height = 0.6 * streak - 2.0 * scratch
    gy, gx = np.gradient(height)
    normal = np.stack([-gx * 0.08, gy * 0.08, np.ones_like(gx)], -1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    return colour, orm, normal * 0.5 + 0.5


def image(name, pixels, colour):
    img = bpy.data.images.new(name, TEXTURE, TEXTURE, alpha=False)
    rgba = np.dstack([pixels, np.ones(pixels.shape[:2])]).astype(np.float32)
    img.pixels.foreach_set(rgba[::-1].ravel())  # (Blender's rows run bottom-up)
    img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
    img.pack()
    return img


def pbr(name, colour, orm, normal):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    base = nodes.new("ShaderNodeTexImage")
    base.image = colour
    links.new(base.outputs["Color"], bsdf.inputs["Base Color"])
    packed = nodes.new("ShaderNodeTexImage")
    packed.image = orm
    split = nodes.new("ShaderNodeSeparateColor")
    links.new(packed.outputs["Color"], split.inputs["Color"])
    links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
    links.new(split.outputs["Blue"], bsdf.inputs["Metallic"])
    bump = nodes.new("ShaderNodeTexImage")
    bump.image = normal
    normal_map = nodes.new("ShaderNodeNormalMap")
    links.new(bump.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def materials():
    rng = np.random.default_rng(11)
    blade = steel_maps(rng, 0.78, 0.38)
    hilt = steel_maps(rng, 0.45, 0.45)
    out = [pbr("blade_steel", image("blade_color", blade[0], True), image("blade_orm", blade[1], False),
               image("blade_normal", blade[2], False)),
           pbr("hilt_steel", image("hilt_color", hilt[0], True), image("hilt_orm", hilt[1], False),
               image("hilt_normal", hilt[2], False))]
    leather = []
    for kind in ("diff", "arm", "nor_gl"):
        img = bpy.data.images.load(str(LEATHER / ("brown_leather_%s_2k.jpg" % kind)))
        img.scale(TEXTURE, TEXTURE)
        img.colorspace_settings.name = "sRGB" if kind == "diff" else "Non-Color"
        img.pack()
        leather.append(img)
    out.append(pbr("grip_leather", *leather))
    return out


def blade(bm, uv):
    """Lofted cross-sections from the guard to the point: edges at +-Y, flats at +-X."""
    z0, z1 = BLADE
    rings = []
    for i in range(STATIONS + 1):
        t = i / STATIONS
        z = z0 + (z1 - z0) * t
        width = BLADE_WIDTH[0] + (BLADE_WIDTH[1] - BLADE_WIDTH[0]) * min(t / POINT, 1.0)
        thick = BLADE_THICK[0] + (BLADE_THICK[1] - BLADE_THICK[0]) * t
        if t > POINT:  # an ogive point
            s = (t - POINT) / (1.0 - POINT)
            width *= math.sqrt(max(1.0 - s * s, 0.0))
            thick *= max(1.0 - s * 0.85, 0.0)
        fuller = 1.0 if t < FULLER[0] else max(0.0, 1.0 - (t - FULLER[0]) / (FULLER[1] - FULLER[0]))
        half, face = width / 2, thick / 2
        # one flat from the +Y edge to the -Y edge: (share of the half-width, share of the thickness)
        profile = [(0.82, 0.42), (0.45, 1.0), (0.22, 1.0 - 0.3 * fuller), (0.0, 1.0 - 0.42 * fuller)]
        points = [(0.0, half)]
        for sign in (1, -1):
            side = [(sign * h * face, f * half) for f, h in profile]
            side += [(sign * h * face, -f * half) for f, h in reversed(profile[:-1])]
            points += side if sign > 0 else list(reversed(side))
            if sign > 0:
                points.append((0.0, -half))
        rings.append([bm.verts.new((x, y, z)) for x, y in points])
    tip = bm.verts.new((0.0, 0.0, z1 + 0.004))
    count = len(rings[0])
    for i in range(STATIONS):
        t0, t1 = i / STATIONS, (i + 1) / STATIONS
        for k in range(count):
            a, b = rings[i][k], rings[i][(k + 1) % count]
            c, d = rings[i + 1][(k + 1) % count], rings[i + 1][k]
            face = bm.faces.new((a, b, c, d))
            face.material_index = BLADE_INDEX
            for loop in face.loops:
                v = loop.vert.co
                loop[uv].uv = (0.5 + v.y / 0.12 + (0.5 if v.x < 0 else 0.0), (v.z - z0) / (z1 - z0))
    for k in range(count):
        face = bm.faces.new((rings[-1][k], rings[-1][(k + 1) % count], tip))
        face.material_index = BLADE_INDEX
        for loop in face.loops:
            loop[uv].uv = (0.5 + loop.vert.co.y / 0.12, 1.0)


def lathe(bm, uv, profile, axis, index, u_scale=1.0, v_scale=1.0, sides=SIDES, ripple=None):
    """A surface of revolution: profile [(along, radius)] about `axis` ("z" or "x")."""
    rings = []
    for along, radius in profile:
        ring = []
        for k in range(sides):
            a = k / sides * math.tau
            r = radius + (ripple(along, a) if ripple else 0.0)
            if axis == "z":
                ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), along)))
            else:
                ring.append(bm.verts.new((along, r * math.cos(a), POMMEL + r * math.sin(a))))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(sides):
            face = bm.faces.new((rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides], rings[i + 1][k]))
            face.material_index = index
            for loop, (kk, ii) in zip(face.loops, ((k, i), (k + 1, i), (k + 1, i + 1), (k, i + 1))):
                loop[uv].uv = (kk / sides * u_scale, profile[ii][0] * v_scale)


def guard(bm, uv):
    """A straight bar across the edges, flared and slightly swept toward the blade at its
    ends, a raised block at its middle; an octagonal section."""
    steps = 40
    rings = []
    for i in range(steps + 1):
        y = -0.122 + 0.244 * i / steps
        s = abs(y) / 0.122
        swell = 1.0 + 0.55 * math.exp(-(y / 0.018) ** 2) + 0.45 * s ** 6  # middle block, flared ends
        hx, hz = 0.0105 * swell, 0.0085 * (1.0 + 0.4 * math.exp(-(y / 0.018) ** 2))
        cz = GUARD + 0.011 * s ** 2
        ring = []
        for k in range(8):
            a = (k + 0.5) / 8 * math.tau
            ring.append(bm.verts.new((hx * math.cos(a) * 1.08, y, cz + hz * math.sin(a) * 1.08)))
        rings.append(ring)
    for i in range(steps):
        for k in range(8):
            face = bm.faces.new((rings[i][k], rings[i][(k + 1) % 8], rings[i + 1][(k + 1) % 8], rings[i + 1][k]))
            face.material_index = HILT
            for loop, (kk, ii) in zip(face.loops, ((k, i), (k + 1, i), (k + 1, i + 1), (k, i + 1))):
                loop[uv].uv = (kk / 8 * 0.15, ii / steps * 0.9)
    for ring in (rings[0], list(reversed(rings[-1]))):
        face = bm.faces.new(ring if ring is rings[0] else ring)
        face.material_index = HILT


def build():
    for obj in list(bpy.data.objects):  # (the factory scene's cube, camera and light)
        bpy.data.objects.remove(obj)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    blade(bm, uv)
    guard(bm, uv)
    lo, hi = GRIP

    def wrap(z, a):  # a spiral of leather strip, its turns a little proud
        return 0.0011 * math.cos(math.tau * ((z - lo) / 0.021 + a / math.tau)) ** 2

    grip = [(lo + (hi - lo) * i / 48, 0.0152 + 0.0012 * math.sin(math.pi * i / 48)) for i in range(49)]
    lathe(bm, uv, grip, "z", GRIP_INDEX, u_scale=0.3, v_scale=1.6, ripple=wrap)
    # the wheel pommel (about X) with a raised boss, and the peen through it
    wheel = [(-0.0125, 0.0), (-0.0125, 0.012), (-0.0155, 0.012), (-0.0155, 0.0), (-0.0156, 0.0)]
    wheel = [(-0.0157, 0.0), (-0.0157, 0.0105), (-0.012, 0.0125), (-0.012, 0.022), (-0.0095, 0.0295),
             (-0.005, 0.0322), (0.005, 0.0322), (0.0095, 0.0295), (0.012, 0.022), (0.012, 0.0125),
             (0.0157, 0.0105), (0.0157, 0.0)]
    lathe(bm, uv, wheel, "x", HILT, u_scale=0.2, v_scale=4.0, sides=32)
    lathe(bm, uv, [(POMMEL - 0.036, 0.0), (POMMEL - 0.036, 0.006), (POMMEL - 0.03, 0.0075),
                   (POMMEL - 0.026, 0.0)], "z", HILT, u_scale=0.1, v_scale=4.0, sides=12)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    mesh = bpy.data.meshes.new("sword")
    bm.to_mesh(mesh)
    bm.free()
    for mat in materials():
        mesh.materials.append(mat)
    obj = bpy.data.objects.new("sword", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(32))
    return obj


def export(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT), use_selection=True, export_format="GLB", export_yup=True,
                              export_apply=True, export_image_format="JPEG")
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print("sword: %d tris, %.2f m long -> %s" % (tris, BLADE[1] - (POMMEL - 0.036), OUT))


def shots(obj, folder):
    """Previews lit by the game's sky: the whole sword, and the hilt close."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 1200, 800
    world = bpy.data.worlds.new("sky")
    world.use_nodes = True
    env = world.node_tree.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(str(SKY))
    world.node_tree.links.new(env.outputs["Color"], world.node_tree.nodes["Background"].inputs["Color"])
    scene.world = world
    obj.rotation_euler = (math.radians(-62), 0.0, 0.0)  # tipped over, the point to +Y, a flat to +X
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    Path(folder).mkdir(parents=True, exist_ok=True)
    for name, aim, far, lens in (("sword", (0.0, 0.33, 0.17), 1.9, 50), ("hilt", (0.0, -0.02, -0.01), 0.5, 50)):
        aim = Vector(aim)
        cam.location = aim + Vector((far, -far * 0.35, far * 0.3))
        cam.rotation_euler = (aim - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = lens
        bpy.context.view_layer.update()
        scene.render.filepath = str(Path(folder) / (name + ".png"))
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    sword = build()
    export(sword)
    if "--shots" in args:
        shots(sword, args[args.index("--shots") + 1])
