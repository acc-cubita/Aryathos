"""The Arkanor rune axe (concept: char/Arkanor.jpg), modelled, painted and exported.

Run after the other arkanor_*.py modules (same namespace):
    exec(open(r"D:/my game/tools/art/blender/arkanor_axe.py").read())
    axe_pass()      # model + paint (Cycles bake) + export game/art/weapons/rune_axe.glb

Frame (Blender): grip at the origin, haft along +Z, blade toward +Y. glTF turns
that into +Y up / blade toward -Z, which is what CharacterModel expects.
"""
AXE_OUT = ROOT + "/game/art/weapons"
AXE_TEX = ROOT + "/art/weapons/tex"


def axe_mats():
    return {n: paint_material("axe", n) for n in ("wood", "wrap", "gold", "steel", "crystal")}


def blade(bm, rows=14, cols=8):
    """Crescent blade on the +Y side: thick at the socket, thin at the cutting edge.
    detail UV: u along the edge (bottom -> top), v from the socket (0) to the edge (1)."""
    uvl = bm.loops.layers.uv.get("detail") or bm.loops.layers.uv.new("detail")
    grid = {}
    for side in (1, -1):
        for i in range(rows + 1):
            v = i / rows
            for j in range(cols + 1):
                u = j / cols
                zs = 0.575 + 0.23 * v                      # along the socket
                ze = 0.39 + 0.6 * v + 0.03 * math.sin(v * math.pi)  # flared edge
                y_edge = 0.31 - 0.07 * (2 * v - 1) ** 2
                y = 0.035 + (y_edge - 0.035) * u
                z = zs + (ze - zs) * u ** 1.3
                t = 0.011 * (1 - u) ** 0.8 + 0.0012
                grid[side, i, j] = bm.verts.new((side * t, y, z))
    for side in (1, -1):
        for i in range(rows):
            for j in range(cols):
                quad = [grid[side, i, j], grid[side, i, j + 1], grid[side, i + 1, j + 1], grid[side, i + 1, j]]
                f = bm.faces.new(quad if side > 0 else quad[::-1])
                for loop, (a, b) in zip(f.loops, ((i, j), (i, j + 1), (i + 1, j + 1), (i + 1, j)) if side > 0 else ((i + 1, j), (i + 1, j + 1), (i, j + 1), (i, j))):
                    loop[uvl].uv = (a / rows, b / cols)
    # close the rim (edge, top, bottom, socket side) between the two faces
    rim = [(i, cols) for i in range(rows + 1)] + [(rows, j) for j in range(cols - 1, -1, -1)] + \
          [(i, 0) for i in range(rows - 1, -1, -1)] + [(0, j) for j in range(1, cols)]
    for (i0, j0), (i1, j1) in zip(rim, rim[1:] + rim[:1]):
        bm.faces.new((grid[1, i0, j0], grid[1, i1, j1], grid[-1, i1, j1], grid[-1, i0, j0]))


def crystal(bm, base, direction, length, radius, sides=6, seed=1, flat=1.0):
    """Faceted bipyramid crystal, slightly irregular; flat < 1 squashes it sideways (X)."""
    rng = np.random.default_rng(seed)
    d = unit(direction)
    T, B, U = frame(d, (1, 0, 0) if abs(d[0]) < 0.9 else (0, 0, 1))
    base = np.asarray(base, dtype=float)
    waist = base + d * length * 0.32
    ring = [bm.verts.new(waist + radius * (1 + rng.uniform(-0.15, 0.15)) * (B * math.cos(a) + U * math.sin(a)) * np.array((flat, 1.0, 1.0)) + d * rng.uniform(-0.01, 0.01))
            for a in np.linspace(0, 2 * math.pi, sides, endpoint=False)]
    tip = bm.verts.new(base + d * length)
    bottom = bm.verts.new(base)
    for k in range(sides):
        a, b = ring[k], ring[(k + 1) % sides]
        bm.faces.new((a, b, tip))
        bm.faces.new((b, a, bottom))


def ring_band(bm, z0, z1, r0, r1, sides=16):
    tube(bm, [np.array((0, 0, z0)), np.array((0, 0, z1))], [r0, r1], (1, 0, 0), sides=sides, every=1)


def build_axe():
    M = axe_mats()
    parts = {}
    # haft: dark wood, slightly thicker toward the head
    bm = bmesh.new()
    tube(bm, [np.array((0, 0, z)) for z in np.linspace(-0.3, 0.86, 9)], list(np.linspace(0.02, 0.024, 9)), (1, 0, 0), sides=12, every=1)
    parts["wood"] = bm
    # leather wraps: grip and below the head
    bm = bmesh.new()
    for z0, z1 in ((-0.13, 0.13), (0.36, 0.5)):
        for k, z in enumerate(np.arange(z0, z1, 0.022)):
            ring_band(bm, z, z + 0.02, 0.0245, 0.0255, sides=12)
    parts["wrap"] = bm
    # gold: rings, pommel cap, head socket, top spike
    bm = bmesh.new()
    for z in (-0.27, 0.17, 0.33, 0.53):
        ring_band(bm, z, z + 0.018, 0.029, 0.029)
    ring_band(bm, -0.33, -0.27, 0.032, 0.026)
    sock = [(0.555, 0.03), (0.58, 0.042), (0.8, 0.042), (0.83, 0.03)]
    tube(bm, [np.array((0, 0, z)) for z, _ in sock], [r for _, r in sock], (1, 0, 0), sides=8, every=1)
    bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.026, radius2=0.0, depth=0.1,
                          matrix=Matrix.Translation((0, 0, 0.88)))
    # back hook: curling spike behind the socket
    path, s = spline([np.array(p) for p in ((0, -0.035, 0.74), (0, -0.1, 0.73), (0, -0.16, 0.68), (0, -0.19, 0.6))])
    tube(bm, path, list(0.02 * (1 - s / s[-1]) + 0.002), (1, 0, 0), sides=8, every=3)
    parts["gold"] = bm
    # steel blade
    bm = bmesh.new()
    blade(bm)
    parts["steel"] = bm
    # crystals: the big one riding the top of the head, a gem in the socket, one on the pommel
    bm = bmesh.new()
    crystal(bm, (0, 0.02, 0.78), (0, 0.9, 0.44), 0.46, 0.085, sides=7, seed=3, flat=0.45)  # the head's great crystal
    crystal(bm, (0.03, 0.0, 0.69), (1, 0, 0), 0.03, 0.018, sides=6, seed=4)
    crystal(bm, (-0.03, 0.0, 0.69), (-1, 0, 0), 0.03, 0.018, sides=6, seed=5)
    crystal(bm, (0, 0, -0.32), (0, 0, -1), 0.11, 0.022, seed=6)
    parts["crystal"] = bm
    # one object per part, joined: materials and the blade's "detail" UV merge by name
    old = bpy.data.objects.get("rune_axe")
    if old:
        bpy.data.objects.remove(old)
    coll = collection("Rune Axe")
    objs = []
    for name, part in parts.items():
        bmesh.ops.recalc_face_normals(part, faces=part.faces)
        me = bpy.data.meshes.new("axe_" + name)
        part.to_mesh(me)
        part.free()
        me.materials.append(M[name])
        if name in ("wood", "wrap", "gold"):
            me.shade_smooth()
        o = bpy.data.objects.new("axe_" + name, me)
        coll.objects.link(o)
        objs.append(o)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = objs[0]
    obj.name = obj.data.name = "rune_axe"
    obj.location = (0, -1.2, 0)
    return obj


def axe_recipe(name, n):
    P = PALETTE
    if name == "wood":
        grain = n.remap(n.wave(55.0, "X", 8.0, 2.0), 0.0, 1.0, 0.7, 1.1)
        return n.scale(srgb(78, 50, 32), grain), (0, 0, 0)
    if name == "wrap":
        bands = n.remap(n.math("ABSOLUTE", n.math("SUBTRACT", n.wave(90.0, "DIAGONAL", 0.5), 0.5)), 0.0, 0.14, 0.55, 1.0)
        return n.scale(srgb(96, 62, 38), bands), (0, 0, 0)
    if name == "gold":
        shine = n.remap(n.nz, -1.0, 1.0, 0.7, 1.35)
        return n.scale(srgb(196, 150, 72), shine), (0, 0, 0)
    if name == "steel":
        du, dv, _ = n.sep(n.uv("detail"))
        # rune band engraved along the blade, glowing like the concept
        band = n.mul(n.remap(dv, 0.5, 0.54, 0, 1), n.remap(dv, 0.8, 0.76, 0, 1), n.remap(du, 0.12, 0.16, 0, 1), n.remap(du, 0.88, 0.84, 0, 1))
        rune = n.math("MULTIPLY", n.rgb(n.image("runes.png", n.combine(n.math("MULTIPLY", du, 0.65), n.remap(dv, 0.52, 0.78, 0.0, 1.0)), 'REPEAT'))[0], band)
        edge = n.remap(dv, 0.85, 0.97, 1.0, 1.35)  # honed edge catches light
        steel = n.scale(n.scale(srgb(176, 184, 196), edge), n.remap(n.noise(25.0), 0.3, 0.7, 0.9, 1.06))
        color = n.lerp(n.lerp(steel, n.scale(steel, 0.55), band), P["cyan"], rune)
        return color, n.scale(P["cyan"], rune)
    if name == "crystal":
        # deep blue at the base, bright cyan toward the tips, lit from inside
        glowk = n.remap(n.noise(6.0, 2.0), 0.3, 0.7, 0.6, 1.0)
        color = n.lerp(srgb(18, 64, 190), srgb(90, 190, 255), n.remap(n.nz, -1.0, 1.0, 0.0, 1.0))
        return color, n.scale(srgb(40, 140, 255), glowk)
    return (0.5, 0.5, 0.5), (0, 0, 0)


def paint_axe(obj, size=1024):
    import os
    os.makedirs(AXE_TEX, exist_ok=True)
    me = obj.data
    uv = me.uv_layers.get("atlas") or me.uv_layers.new(name="atlas")
    me.uv_layers.active = uv
    uv.active_render = True
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    scene = bpy.context.scene
    engine = scene.render.engine
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 16
    use_gpu(scene)
    for mat in me.materials:
        n = Nodes(mat)
        color, glow = axe_recipe(mat.name.split("_", 2)[2], n)
        shade = n.math("POWER", n.remap(n.ao, 0.0, 1.0, 0.35, 1.0), 1.2)
        top = n.remap(n.nz, -1.0, 1.0, 0.72, 1.15)
        edges = n.math("ADD", 1.0, n.remap(n.pointiness, 0.5, 0.58, 0.0, 0.4))
        painted = n.scale(n.scale(n.scale(color, shade), top), edges)
        for node_name, value in (("PaintEmit", painted), ("GlowEmit", glow)):
            emit = n.new("ShaderNodeEmission")
            emit.name = node_name
            n.feed(emit.inputs["Color"], value)
        n.new("ShaderNodeOutputMaterial").name = "Output"
        target = n.new("ShaderNodeTexImage")
        target.name = "BakeTarget"
        n.tree.nodes.active = target
    images = []
    for suffix, sz in (("color", size), ("glow", size // 2)):
        name = "rune_axe_" + suffix
        old = bpy.data.images.get(name)
        if old:
            bpy.data.images.remove(old)
        images.append(bpy.data.images.new(name, sz, sz))
    global TEX
    tex_dir, TEX = TEX, AXE_TEX  # bake_one saves into TEX
    try:
        bake_one(obj, images[0], "PaintEmit")
        bake_one(obj, images[1], "GlowEmit")
    finally:
        TEX = tex_dir
    scene.render.engine = engine
    final = bpy.data.materials.get("rune_axe_painted") or bpy.data.materials.new("rune_axe_painted")
    final.use_nodes = True
    nt = final.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    col = nt.nodes.new("ShaderNodeTexImage")
    col.image = images[0]
    glow = nt.nodes.new("ShaderNodeTexImage")
    glow.image = images[1]
    nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(glow.outputs["Color"], bsdf.inputs["Emission Color"])
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    bsdf.inputs["Emission Strength"].default_value = 2.5
    bsdf.inputs["Roughness"].default_value = 0.6
    me.materials.clear()
    me.materials.append(final)
    me.polygons.foreach_set("material_index", np.zeros(len(me.polygons), dtype=np.int32))
    for name in [l.name for l in me.uv_layers if l.name != "atlas"]:
        me.uv_layers.remove(me.uv_layers[name])
    me.update()


def export_axe(obj):
    import os
    os.makedirs(AXE_OUT, exist_ok=True)
    loc = obj.location.copy()
    obj.location = (0, 0, 0)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = AXE_OUT + "/rune_axe.glb"
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format='GLB', export_yup=True,
                              export_apply=True, export_animations=False, export_image_format='AUTO')
    obj.location = loc
    return path


def axe_pass():
    obj = build_axe()
    paint_axe(obj)
    return {"faces": len(obj.data.polygons), "path": export_axe(obj)}
