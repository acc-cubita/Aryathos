"""Arkanor hands: finger bones found on the hand mesh, finger weights, grip marker.

Run after paint_pass() (works on the joined game mesh), before anim_pass():
    exec(open(r"D:/my game/tools/art/blender/arkanor_hands.py").read())
    hands_pass("male"); hands_pass("female")

Bones use Godot's humanoid names (LeftIndexProximal, LeftThumbMetacarpal, ...).
Each finger bone stores its curl and spread axes (armature space) so the
animation module can curl fingers toward the palm on either hand.
RightGrip -> RightGripTip mark where an axe handle runs through the closed fist.
"""
from collections import deque

FINGERS = ("Index", "Middle", "Ring", "Little")
FINGER_SEGS = ("Proximal", "Intermediate", "Distal")
THUMB_SEGS = ("Metacarpal", "Proximal", "Distal")


def hand_weights(game, group):
    gi = game.vertex_groups[group].index
    w = np.zeros(len(game.data.vertices))
    for v in game.data.vertices:
        for g in v.groups:
            if g.group == gi:
                w[v.index] = g.weight
    return w


def components(sel, adj):
    seen, comps = set(), []
    for v in sel:
        if v in seen:
            continue
        q, comp = deque([v]), []
        seen.add(v)
        while q:
            x = q.popleft()
            comp.append(x)
            for y in adj[x]:
                if y in sel and y not in seen:
                    seen.add(y)
                    q.append(y)
        comps.append(comp)
    return sorted(comps, key=len, reverse=True)


def find_hand(key, side, w, adj):
    """Joint positions (world) of one hand: chains for thumb + 4 fingers, palm normal, grip."""
    game = bpy.data.objects["arkanor_%s" % key]
    pre = "Left" if side > 0 else "Right"
    W, T = bone_point(key, pre + "Hand", 0.0), bone_point(key, pre + "Hand", 1.0)
    D = unit(T - W)
    hand = np.where(hand_weights(game, pre + "Hand") > 0.3)[0]
    s_all = (w - W) @ D
    s = s_all[hand]
    L = s.max()
    for frac in (0.55, 0.6, 0.5, 0.65):
        comps = components(set(hand[s > frac * L].tolist()), adj)
        if len(comps) >= 4 and len(comps[3]) > 15:
            comps = comps[:4]
            break
    else:
        raise RuntimeError("fingers not separated on %s %s hand" % (key, pre))
    in_finger = set(v for c in comps for v in c)
    # thumb tip: the point of the hand sticking out furthest from the hand's axis, below the fingers
    rest = np.array([v for v in hand if v not in in_finger and 0.1 * L < s_all[v] < 0.62 * L])
    perp = np.linalg.norm((w[rest] - W) - np.outer(s_all[rest], D), axis=1)
    thumb_tip = w[rest[perp.argmax()]]
    lat = unit((thumb_tip - W) - D * ((thumb_tip - W) @ D))  # toward the thumb
    # fingers ordered from the thumb side
    info = []
    for c in comps:
        c = np.array(c)
        cs = s_all[c]
        tip = w[c[cs > cs.max() - 0.01]].mean(axis=0)
        base = w[c[cs < cs.min() + 0.012]].mean(axis=0)
        info.append((base @ lat, c, tip, base))
    info.sort(key=lambda t: -t[0])
    N = unit(np.cross(D, lat))
    curl = np.mean([((tip - base) - D * ((tip - base) @ D)) @ N for _, _, tip, base in info])
    if abs(curl) > 0.003:
        N = N * np.sign(curl)  # fingers already bend a little toward the palm
    elif (thumb_tip - W) @ N < 0:
        N = -N
    chains = {}
    for name, (_, c, tip, base) in zip(FINGERS, info):
        f = unit(tip - base)
        mcp = base - f * 0.07 * L
        length = np.linalg.norm(tip - mcp)

        def centred(p, verts=c):
            near = verts[np.linalg.norm(w[verts] - p, axis=1) < 0.012]
            return w[near].mean(axis=0) if len(near) > 3 else p

        chains[name] = [mcp, centred(mcp + f * 0.44 * length), centred(mcp + f * 0.71 * length), tip]
    thumb_lat = (thumb_tip - W) @ lat
    tv = np.array([v for v in hand if v not in in_finger and np.linalg.norm(w[v] - thumb_tip) < 0.38 * L and (w[v] - W) @ lat > 0.3 * thumb_lat])
    cmc = W + D * 0.1 * L + lat * 0.3 * thumb_lat
    tdir = thumb_tip - cmc

    def tcentred(p):
        near = tv[np.linalg.norm(w[tv] - p, axis=1) < 0.014] if len(tv) else []
        return w[near].mean(axis=0) if len(near) > 3 else p

    chains["Thumb"] = [cmc, tcentred(cmc + tdir * 0.42), tcentred(cmc + tdir * 0.72), thumb_tip]
    knuckles = np.mean([chains[f][0] for f in FINGERS], axis=0)
    grip = knuckles + D * 0.04 * L + N * 0.11 * L  # inside the closed fist
    return {"D": D, "N": N, "lat": lat, "L": L, "chains": chains, "grip": grip,
            "regions": {**{f: c for f, (_, c, _, _) in zip(FINGERS, info)}, "Thumb": tv}}


def add_finger_bones(key, hands):
    _, _, rig = objects(key)
    inv = rig.matrix_world.inverted()
    bpy.context.view_layer.objects.active = rig
    rig.hide_set(False)
    rig.hide_viewport = False
    bpy.ops.object.mode_set(mode='EDIT')
    eb = rig.data.edit_bones
    for b in list(eb):
        if any(f in b.name for f in FINGERS + ("Thumb", "Grip")):
            eb.remove(b)
    for side, h in hands.items():
        pre = "Left" if side > 0 else "Right"
        for finger, pts in h["chains"].items():
            segs = THUMB_SEGS if finger == "Thumb" else FINGER_SEGS
            parent = eb[pre + "Hand"]
            for seg, a, b in zip(segs, pts, pts[1:]):
                bone = eb.new(pre + finger + seg)
                bone.head, bone.tail = inv @ Vector(a), inv @ Vector(b)
                bone.parent = parent
                bone.use_connect = parent.name != pre + "Hand"
                bone.use_deform = True
                parent = bone
        if side < 0:  # weapon grip marker in the right fist: handle runs toward the thumb
            g = eb.new("RightGrip")
            g.head = inv @ Vector(h["grip"])
            g.tail = inv @ Vector(h["grip"] + h["lat"] * 0.08)
            g.parent = eb["RightHand"]
            g.use_deform = True  # no weights; deform so the glTF export (deform bones only) keeps it
            t = eb.new("RightGripTip")
            t.head, t.tail = g.tail, inv @ Vector(h["grip"] + h["lat"] * 0.1)
            t.parent = g
            t.use_deform = True
    bpy.ops.object.mode_set(mode='OBJECT')
    # curl / spread axes per finger bone (armature space), read by the animation module
    for side, h in hands.items():
        pre = "Left" if side > 0 else "Right"
        for finger in h["chains"]:
            outward = {"Index": 1, "Middle": 0, "Ring": -1, "Little": -1, "Thumb": 1}[finger]
            for seg in (THUMB_SEGS if finger == "Thumb" else FINGER_SEGS):
                b = rig.data.bones[pre + finger + seg]
                d = unit(np.array(b.tail_local - b.head_local))
                n = h["N"] if finger != "Thumb" else unit(h["N"] - h["lat"] * 0.6)  # the thumb folds across the palm
                curl_axis = unit(np.cross(d, n))
                spread = unit(np.cross(n, d))  # rotating about n moves d this way
                s_sign = np.sign(spread @ h["lat"]) * outward if outward else 1.0
                b["curl_axis"] = list(curl_axis)
                b["spread_axis"] = list(np.asarray(n) * s_sign)


def finger_weights(key, hands, w):
    """Split each hand vertex's Hand weight over the finger chain it belongs to."""
    game = bpy.data.objects["arkanor_%s" % key]
    blend = 0.006
    for side, h in hands.items():
        pre = "Left" if side > 0 else "Right"
        hw = hand_weights(game, pre + "Hand")
        groups = {}
        for finger, pts in h["chains"].items():
            segs = THUMB_SEGS if finger == "Thumb" else FINGER_SEGS
            for seg in segs:
                name = pre + finger + seg
                groups[name] = game.vertex_groups.get(name) or game.vertex_groups.new(name=name)
        hand_group = game.vertex_groups[pre + "Hand"]
        # palm verts near the knuckles follow the nearest finger a little
        member = {}
        for finger, verts in h["regions"].items():
            for v in verts:
                member[v] = finger
        hand_idx = np.where(hw > 0.0)[0]
        D = h["D"]
        knuckle_s = min((h["chains"][f][0] - bone_point(key, pre + "Hand")) @ D for f in FINGERS)
        for v in hand_idx:
            if v in member:
                continue
            if (w[v] - bone_point(key, pre + "Hand")) @ D > knuckle_s - 0.012:
                dists = {f: np.linalg.norm(w[v] - h["chains"][f][0]) for f in FINGERS}
                f = min(dists, key=dists.get)
                if dists[f] < 0.03:
                    member[v] = f
        for v, finger in member.items():
            pts = h["chains"][finger]
            segs = THUMB_SEGS if finger == "Thumb" else FINGER_SEGS
            # arc parameter of the vertex along the chain
            lens = [np.linalg.norm(b - a) for a, b in zip(pts, pts[1:])]
            starts = np.r_[0, np.cumsum(lens)]
            best, t = 1e9, 0.0
            for i, (a, b) in enumerate(zip(pts, pts[1:])):
                seg = b - a
                k = np.clip((w[v] - a) @ seg / seg.dot(seg), -1.0 if i == 0 else 0.0, 1.0)
                d = np.linalg.norm(w[v] - (a + seg * k))
                if d < best:
                    best, t = d, starts[i] + k * lens[i]
            # piecewise weights with soft joints: Hand before the first joint
            joints = starts[:3]
            wts = []
            for i in range(3):
                lo = smoothstep(joints[i] - blend, joints[i] + blend, t)
                hi = 1.0 - smoothstep(joints[i + 1] - blend, joints[i + 1] + blend, t) if i < 2 else 1.0
                wts.append(float(lo * hi))
            total_hand = hw[v]
            finger_share = sum(wts)
            if finger_share <= 0:
                continue
            hand_group.add([int(v)], float(total_hand * (1 - min(finger_share, 1.0))), 'REPLACE')
            for seg, wt in zip(segs, wts):
                if wt > 0:
                    groups[pre + finger + seg].add([int(v)], float(total_hand * wt), 'REPLACE')


def left_grip(key):
    """LeftGrip -> LeftGripTip markers in the left fist, from the finger bones (re-runnable).

    Same placement as the right one: knuckles + a little down the fingers + toward
    the palm; the tip points toward the thumb (a two-handed grip has both thumbs
    toward the axe head)."""
    _, _, rig = objects(key)
    bones = rig.data.bones
    hand = bones["LeftHand"]
    D = unit(np.array(hand.tail_local - hand.head_local))
    L = np.linalg.norm(np.array(bones["LeftMiddleDistal"].tail_local - hand.head_local))
    knuckles = np.mean([np.array(bones["Left%sProximal" % f].head_local) for f in FINGERS], axis=0)
    b = bones["LeftIndexProximal"]
    N = unit(np.cross(np.array(b["curl_axis"]), unit(np.array(b.tail_local - b.head_local))))
    thumb = np.array(bones["LeftThumbDistal"].tail_local - hand.head_local)
    lat = unit(thumb - D * (thumb @ D))
    grip = knuckles + D * 0.04 * L + N * 0.11 * L
    bpy.context.view_layer.objects.active = rig
    rig.hide_set(False)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = rig.data.edit_bones
    for n in ("LeftGrip", "LeftGripTip"):
        if n in eb:
            eb.remove(eb[n])
    g = eb.new("LeftGrip")
    g.head, g.tail = Vector(grip), Vector(grip + lat * 0.08)
    g.parent = eb["LeftHand"]
    t = eb.new("LeftGripTip")
    t.head, t.tail = g.tail, Vector(grip + lat * 0.1)
    t.parent = g
    bpy.ops.object.mode_set(mode='OBJECT')
    for n in ("LeftGrip", "LeftGripTip"):
        rig.data.bones[n].use_deform = True  # kept by the glTF export (deform bones only)


def hands_pass(key):
    """Not re-runnable on its own: it splits the Hand weights, so run paint_pass() first."""
    game = bpy.data.objects["arkanor_%s" % key]
    me = game.data
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    m = np.array(game.matrix_world)
    w = co.reshape(-1, 3) @ m[:3, :3].T + m[:3, 3]
    e = np.empty(len(me.edges) * 2, dtype=np.int32)
    me.edges.foreach_get("vertices", e)
    adj = [[] for _ in range(len(w))]
    for a, b in e.reshape(-1, 2):
        adj[a].append(b)
        adj[b].append(a)
    hands = {side: find_hand(key, side, w, adj) for side in (1, -1)}
    add_finger_bones(key, hands)
    finger_weights(key, hands, w)
    left_grip(key)
    return {("L" if s > 0 else "R"): {f: [list(np.round(p, 3)) for p in pts[:1]] for f, pts in h["chains"].items()} for s, h in hands.items()}
