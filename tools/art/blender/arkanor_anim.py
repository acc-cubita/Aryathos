"""Arkanor animations, keyed procedurally on the game rigs, + glTF export for Godot.

Run after the other arkanor_*.py modules (same namespace):
    exec(open(r"D:/my game/tools/art/blender/arkanor_anim.py").read())
    anim_pass("male"); anim_pass("female"); export("male"); export("female")

Poses are written as rotations in the character's own frame (X = her/his left,
Y = back, Z = up; degrees, applied at the joint in rest orientation) so they
read like a choreographer's notes. Loops end on their first pose.
Animation names ending in _loop loop in Godot.

The axe is placed, not posed: a pose gives where the right fist goes ("fist"),
where the axe points ("haft") and where the blade faces ("edge"); the arms
reach there by IK, nudged until neither arm cuts into the body. Walk, run and
backpedal come from a gait model: feet planted on the ground by leg IK (no
sliding at the game's speeds), heel-to-toe roll, pelvis bob/sway/turn and the
torso turning against it.
"""
FPS = 30
GAME_ART = ROOT + "/game/art/characters/arkanor"

# Arms hang from the modelling A-pose down to a relaxed stance (deg about Y).
RELAX = {"male": 24, "female": 22}


def joint_quat(rig, bone, rx=0.0, ry=0.0, rz=0.0):
    rest = rig.data.bones[bone].matrix_local.to_3x3()
    # side swing (ry) first, then twist (rz), then the forward/back pitch (rx): an A-pose
    # arm is brought in to the body before it swings forward, so chops land in front
    r = (Matrix.Rotation(math.radians(rx), 3, 'X') @ Matrix.Rotation(math.radians(rz), 3, 'Z')
         @ Matrix.Rotation(math.radians(ry), 3, 'Y'))
    return (rest.inverted() @ r @ rest).to_quaternion()


def finger_quat(bone, curl, spread):
    """Finger joints bend about the axes stored by arkanor_hands (curl toward the palm)."""
    rest = bone.matrix_local.to_3x3()
    r = Matrix.Rotation(math.radians(spread), 3, Vector(bone["spread_axis"])) @ Matrix.Rotation(math.radians(curl), 3, Vector(bone["curl_axis"]))
    return (rest.inverted() @ r @ rest).to_quaternion()


# per joint curl (proximal, intermediate, distal) of the fingers, then of the thumb
GRIP = ((78, 95, 55), (28, 38, 32))     # closed around a handle
RELAXED = ((16, 26, 14), (6, 8, 8))
OPEN = ((2, 4, 0), (-4, 0, 0))          # spell gesture, fingers spread


def hand_pose(s, fingers, thumb, spread=0.0):
    pre = "Left" if s > 0 else "Right"
    out = {}
    for f in ("Index", "Middle", "Ring", "Little"):
        for seg, c in zip(("Proximal", "Intermediate", "Distal"), fingers):
            out[pre + f + seg] = (c, spread * {"Index": 1.0, "Middle": 0.0, "Ring": 0.8, "Little": 1.6}[f] if seg == "Proximal" else 0.0, 0.0)
    for seg, c in zip(("Metacarpal", "Proximal", "Distal"), thumb):
        out[pre + "Thumb" + seg] = (c, 0.0, 0.0)
    return out


def expand(pose):
    """{"UpperArm": (rx, ry, rz)} applies to both sides mirrored; "LeftX"/"RightX" add to one side."""
    out = {}

    def put(k, r):
        out[k] = tuple(a + b for a, b in zip(out.get(k, (0.0, 0.0, 0.0)), map(float, r)))

    for name, rot in pose.items():
        if name in SPECIAL:
            continue
        if name.startswith(("Left", "Right")) or name in ("Hips", "Spine", "Chest", "UpperChest", "Neck", "Head"):
            put(name, rot)
        else:
            rx, ry, rz = rot
            put("Left" + name, (rx, ry, rz))
            put("Right" + name, (rx, -ry, -rz))  # mirror across the X = 0 plane
    return out


# pose keys that are not bones:
#   "loc"   Hips offset (m, added up)
#   "fist"  where the right fist (RightGrip) goes, "haft" where the axe points (toward its head),
#   "edge"  where the blade edge faces, "pole" where the right elbow bends (all character frame);
#   "carry" True: fist/haft/edge ride along with the upper chest (held in front while moving)
#   "two"   weight of the left hand on the haft, "hold" where it grips (m along the haft from
#           the right fist, - = toward the pommel)
SPECIAL = ("loc", "fist", "haft", "edge", "pole", "carry", "two", "hold")


def add(*poses):
    out = {}
    for p in poses:
        for k, v in p.items():
            if k == "loc":
                out["loc"] = tuple(a + b for a, b in zip(out.get("loc", (0, 0, 0)), v))
            elif k in SPECIAL:
                out[k] = v  # last one wins
            else:
                out[k] = tuple(a + b for a, b in zip(out.get(k, (0, 0, 0)), v))
    return out


def side(name, s, rx=0.0, ry=0.0, rz=0.0):
    """One side only, with the mirroring done for the right side (s = +1 left, -1 right)."""
    return {("Left" if s > 0 else "Right") + name: (rx, ry * s, rz * s)}


def set_pose(rig, pose):
    """FK rotations + hips offset of one pose, then the axe placement if it has one."""
    rots = expand(pose)
    hips_rest = rig.data.bones["Hips"].matrix_local.to_3x3()
    for bone in rig.data.bones:
        pb = rig.pose.bones[bone.name]
        pb.scale, pb.location = (1, 1, 1), (0, 0, 0)
        r = rots.get(bone.name, (0, 0, 0))
        pb.rotation_quaternion = finger_quat(bone, r[0], r[1]) if "curl_axis" in bone else joint_quat(rig, bone.name, *r)
    rig.pose.bones["Hips"].location = hips_rest.inverted() @ Vector(pose.get("loc", (0, 0, 0)))
    bpy.context.view_layer.update()
    if "fist" in pose:
        place_fist(rig, pose)
        if pose.get("two", 0.0) > 0:  # key the left hand on the haft too, so letting go eases from there
            left_on_haft(rig, pose.get("hold", LEFT_HOLD))


def key_pose(rig, f, prev):
    """Key every bone at frame f, keeping each quaternion on the hemisphere of the last key."""
    for pb in rig.pose.bones:
        q = pb.rotation_quaternion.copy()
        if pb.name in prev and q.dot(prev[pb.name]) < 0:
            q.negate()  # or the curve flips the long way round between keys
            pb.rotation_quaternion = q
        prev[pb.name] = q
        pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
    rig.pose.bones["Hips"].keyframe_insert("location", frame=f, group="Hips")


def key_action(key, name, keys, loop, feet=None):
    """keys: [(seconds, pose)]; feet: {frame: {"Left"/"Right": (ankle, pitch, toe pitch)}} plants the legs by IK."""
    _, _, rig = objects(key)
    act = bpy.data.actions.get("%s_%s" % (key, name))
    if act:
        bpy.data.actions.remove(act)
    rig.animation_data_create()
    act = bpy.data.actions.new("%s_%s" % (key, name))
    act.use_fake_user = True
    rig.animation_data.action = act
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    prev, axe = {}, {}
    holds_axe = any("fist" in p for _, p in keys)
    for t, pose in keys:
        f = round(t * FPS) + 1
        set_pose(rig, pose)
        if feet and f in feet:
            plant_feet(rig, feet[f])
        if holds_axe:
            axe[f] = axe_state(rig, pose)
        key_pose(rig, f, prev)
    end = round(keys[-1][0] * FPS) + 1
    act.frame_range = (1, end)
    act.use_frame_range = True
    if loop:
        act.use_cyclic = True
    poles = right_hand(rig, keys, axe, end) if holds_axe else None
    if any(p.get("two", 0.0) > 0 for _, p in keys):
        two_hands(rig, keys, end, poles)
    return act


# ---------------------------------------------------------------- reaching

def set_matrix(pb, m):
    """Pose a bone by its armature-space matrix, rotation only: the setter also writes the
    rounding errors into scale and location, which pile up pose after pose."""
    pb.matrix = m
    pb.scale = (1, 1, 1)
    if pb.name != "Hips":
        pb.location = (0, 0, 0)
    bpy.context.view_layer.update()


def rotate_about(pb, head, r):
    set_matrix(pb, Matrix.Translation(head) @ r.to_matrix().to_4x4() @ Matrix.Translation(-head) @ pb.matrix)


def aim_bone(pb, direction):
    y = Vector(pb.matrix.col[1][:3]).normalized()
    rotate_about(pb, pb.head.copy(), y.rotation_difference(direction.normalized()))


def two_bone(P, upper, lower, end, target, pole):
    """Aim upper + lower so the end bone's head reaches target (as near as the limb
    allows), the middle joint bending toward pole. Returns how far out of reach it was."""
    S = P[upper].head.copy()
    l1 = (P[lower].head - S).length
    l2 = (P[end].head - P[lower].head).length
    u = target - S
    excess = u.length - (l1 + l2)
    d = min(max(u.length, abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
    u.normalize()
    v = pole - u * pole.dot(u)
    v = v.normalized() if v.length > 1e-6 else Vector((0, 0, -1))
    a = math.acos(max(-1.0, min(1.0, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d))))
    mid = S + (u * math.cos(a) + v * math.sin(a)) * l1
    aim_bone(P[upper], mid - S)
    aim_bone(P[lower], S + u * d - mid)
    return excess


def axe_rotation(rig, haft, edge):
    """Rotation (armature space) from the rest right hand to one whose axe points along
    haft with the blade edge (down the fingers, see CharacterModel._grip) toward edge."""
    B = rig.data.bones
    h0 = (B["RightGripTip"].head_local - B["RightGrip"].head_local).normalized()
    e0 = B["RightMiddleProximal"].head_local - B["RightHand"].head_local
    e0 = (e0 - h0 * e0.dot(h0)).normalized()
    h1 = Vector(haft).normalized()
    e1 = Vector(edge) - h1 * Vector(edge).dot(h1)
    if e1.length < 1e-3:
        e1 = h1.orthogonal()
    e1.normalize()
    f0 = Matrix((h0, e0, h0.cross(e0))).transposed()
    f1 = Matrix((h1, e1, h1.cross(e1))).transposed()
    return f1 @ f0.transposed()


RIGHT_POLE = (-1.0, 0.3, -0.7)  # right elbow out, back and down
LEFT_POLE = Vector((1.0, -0.6, -0.7))  # left elbow out, forward and down: the forearm stays in front of the body
# where else the left elbow may go when the arm reaches across the chest (out front, raised, wide)
LEFT_POLES = [LEFT_POLE, Vector((0.7, -1.0, 0.0)), Vector((0.5, -0.8, 0.6)), Vector((1.0, 0.0, -0.3))]
FIST_FIX = {}  # (character, fist, haft) -> offset found by place_fist's search


def hold_axe(rig, fist, haft, edge, pole):
    """Right fist (RightGrip) at fist, the axe along haft. Returns how far out of reach."""
    P, B = rig.pose.bones, rig.data.bones
    q = axe_rotation(rig, haft, edge)
    offset = q @ (B["RightGrip"].head_local - B["RightHand"].head_local)
    excess = two_bone(P, "RightUpperArm", "RightLowerArm", "RightHand", fist - offset, Vector(pole))
    hand = P["RightHand"]
    set_matrix(hand, Matrix.Translation(hand.head) @ (q @ B["RightHand"].matrix_local.to_3x3()).to_4x4())
    return excess


def left_on_haft(rig, hold, pole=LEFT_POLE):
    """Left hand on the haft, hold m from the right fist, thumb toward the axe head."""
    P = rig.pose.bones
    haft_o = P["RightGrip"].head.copy()
    haft_d = (P["RightGripTip"].head - haft_o).normalized()
    target = haft_o + haft_d * hold
    grip = P["LeftGrip"].head.copy()
    q = (P["LeftGripTip"].head - grip).normalized().rotation_difference(haft_d)
    hand_rot = q.to_matrix() @ P["LeftHand"].matrix.to_3x3()
    excess = two_bone(P, "LeftUpperArm", "LeftLowerArm", "LeftHand", target - q @ (grip - P["LeftHand"].head), pole)
    set_matrix(P["LeftHand"], Matrix.Translation(P["LeftHand"].head) @ hand_rot.to_4x4())
    return excess


def place_fist(rig, pose):
    """Put the axe where the pose says. The first time a placement is seen, nearby fist
    spots are tried (with the left hand on the haft) and the closest one where both arms
    stay clear of the body is kept; repeats of that pose reuse it."""
    P, B = rig.pose.bones, rig.data.bones
    fist, haft = Vector(pose["fist"]), Vector(pose["haft"])
    edge = Vector(pose.get("edge", (0, -1, 0)))
    pole = pose.get("pole", RIGHT_POLE)
    if pose.get("carry"):  # ride along with the chest's turn and lean
        c = P["UpperChest"].matrix @ B["UpperChest"].matrix_local.inverted()
        fist, haft, edge = c @ fist, c.to_3x3() @ haft, c.to_3x3() @ edge
    # IK aims from the current orientation, so every try starts from the FK arms
    fk = {b: P[b].rotation_quaternion.copy() for b in ("LeftUpperArm", "LeftLowerArm", "LeftHand",
                                                        "RightUpperArm", "RightLowerArm", "RightHand")}

    def reset():
        for b, q in fk.items():
            P[b].rotation_quaternion = q
        bpy.context.view_layer.update()

    key = (rig.name, tuple(pose["fist"]), tuple(pose["haft"]))
    if key not in FIST_FIX:
        vols = body_volumes(rig)
        best = None
        for dx in (-0.08, -0.04, 0.0, 0.04, 0.08):
            for dy in (-0.15, -0.1, -0.05, 0.0, 0.05):
                for dz in (-0.1, -0.05, 0.0, 0.05, 0.1):
                    off = Vector((dx, dy, dz))
                    miss = max(0.0, hold_axe(rig, fist + off, haft, edge, pole))
                    if pose.get("two", 0.0) > 0:
                        miss += max(0.0, left_on_haft(rig, pose.get("hold", LEFT_HOLD)))
                    score = min(clearance(rig, vols), 0.03) - 0.25 * off.length - 3.0 * miss
                    if best is None or score > best[0]:
                        best = (score, off)
                    reset()
        FIST_FIX[key] = best[1]
    reset()
    hold_axe(rig, fist + FIST_FIX[key], haft, edge, pole)


LEFT_HOLD = -0.24  # left hand below the right one, toward the pommel, like the concept


def two_hands(rig, keys, end, poles=None):
    """Left hand on the haft: two-bone IK of the left arm every frame, blended by "two"
    (poles: the left elbow direction per frame chosen by right_hand)."""
    scene = bpy.context.scene
    P = rig.pose.bones
    times = [t for t, _ in keys]
    weights = [p.get("two", 0.0) for _, p in keys]
    holds = [p.get("hold", LEFT_HOLD) for _, p in keys]
    arm = ["LeftUpperArm", "LeftLowerArm", "LeftHand"]
    fingers = {b: (finger_quat(rig.data.bones[b], *hand_pose(1, *RELAXED)[b][:2]), finger_quat(rig.data.bones[b], *hand_pose(1, *GRIP)[b][:2]))
               for b in hand_pose(1, *GRIP)}
    prev = {}
    for f in range(1, end + 1):
        w = float(np.interp((f - 1) / FPS, times, weights))
        if w <= 0.001:
            continue
        scene.frame_set(f)
        fk = {b: P[b].rotation_quaternion.copy() for b in arm}
        excess = left_on_haft(rig, float(np.interp((f - 1) / FPS, times, holds)), (poles or {}).get(f, LEFT_POLE))
        w *= float(smoothstep(0.1, -0.02, excess))  # out of reach: let go gently
        for b in arm:
            q = fk[b].slerp(P[b].rotation_quaternion.copy(), w)
            if b in prev and q.dot(prev[b]) < 0:
                q.negate()  # stay on the same hemisphere as the last key, or the curves flip
            prev[b] = q.copy()
            P[b].rotation_quaternion = q
            P[b].keyframe_insert("rotation_quaternion", frame=f, group=b)
        for b, (relaxed, closed) in fingers.items():
            P[b].rotation_quaternion = relaxed.slerp(closed, w)
            P[b].keyframe_insert("rotation_quaternion", frame=f, group=b)


def axe_state(rig, pose):
    """Where the axe is in the keyed pose: fist, haft and edge directions, elbow pole, IK weight."""
    P = rig.pose.bones
    fist = P["RightGrip"].head.copy()
    haft = (P["RightGripTip"].head - fist).normalized()
    edge = P["RightMiddleProximal"].head - P["RightHand"].head
    return fist, haft, (edge - haft * edge.dot(haft)).normalized(), Vector(pose.get("pole", RIGHT_POLE)), 1.0 if "fist" in pose else 0.0


def right_hand(rig, keys, axe, end):
    """Right arm by IK every frame: the fist travels on an eased path between the keyed
    placements (rotating the arm joints between two placements can swing it through the
    body), pushed out in front of the chest wherever an arm would still touch the body."""
    scene = bpy.context.scene
    P, B = rig.pose.bones, rig.data.bones
    vols = body_volumes(rig)
    arm = ["RightUpperArm", "RightLowerArm", "RightHand"]
    left = ["LeftUpperArm", "LeftLowerArm", "LeftHand"]
    frames = sorted(axe)
    times = [t for t, _ in keys]
    twos = [p.get("two", 0.0) for _, p in keys]
    holds = [p.get("hold", LEFT_HOLD) for _, p in keys]

    def target(f):
        i = max(0, min(len(frames) - 2, np.searchsorted(frames, f, side="right") - 1))
        f0, f1 = frames[i], frames[i + 1]
        t = float(smoothstep(0.0, 1.0, (f - f0) / (f1 - f0)))
        a, b = axe[f0], axe[f1]
        return (a[0].lerp(b[0], t), a[1].lerp(b[1], t).normalized(), a[2].lerp(b[2], t), a[3].lerp(b[3], t), a[4] + (b[4] - a[4]) * t)

    def pose_at(f, push):
        fist, haft, edge, pole, w = target(f)
        c = P["UpperChest"].matrix.to_3x3() @ B["UpperChest"].matrix_local.to_3x3().inverted()
        hold_axe(rig, fist + c @ Vector((0, -push, 0)), haft, edge, pole)
        return w

    pushes = np.zeros(end + 1)
    choice = {}
    for f in range(1, end + 1):
        scene.frame_set(f)
        if target(f)[4] <= 0.001:
            continue
        fk = {b: P[b].rotation_quaternion.copy() for b in arm + left}
        two = float(np.interp((f - 1) / FPS, times, twos))
        best = (-1.0, 0.0, LEFT_POLE)
        for k in range(11):
            for pole in (LEFT_POLES if two > 0 else LEFT_POLES[:1]):
                pose_at(f, 0.025 * k)
                if two > 0:
                    left_on_haft(rig, float(np.interp((f - 1) / FPS, times, holds)), pole)
                c = clearance(rig, vols)
                if c > best[0]:
                    best = (c, 0.025 * k, pole)
                for b, q in fk.items():
                    P[b].rotation_quaternion = q
                bpy.context.view_layer.update()
                if c >= 0.01:
                    break
            if best[0] >= 0.01:
                break
        pushes[f], choice[f] = best[1], best[2]
    # smooth the pushes so the fist eases out and back in
    wide = np.array([pushes[max(1, f - 2):f + 3].max() for f in range(end + 1)])
    pushes = np.array([wide[max(1, f - 3):f + 4].mean() for f in range(end + 1)])
    prev = {}
    for f in range(1, end + 1):
        scene.frame_set(f)
        fk = {b: P[b].rotation_quaternion.copy() for b in arm}
        w = pose_at(f, float(pushes[f]))
        for b in arm:
            q = fk[b].slerp(P[b].rotation_quaternion.copy(), w)
            if b in prev and q.dot(prev[b]) < 0:
                q.negate()
            prev[b] = q.copy()
            P[b].rotation_quaternion = q
            P[b].keyframe_insert("rotation_quaternion", frame=f, group=b)
    # the left elbow direction, blended over neighbouring frames so it never snaps
    poles = {}
    for f in choice:
        near = [choice[g] for g in range(f - 3, f + 4) if g in choice]
        poles[f] = sum(near, Vector()) / len(near)
    return poles


# ---------------------------------------------------------------- body clearance

_VOLUMES = {}


def body_volumes(rig):
    """Torso slabs (hips to upper chest) and a head + beard ellipsoid, each measured on
    the rest mesh in its bone's frame from the vertices that bone mostly moves."""
    if rig.name in _VOLUMES:
        return _VOLUMES[rig.name]
    mesh = bpy.data.objects[rig.name.replace("_rig", "")]
    owner = {"Hips": "Hips", "Spine": "Spine", "Chest": "Chest", "UpperChest": "UpperChest", "Neck": "Head", "Head": "Head"}
    index = {mesh.vertex_groups[n].index: b for n, b in owner.items() if n in mesh.vertex_groups}
    to_rig = rig.matrix_world.inverted() @ mesh.matrix_world
    pts = {}
    for v in mesh.data.vertices:
        if len(v.groups):
            g = max(v.groups, key=lambda g: g.weight)
            if g.group in index:
                pts.setdefault(index[g.group], []).append(to_rig @ v.co)
    vols = {}
    for b, ps in pts.items():
        inv = rig.data.bones[b].matrix_local.inverted()
        local = np.array([inv @ p for p in ps])
        vols[b] = (Vector(np.percentile(local, 1, axis=0)), Vector(np.percentile(local, 99, axis=0)))
    _VOLUMES[rig.name] = vols
    return vols


def clearance(rig, vols):
    """Smallest gap (m, < 0 = inside) between the arms and the torso / head volumes;
    the upper part of the upper arm is left out: it meets the chest at the shoulder and
    presses on it when the arm crosses the body."""
    P = rig.pose.bones
    pts = []
    for pre in ("Left", "Right"):
        a, b, c = P[pre + "UpperArm"].head, P[pre + "LowerArm"].head, P[pre + "Hand"].head
        k = P[pre + "MiddleProximal"].head
        pts += [(a.lerp(b, t), 0.05) for t in (0.7, 1.0)]
        pts += [(b.lerp(c, t), 0.045) for t in (0.33, 0.66, 1.0)]
        pts += [(c.lerp(k, 0.5), 0.04), (k, 0.035)]
    worst = 1.0
    for bone, (lo, hi) in vols.items():
        inv = P[bone].matrix.inverted()
        mid, rad = (lo + hi) / 2, (hi - lo) / 2
        for p, r in pts:
            q = inv @ p
            if bone != "Head" and not lo.y <= q.y <= hi.y:
                continue
            n = Vector(((q.x - mid.x) / rad.x, (q.y - mid.y) / rad.y if bone == "Head" else 0.0, (q.z - mid.z) / rad.z))
            worst = min(worst, (n.length - 1.0) * min(rad.x, rad.z) - r)
    return worst


def check(key):
    """Worst arm/body clearance (mm) over every frame of every action, and where."""
    _, _, rig = objects(key)
    vols = body_volumes(rig)
    out = {}
    for tr in rig.animation_data.nla_tracks:
        act = tr.strips[0].action
        rig.animation_data.action = act
        worst = (1.0, 0)
        for f in range(int(act.frame_range[0]), int(act.frame_range[1]) + 1):
            bpy.context.scene.frame_set(f)
            worst = min(worst, (clearance(rig, vols), f))
        out[tr.name] = (round(worst[0] * 1000), worst[1])
    rig.animation_data.action = bpy.data.actions["%s_idle_loop" % key]
    return out


# ---------------------------------------------------------------- gait

# speed: m/s of the game's movement (CharacterModel WALK/RUN/BACK_SPEED); cycle: s for two
# steps; duty: share of the cycle a foot is planted; ahead: share of the planted travel in
# front of the hip; track: feet from the centre line; drop/bob/sway (m) and yaw/roll/tilt
# (deg): pelvis; lean: torso; strike/toe_off: foot pitch (deg, + = heel up); heel_off: where in
# the stance the heel rises; lift/peak: swing foot clearance and when it is highest; follow: how
# much of the ground's speed the foot keeps as it leaves and lands (more = longer reach back/forward);
# arm/elbow/elbow_swing: arm swing (deg); reverse: played backwards (backpedal)
GAITS = {
    "walk": dict(speed=1.5, cycle=28 / FPS, duty=0.62, ahead=0.42, track=0.1, drop=0.03, bob=0.016, sway=0.022,
                 yaw=5, roll=3.5, tilt=2, lean=2, strike=-14, toe_off=32, heel_off=0.55, lift=0.05, peak=0.4,
                 follow=0.6, arm=15, elbow=14, elbow_swing=8),
    "run": dict(speed=7.0, cycle=20 / FPS, duty=0.2, ahead=0.36, track=0.05, drop=0.05, bob=0.03, sway=0.01,
                yaw=7, roll=4, tilt=6, lean=9, strike=-4, toe_off=50, heel_off=0.35, lift=0.22, peak=0.32,
                follow=0.12, arm=36, elbow=82, elbow_swing=12),
    "back": dict(speed=4.5, cycle=22 / FPS, duty=0.28, ahead=0.4, track=0.07, drop=0.05, bob=0.022, sway=0.012,
                 yaw=5, roll=3, tilt=3, lean=3, strike=-6, toe_off=40, heel_off=0.4, lift=0.12, peak=0.4,
                 follow=0.25, arm=20, elbow=45, elbow_swing=10, reverse=True),
}
TOE_IN = 11  # the base mesh's feet turn out ~21 deg; walking duck-footed reads as a limp
# how much of the GAITS pelvis sway / roll / turn each character uses: a big swaying
# pelvis reads feminine, the warrior keeps his hips square
HIP_MOTION = {"male": 0.4, "female": 1.0}


def foot_frame(rig, s):
    """Rest ankle, and heel / ball points on the ground (armature space) of one foot."""
    B = rig.data.bones
    pre = "Left" if s > 0 else "Right"
    mesh = bpy.data.objects[rig.name.replace("_rig", "")]
    to_rig = rig.matrix_world.inverted() @ mesh.matrix_world
    ankle = B[pre + "Foot"].head_local.copy()
    sole = [to_rig @ v.co for v in mesh.data.vertices]
    sole = [p for p in sole if p.z < 0.03 and p.x * s > 0.04 and abs(p.x - ankle.x) < 0.12]
    heel = Vector((ankle.x, max(p.y for p in sole) - 0.02, 0.0))
    ball = B[pre + "Toes"].head_local.copy()
    ball.z = 0.0
    yaw = Matrix.Rotation(math.radians(-TOE_IN * s), 3, 'Z')
    return ankle, ankle + yaw @ (heel - ankle), ankle + yaw @ (ball - ankle), yaw


def hermite(p0, m0, p1, m1, t):
    return ((2 * t ** 3 - 3 * t ** 2 + 1) * p0 + (t ** 3 - 2 * t ** 2 + t) * m0
            + (-2 * t ** 3 + 3 * t ** 2) * p1 + (t ** 3 - t ** 2) * m1)


def foot_at(g, q):
    """One foot at its own phase q (0 = it strikes): flat-foot forward offset (m),
    lift (m), foot pitch and toe pitch (deg, world)."""
    T, duty = g["cycle"], g["duty"]
    travel = g["speed"] * T * duty
    y0 = -travel * g["ahead"]
    if q < duty:  # planted: slides back under the body exactly as fast as the ground
        s = q / duty
        pitch = g["strike"] * (1 - smoothstep(0, 0.15, s)) + g["toe_off"] * smoothstep(g["heel_off"], 1.0, s) ** 1.3
        return y0 + travel * s, 0.0, float(pitch), float(min(pitch, 0.0))
    t = (q - duty) / (1 - duty)  # swing: carried back a little, swung through, reaching forward to land
    m = g["speed"] * T * (1 - duty) * g["follow"]
    y = hermite(y0 + travel, m, y0, m, t)
    lift = g["lift"] * math.sin(math.pi * t ** (math.log(0.5) / math.log(g["peak"])))
    pitch = g["toe_off"] + (g["strike"] - g["toe_off"]) * smoothstep(0.0, 0.8, t)
    return y, lift, float(pitch), float(pitch * smoothstep(0.0, 0.35, t))


def gait(key, name, carry=None):
    """Every-frame keys + planted feet for one gait (see GAITS)."""
    g = GAITS[name]
    _, _, rig = objects(key)
    B = rig.data.bones
    m = key == "male"
    frames = round(g["cycle"] * FPS)
    feet_rest = {s: foot_frame(rig, s) for s in (1, -1)}
    hips0 = B["Hips"].head_local
    legs = {s: B[("Left" if s > 0 else "Right") + "UpperLeg"].head_local - hips0 for s in (1, -1)}
    reach = (B["LeftLowerLeg"].head_local - B["LeftUpperLeg"].head_local).length + (B["LeftFoot"].head_local - B["LeftLowerLeg"].head_local).length
    relax = RELAX[key]
    base = add({"UpperArm": (0, relax, 0), "Hand": (0, 0, 0), "Foot": (0, 0, 0)},
               hand_pose(1, *RELAXED), hand_pose(-1, *GRIP) if m else hand_pose(-1, *RELAXED))
    out, feet, need = [], {}, []
    for i in range(frames + 1):
        p = (i % frames) / frames
        if g.get("reverse"):
            p = (1.0 - p) % 1.0
        duty = g["duty"]
        low = (duty - 0.5) / 2 if duty > 0.5 else duty / 2  # lowest at double support (walk) / mid-stance (run)
        z = -g["drop"] - g["bob"] * math.cos(4 * math.pi * (p - low))
        hip = HIP_MOTION[key]
        x = g["sway"] * hip * math.cos(2 * math.pi * (p - duty / 2))
        yaw = -g["yaw"] * hip * math.cos(2 * math.pi * p)      # left hip forward as the left foot lands
        roll = -g["roll"] * hip * math.cos(2 * math.pi * (p - duty / 2))  # swing side hip drops
        lean, tilt = g["lean"], g["tilt"]
        c = math.cos(2 * math.pi * (p - 0.04))           # arms follow the opposite leg, a little late
        pose = add(base, {
            "Hips": (tilt, roll, yaw), "loc": (x, 0, z),
            "Spine": (lean * 0.6, -roll * 0.6, -yaw * 0.7), "Chest": (lean * 0.4, -roll * 0.3, -yaw * 0.6),
            "UpperChest": (0, -roll * 0.1, -yaw * 0.3), "Neck": (-(lean + tilt) * 0.35, 0, yaw * 0.3),
            "Head": (-(lean + tilt) * 0.35, 0, yaw * 0.3)})
        if carry:
            pose = add(pose, carry)
        else:
            pose = add(pose, side("UpperArm", 1, g["arm"] * c), side("UpperArm", -1, -g["arm"] * c),
                       side("LowerArm", 1, -(g["elbow"] - g["elbow_swing"] * c)), side("LowerArm", -1, -(g["elbow"] + g["elbow_swing"] * c)))
        # feet: where each ankle goes, from the flat-foot placement rolled about heel or ball
        r_hips = Matrix.Rotation(math.radians(tilt), 3, 'X') @ Matrix.Rotation(math.radians(yaw), 3, 'Z') @ Matrix.Rotation(math.radians(roll), 3, 'Y')
        targets, deficit = {}, 0.0
        for s, phase in ((1, p), (-1, (p + 0.5) % 1.0)):
            ankle, heel, ball, toe_in = feet_rest[s]
            dy, lift, pitch, toe = foot_at(g, phase)
            pivot = heel if pitch < 0 else ball
            rot = Matrix.Rotation(math.radians(pitch), 3, 'X')
            target = pivot + rot @ (ankle - pivot) + Vector((s * g["track"] - ankle.x, dy, lift))
            targets["Left" if s > 0 else "Right"] = (target, rot @ toe_in, Matrix.Rotation(math.radians(toe), 3, 'X') @ toe_in)
            hip = hips0 + Vector((x, 0, z)) + r_hips @ legs[s]
            flat = math.hypot(target.x - hip.x, target.y - hip.y)
            deficit = max(deficit, hip.z - target.z - math.sqrt(max((0.985 * reach) ** 2 - flat ** 2, 0.0)))
        out.append(pose)
        feet[i + 1] = targets
        need.append(deficit)
    # lower the hips wherever a leg could not reach the ground, smoothed round the loop
    need = np.maximum(np.array(need[:-1]), 0.0)
    wide = np.max([np.roll(need, k) for k in range(-2, 3)], axis=0)
    drop = np.mean([np.roll(wide, k) for k in range(-3, 4)], axis=0)
    keys = []
    for i, pose in enumerate(out):
        d = float(drop[i % frames])
        keys.append((i / FPS, add(pose, {"loc": (0, 0, -d)})))
    return keys, feet, float(drop.max())


def plant_feet(rig, targets):
    """Legs by IK onto the gait's ankle targets (knees forward), feet and toes pitched."""
    P, B = rig.pose.bones, rig.data.bones
    for pre, (ankle, foot_rot, toe_rot) in targets.items():
        s = 1 if pre == "Left" else -1
        two_bone(P, pre + "UpperLeg", pre + "LowerLeg", pre + "Foot", ankle, Vector((0.12 * s, -1, 0)))
        foot = P[pre + "Foot"]
        set_matrix(foot, Matrix.Translation(foot.head) @ (foot_rot @ B[pre + "Foot"].matrix_local.to_3x3()).to_4x4())
        toes = P[pre + "Toes"]
        set_matrix(toes, Matrix.Translation(toes.head) @ (toe_rot @ B[pre + "Toes"].matrix_local.to_3x3()).to_4x4())


# ---------------------------------------------------------------- choreography

def poses(key):
    m = key == "male"
    relax = RELAX[key]
    arms = {"UpperArm": (0, relax, 0), "LowerArm": (-14, 0, 0), "Hand": (0, 0, 0)}
    right = hand_pose(-1, *GRIP) if m else hand_pose(-1, *RELAXED)  # the male carries the axe
    base = add(arms, hand_pose(1, *RELAXED), right, {"Foot": (0, 0, -TOE_IN)})
    cast_hands = add(hand_pose(1, *OPEN, spread=14), right if m else hand_pose(-1, *OPEN, spread=14))

    # the male holds the axe in both hands: right fist near the head, left toward the pommel
    def axe(fist, haft, edge, pole=RIGHT_POLE, carry=False, hold=LEFT_HOLD):
        return add({"fist": fist, "haft": haft, "edge": edge, "pole": pole, "carry": carry, "two": 1.0, "hold": hold},
                   side("Shoulder", 1, 0, 0, -10)) if m else {}

    # ready stance: axe up by the right shoulder, held across the body
    stance = add({"Chest": (0, 0, -6), "Spine": (0, 0, -3)},
                 axe((-0.24, -0.36, 1.2), (-0.45, -0.25, 0.86), (-0.5, -0.85, 0.0), carry=True)) if m else {}
    breathe_in = add(base, stance, {"Chest": (-2, 0, 0), "UpperArm": (0, -1.5, 0), "Head": (1, 0, 0)})
    breathe_out = add(base, stance, {"Chest": (1, 0, 0), "UpperArm": (0, 1, 0), "Head": (-0.5, 0, 0)})

    # overhead chop: wound up over the right shoulder, down in front
    wind = add(base, {"Spine": (-6, 0, -14), "Chest": (-4, 0, -10), "Head": (4, 0, 8)},
               side("UpperArm", 1, -20, -8, 0), side("LowerArm", 1, -30),
               axe((-0.3, -0.08, 1.72), (-0.15, 0.5, 0.85), (0.0, -0.85, 0.5), (-1.0, 0.0, -0.3)))
    strike = add(base, {"Spine": (12, 0, 12), "Chest": (8, 0, 8), "Head": (-6, 0, -6), "loc": (0, -0.04, -0.03)},
                 side("UpperArm", 1, 18, 4, 0), side("LowerArm", 1, -25),
                 side("UpperLeg", 1, -18), side("LowerLeg", 1, 18), side("UpperLeg", -1, 8), side("LowerLeg", -1, 10),
                 axe((-0.08, -0.5, 1.05), (0.0, -0.92, -0.38), (0.0, 0.37, -0.93), hold=-0.2))  # hands closer: the pommel ends by the belly
    attack = [(0.0, breathe_out), (0.32, wind), (0.45, strike), (0.62, strike), (0.95, breathe_out)]
    # horizontal sweep: wound up out to the right, cutting across the front to the left
    wind2 = add(base, {"Spine": (2, 0, -18), "Chest": (0, 0, -14), "Head": (0, 0, 10)}, side("UpperArm", 1, -15, 0, 0),
                axe((-0.42, -0.15, 1.3), (-0.85, 0.45, 0.28), (-0.45, -0.85, 0.0)))
    strike2 = add(base, {"Spine": (6, 0, 16), "Chest": (4, 0, 14), "Head": (0, 0, -8), "loc": (0, -0.02, -0.02)},
                  side("UpperArm", 1, 10, -6, 0), side("UpperLeg", 1, -10), side("LowerLeg", 1, 12),
                  axe((0.15, -0.45, 1.2), (0.75, -0.62, 0.2), (0.62, 0.75, 0.0), hold=-0.2))
    attack2 = [(0.0, breathe_out), (0.3, wind2), (0.42, strike2), (0.58, strike2), (0.92, breathe_out)]
    # rising diagonal: low behind on the right, up across to the left
    wind3 = add(base, {"Spine": (10, 0, -12), "Chest": (4, 0, -8), "loc": (0, 0, -0.045)},
                side("UpperLeg", 1, -14), side("LowerLeg", 1, 22), side("UpperLeg", -1, 6), side("LowerLeg", -1, 18),
                axe((-0.35, -0.05, 0.95), (-0.45, 0.55, -0.7), (0.3, -0.75, -0.6)))
    strike3 = add(base, {"Spine": (-8, 0, 12), "Chest": (-4, 0, 10), "Head": (-4, 0, -6), "loc": (0, -0.02, 0.01)},
                  side("UpperArm", 1, 12, -8, 0),
                  axe((0.1, -0.42, 1.55), (0.35, -0.45, 0.82), (0.4, 0.7, 0.2), hold=-0.2))
    attack3 = [(0.0, breathe_out), (0.28, wind3), (0.4, strike3), (0.55, strike3), (0.9, breathe_out)]

    # spell: both hands pushed forward at chest height, palms channeling
    cast_a = add(arms, cast_hands, {"Spine": (4, 0, 0), "Chest": (-3, 0, 0), "Head": (6, 0, 0), "loc": (0, 0, -0.015)},
                 side("UpperArm", 1, -62, 10, 0), side("UpperArm", -1, -62, 10, 0),
                 side("LowerArm", 1, -38), side("LowerArm", -1, -38), side("Hand", 1, 0, 0, 10), side("Hand", -1, 0, 0, 10),
                 side("UpperLeg", 1, -6), side("LowerLeg", 1, 10), side("LowerLeg", -1, 10))
    cast_b = add(cast_a, {"Chest": (-2, 0, 0), "loc": (0, 0, 0.008)}, side("UpperArm", 1, -6), side("UpperArm", -1, -6))
    cast = [(0.0, cast_a), (0.6, cast_b), (1.2, cast_a)]

    hit = [(0.0, breathe_out), (0.08, add(breathe_out, {"Spine": (-9, 0, 4), "Chest": (-6, 0, 0), "Head": (-10, 0, 0), "loc": (0, 0.03, 0)},
                                          side("UpperArm", 1, 0, -10), side("UpperArm", -1, 0, -10))), (0.35, breathe_out)]

    # death: knees give, then the body tips over backwards onto the ground (the axe is let go)
    hip_z = bone_point(key, "Hips")[2]
    knees = add(base, {"Spine": (14, 0, 0), "Head": (12, 0, 0), "loc": (0, 0.05, -0.28)},
                side("UpperLeg", 1, -55), side("LowerLeg", 1, 95), side("Foot", 1, -35),
                side("UpperLeg", -1, -45), side("LowerLeg", -1, 85), side("Foot", -1, -35),
                side("UpperArm", 1, -30, -25), side("UpperArm", -1, -30, -25))  # arms fly out, clear of the body
    # tipping the hips back already lays the legs forward along the ground; knees stay a little bent
    down = add(base, {"Hips": (-84, 0, 0), "Spine": (-4, 0, 0), "Head": (-10, 0, 14), "loc": (0, 0.3, -(hip_z - 0.15))},
               side("UpperLeg", 1, -12, 0, 6), side("LowerLeg", 1, 25), side("UpperLeg", -1, -4, 0, 10), side("LowerLeg", -1, 12),
               side("UpperArm", 1, 25, -55), side("UpperArm", -1, 10, -40), side("LowerArm", 1, -20), side("LowerArm", -1, -35))
    death = [(0.0, breathe_out), (0.35, knees), (0.9, down), (1.3, down)]

    return {
        "idle_loop": [(0.0, breathe_out), (1.3, breathe_in), (2.6, breathe_out)],
        "attack": attack, "attack2": attack2, "attack3": attack3,
        "cast_loop": cast, "hit": hit, "death": death,
    }, stance


def anim_pass(key):
    _, _, rig = objects(key)
    game = bpy.data.objects["arkanor_%s" % key]
    shown = game.hide_viewport
    game.hide_viewport = True  # nothing to deform while keying: much faster scene updates
    try:
        FIST_FIX.clear()
        clips, stance = poses(key)
        acts = {name: key_action(key, name, keys, name.endswith("_loop")) for name, keys in clips.items()}
        for name in GAITS:
            keys, feet, dropped = gait(key, name, stance)
            acts[name + "_loop"] = key_action(key, name + "_loop", keys, True, feet)
    finally:
        game.hide_viewport = shown
    # every action on its own muted NLA track so the glTF exporter writes them all
    ad = rig.animation_data
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    for name, act in acts.items():
        tr = ad.nla_tracks.new()
        tr.name = name
        tr.strips.new(name, int(act.frame_range[0]), act)
        tr.mute = True
    ad.action = acts["idle_loop"]
    return sorted(acts)


def export(key):
    import os
    os.makedirs(GAME_ART, exist_ok=True)
    body, _, rig = objects(key)
    game = bpy.data.objects["arkanor_%s" % key]
    for o in (rig, game):  # hidden objects cannot be selected, so would not export
        o.hide_viewport = False
        o.hide_set(False)
    for pb in rig.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location, pb.scale = (0, 0, 0), (1, 1, 1)
    rig.location = (0, 0, 0)  # export centred on its feet
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    game.select_set(True)
    bpy.context.view_layer.objects.active = rig
    path = GAME_ART + "/arkanor_%s.glb" % key
    bpy.ops.export_scene.gltf(
        filepath=path, use_selection=True, export_format='GLB', export_yup=True,
        export_apply=False, export_skins=True, export_animations=True,
        export_animation_mode='NLA_TRACKS', export_force_sampling=True, export_frame_step=1,
        export_def_bones=True, export_morph=False, export_image_format='AUTO')
    rig.location = body.location
    return path
