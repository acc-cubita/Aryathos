"""Arkanor outfits.

Run after arkanor_hq.py and arkanor_head.py, in the same namespace:
    exec(open(r"D:/my game/tools/art/blender/arkanor_clothes.py").read())
    clothes_pass("male"); clothes_pass("female")

Tight clothing is the body itself: its faces get cloth materials and are pushed
out along their normals (no hidden skin, little clipping when animated).
Loose pieces (skirt, belt, collar, tabards) are separate meshes lofted around
the body; they take their skin weights from the body by data transfer.
Re-runnable: the body is reset to its post-head-pass shape first.
"""

STRIP = ("Left", "Right")


def bone_name(n):
    for s in STRIP:
        if n.startswith(s):
            return n[len(s):]
    return n


def body_bones(key):
    """Per vertex: dominant bone (side-less name), t along it (0 head .. 1 tail), world coords."""
    body, _, rig = objects(key)
    me = body.data
    groups = [g.name for g in body.vertex_groups]
    dom = np.zeros(len(me.vertices), dtype=np.int32)
    best = np.zeros(len(me.vertices))
    for v in me.vertices:
        for g in v.groups:
            if g.weight > best[v.index]:
                best[v.index], dom[v.index] = g.weight, g.group
    w = get_world(body)
    mw = rig.matrix_world
    t = np.zeros(len(w))
    names = np.array([bone_name(groups[d]) for d in dom])
    for gi, g in enumerate(groups):
        b = rig.data.bones.get(g)
        sel = dom == gi
        if b is None or not sel.any():
            continue
        h, tl = np.array(mw @ b.head_local), np.array(mw @ b.tail_local)
        d = tl - h
        t[sel] = (w[sel] - h) @ d / d.dot(d)
    return names, t, w


def bone_point(key, name, t=0.0):
    _, _, rig = objects(key)
    b = rig.data.bones[name]
    mw = rig.matrix_world
    h, tl = np.array(mw @ b.head_local), np.array(mw @ b.tail_local)
    return h + (tl - h) * t


def vertex_normals(obj):
    me = obj.data
    n = np.empty(len(me.vertices) * 3)
    me.vertex_normals.foreach_get("vector", n)
    return n.reshape(-1, 3)


def edges_of(obj):
    e = np.empty(len(obj.data.edges) * 2, dtype=np.int32)
    obj.data.edges.foreach_get("vertices", e)
    return e.reshape(-1, 2)


def laplacian(w, edges, mask, iterations=8, factor=0.5):
    """Smooth only the masked verts whose neighbours are all masked (keeps hems crisp)."""
    n = len(w)
    interior = mask.copy()
    bad = mask[edges[:, 0]] != mask[edges[:, 1]]
    interior[edges[bad].ravel()] = False
    deg = np.bincount(edges.ravel(), minlength=n).astype(float)
    for _ in range(iterations):
        acc = np.zeros_like(w)
        np.add.at(acc, edges[:, 0], w[edges[:, 1]])
        np.add.at(acc, edges[:, 1], w[edges[:, 0]])
        avg = acc / np.maximum(deg, 1)[:, None]
        w[interior] += factor * (avg[interior] - w[interior])
    return w


def checkpoint(key):
    """Body coords after the head pass; captured on first use, restored after."""
    body, _, _ = objects(key)
    name = "arkanor_%s_body_preclothes" % key
    me = bpy.data.meshes.get(name)
    if me is None:
        me = body.data.copy()
        me.name = name
        me.use_fake_user = True
        return
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    body.data.vertices.foreach_set("co", co)
    body.data.update()


def boot_last(w, feet, cx):
    """Project each foot onto its convex hull (fills between the toes), fading out up the ankle."""
    from mathutils.bvhtree import BVHTree
    w = w.copy()
    for side in (1, -1):
        idx = np.where(feet & (np.sign(w[:, 0] - cx) == side))[0]
        bm = bmesh.new()
        vs = [bm.verts.new(p) for p in w[idx]]
        res = bmesh.ops.convex_hull(bm, input=vs)
        bmesh.ops.delete(bm, geom=[g for g in res["geom_interior"] if isinstance(g, bmesh.types.BMVert)], context='VERTS')
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
        # soften the hull itself (toe-tip corners), so the projected boot is smooth without shrinking the toes
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=2, use_grid_fill=True)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        for _ in range(12):
            bmesh.ops.smooth_vert(bm, verts=bm.verts[:], factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
        tree = BVHTree.FromBMesh(bm)
        top = w[idx, 2].max()
        # radial projection from the foot's centre line: injective, so nothing folds between the toes
        f = w[idx]
        low = f[f[:, 2] < 0.5 * top]
        heel, toe = low[low[:, 1].argmax()], low[low[:, 1].argmin()]
        a0 = heel + 0.3 * (toe - heel)
        a1 = heel + 0.75 * (toe - heel)
        a0[2] = a1[2] = 0.4 * low[:, 2].max()
        ax = a1 - a0
        for i in idx:
            c = a0 + ax * np.clip((w[i] - a0) @ ax / ax.dot(ax), 0, 1)
            d = w[i] - c
            if np.linalg.norm(d) < 1e-6:
                continue
            hit = tree.ray_cast(Vector(c), Vector(unit(d)))[0]
            if hit is None:
                continue
            k = smoothstep(top, top - 0.06, w[i, 2])
            w[i] += k * (np.array(hit) - w[i])
        bm.free()
    return w


def assign(key, region, slots, inflate, smooth_mask, boots=None):
    """Region index per vertex -> face materials; push verts out; smooth cloth interiors."""
    body, _, _ = objects(key)
    me = body.data
    me.materials.clear()
    for m in slots:
        me.materials.append(m)
    e = edges_of(body)
    w = get_world(body) + vertex_normals(body) * inflate[:, None]
    w = laplacian(w, e, smooth_mask)
    if boots is not None:  # boot last: the inflated foot projected onto its own hull (no toes)
        w = boot_last(w, boots, body.location.x)
        w = laplacian(w, e, boots, iterations=2, factor=0.4)
    set_world(body, w)
    # face material = most common region among its verts
    fv = [p.vertices[:] for p in me.polygons]
    mat = [np.bincount(region[list(v)]).argmax() for v in fv]
    me.polygons.foreach_set("material_index", np.array(mat, dtype=np.int32))
    me.update()


def angle_around(w, center, front=(0, -1)):
    """Angle (deg, 0 = front, signed toward +X) of verts around a vertical axis."""
    d = w[:, :2] - np.asarray(center)[:2]
    return np.degrees(np.arctan2(d[:, 0], -d[:, 1]))


def support_ring(w, center, z, band, angles, offset, inner=0.0):
    """Radius of the body's outer hull at height z for each angle (deg) + offset."""
    s = w[abs(w[:, 2] - z) < band]
    d = s[:, :2] - np.asarray(center)[:2]
    a = np.radians(np.asarray(angles))
    dirs = np.column_stack((np.sin(a), -np.cos(a)))
    r = (d @ dirs.T).max(axis=0)
    r = np.maximum(r, inner)
    # smooth around the ring
    k = np.array([1, 2, 3, 2, 1], dtype=float)
    k /= k.sum()
    rp = np.r_[r[-2:], r, r[:2]] if abs(angles[-1] - angles[0]) >= 359 else np.r_[r[:1], r[:1], r, r[-1:], r[-1:]]
    r = np.convolve(rp, k, mode='valid')
    return r + offset


def loft(bm, rings, closed):
    """rings: list of (N,3) point arrays -> quad strip surface.

    Writes a "detail" UV: u across the rings (0..1), v from the first ring (0) to the last (1),
    used by the painter for hems, edges and embroidery."""
    uv = bm.loops.layers.uv.get("detail") or bm.loops.layers.uv.new("detail")
    vs = [[bm.verts.new(p) for p in ring] for ring in rings]
    n = len(rings[0])
    span = n if closed else n - 1
    for i, (a, b) in enumerate(zip(vs, vs[1:])):
        v0, v1 = i / (len(rings) - 1), (i + 1) / (len(rings) - 1)
        for k in range(span):
            k2 = (k + 1) % n
            f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
            for loop, c in zip(f.loops, ((k / span, v0), ((k + 1) / span, v0), ((k + 1) / span, v1), (k / span, v1))):
                loop[uv].uv = c


def ring_points(center, z, angles, radii):
    a = np.radians(np.asarray(angles))
    return np.column_stack((center[0] + np.sin(a) * radii, center[1] - np.cos(a) * radii, np.full(len(a), z)))


def bind(o, key, thickness=0.0):
    """Skin weights from the body (nearest surface), then deform with the rig."""
    body, _, rig = objects(key)
    o.parent = rig
    o.parent_type = 'OBJECT'
    o.matrix_parent_inverse = rig.matrix_world.inverted()
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    dt = o.modifiers.new("Weights", 'DATA_TRANSFER')
    dt.object = body
    dt.use_vert_data = True
    dt.data_types_verts = {'VGROUP_WEIGHTS'}
    dt.vert_mapping = 'POLYINTERP_NEAREST'
    bpy.ops.object.datalayout_transfer(modifier=dt.name)
    bpy.ops.object.modifier_apply(modifier=dt.name)
    if thickness:
        s = o.modifiers.new("Solidify", 'SOLIDIFY')
        s.thickness, s.offset = thickness, 1.0
    a = o.modifiers.new("Armature", 'ARMATURE')
    a.object = rig


def cloth_object(key, name, bm, mat, thickness=0.0):
    body, _, _ = objects(key)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.shade_smooth()
    me.materials.append(mat)
    old = bpy.data.objects.get(name)
    if old:
        bpy.data.objects.remove(old)
    o = bpy.data.objects.new(name, me)
    body.users_collection[0].objects.link(o)
    bind(o, key, thickness)
    return o


def CLOTH_MATS():
    return {
        "skin": material("arkanor_skin", (0.86, 0.63, 0.52), 0.55),
        "tunic": material("arkanor_tunic", (0.47, 0.41, 0.33), 0.85),
        "tunic_trim": material("arkanor_tunic_trim", (0.35, 0.3, 0.24), 0.85),
        "belt": material("arkanor_sash", (0.36, 0.32, 0.27), 0.85),
        "pants": material("arkanor_pants", (0.42, 0.42, 0.36), 0.9),
        "wrap": material("arkanor_wrap", (0.5, 0.48, 0.42), 0.9),
        "boots": material("arkanor_boots", (0.34, 0.26, 0.19), 0.6),
        "suit": material("arkanor_suit", (0.1, 0.17, 0.38), 0.5),
        "suit_boots": material("arkanor_suit_boots", (0.09, 0.15, 0.33), 0.45),
        "silver": material("arkanor_silver_trim", (0.78, 0.8, 0.86), 0.3, 0.9),
    }


# ---------------------------------------------------------------- trims (separate smooth bands)

def limb_ring(key, names, t, w, bone, side, t_of, n=48, band=0.03, phis=None):
    """Points + outward dirs around a limb at t_of(phi) (phi deg, 0 = front), from that limb's own verts."""
    cx = objects(key)[0].location.x
    pre = "Left" if side > 0 else "Right"
    h, tl = bone_point(key, pre + bone, 0.0), bone_point(key, pre + bone, 1.0)
    a = unit(tl - h)
    f = np.array((0.0, -1.0, 0.0))
    u = unit(f - a * f.dot(a))  # front, perpendicular to the bone
    v = np.cross(a, u)
    mine = (names == bone) & (np.sign(w[:, 0] - cx) == side)
    pts, dirs = [], []
    for phi in (np.linspace(0, 360, n, endpoint=False) if phis is None else phis):
        d = np.cos(np.radians(phi)) * u + np.sin(np.radians(phi)) * v * side
        tt = t_of(phi)
        sel = mine & (abs(t - tt) < band)
        c = h + (tl - h) * tt
        r = ((w[sel] - c) @ d).max() if sel.any() else 0.05
        pts.append(c + d * r)
        dirs.append(d)
    return np.array(pts), np.array(dirs), a


def ribbon(bm, pts, outs, along, width, lift, closed=True):
    """Flat band through pts, facing outs, `width` wide across the `along` direction."""
    n = len(pts)
    uv = bm.loops.layers.uv.get("detail") or bm.loops.layers.uv.new("detail")
    top = [bm.verts.new(p + o * lift + along_i * width / 2) for p, o, along_i in zip(pts, outs, along)]
    bot = [bm.verts.new(p + o * lift - along_i * width / 2) for p, o, along_i in zip(pts, outs, along)]
    span = n if closed else n - 1
    for k in range(span):
        k2 = (k + 1) % n
        f = bm.faces.new((top[k], top[k2], bot[k2], bot[k]))
        for loop, c in zip(f.loops, ((k / span, 1), ((k + 1) / span, 1), ((k + 1) / span, 0), (k / span, 0))):
            loop[uv].uv = c  # u along the band, v across it


def limb_band(bm, key, names, t, w, bone, t_of, width, lift):
    for side in (1, -1):
        pts, dirs, a = limb_ring(key, names, t, w, bone, side, t_of)
        ribbon(bm, pts, dirs, [a] * len(pts), width, lift)


def plate(bm, key, names, t, w, bone, t0, length, half_width, lift, rows=7, cols=7):
    """Pointed plate on the front of a limb: tip up at t0, widening down the bone."""
    for side in (1, -1):
        rings = []
        for i in range(rows):
            k = i / (rows - 1)
            hw = np.degrees((0.006 + half_width * k) / 0.06)  # half width (m) -> degrees on a ~6 cm limb
            pts, dirs, _ = limb_ring(key, names, t, w, bone, side, lambda q, k=k: t0 + length * k, phis=np.linspace(-hw, hw, cols))
            rings.append(pts + dirs * lift)
        loft(bm, rings, closed=False)


def girdle(bm, w, center, waist_z, dip, width, lift, n=72):
    """V belt around the waist: level at the back, dipping to a point at the front."""
    ang = np.linspace(-180, 180, n, endpoint=False)
    pts, outs = [], []
    for a in ang:
        z = waist_z - dip * max(0.0, 1 - abs(a) / 60.0)
        r = support_ring(w, center, z, 0.012, np.array([a - 2, a, a + 2]), 0.0)[1]
        d = np.array((np.sin(np.radians(a)), -np.cos(np.radians(a)), 0.0))
        pts.append(np.array((center[0], center[1], z)) + d * r)
        outs.append(d)
    pts = np.array(pts)
    # band width runs along the belt's own slope
    along = []
    for k in range(n):
        tan = pts[(k + 1) % n] - pts[k - 1]
        along.append(unit(np.cross(outs[k], tan)) * np.sign(np.cross(outs[k], tan)[2] or 1))
    ribbon(bm, pts, outs, along, width, lift)


# ---------------------------------------------------------------- male

def male_outfit():
    key = "male"
    M = CLOTH_MATS()
    names, t, w = body_bones(key)
    cx = objects(key)[0].location.x
    hip_z = bone_point(key, "LeftUpperLeg")[2]
    knee_z = bone_point(key, "LeftLowerLeg")[2]
    belt_z = 1.0
    hem_z = hip_z - 0.43 * (hip_z - knee_z)

    torso = np.isin(names, ("Hips", "Spine", "Chest", "UpperChest", "Shoulder"))
    sleeve = (names == "UpperArm") & (t < 0.5)
    neck = (names == "Neck") & (t < 0.15)
    upper = (torso | sleeve | neck) & (w[:, 2] >= belt_z)
    legs = np.isin(names, ("Hips", "Spine", "UpperLeg", "LowerLeg", "Foot", "Toes")) & (w[:, 2] < belt_z)
    shin = names == "LowerLeg"
    wrap = shin & (t >= 0.2) & (t < 0.34)
    boot = (shin & (t >= 0.34)) | np.isin(names, ("Foot", "Toes"))
    pants = legs & ~wrap & ~boot
    hem = sleeve & (t > 0.43)

    # 0 skin, 1 tunic, 2 trim, 3 pants, 4 wrap, 5 boots
    region = np.zeros(len(w), dtype=np.int32)
    region[upper] = 1
    region[pants] = 3
    region[wrap] = 4
    region[boot] = 5
    inflate = np.zeros(len(w))
    inflate[upper] = 0.011
    inflate[sleeve] = 0.013 + 0.006 * smoothstep(0.25, 0.5, t[sleeve])
    knee_k = np.where(names == "UpperLeg", smoothstep(0.3, 1.0, t), np.where(shin, 1.0, 0.0))
    inflate[pants] = 0.02 + 0.008 * knee_k[pants] + 0.007 * (shin[pants] * smoothstep(0.08, 0.2, t[pants]))  # blouses over the wrap
    inflate[wrap] = 0.017
    inflate[boot] = 0.013 + 0.005 * (shin[boot] * smoothstep(0.42, 0.34, t[boot]))  # cuff
    toes = np.isin(names, ("Toes",)) | ((names == "Foot") & (t > 0.6))
    inflate[toes] += 0.008
    feet = np.isin(names, ("Foot", "Toes"))
    assign(key, region, [M["skin"], M["tunic"], M["tunic_trim"], M["pants"], M["wrap"], M["boots"]], inflate, region > 0, boots=feet)
    flatten_soles(key, boot)

    names, t, wb = body_bones(key)
    bm = bmesh.new()
    limb_band(bm, key, names, t, wb, "UpperArm", lambda phi: 0.49, 0.024, 0.002)
    cloth_object(key, "arkanor_male_trims", bm, M["tunic_trim"], thickness=0.006)

    arms = np.isin(names, ("UpperArm", "LowerArm", "Hand"))
    w = get_world(objects(key)[0])[~arms]
    center = np.array((cx, w[(w[:, 2] > hem_z) & (w[:, 2] < belt_z)][:, 1].mean()))
    # tunic skirt: two panels split at the front, hanging over the hips and thighs
    bm = bmesh.new()
    gap = 7  # deg either side of the front slit
    angles = np.linspace(gap, 360 - gap, 72)
    zs = np.linspace(belt_z - 0.02, hem_z, 9)
    rings = []
    for i, z in enumerate(zs):
        k = i / (len(zs) - 1)
        r = support_ring(w, center, z, 0.02, angles, 0.005 + 0.022 * k)
        if rings:  # hang: never tuck back in below the hips
            r = np.maximum(r, prev)
        prev = r
        rings.append(ring_points(center, z, angles, r))
    loft(bm, rings, closed=False)
    cloth_object(key, "arkanor_male_skirt", bm, M["tunic"], thickness=0.006)
    # wide wrapped sash over the tunic
    bm = bmesh.new()
    angles = np.linspace(0, 360, 72, endpoint=False)
    rings = [ring_points(center, z, angles, support_ring(w, center, z, 0.02, np.r_[angles, 360], off)[:-1])
             for z, off in ((belt_z - 0.045, 0.01), (belt_z - 0.02, 0.015), (belt_z + 0.02, 0.015), (belt_z + 0.045, 0.006))]
    loft(bm, rings, closed=True)
    cloth_object(key, "arkanor_male_belt", bm, M["belt"], thickness=0.006)


def flatten_soles(key, boot):
    """Boots stand flat on the ground: nothing below z=0, a slab-like sole."""
    body, _, _ = objects(key)
    w = get_world(body)
    low = boot & (w[:, 2] < 0.012)
    w[low, 2] = np.where(w[low, 2] < 0.004, 0.0, w[low, 2])
    w[boot & (w[:, 2] < 0.0), 2] = 0.0
    set_world(body, w)


# ---------------------------------------------------------------- female

def female_outfit():
    key = "female"
    M = CLOTH_MATS()
    names, t, w = body_bones(key)
    body = objects(key)[0]
    cx = body.location.x
    waist_z = bone_point(key, "Spine")[2]
    knee_z = bone_point(key, "LeftLowerLeg")[2]

    torso = np.isin(names, ("Hips", "Spine", "Chest", "UpperChest", "Shoulder", "UpperLeg"))
    sleeve = (names == "UpperArm") & (t < 0.55)
    neck = (names == "Neck") & (t < 0.6)
    shin = names == "LowerLeg"
    # boot top: higher at the front (pointed), lower behind
    knee = bone_point(key, "LeftLowerLeg")
    side = np.sign(w[:, 0] - cx)
    knee_y = knee[1]
    front = smoothstep(0.0, -0.04, w[:, 1] - knee_y)
    t_top = 0.1 - 0.13 * front
    boot = (shin & (t >= t_top)) | np.isin(names, ("Foot", "Toes"))
    suit = (torso | sleeve | neck | shin) & ~boot
    # 0 skin, 1 suit, 2 boots (slot 3 silver is used by the trim meshes)
    region = np.zeros(len(w), dtype=np.int32)
    region[suit] = 1
    region[boot] = 2
    inflate = np.zeros(len(w))
    inflate[suit] = 0.003
    inflate[boot] = 0.008
    feet = np.isin(names, ("Foot", "Toes"))
    assign(key, region, [M["skin"], M["suit"], M["suit_boots"], M["silver"]], inflate, (region == 1) | (region == 2), boots=feet)
    flatten_soles(key, boot)

    names, t, wb = body_bones(key)
    arms = np.isin(names, ("UpperArm", "LowerArm", "Hand"))
    w = wb[~arms]
    hips = w[(w[:, 2] > knee_z) & (w[:, 2] < waist_z)]
    center = np.array((cx, hips[:, 1].mean()))
    # silver: V girdle, sleeve hems, boot top + ankle bands, knee plates
    front_t = lambda phi: 0.1 - 0.13 * smoothstep(60, 0, min(abs(phi), 360 - abs(phi)))
    bm = bmesh.new()
    girdle(bm, w, center, waist_z, 0.065, 0.024, 0.003)
    limb_band(bm, key, names, t, wb, "UpperArm", lambda phi: 0.52, 0.014, 0.003)
    limb_band(bm, key, names, t, wb, "LowerLeg", lambda phi: front_t(phi) + 0.012, 0.016, 0.003)
    limb_band(bm, key, names, t, wb, "LowerLeg", lambda phi: 0.87, 0.014, 0.003)
    plate(bm, key, names, t, wb, "LowerLeg", -0.02, 0.14, 0.03, 0.004)
    cloth_object(key, "arkanor_female_trims", bm, M["silver"], thickness=0.003)
    tip_z = knee_z + 0.07
    # front tabard: from the girdle's V down between the legs to a point
    tabard(key, "arkanor_female_tabard", w, center, 0.0, waist_z - 0.06, tip_z, 0.075, M["suit"], M["silver"])
    # two long flaps at the back of the hips
    for sx in (1, -1):
        tabard(key, "arkanor_female_flap.%s" % ("L" if sx > 0 else "R"), w, center, sx * 125, waist_z - 0.01, tip_z - 0.03, 0.06, M["suit"], M["silver"])
    collar(key, w)


def tabard(key, name, w, center, angle, top_z, tip_z, half_width, mat, edge_mat):
    """Hanging pointed panel centred at `angle` (deg around the body, 0 = front)."""
    bm = bmesh.new()
    zs = np.linspace(top_z, tip_z, 14)
    rings = []
    prev = None
    for i, z in enumerate(zs):
        k = i / (len(zs) - 1)
        hw = half_width * (1 - k ** 1.6) + 0.004
        # angular half-width from the panel width at this radius
        r0 = support_ring(w, center, max(z, tip_z), 0.02, np.array([angle - 5, angle, angle + 5]), 0.0)[1]
        span = np.degrees(hw / max(r0, 0.05))
        angles = np.linspace(angle - span, angle + span, 9)
        r = support_ring(w, center, z, 0.02, angles, 0.008 + 0.01 * k) if (abs(w[:, 2] - z) < 0.02).any() else prev
        if prev is not None:
            r = np.maximum(r, prev)
        prev = r
        rings.append(ring_points(center, z, angles, r))
    loft(bm, rings, closed=False)
    o = cloth_object(key, name, bm, mat, thickness=0.004)
    return o


def collar(key, w):
    """Tall standing collar, open in a V at the front, flaring at the top."""
    M = CLOTH_MATS()
    neck = bone_point(key, "Neck")
    z0 = neck[2] - 0.012
    nw = w[(abs(w[:, 2] - z0) < 0.03) & (np.hypot(w[:, 0] - neck[0], w[:, 1] - neck[1]) < 0.09)]
    center = np.array((neck[0], nw[:, 1].mean()))
    bm = bmesh.new()
    rings = []
    for i, (dz, off, gap) in enumerate(((0.0, 0.006, 12), (0.035, 0.01, 16), (0.07, 0.024, 26), (0.088, 0.038, 32))):
        angles = np.linspace(gap, 360 - gap, 48)
        r = support_ring(nw, center, z0, 0.03, angles, off)
        rings.append(ring_points(center, z0 + dz, angles, r))
    loft(bm, rings, closed=False)
    cloth_object(key, "arkanor_female_collar", bm, M["suit"], thickness=0.004)


def clothes_pass(key):
    checkpoint(key)
    (male_outfit if key == "male" else female_outfit)()
