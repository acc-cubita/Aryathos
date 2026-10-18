"""Semi-realistic game trees: bark tubes + crowns of alpha cards (tools/art/foliage_cards.py).

    blender -b --factory-startup --python tools/art/blender/trees.py

Builds broadleaf, pine and bush variants and exports each as
game/art/trees/<kind>_<n>.glb holding two meshes, "trunk" and "leaves" (the game
assigns its own materials). Trunk UVs tile the bark texture (~1.2 m per repeat).
Leaf cards sample one of the 2 x 2 clusters in the foliage atlas; their normals are
bent away from the crown centre so a crown shades like one leafy volume rather than
flat cards, and UV2 = (shade, phase): shade darkens the inside and underside of the
crown, phase staggers each card's flutter in the wind.
"""
import math
import os
import random

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ROOT, "game", "art", "trees")
BARK_TILE = 1.2  # meters of bark per texture repeat


class Geo:
    """Vertices with per-vertex normal, UV and UV2, and faces; becomes one Blender mesh."""

    def __init__(self):
        self.verts, self.normals, self.uvs, self.uv2s, self.faces = [], [], [], [], []

    def vertex(self, co, normal, uv, uv2=(1.0, 0.0)):
        self.verts.append(Vector(co))
        self.normals.append(Vector(normal).normalized())
        self.uvs.append(uv)
        self.uv2s.append(uv2)
        return len(self.verts) - 1

    def mesh(self, name):
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        for layer_name, values in (("UVMap", self.uvs), ("UV2", self.uv2s)):
            layer = me.uv_layers.new(name=layer_name)
            for poly in me.polygons:
                for li in poly.loop_indices:
                    layer.data[li].uv = values[me.loops[li].vertex_index]
        me.normals_split_custom_set_from_vertices([tuple(n) for n in self.normals])
        me.validate()
        return me


def tube(geo, path, radii, sides):
    """A tapered tube along `path` (parallel-transported rings), bark UVs in meters."""
    normal = (path[1] - path[0]).normalized().orthogonal().normalized()
    around = max(1, round(2 * math.pi * radii[0] / BARK_TILE))
    rings, v = [], 0.0
    for i, p in enumerate(path):
        t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        normal = (normal - t * normal.dot(t)).normalized()
        side = t.cross(normal)
        if i:
            v += (p - path[i - 1]).length / BARK_TILE
        ring = []
        for k in range(sides + 1):  # seam vertex doubled so the UVs wrap
            a = 2 * math.pi * k / sides
            off = normal * math.cos(a) + side * math.sin(a)
            ring.append(geo.vertex(p + off * radii[i], off, (around * k / sides, v)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for k in range(sides):
            geo.faces.append((a[k], a[k + 1], b[k + 1], b[k]))


def curve(start, direction, length, steps, rise, rng, wander=0.08):
    """Points from `start` along `direction`, bending by `rise` (+ up, - droop) per step."""
    pts, d, p = [Vector(start)], Vector(direction).normalized(), Vector(start)
    for _ in range(steps):
        d = (d + Vector((0, 0, rise)) + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * wander).normalized()
        p = p + d * (length / steps)
        pts.append(p)
    return pts


def taper(n, r0, r1):
    return [r0 + (r1 - r0) * (i / (n - 1)) ** 0.8 for i in range(n)]


def card(geo, base, up, facing, width, height, cell, crown, rng):
    """One leaf card standing on `base`, its long axis along `up`, facing `facing`."""
    up = up.normalized()
    side = up.cross(facing)
    if side.length < 1e-4:
        side = up.orthogonal()
    side.normalize()
    facing = side.cross(up).normalized()
    u0, v0 = (cell % 2) * 0.5, (cell // 2) * 0.5
    centre, radii = crown
    phase = rng.random()
    corners = (
        (base - side * width / 2, (u0, v0 + 0.5)),
        (base + side * width / 2, (u0 + 0.5, v0 + 0.5)),
        (base + side * width / 2 + up * height, (u0 + 0.5, v0)),
        (base - side * width / 2 + up * height, (u0, v0)),
    )
    ids = []
    for co, uv in corners:
        rel = Vector(((co.x - centre.x) / radii.x, (co.y - centre.y) / radii.y, (co.z - centre.z) / radii.z))
        out = rel.normalized() if rel.length > 1e-4 else Vector((0, 0, 1))
        # inside and underneath the crown is darker; the sunny top and rim brightest
        shade = min(1.0, 0.35 + 0.45 * min(rel.length, 1.0) + 0.25 * max(rel.z, -0.6))
        ids.append(geo.vertex(co, facing.lerp(out, 0.75), uv, (shade, phase)))
    geo.faces.append(tuple(ids))


def broadleaf(seed):
    rng = random.Random(seed)
    trunk, leaves = Geo(), Geo()
    fork = rng.uniform(2.0, 2.7)
    height = rng.uniform(6.8, 8.8)
    r0 = rng.uniform(0.2, 0.27)
    lean = Vector((rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.1), 1.0))
    stem = curve(Vector((0, 0, -0.3)), lean, height * 0.78, 10, 0.02, rng, 0.04)
    radii = taper(len(stem), r0, 0.05)
    radii[0] *= 1.35  # root flare
    tube(trunk, stem, radii, 10)
    crown = (Vector((stem[-1].x * 0.6, stem[-1].y * 0.6, fork + (height - fork) * 0.52)),
             Vector((rng.uniform(2.3, 2.9), rng.uniform(2.3, 2.9), (height - fork) * 0.55)))
    twigs = []
    limbs = rng.randint(4, 6)
    for i in range(limbs):
        z = fork + rng.uniform(0, 1.5)
        k = min(len(stem) - 1, int(z / (height * 0.78) * (len(stem) - 1)))
        az = 2 * math.pi * i / limbs + rng.uniform(-0.4, 0.4)
        pitch = math.radians(rng.uniform(35, 58))
        d = Vector((math.cos(az) * math.sin(pitch), math.sin(az) * math.sin(pitch), math.cos(pitch)))
        limb = curve(stem[k], d, rng.uniform(2.4, 3.3), 6, 0.05, rng)
        tube(trunk, limb, taper(len(limb), radii[k] * 0.6, 0.025), 6)
        twigs.append(limb)
        for _ in range(rng.randint(3, 5)):
            j = rng.randint(2, len(limb) - 2)
            out = (limb[j] - crown[0]).normalized()
            sd = (limb[j + 1] - limb[j]).normalized().lerp(out, 0.5) + Vector((rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), rng.uniform(-0.1, 0.5)))
            branch = curve(limb[j], sd, rng.uniform(1.0, 1.7), 3, 0.06, rng)
            tube(trunk, branch, taper(len(branch), 0.045, 0.012), 4)
            twigs.append(branch)
    twigs.append(stem[-4:])
    for twig in twigs:
        for j in range(1, len(twig)):
            for _ in range(rng.randint(2, 3)):
                base = twig[j - 1].lerp(twig[j], rng.random())
                out = (base - crown[0])
                out = out.normalized() if out.length > 1e-3 else Vector((0, 0, 1))
                up = (twig[j] - twig[j - 1]).normalized().lerp(out, 0.55) + Vector((0, 0, 0.25))
                facing = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.3, 1)))
                size = rng.uniform(1.3, 1.85)
                card(leaves, base, up, facing, size, size, rng.randrange(4), crown, rng)
    return trunk, leaves


def pine(seed):
    rng = random.Random(seed)
    trunk, leaves = Geo(), Geo()
    height = rng.uniform(8.5, 12.0)
    r0 = rng.uniform(0.18, 0.25)
    stem = curve(Vector((0, 0, -0.3)), Vector((0, 0, 1)), height + 0.3, 14, 0.0, rng, 0.015)
    radii = taper(len(stem), r0, 0.02)
    radii[0] *= 1.3
    tube(trunk, stem, radii, 8)
    crown = (Vector((0, 0, height * 0.55)), Vector((2.2, 2.2, height * 0.5)))
    z = rng.uniform(1.3, 1.9)
    spread = rng.uniform(2.3, 2.8)
    turn = rng.uniform(0, 6.28)
    up = Vector((0, 0, 1))
    while z < height - 0.7:
        frac = (z - 1.3) / (height - 1.3)
        reach = 0.4 + spread * (1 - frac) ** 1.1
        count = rng.randint(6, 8)
        turn += 0.7
        for i in range(count):
            az = turn + 2 * math.pi * i / count + rng.uniform(-0.25, 0.25)
            tilt = -0.3 + 0.55 * frac + rng.uniform(-0.1, 0.1)
            d = Vector((math.cos(az), math.sin(az), tilt))
            k = min(len(stem) - 1, int((z + 0.3) / (height + 0.3) * (len(stem) - 1)))
            start = Vector((stem[k].x, stem[k].y, z))
            branch = curve(start, d, reach, 3, -0.12 * (1 - frac), rng, 0.04)
            # the bare branch only shows near the trunk; the sprays cover the rest
            inner = [start.lerp(p, 0.6) for p in branch]
            tube(trunk, inner, taper(len(inner), 0.01 + 0.03 * (1 - frac), 0.006), 4)
            steps = max(2, round(reach / 0.38))
            for c in range(steps):
                t = 0.1 + c / steps * 0.75
                seg = min(int(t * (len(branch) - 1)), len(branch) - 2)
                base = branch[seg].lerp(branch[seg + 1], t * (len(branch) - 1) - seg)
                along = (branch[seg + 1] - branch[seg]).normalized()
                flat = along.cross(up).normalized()
                size = rng.uniform(0.95, 1.35) * min(1.0, 0.5 + reach * 0.3)
                # a flat spray and a steeper crossing one: full from the side and from below
                for roll in (rng.uniform(-0.35, 0.35), rng.choice((-1, 1)) * rng.uniform(0.8, 1.2)):
                    facing = up * math.cos(roll) + flat * math.sin(roll)
                    card(leaves, base, along, facing, size * 0.9, size, rng.randrange(4), crown, rng)
        # inner fill: short sprays around the trunk so the crown is not hollow
        for i in range(3):
            az = rng.uniform(0, 2 * math.pi)
            d = Vector((math.cos(az), math.sin(az), 0.2))
            card(leaves, Vector((0, 0, z)), d, up, 0.9, 1.0, rng.randrange(4), crown, rng)
        z += rng.uniform(0.42, 0.55)
    for i in range(4):  # leader shoot
        a = i * math.pi / 4
        card(leaves, Vector((0, 0, height - 1.4)), Vector((0, 0, 1)), Vector((math.cos(a), math.sin(a), 0)), 0.9, 1.6, rng.randrange(4), crown, rng)
    return trunk, leaves


def bush(seed):
    rng = random.Random(seed)
    trunk, leaves = Geo(), Geo()
    radius = rng.uniform(0.8, 1.05)
    crown = (Vector((0, 0, 0.45)), Vector((radius, radius, 0.75)))
    for _ in range(4):
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 1.6))
        stem = curve(Vector((0, 0, -0.1)), d, 0.7, 2, 0.1, rng)
        tube(trunk, stem, taper(len(stem), 0.025, 0.01), 4)
    for _ in range(rng.randint(42, 54)):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.0, 0.45) * radius
        base = Vector((math.cos(a) * r, math.sin(a) * r, rng.uniform(0.0, 0.35)))
        up = Vector((math.cos(a) * rng.uniform(0.3, 1.0), math.sin(a) * rng.uniform(0.3, 1.0), rng.uniform(0.5, 1.2)))
        facing = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.2, 1)))
        size = rng.uniform(0.75, 1.05)
        card(leaves, base, up, facing, size, size, rng.randrange(4), crown, rng)
    return trunk, leaves


def export(name, parts):
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    objs = []
    for part_name, geo in zip(("trunk", "leaves"), parts):
        if not geo.faces:
            continue
        o = bpy.data.objects.new(part_name, geo.mesh(part_name))
        bpy.context.scene.collection.objects.link(o)
        objs.append(o)
    for o in objs:
        o.select_set(True)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
                              export_texcoords=True, export_normals=True, export_materials='NONE',
                              export_animations=False)
    tris = sum(len(g.faces) * 2 for g in parts)
    print("exported", path, "~%d triangles" % tris)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for i, seed in enumerate((11, 12, 13)):
        export("broadleaf_%d" % i, broadleaf(seed))
    for i, seed in enumerate((1, 2, 3)):
        export("pine_%d" % i, pine(seed))
    for i, seed in enumerate((31, 32)):
        export("bush_%d" % i, bush(seed))
