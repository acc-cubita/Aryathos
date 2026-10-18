"""Arkanor painting: one game mesh per character + hand-painted color/glow maps.

Run after arkanor_hq.py, arkanor_head.py and arkanor_clothes.py (same namespace):
    exec(open(r"D:/my game/tools/art/blender/arkanor_paint.py").read())
    paint_pass("male"); paint_pass("female")

1. game_mesh(): copies every piece with its modifiers applied (not the rig), gives
   rigid pieces (hair, beard, eyes) full Head weight, adds pattern coordinates
   ("detail" UV) + masks, joins them into arkanor_<key> deformed by the rig.
2. atlas(): Smart-UV atlas, face and eye islands scaled up for more texels.
3. bake_maps(): per-piece procedural "hand painting" in Cycles (palette, AO, top
   light, edge highlights, strands, runes, tattoos, face marks) baked to
   tex/arkanor_<key>_color.png and tex/arkanor_<key>_glow.png.
The source pieces stay (hidden) so every step can be re-run.
"""
PAINT_SIZE, GLOW_SIZE = 2048, 1024
RIGID = ("hair", "braids", "bun", "bun_tie", "brows", "beard", "beard_face", "beard_braids", "beard_beads", "strands", "eye.L", "eye.R")


def srgb(r, g, b):
    f = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (f(r / 255), f(g / 255), f(b / 255))


PALETTE = {
    "skin_male": srgb(206, 150, 118), "skin_female": srgb(224, 170, 140),
    "hair": srgb(200, 204, 212), "tunic": srgb(132, 119, 98), "sash": srgb(104, 94, 80),
    "pants": srgb(118, 117, 100), "wrap": srgb(150, 144, 126), "boots": srgb(104, 78, 58),
    "sole": srgb(40, 32, 26), "suit": srgb(30, 48, 96), "suit_boots": srgb(24, 38, 80),
    "silver": srgb(196, 202, 214), "leather": srgb(70, 42, 26), "lips": srgb(176, 92, 84),
    "cyan": srgb(90, 225, 255), "gold": srgb(255, 190, 60),
    "thread": srgb(196, 182, 140), "band": srgb(78, 68, 54),
}


# ---------------------------------------------------------------- game mesh

def recipe_of(suffix, mat):
    m = mat.replace("arkanor_", "")
    if m == "hair":
        if suffix == "hair":
            return "hair_cap"
        return "hair_beard" if suffix in ("beard", "beard_face", "brows") else "hair_braid"
    if m == "tunic" and suffix == "skirt":
        return "skirt"
    if m == "suit" and suffix.startswith(("tabard", "flap")):
        return "panel"
    if m == "suit" and suffix == "collar":
        return "collar"
    if m in ("silver", "silver_trim"):
        return "silver"
    return m


def paint_material(key, recipe):
    name = "paint_%s_%s" % (key, recipe)
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    return m


def body_detail(key, me):
    """Pattern coords + masks on the body: forearm tattoo zone (R), face (G), bodice front (B)."""
    names, t, w = body_bones(key)
    m = head_marks(key)
    cx = m["cx"]
    n = len(w)
    uv = np.zeros((n, 2))
    mask = np.zeros((n, 4))
    mask[:, 3] = 1
    sleeve_end = 0.5 if key == "male" else 0.55
    for side in (1, -1):
        for bone, lo, hi in (("UpperArm", sleeve_end, 1.0), ("LowerArm", 0.0, 1.0)):
            pre = "Left" if side > 0 else "Right"
            h, tl = bone_point(key, pre + bone, 0.0), bone_point(key, pre + bone, 1.0)
            a = unit(tl - h)
            f = np.array((0.0, -1.0, 0.0))
            u_ax = unit(f - a * f.dot(a))
            v_ax = np.cross(a, u_ax)
            sel = (names == bone) & (np.sign(w[:, 0] - cx) == side) & (t >= lo - 0.02)
            rel = w[sel] - h
            phi = np.degrees(np.arctan2((rel @ v_ax) * side, rel @ u_ax)) % 360
            # arm param: 0 at the sleeve end .. 1 at the wrist (upper arm takes the first third)
            tt = np.clip(t[sel], lo, hi)
            ap = (tt - lo) / (hi - lo) * 0.33 if bone == "UpperArm" else 0.33 + tt * 0.67
            uv[sel] = np.column_stack(((phi / 360 + 0.4) % 1.0, 1 - ap))
            mask[sel, 0] = (t[sel] >= lo) * 1.0
    face = (names == "Head") & (w[:, 1] < m["hc"][1])
    uv[face] = np.column_stack(((w[face, 0] - cx) / 0.2 + 0.5, (w[face, 2] - m["eye_z"]) / 0.2 + 0.5))
    mask[face, 1] = 1
    if key == "female":
        waist = bone_point(key, "Spine")[2]
        torso = np.isin(names, ("Spine", "Chest", "UpperChest")) & (w[:, 1] < bone_point(key, "Chest")[1])
        uv[torso] = np.column_stack(((w[torso, 0] - cx) / 0.4 + 0.5, (w[torso, 2] - waist) / 0.4))
        mask[torso, 2] = 1
    for l in list(me.uv_layers):
        me.uv_layers.remove(l)
    layer = me.uv_layers.new(name="detail")
    vi = np.empty(len(me.loops), dtype=np.int32)
    me.loops.foreach_get("vertex_index", vi)
    layer.data.foreach_set("uv", uv[vi].ravel())
    attr = me.color_attributes.new("masks", 'FLOAT_COLOR', 'POINT')
    attr.data.foreach_set("color", mask.ravel())


def game_mesh(key):
    body, eyes, rig = objects(key)
    src = [o for o in body.users_collection[0].objects if o.type == 'MESH']
    coll = collection("Arkanor Game")
    name = "arkanor_%s" % key
    old = bpy.data.objects.get(name)
    if old:
        bpy.data.objects.remove(old)
    dups = []
    for o in src:
        o.hide_viewport = False
        for md in o.modifiers:
            if md.type == 'ARMATURE':
                md.show_viewport = False
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    for o in src:
        suffix = o.name[len("arkanor_%s_" % key):]
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        me.transform(o.matrix_world)
        d = bpy.data.objects.new("%s_%s_tmp" % (name, suffix), me)
        coll.objects.link(d)
        if suffix in RIGID:
            d.vertex_groups.clear()
            d.vertex_groups.new(name="Head").add(range(len(me.vertices)), 1.0, 'REPLACE')
        for i, mat in enumerate(me.materials):
            me.materials[i] = paint_material(key, recipe_of(suffix, mat.name))
        if suffix.startswith("eye"):
            act = me.uv_layers.active
            for l in list(me.uv_layers):
                if l != act:
                    me.uv_layers.remove(l)
            me.uv_layers[0].name = "eye"
        elif suffix == "body":
            body_detail(key, me)
        else:
            for l in list(me.uv_layers):
                if l.name != "detail":
                    me.uv_layers.remove(l)
        dups.append(d)
    for o in src:
        for md in o.modifiers:
            if md.type == 'ARMATURE':
                md.show_viewport = True
        o.hide_viewport = o.hide_render = True
    bpy.ops.object.select_all(action='DESELECT')
    for d in dups:
        d.select_set(True)
    main = next(d for d in dups if d.name.endswith("_body_tmp"))
    bpy.context.view_layer.objects.active = main
    bpy.ops.object.join()
    main.name = main.data.name = name
    main.parent = rig
    main.matrix_parent_inverse = rig.matrix_world.inverted()
    a = main.modifiers.new("Armature", 'ARMATURE')
    a.object = rig
    return main


def atlas(game, key):
    """Smart-UV atlas; the face + eyes are unwrapped on their own and get 2.2x the texel density."""
    me = game.data
    uv = me.uv_layers.get("atlas") or me.uv_layers.new(name="atlas")
    me.uv_layers.active = uv
    uv.active_render = True
    bpy.ops.object.select_all(action='DESELECT')
    game.select_set(True)
    bpy.context.view_layer.objects.active = game
    eye_slots = {i for i, m in enumerate(me.materials) if "_eye_" in m.name}
    attr = me.color_attributes.get("masks")
    g = np.zeros(len(me.vertices))
    if attr is not None:
        col = np.empty(len(me.vertices) * 4)
        attr.data.foreach_get("color", col)
        g = col.reshape(-1, 4)[:, 1]
    face_zone = np.array([p.material_index in eye_slots or all(g[v] > 0.5 for v in p.vertices) for p in me.polygons])
    bpy.ops.object.mode_set(mode='EDIT')
    for zone in (True, False):  # separate unwraps so face islands hold face faces only
        bm = bmesh.from_edit_mesh(me)
        bm.faces.ensure_lookup_table()
        for f in bm.faces:
            f.select_set(bool(face_zone[f.index]) == zone)
        bmesh.update_edit_mesh(me)
        bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.002, area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    uv = me.uv_layers["atlas"]  # edit-mode round trips invalidate layer references
    loops_face = np.repeat(face_zone, [p.loop_total for p in me.polygons])
    co = np.empty(len(me.loops) * 2)
    uv.data.foreach_get("uv", co)
    co = co.reshape(-1, 2)
    co[loops_face] *= 2.2
    uv.data.foreach_set("uv", co.ravel())
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.select_all(action='SELECT')
    bpy.ops.uv.pack_islands(rotate=True, margin=0.003)
    bpy.ops.object.mode_set(mode='OBJECT')


# ---------------------------------------------------------------- shader painting

class Nodes:
    """Shorthand for shader math. Values may be constants or node sockets."""

    def __init__(self, mat):
        self.tree = mat.node_tree
        self.tree.nodes.clear()
        self.coords = self.new("ShaderNodeTexCoord").outputs["Object"]
        self.x, self.y, self.z = self.sep(self.coords)
        geo = self.new("ShaderNodeNewGeometry")
        self.nx, self.ny, self.nz = self.sep(geo.outputs["Normal"])
        self.pointiness = geo.outputs["Pointiness"]
        ao = self.new("ShaderNodeAmbientOcclusion", samples=16)
        ao.inputs["Distance"].default_value = 0.12
        self.ao = ao.outputs["AO"]

    def new(self, kind, **props):
        node = self.tree.nodes.new(kind)
        for k, v in props.items():
            setattr(node, k, v)
        return node

    def feed(self, socket, value):
        if isinstance(value, bpy.types.NodeSocket):
            self.tree.links.new(value, socket)
        elif socket.type == "RGBA" and len(value) == 3:
            socket.default_value = (*value, 1.0)
        else:
            socket.default_value = value

    def sep(self, vec):
        node = self.new("ShaderNodeSeparateXYZ")
        self.feed(node.inputs[0], vec)
        return node.outputs["X"], node.outputs["Y"], node.outputs["Z"]

    def combine(self, x, y, z=0.0):
        node = self.new("ShaderNodeCombineXYZ")
        for i, v in enumerate((x, y, z)):
            self.feed(node.inputs[i], v)
        return node.outputs[0]

    def math(self, op, a, b=0.0):
        node = self.new("ShaderNodeMath", operation=op)
        self.feed(node.inputs[0], a)
        self.feed(node.inputs[1], b)
        return node.outputs[0]

    def vec(self, op, a, b):
        node = self.new("ShaderNodeVectorMath", operation=op)
        self.feed(node.inputs[0], a)
        self.feed(node.inputs[1], b)
        return node.outputs["Value"] if op == "DOT_PRODUCT" else node.outputs[0]

    def scale(self, a, factor):
        node = self.new("ShaderNodeVectorMath", operation="SCALE")
        self.feed(node.inputs[0], a)
        self.feed(node.inputs[3], factor)
        return node.outputs[0]

    def remap(self, value, a, b, c, d, smooth=False):
        node = self.new("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP" if smooth else "LINEAR", clamp=True)
        self.feed(node.inputs[0], value)
        for i, v in zip((1, 2, 3, 4), (a, b, c, d)):
            node.inputs[i].default_value = v
        return node.outputs[0]

    def lerp(self, a, b, t):
        return self.vec("ADD", a, self.scale(self.vec("SUBTRACT", b, a), t))

    def mul(self, *v):
        out = v[0]
        for x in v[1:]:
            out = self.math("MULTIPLY", out, x)
        return out

    def noise(self, scale, detail=3.0, distortion=0.0, vector=None):
        node = self.new("ShaderNodeTexNoise")
        self.feed(node.inputs["Vector"], vector if vector is not None else self.coords)
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

    def attr(self, name):
        node = self.new("ShaderNodeAttribute", attribute_name=name)
        return node.outputs["Color"]

    def uv(self, name):
        return self.new("ShaderNodeUVMap", uv_map=name).outputs["UV"]

    def image(self, file, vector, extension='REPEAT', color=False):
        node = self.new("ShaderNodeTexImage", extension=extension)
        img = bpy.data.images.load(TEX + "/" + file, check_existing=True)
        if not color:
            img.colorspace_settings.name = 'Non-Color'
        node.image = img
        self.feed(node.inputs["Vector"], vector)
        return node.outputs["Color"]

    def rgb(self, color):
        node = self.new("ShaderNodeSeparateColor")
        self.feed(node.inputs[0], color)
        return node.outputs[0], node.outputs[1], node.outputs[2]

    def around(self, origin, a, b):
        """Angle (rad) of the position around an axis, in the plane of unit vectors a, b."""
        rel = self.vec("SUBTRACT", self.coords, tuple(origin))
        return self.math("ARCTAN2", self.vec("DOT_PRODUCT", rel, tuple(a)), self.vec("DOT_PRODUCT", rel, tuple(b)))

    def strands(self, angle, k, lo=0.6, hi=1.12, wobble=1.2):
        phase = self.math("ADD", self.math("MULTIPLY", angle, k), self.math("MULTIPLY", self.noise(9.0, 2.0), wobble * 6))
        return self.remap(self.math("SINE", phase), -1.0, 1.0, lo, hi)

    def box(self, u, v, u0, u1, v0, v1, soft=0.01):
        """1 inside the uv rectangle, soft edges."""
        return self.mul(self.remap(u, u0 - soft, u0, 0, 1), self.remap(u, u1, u1 + soft, 1, 0),
                        self.remap(v, v0 - soft, v0, 0, 1), self.remap(v, v1, v1 + soft, 1, 0))


def ctx_of(key):
    m = head_marks(key)
    return {
        "key": key, "cx": m["cx"], "hc": m["hc"], "eye_z": m["eye_z"], "chin": m["chin"],
        "mouth_v": ((m["nose"][2] - 0.05) - m["eye_z"]) / 0.2 + 0.5,
        "belt_z": 1.0, "neck_z": bone_point(key, "Neck")[2],
    }


def recipe(name, n, c):
    """Returns (color, glow) for a piece."""
    P = PALETTE
    black = (0.0, 0.0, 0.0)
    if name == "skin":
        base = P["skin_" + c["key"]]
        color = n.lerp(base, srgb(170, 80, 60), n.remap(n.noise(6.0), 0.4, 0.75, 0.0, 0.35))
        masks = n.rgb(n.attr("masks"))
        d = n.uv("detail")
        du, dv, _ = n.sep(d)
        cyan_m, gold_m, dark = n.rgb(n.image("face_%s.png" % c["key"], d, 'CLIP'))
        face = masks[1]
        if c["key"] == "female":
            lips = n.mul(n.box(du, dv, 0.4, 0.6, c["mouth_v"] - 0.01, c["mouth_v"] + 0.045, 0.02), face)
            color = n.lerp(color, P["lips"], n.math("MULTIPLY", lips, 0.7))
        for cheek_u in (0.3, 0.7):  # warm cheeks
            reach = n.math("ADD", n.math("ABSOLUTE", n.math("SUBTRACT", du, cheek_u)), n.math("ABSOLUTE", n.math("SUBTRACT", dv, 0.33)))
            blush = n.math("MULTIPLY", n.remap(reach, 0.0, 0.12, 0.25, 0.0), face)
            color = n.lerp(color, srgb(200, 100, 85), blush)
        color = n.lerp(color, srgb(62, 58, 62), n.mul(dark, face))  # brows + lash lines, dark grey
        tat = n.math("MULTIPLY", n.rgb(n.image("tattoo.png", d))[0], masks[0])
        cyan = n.math("MINIMUM", n.math("ADD", n.mul(cyan_m, face), tat), 1.0)
        gold = n.mul(gold_m, face)
        color = n.lerp(n.lerp(color, P["cyan"], n.math("MULTIPLY", cyan, 0.9)), P["gold"], n.math("MULTIPLY", gold, 0.9))
        glow = n.vec("ADD", n.scale(P["cyan"], cyan), n.scale(P["gold"], gold))
        return color, glow
    if name.startswith("eye_"):
        e = n.image("%s_color.png" % name, n.uv("eye"), 'EXTEND', color=True)
        g = n.image("%s_glow.png" % name, n.uv("eye"), 'EXTEND', color=True)
        return e, g
    if name.startswith("hair"):
        hc = c["hc"]
        if name == "hair_cap" and c["key"] == "male":  # swept straight back
            ang, k = n.around(hc, (1, 0, 0), (0, 0, 1)), 70
        elif name == "hair_cap":  # gathered up into the bun
            ang, k = n.around(hc, (1, 0, 0), (0, 0.78, -0.62)), 70
        elif name == "hair_beard":  # hangs straight down
            ang, k = n.around((c["cx"], c["chin"][1] + 0.06, 0), (1, 0, 0), (0, -1, 0)), 45
        else:
            ang, k = None, 0
        if ang is not None:
            s = n.strands(ang, k)
        else:
            s = n.remap(n.wave(60.0, "Z", 6.0, 1.0), 0.0, 1.0, 0.68, 1.1)
        clumps = n.remap(n.noise(4.0, 2.0), 0.35, 0.65, 0.78, 1.1)
        return n.scale(n.scale(P["hair"], s), clumps), black
    if name in ("tunic", "skirt"):
        folds = n.remap(n.wave(4.5, "X", 5.0), 0.0, 1.0, 0.86, 1.08)
        grain = n.remap(n.noise(45.0), 0.3, 0.7, 0.93, 1.06)
        color = n.scale(n.scale(P["tunic"], folds), grain)
        if name == "tunic":  # centre front seam
            seam = n.mul(n.remap(n.math("ABSOLUTE", n.math("SUBTRACT", n.x, c["cx"])), 0.003, 0.006, 1, 0), n.remap(n.y, -0.05, 0.0, 1, 0), n.remap(n.z, c["belt_z"], c["belt_z"] + 0.02, 0, 1))
            return n.lerp(color, n.scale(color, 0.55), seam), black
        du, dv, _ = n.sep(n.uv("detail"))
        edge_u = n.math("MINIMUM", du, n.math("SUBTRACT", 1.0, du))
        slit = n.remap(edge_u, 0.034, 0.03, 0, 1)
        hem = n.remap(dv, 0.855, 0.86, 0, 1)
        r_slit = n.rgb(n.image("runes.png", n.combine(n.math("MULTIPLY", dv, 0.62), n.math("DIVIDE", edge_u, 0.032))))[0]
        r_hem = n.rgb(n.image("runes.png", n.combine(n.math("MULTIPLY", du, 4.0), n.math("DIVIDE", n.math("SUBTRACT", dv, 0.86), 0.14))))[0]
        band = n.math("MAXIMUM", slit, hem)
        rune = n.math("MAXIMUM", n.math("MULTIPLY", r_slit, slit), n.math("MULTIPLY", r_hem, n.math("MULTIPLY", hem, n.math("SUBTRACT", 1.0, slit))))
        color = n.lerp(color, P["band"], band)
        return n.lerp(color, P["thread"], rune), black
    if name == "tunic_trim":
        du, dv, _ = n.sep(n.uv("detail"))
        rune = n.rgb(n.image("runes.png", n.combine(n.math("MULTIPLY", du, 2.4), dv)))[0]
        return n.lerp(P["band"], P["thread"], rune), black
    if name == "sash":
        folds = n.remap(n.wave(22.0, "DIAGONAL", 3.0), 0.0, 1.0, 0.72, 1.1)
        return n.scale(P["sash"], folds), black
    if name == "pants":
        folds = n.remap(n.noise(3.5, 3.0, 1.5), 0.35, 0.65, 0.84, 1.08)  # soft cloth folds, no regular bands
        return n.scale(n.scale(P["pants"], folds), n.remap(n.noise(30.0), 0.3, 0.7, 0.95, 1.04)), black
    if name == "wrap":
        bands = n.remap(n.math("ABSOLUTE", n.math("SUBTRACT", n.wave(70.0, "DIAGONAL", 0.5), 0.5)), 0.0, 0.12, 0.62, 1.0)
        return n.scale(P["wrap"], bands), black
    if name == "boots":
        leather = n.remap(n.noise(14.0, 4.0), 0.3, 0.7, 0.8, 1.12)
        scuff = n.math("ADD", 1.0, n.mul(n.remap(n.ny, -0.4, -0.9, 0.0, 0.35), n.remap(n.z, 0.09, 0.03, 0, 1)))
        boot = n.scale(n.scale(P["boots"], leather), scuff)
        return n.lerp(P["sole"], boot, n.remap(n.z, 0.012, 0.022, 0.0, 1.0)), black
    if name in ("suit", "panel", "collar", "suit_boots"):
        base = P["suit_boots" if name == "suit_boots" else "suit"]
        sheen = n.remap(n.noise(5.0, 2.0), 0.3, 0.7, 0.9, 1.1)
        color = n.scale(base, sheen)
        if name == "suit":
            orn = n.math("MULTIPLY", n.rgb(n.image("ornament.png", n.uv("detail"), 'CLIP'))[0], n.rgb(n.attr("masks"))[2])
            return n.lerp(color, P["silver"], orn), black
        if name == "suit_boots":
            return color, black
        du, dv, _ = n.sep(n.uv("detail"))
        if name == "panel":
            edge = n.math("MAXIMUM", n.math("MAXIMUM", n.remap(du, 0.13, 0.09, 0, 1), n.remap(du, 0.87, 0.91, 0, 1)), n.remap(dv, 0.05, 0.03, 0, 1))
            inner = n.math("MAXIMUM", n.remap(n.math("ABSOLUTE", n.math("SUBTRACT", du, 0.2)), 0.012, 0.006, 0, 1), n.remap(n.math("ABSOLUTE", n.math("SUBTRACT", du, 0.8)), 0.012, 0.006, 0, 1))
            edge = n.math("MAXIMUM", edge, n.math("MULTIPLY", inner, n.remap(dv, 0.85, 0.8, 0, 1)))
        else:
            edge = n.math("MAXIMUM", n.math("MAXIMUM", n.remap(du, 0.06, 0.04, 0, 1), n.remap(du, 0.94, 0.96, 0, 1)), n.remap(dv, 0.85, 0.88, 0, 1))
        return n.lerp(color, P["silver"], edge), black
    if name == "silver":
        du, dv, _ = n.sep(n.uv("detail"))
        groove = n.remap(n.math("ABSOLUTE", n.math("SUBTRACT", dv, 0.5)), 0.05, 0.1, 0.55, 1.0)
        shine = n.remap(n.nz, -0.2, 1.0, 0.75, 1.25)
        return n.scale(n.scale(P["silver"], groove), shine), black
    if name == "leather":
        return n.scale(P["leather"], n.remap(n.wave(40.0, "Z", 1.0), 0.0, 1.0, 0.75, 1.1)), black
    return (0.5, 0.5, 0.5), black


def setup_painting(mat, c):
    n = Nodes(mat)
    name = mat.name.split("_", 2)[2]
    color, glow = recipe(name, n, c)
    shade = n.math("POWER", n.remap(n.ao, 0.0, 1.0, 0.3, 1.0), 1.3)
    top = n.remap(n.nz, -1.0, 1.0, 0.68, 1.18)
    edge_k = 0.55 if name == "silver" else (0.12 if name.startswith("hair") else 0.25)
    edges = n.math("ADD", 1.0, n.remap(n.pointiness, 0.5, 0.58, 0.0, edge_k))
    creases = n.remap(n.pointiness, 0.38, 0.5, 0.75, 1.0)
    painted = n.scale(n.scale(n.scale(n.scale(color, shade), top), edges), creases)
    for node_name, value in (("PaintEmit", painted), ("GlowEmit", glow)):
        emit = n.new("ShaderNodeEmission")
        emit.name = node_name
        n.feed(emit.inputs["Color"], value)
    n.new("ShaderNodeOutputMaterial").name = "Output"
    target = n.new("ShaderNodeTexImage")
    target.name = "BakeTarget"
    n.tree.nodes.active = target


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
                for dev in prefs.devices:
                    dev.use = dev.type == kind
                scene.cycles.device = "GPU"
                return kind
    except Exception as error:  # any trouble: the CPU bakes too, just slower
        print("GPU not used:", error)
    scene.cycles.device = "CPU"
    return "CPU"


def soften(image):
    """A light blur hides bake noise, like soft brush strokes."""
    w, h = image.size
    px = np.empty(w * h * 4, np.float32)
    image.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)
    rgb = px[..., :3]
    px[..., :3] = (rgb * 2 + np.roll(rgb, 1, 0) + np.roll(rgb, -1, 0) + np.roll(rgb, 1, 1) + np.roll(rgb, -1, 1)) / 6
    image.pixels.foreach_set(px.ravel())


def bake_one(game, image, emit_node):
    for mat in game.data.materials:
        tree = mat.node_tree
        tree.links.new(tree.nodes[emit_node].outputs[0], tree.nodes["Output"].inputs["Surface"])
        tree.nodes["BakeTarget"].image = image
        tree.nodes.active = tree.nodes["BakeTarget"]
    bpy.ops.object.select_all(action='DESELECT')
    game.select_set(True)
    bpy.context.view_layer.objects.active = game
    bpy.ops.object.bake(type='EMIT', margin=8, use_clear=True)
    soften(image)
    image.filepath_raw = TEX + "/%s.png" % image.name
    image.file_format = 'PNG'
    image.save()


def bake_maps(game, key, samples=16):
    scene = bpy.context.scene
    engine = scene.render.engine
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = samples
    device = use_gpu(scene)
    c = ctx_of(key)
    for mat in game.data.materials:
        setup_painting(mat, c)
    images = []
    for suffix, size in (("color", PAINT_SIZE), ("glow", GLOW_SIZE)):
        name = "arkanor_%s_%s" % (key, suffix)
        old = bpy.data.images.get(name)
        if old:
            bpy.data.images.remove(old)
        images.append(bpy.data.images.new(name, size, size))
    bake_one(game, images[0], "PaintEmit")
    bake_one(game, images[1], "GlowEmit")
    scene.render.engine = engine
    final = bpy.data.materials.get("arkanor_%s_painted" % key) or bpy.data.materials.new("arkanor_%s_painted" % key)
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
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Specular IOR Level"].default_value = 0.15
    me = game.data
    me.materials.clear()
    me.materials.append(final)
    me.polygons.foreach_set("material_index", np.zeros(len(me.polygons), dtype=np.int32))
    strip_bake_layers(game)
    return device


def strip_bake_layers(game):
    """The pattern UVs and masks only feed the bake: ship just the atlas (glTF TEXCOORD_0)."""
    me = game.data
    for name in [l.name for l in me.uv_layers if l.name != "atlas"]:
        me.uv_layers.remove(me.uv_layers[name])
    for name in [a.name for a in me.color_attributes]:
        me.color_attributes.remove(me.color_attributes[name])
    me.update()


def paint_pass(key, samples=16):
    import time
    t0 = time.time()
    game = game_mesh(key)
    atlas(game, key)
    device = bake_maps(game, key, samples)
    return {"tris": sum(len(p.vertices) - 2 for p in game.data.polygons), "device": device, "sec": round(time.time() - t0, 1)}
