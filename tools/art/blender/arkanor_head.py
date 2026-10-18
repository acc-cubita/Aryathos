"""Arkanor heads: face shaping, glowing eyes, hair, braids, buns, brows, beard.

Run in the live Blender after arkanor_hq.py, in the same namespace:
    exec(open(r"D:/my game/tools/art/blender/arkanor_hq.py").read())
    exec(open(r"D:/my game/tools/art/blender/arkanor_head.py").read())
    head_pass("male"); head_pass("female")

Everything is placed from landmarks measured on the morphed body (head_marks),
so it follows any later proportion change. Strand detail is left to textures;
geometry carries the chunky hand-painted forms (WoW style).
"""
import bmesh
import numpy as np
from mathutils import Matrix, Vector

TEX = ROOT + "/art/characters/arkanor/tex"


# ---------------------------------------------------------------- helpers

def smoothstep(e0, e1, x):
    t = np.clip((np.asarray(x, dtype=float) - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def unit(v):
    v = np.asarray(v, dtype=float)
    return v / np.linalg.norm(v)


def get_world(obj):
    m = np.array(obj.matrix_world)
    return mesh_coords(obj) @ m[:3, :3].T + m[:3, 3]


def set_world(obj, w):
    m = np.array(obj.matrix_world.inverted())
    obj.data.vertices.foreach_set("co", (w @ m[:3, :3].T + m[:3, 3]).ravel())
    obj.data.update()


def bbox_center(obj):
    return np.array(sum((obj.matrix_world @ Vector(c) for c in obj.bound_box), Vector()) / 8)


def soft(obj, center, radii, A=None, t=(0, 0, 0), core=0.0):
    """Falloff edit: p += w * (A (p - c) + c + t - p), w = 1 inside core, 0 at the radii."""
    c = np.asarray(center, dtype=float)
    r = np.asarray(radii, dtype=float) * np.ones(3)
    A = np.eye(3) if A is None else np.asarray(A, dtype=float)
    w = get_world(obj)
    k = smoothstep(1.0, core, np.linalg.norm((w - c) / r, axis=1))[:, None]
    set_world(obj, w + k * ((w - c) @ A.T + c + np.asarray(t) - w))


def head_marks(key):
    body, eyes, rig = objects(key)
    w = get_world(body)
    cx = body.location.x
    hz = (rig.matrix_world @ rig.data.bones["Head"].head_local).z
    h = w[w[:, 2] > hz - 0.07]
    mid = h[abs(h[:, 0] - cx) < 0.012]
    nose = mid[mid[:, 1].argmin()]
    front = mid[mid[:, 1] < nose[1] + 0.05]
    chin = front[front[:, 2].argmin()]
    ear = h[(h[:, 0] - cx).argmax()]
    el, er = bbox_center(eyes[0]), bbox_center(eyes[1])
    eye_r = eyes[0].dimensions.x / 2
    chest = w[(abs(w[:, 0] - cx) < 0.04) & (w[:, 2] > 1.0) & (w[:, 2] < hz - 0.08)]
    return {
        "cx": cx, "head_z": hz, "eyeL": el, "eyeR": er, "eye_r": eye_r,
        "eye_z": el[2], "nose": nose, "chin": chin, "top": h[h[:, 2].argmax()],
        "back": h[h[:, 1].argmax()], "ear_y": ear[1], "ear_dx": ear[0] - cx,
        "hc": np.array((cx, ear[1], el[2])),  # head center: between the ears at eye height
        "chest": chest,
    }


def chest_front(m, z):
    """Most forward body y around height z on the midline (beard rests in front)."""
    c = m["chest"]
    band = c[abs(c[:, 2] - z) < 0.02]
    if len(band) == 0:
        band = c[abs(c[:, 2] - z) <= abs(c[:, 2] - z).min() + 0.01]
    return band[:, 1].min()


def material(name, color, rough=0.6, metal=0.0, emit=None, strength=0.0):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = strength
    m.diffuse_color = (*color, 1)
    return m


def image_material(name, color_png, glow_png=None, strength=2.5, rough=0.2):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    tex = nt.nodes.get("color") or nt.nodes.new("ShaderNodeTexImage")
    tex.name = "color"
    tex.image = bpy.data.images.load(TEX + "/" + color_png, check_existing=True)
    nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = rough
    if glow_png:
        g = nt.nodes.get("glow") or nt.nodes.new("ShaderNodeTexImage")
        g.name = "glow"
        g.location = (tex.location.x, tex.location.y - 300)
        g.image = bpy.data.images.load(TEX + "/" + glow_png, check_existing=True)
        nt.links.new(g.outputs["Color"], b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = strength
    return m


def MATS():
    return {
        "hair": material("arkanor_hair", (0.72, 0.74, 0.78), 0.55),
        "leather": material("arkanor_leather", (0.30, 0.17, 0.08), 0.7),
        "metal": material("arkanor_silver", (0.80, 0.82, 0.86), 0.3, 1.0),
    }


def new_object(key, name, bm, mat, smooth=True):
    """bmesh (world coords) -> object in the character collection, parented to the Head bone."""
    body, _, rig = objects(key)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if smooth:
        me.shade_smooth()
    me.materials.append(mat)
    old = bpy.data.objects.get(name)
    if old:
        bpy.data.objects.remove(old)
    o = bpy.data.objects.new(name, me)
    body.users_collection[0].objects.link(o)
    o.parent, o.parent_type, o.parent_bone = rig, 'BONE', "Head"
    bpy.context.view_layer.update()
    o.matrix_world = Matrix.Identity(4)  # geometry is already in world space
    return o


def frame(T, up):
    T = unit(T)
    B = np.cross(T, up)
    B = unit(B if np.linalg.norm(B) > 1e-6 else np.cross(T, (0, 0, 1)))
    return T, B, np.cross(B, T)


def ellipsoid(bm, center, axes, radii, seg=8, rings=5):
    """axes: 3 unit vectors (columns of the basis), radii along them."""
    basis = Matrix(np.column_stack([np.asarray(a) * r for a, r in zip(axes, radii)]).tolist()).to_4x4()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0,
                              matrix=Matrix.Translation(Vector(center)) @ basis)


def spline(points, step=0.002):
    """Catmull-Rom through the points, resampled by arc length -> (N,3), (N,) lengths."""
    p = [np.asarray(points[0])] + [np.asarray(q) for q in points] + [np.asarray(points[-1])]
    out = []
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        for t in np.linspace(0, 1, 24, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(p[-2])
    out = np.array(out)
    seg = np.r_[0, np.cumsum(np.linalg.norm(np.diff(out, axis=0), axis=1))]
    s = np.arange(0, seg[-1], step)
    res = np.column_stack([np.interp(s, seg, out[:, i]) for i in range(3)])
    return res, s


def along(path, s, at):
    """Point and tangent at arc length `at`."""
    i = int(np.clip(np.searchsorted(s, at), 1, len(s) - 1))
    return path[i], unit(path[i] - path[i - 1])


def braid(bm, points, width, up, lobe=None, taper=(1.0, 1.0), flat=0.75, tilt=38, core=True):
    """Three-strand braid as alternating chevron lobes around a core.

    up: vector or callable(p) -> the side the braid shows (away from the head)."""
    path, s = spline(points)
    L = s[-1]
    lobe = lobe or width * 1.15
    n = max(2, int(L / (lobe * 0.4)))
    ang = np.radians(tilt)
    for i in range(n + 1):
        at = min(L * i / n, L - 1e-4)
        p, T = along(path, s, at)
        u = up(p) if callable(up) else np.asarray(up, dtype=float)
        T, B, U = frame(T, u)
        w = width * (taper[0] + (taper[1] - taper[0]) * at / L)
        side = 1 if i % 2 else -1
        d = unit(T * np.cos(ang) - B * side * np.sin(ang))
        lat = unit(np.cross(U, d))
        ellipsoid(bm, p + B * side * w * 0.2 + U * w * 0.04, (d, lat, U), (lobe * 0.6 * w / width, w * 0.36, w * 0.36 * flat), seg=10, rings=6)
    if core:
        tube(bm, path, [width * 0.3 * (taper[0] + (taper[1] - taper[0]) * a / L) for a in s], up)


def tube(bm, path, radii, up, sides=8, every=4):
    rings = []
    idx = list(range(0, len(path), every))
    if idx[-1] != len(path) - 1:
        idx.append(len(path) - 1)
    for i in idx:
        p = path[i]
        T = unit(path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)])
        u = up(p) if callable(up) else np.asarray(up, dtype=float)
        T, B, U = frame(T, u)
        r = radii[i]
        rings.append([bm.verts.new(p + r * (B * np.cos(a) + U * np.sin(a))) for a in np.linspace(0, 2 * np.pi, sides, endpoint=False)])
    for a, b in zip(rings, rings[1:]):
        for k in range(sides):
            bm.faces.new((a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k]))
    for ring in (rings[0], rings[-1][::-1]):
        bm.faces.new(ring[::-1] if ring is rings[0] else ring)


def surface(obj, origin, direction, lift=0.0):
    """Ray from outside toward `origin` along -direction; hit on obj + lift outward."""
    d = Vector(unit(direction))
    start = Vector(origin) + d * 0.5
    mi = obj.matrix_world.inverted()
    ok, loc, nrm, _ = obj.ray_cast(mi @ start, (mi.to_3x3() @ -d).normalized())
    if not ok:
        raise RuntimeError("no surface hit on %s from %s" % (obj.name, tuple(direction)))
    return np.array(obj.matrix_world @ loc) + np.asarray(d) * lift


# ---------------------------------------------------------------- face

def lid_angles(key):
    """Current opening of each eye: elevation (deg) of the upper and lower lid margins."""
    body, _, _ = objects(key)
    m = head_marks(key)
    w = get_world(body)
    out = []
    for c in (m["eyeL"], m["eyeR"]):
        rel = w - c
        d = np.linalg.norm(rel, axis=1)
        sel = (d < m["eye_r"] * 1.25) & (rel[:, 1] < -0.5 * m["eye_r"]) & (abs(rel[:, 0]) < 0.25 * m["eye_r"])
        el = np.degrees(np.arctan2(rel[sel, 2], -rel[sel, 1]))
        out.append((float(el[el > 0].min()), float(el[el < 0].max())))
    return out


def lids(key, upper_target, lower_target):
    """Rotate the eyelids around the eyeball center until the margins sit at the target elevations."""
    body, _, _ = objects(key)
    m = head_marks(key)
    r = m["eye_r"]
    for c, (up_now, low_now) in zip((m["eyeL"], m["eyeR"]), lid_angles(key)):
        w = get_world(body)
        rel = w - c
        d = np.linalg.norm(rel, axis=1)
        k = smoothstep(1.75 * r, 1.12 * r, d) * smoothstep(0.35 * r, 0.0, rel[:, 1])
        upper = smoothstep(-0.15 * r, 0.15 * r, rel[:, 2])
        ang = np.radians(k * (upper * (up_now - upper_target) + (1 - upper) * (low_now - lower_target)))
        y, z = rel[:, 1], rel[:, 2]
        rel = np.column_stack((rel[:, 0], y * np.cos(ang) - z * np.sin(ang), y * np.sin(ang) + z * np.cos(ang)))
        set_world(body, rel + c)


FACES = {
    # heavy overhanging brow, frown, broad nose; lids narrowed to a stern squint
    "male": dict(lids=(2, -14), brow=(0, -0.007, -0.009), frown=(0, -0.003, -0.007), nose=(1.15, 1.05, 1.05)),
    # adult athletic face: lighter brow, longer chin, slimmer jaw, almond eyes
    "female": dict(lids=(8, -18), brow=(0, -0.002, -0.003), frown=(0, 0, -0.002), chin=(0, -0.003, -0.011), jaw=0.93,
                   nose=(0.84, 1.0, 1.0), mouth=(0.86, 0.95, 0.85)),
}


SAVED = ROOT + "/art/characters/arkanor/arkanor_body_pass.blend"  # checkpoint copy saved after body_pass()


def restore_body(key):
    """Reset the body to its saved post-body-pass shape so face edits never stack."""
    body, _, _ = objects(key)
    name = "arkanor_%s_body_preface" % key
    me = bpy.data.meshes.get(name)
    if me is None:
        with bpy.data.libraries.load(SAVED, link=False) as (src, dst):
            dst.meshes = [body.data.name]
        me = dst.meshes[0]
        me.name = name
        me.use_fake_user = True
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    body.data.vertices.foreach_set("co", co)
    body.data.update()


def face(key):
    restore_body(key)
    body, eyes, _ = objects(key)
    m = head_marks(key)
    f = FACES[key]
    r = m["eye_r"]
    lids(key, *f["lids"])
    for c in (m["eyeL"], m["eyeR"]):
        inward = np.sign(m["cx"] - c[0])
        soft(body, c + (0, -0.3 * r, 0.95 * r), (0.045, 0.04, 0.024), t=f["brow"], core=0.25)
        soft(body, c + (inward * 0.55 * r, -0.45 * r, 0.75 * r), (0.022, 0.03, 0.018), t=np.asarray(f["frown"]) * 0.8, core=0.2)
    soft(body, (m["cx"], m["eyeL"][1] - 0.03, m["eye_z"] + 0.7 * r), (0.025, 0.03, 0.02), t=f["frown"], core=0.2)
    if "nose" in f:
        n = m["nose"]
        soft(body, n + (0, 0.025, 0), (0.035, 0.045, 0.04), A=np.diag(f["nose"]), core=0.3)
    if "mouth" in f:
        n = m["nose"]
        soft(body, (m["cx"], n[1] + 0.03, n[2] - 0.05), (0.045, 0.035, 0.028), A=np.diag(f["mouth"]), core=0.3)
        for sx in (1, -1):
            soft(body, (m["cx"] + sx * 0.028, n[1] + 0.04, n[2] - 0.05), (0.016, 0.02, 0.014), t=(0, 0.002, -0.0035), core=0.2)
            soft(body, (m["cx"] + sx * 0.058, n[1] + 0.06, m["eye_z"] - 0.05), (0.04, 0.04, 0.035), A=np.diag((0.94, 0.97, 1.0)), core=0.3)
    if "chin" in f:
        soft(body, m["chin"] + (0, 0.01, 0.005), (0.05, 0.05, 0.045), t=f["chin"], core=0.3)
    if "jaw" in f:
        ch = m["chin"]
        soft(body, (m["cx"], ch[1] + 0.07, ch[2] + 0.035), (0.11, 0.09, 0.065), A=np.diag((f["jaw"], 1, 1)), core=0.35)


def eye_uv(eye):
    """Front projection so the painted iris sits on the gaze axis (-Y)."""
    me = eye.data
    w = get_world(eye)
    c = bbox_center(eye)
    r = eye.dimensions.x / 2
    vi = np.empty(len(me.loops), dtype=np.int32)
    me.loops.foreach_get("vertex_index", vi)
    rel = w[vi] - c
    uv = np.column_stack((0.5 + rel[:, 0] / (2.2 * r), 0.5 + rel[:, 2] / (2.2 * r)))
    me.uv_layers.active.data.foreach_set("uv", uv.ravel())


def eyes(key):
    _, (left, right), _ = objects(key)
    # concept: the character's right eye is blue, the left one gold
    for e, tex in ((left, "eye_gold"), (right, "eye_blue")):
        eye_uv(e)
        e.data.materials.clear()
        e.data.materials.append(image_material("arkanor_" + tex, tex + "_color.png", tex + "_glow.png"))
        e.data.shade_smooth()


# ---------------------------------------------------------------- hair

# hairline height above the eyes (m) by angle around the head: 0 = front, 180 = back
HAIRLINES = {
    "male": ((0, 0.085), (40, 0.076), (70, 0.052), (90, 0.036), (110, 0.0), (140, -0.045), (180, -0.085)),
    "female": ((0, 0.078), (40, 0.07), (70, 0.046), (90, 0.03), (110, -0.008), (140, -0.05), (180, -0.088)),
}
HAIR_VOLUME = {"male": (0.005, 0.008), "female": (0.016, 0.024)}  # base offset, extra on top
HAIR_BLEND = {"male": 0.012, "female": 0.03}  # how far past the hairline the volume builds up


def shell(key, name, inside, lift, mat, solid=0.004, sink=0.003, blend=0.012):
    """Layer lifted off the body along its normals over the region inside > 0.

    Faces a little outside the region are kept but sunk under the skin, so the
    visible edge is where the layer crosses the skin: a smooth curve instead of
    the mesh's stair-stepped face boundary."""
    body, _, _ = objects(key)
    w = get_world(body)
    src = bmesh.new()
    src.from_mesh(body.data)
    src.normal_update()
    bm = bmesh.new()
    vmap = {}
    for f in src.faces:
        if not all(inside[v.index] > -blend for v in f.verts):
            continue
        for v in f.verts:
            i = v.index
            if i not in vmap:
                off = smoothstep(-blend, blend, inside[i]) * (lift[i] + sink) - sink
                vmap[i] = bm.verts.new(w[i] + np.array(v.normal) * off)
        bm.faces.new([vmap[v.index] for v in f.verts])
    src.free()
    o = new_object(key, name, bm, mat)
    if solid:
        sm = o.modifiers.new("Solidify", 'SOLIDIFY')
        sm.thickness, sm.offset = solid, -1
    return o


def head_space(key):
    """Body verts relative to the head center + angle around it (0 = front, 180 = back) + ear mask."""
    body, _, _ = objects(key)
    m = head_marks(key)
    rel = get_world(body) - m["hc"]
    theta = np.degrees(np.arctan2(abs(rel[:, 0]), -rel[:, 1]))
    ear = (abs(rel[:, 0]) > m["ear_dx"] - 0.042) & (rel[:, 2] > -0.055) & (rel[:, 2] < 0.04) & (rel[:, 1] > -0.05) & (rel[:, 1] < 0.075)
    return m, rel, theta, ear


def scalp(key):
    """Hair cap over the scalp, thicker on top."""
    m, rel, theta, ear = head_space(key)
    th, zv = zip(*HAIRLINES[key])
    inside = rel[:, 2] - np.interp(theta, th, zv)
    inside = np.where(ear | (rel[:, 2] < -0.16), -1.0, inside)
    base, extra = HAIR_VOLUME[key]
    lift = base + extra * smoothstep(0.03, 0.13, rel[:, 2])
    return shell(key, "arkanor_%s_hair" % key, inside, lift, MATS()["hair"], blend=HAIR_BLEND[key])


# beard line below the eyes (m) by angle around the head; the cheeks stay bare above it
BEARDLINE = ((0, -0.058), (20, -0.068), (40, -0.06), (60, -0.045), (80, -0.026), (98, -0.008), (104, -0.008))


def beard_shell():
    """Beard grown on the face: cheeks, jaw, chin, upper lip; fuller lower down."""
    m, rel, theta, ear = head_space("male")
    th, zv = zip(*BEARDLINE)
    inside = np.interp(theta, th, zv) - rel[:, 2]
    off_face = ear | (theta > 104) | (rel[:, 2] < -0.16) | (abs(rel[:, 0]) > 0.115)  # keep it off the neck/shoulders
    inside = np.where(off_face, -1.0, np.minimum(inside, (104 - theta) * 0.002))
    lift = 0.011 + 0.01 * smoothstep(-0.05, -0.12, rel[:, 2])
    return shell("male", "arkanor_male_beard_face", inside, lift, MATS()["hair"], solid=0)


def on_head(key, hair, dirs, lift):
    """Points on the hair cap (or the skin just below the hairline) along directions from the head center."""
    body, _, _ = objects(key)
    hc = head_marks(key)["hc"]
    out = []
    for d in dirs:
        try:
            out.append(surface(hair, hc, d, lift))
        except RuntimeError:
            out.append(surface(body, hc, d, lift + 0.003))
    return out


def front_of(obj, x, z, lift, fallback_y):
    """Front surface of obj at (x, z) seen from -Y, else fallback_y."""
    try:
        p = surface(obj, (x, 0.3, z), (0, -1, 0), lift)
        return (x, p[1], z)
    except RuntimeError:
        return (x, fallback_y, z)


def male_hair():
    key = "male"
    m = head_marks(key)
    hair = scalp(key)
    bpy.context.view_layer.update()
    mats = MATS()
    hc = m["hc"]
    out = lambda p: unit(p - hc)
    # side braids: temple -> over the ear -> back of the head toward the bun
    bm = bmesh.new()
    for sx in (1, -1):
        pts = on_head(key, hair, [(0.92 * sx, -0.25, 0.62), (0.95 * sx, 0.15, 0.55), (0.75 * sx, 0.55, 0.6), (0.35 * sx, 0.8, 0.65)], 0.004)
        braid(bm, pts, 0.03, out, taper=(0.85, 1.0))
    new_object(key, "arkanor_male_braids", bm, mats["hair"])
    # top-knot: base on the crown, tilted back like the side view
    axis = unit((0, 0.55, 0.85))
    root = surface(hair, hc, axis, 0.0)
    bm = bmesh.new()
    T, B, U = frame(axis, (1, 0, 0))
    ellipsoid(bm, root + axis * 0.05, (B, U, axis), (0.05, 0.047, 0.044), seg=14, rings=9)
    path = [root + axis * 0.05 + 0.041 * (B * np.cos(a) + U * np.sin(a)) + axis * (0.012 + 0.022 * a / 8) for a in np.linspace(0, 8, 9)]
    braid(bm, path, 0.022, lambda p: unit(p - (root + axis * 0.05)), flat=0.6, tilt=30, core=False)
    tube(bm, [root - axis * 0.004, root + axis * 0.02], [0.022, 0.02], (1, 0, 0), sides=12, every=1)
    new_object(key, "arkanor_male_bun", bm, mats["hair"])
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.026, radius2=0.025, depth=0.016,
                          matrix=Matrix.Translation(Vector(root + axis * 0.012)) @ Matrix(np.column_stack((B, U, axis)).tolist()).to_4x4())
    new_object(key, "arkanor_male_bun_tie", bm, mats["leather"])
    brows(key, hair_mat=mats["hair"])
    beard()


def brows(key, hair_mat):
    """Bushy white brows angled down toward the nose (angry)."""
    body, _, _ = objects(key)
    m = head_marks(key)
    r = m["eye_r"]
    bm = bmesh.new()
    for c in (m["eyeL"], m["eyeR"]):
        out = np.sign(c[0] - m["cx"])
        pts = []
        for t, (dx, dz) in enumerate(((-0.7, 0.58), (-0.2, 0.72), (0.35, 0.84), (0.85, 0.9), (1.25, 0.86))):
            p = c + (out * dx * r, -0.9 * r, dz * r)
            pts.append(surface(body, p + (0, 0.05, 0), (0, -1, 0.15), 0.004))
        path, s = spline(pts)
        n = 9
        for row, (up, size) in enumerate(((0.0, 1.0), (0.0055, 0.75))):
            for i in range(n - row * 2):
                p, T = along(path, s, s[-1] * (i + 0.5 + row) / n)
                T, B, U = frame(T, (0, -1, 0.3))
                k = 1 - abs(i - 3.5) / 6
                tuft = unit(T + U * (0.35 + 0.25 * i / n))
                ellipsoid(bm, p + U * up - B * 0.002 * row, (tuft, B, U), (0.014 * size, 0.008 * k * size, 0.0065 * k * size), seg=8, rings=5)
    new_object(key, "arkanor_%s_brows" % key, bm, hair_mat)


def beard():
    """Moustache + full beard as blended metaballs, then a centre braid and two side braids."""
    key = "male"
    m = head_marks(key)
    cx, n, ch = m["cx"], m["nose"], m["chin"]
    ez = m["eye_z"]
    mouth_z = n[2] - 0.045
    body, _, _ = objects(key)
    beard_shell()
    elems = []  # (center, half extents, tilt deg about the front axis)
    for sx in (1, -1):
        lip = surface(body, (cx + sx * 0.024, 0.0, n[2] - 0.028), (0, -1, 0), 0.0)
        tail = surface(body, (cx + sx * 0.05, 0.0, mouth_z - 0.02), (sx * 0.4, -1, 0), 0.0)
        elems += [
            (lip + (0, -0.008, 0), (0.034, 0.016, 0.014), sx * 22),    # moustache over the upper lip
            (tail + (0, -0.012, -0.012), (0.022, 0.02, 0.04), sx * 8),  # drooping ends
        ]
    elems += [
        ((cx, ch[1] - 0.005, ch[2] - 0.015), (0.078, 0.045, 0.055), 0),                       # chin
        ((cx, chest_front(m, ch[2] - 0.07) - 0.045, ch[2] - 0.07), (0.098, 0.05, 0.065), 0),  # wide beard under the jaw
        ((cx, chest_front(m, ch[2] - 0.12) - 0.038, ch[2] - 0.12), (0.06, 0.035, 0.045), 0),  # gathers into the braid
    ]
    mb = bpy.data.metaballs.new("beardM")
    mb.resolution = mb.render_resolution = 0.006
    tmp = bpy.data.objects.new("beardM", mb)
    bpy.context.scene.collection.objects.link(tmp)
    for c, ext, tilt in elems:
        R = max(ext) / 0.57
        el = mb.elements.new(type='ELLIPSOID')
        el.co, el.radius = c, R
        el.size_x, el.size_y, el.size_z = (e / max(ext) for e in ext)
        el.rotation = Matrix.Rotation(math.radians(tilt), 4, 'Y').to_quaternion()
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(tmp)
    bpy.data.metaballs.remove(mb)

    # chunky downward clumps: ridges around the beard axis, stronger lower down
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    bm.normal_update()
    for v in bm.verts:
        p = np.array(v.co)
        a = np.arctan2(p[0] - cx, -(p[1] - (ch[1] + 0.06)))
        k = smoothstep(mouth_z, ch[2] - 0.05, p[2]) * smoothstep(0.0, -0.5, np.dot(np.array(v.normal), (0, 1, 0)))
        v.co += v.normal * (0.004 * k * np.sin(a * 14 + 1.5 * np.sin(p[2] * 60)))
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-5)
    o = new_object(key, "arkanor_male_beard", bm, MATS()["hair"])
    d = o.modifiers.new("Decimate", 'DECIMATE')
    d.ratio = 0.35

    # braids: centre one continues the beard's point, side ones lie on the beard's outer front
    bm = bmesh.new()
    centre = [front_of(o, cx, z, -0.012, chest_front(m, z) - 0.035) for z in (ch[2] - 0.08, ch[2] - 0.15)]
    centre += [(cx, chest_front(m, z) - 0.03, z) for z in (ch[2] - 0.22, ch[2] - 0.28)]
    braid(bm, centre, 0.062, (0, -1, 0), taper=(1.0, 0.6))
    sides = []
    for sx in (1, -1):
        z0 = mouth_z - 0.04
        side = [front_of(o, cx + sx * dx, z, 0.006, chest_front(m, z) - 0.05) for dx, z in ((0.06, z0), (0.074, z0 - 0.07), (0.08, z0 - 0.15))]
        braid(bm, side, 0.028, (0, -1, 0), taper=(1.0, 0.7))
        sides.append(side[-1])
    new_object(key, "arkanor_male_beard_braids", bm, MATS()["hair"])

    # silver beads at the braid ends + pointed cap on the centre braid
    bm = bmesh.new()
    for end, rad in [(centre[-1], 0.018)] + [(e, 0.012) for e in sides]:
        bmesh.ops.create_cone(bm, cap_ends=True, segments=14, radius1=rad, radius2=rad, depth=0.02, matrix=Matrix.Translation(Vector(end)))
    tip = np.array(centre[-1]) + (0, 0, -0.012)
    bmesh.ops.create_cone(bm, cap_ends=True, segments=14, radius1=0.0, radius2=0.012, depth=0.045, matrix=Matrix.Translation(Vector(tip + (0, 0, -0.022))))
    new_object(key, "arkanor_male_beard_beads", bm, MATS()["metal"])


def female_hair():
    key = "female"
    m = head_marks(key)
    hair = scalp(key)
    bpy.context.view_layer.update()
    mats = MATS()
    hc = m["hc"]
    out = lambda p: unit(p - hc)
    # big coiled braid bun at the upper back of the head
    axis = unit((0, 0.62, 0.78))
    root = surface(hair, hc, axis, 0.0)
    T, B, U = frame(axis, (1, 0, 0))
    bm = bmesh.new()
    # low dome filler; the coiled braid sits half proud of it
    ellipsoid(bm, root + axis * 0.012, (B, U, axis), (0.05, 0.048, 0.024), seg=14, rings=8)
    turns = np.linspace(0, 2.3 * 2 * np.pi, 46)
    coil = [root + axis * (0.012 + 0.038 * t / turns[-1]) + (0.058 - 0.048 * t / turns[-1]) * (B * np.cos(t) + U * np.sin(t)) for t in turns]
    centre = root + axis * 0.04
    braid(bm, coil, 0.036, lambda p: unit(p - (centre - axis * 0.03)), taper=(1.0, 0.75), flat=0.7)
    new_object(key, "arkanor_female_bun", bm, mats["hair"])
    # crown braids from the hairline back into the bun
    bm = bmesh.new()
    crown = [[(0, -0.7, 0.8), (0, -0.35, 0.95), (0, 0.15, 1.0), (0, 0.55, 0.85)]]
    for sx in (1, -1):
        crown.append([(0.8 * sx, -0.45, 0.75), (0.95 * sx, 0.05, 0.55), (0.65 * sx, 0.55, 0.6), (0.28 * sx, 0.78, 0.6)])
        crown.append([(0.42 * sx, -0.7, 0.8), (0.5 * sx, -0.25, 0.88), (0.35 * sx, 0.3, 0.9), (0.15 * sx, 0.62, 0.8)])
    for i, dirs in enumerate(crown):
        big = i == 0 or i % 2 == 1  # centre crown + the side rolls
        braid(bm, on_head(key, hair, dirs, 0.014 if big else 0.007), 0.044 if big else 0.034, out, taper=(0.75, 1.0))
    new_object(key, "arkanor_female_braids", bm, mats["hair"])
    # two loose strands framing the face, in front of the ears
    bm = bmesh.new()
    for sx in (1, -1):
        s0 = on_head(key, hair, [(0.8 * sx, -0.5, 0.5)], 0.0)[0]
        pts = [s0, s0 + (0.008 * sx, -0.008, -0.035), s0 + (0.012 * sx, -0.006, -0.07), s0 + (0.016 * sx, -0.012, -0.105), s0 + (0.026 * sx, -0.008, -0.125)]
        path, s = spline(pts)
        tube(bm, path, list(0.0065 * (1 - 0.65 * s / s[-1])), (0, -1, 0), sides=8, every=3)
    new_object(key, "arkanor_female_strands", bm, mats["hair"])


def head_pass(key):
    stale = bpy.data.meshes.get("arkanor_%s_body_preclothes" % key)  # clothes must re-capture the new head
    if stale:
        bpy.data.meshes.remove(stale)
    face(key)
    eyes(key)
    (male_hair if key == "male" else female_hair)()
