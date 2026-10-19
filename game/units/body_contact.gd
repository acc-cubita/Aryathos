class_name BodyContact
extends SkeletonModifier3D
## Arms and body know each other's surface: no arm, elbow or hand passes into the body,
## whatever the clip, the IK or the swing does with it.
##
## The body's shape is measured from the character's own meshes as worn (setup()): every
## vertex skinned mostly to a body bone (hips, spine, chest, neck, head, thighs) gives that
## bone's volume, a stack of SLICES across the bone, each its outline as how far the body
## reaches in SECTORS directions round its middle (the chest narrowing to the front, the
## lats out behind), carried by the bone as it moves; the arms' thickness is measured the
## same way. Each frame a few points down each arm (upper arm, forearm, hand) are tested:
## one inside the body (with the arm's thickness) is pushed out to its surface by turning
## the arm about the line from shoulder to wrist (the elbow swings out, the hand stays where
## it was, on a haft if it holds one), or, for a hand left inside, by turning the whole arm
## out at the shoulder (a hand that rests on the hip stays on it). `pinned` arms (both hands
## on a weapon, TwoHandGrip) only swing their elbows: the grip places their hands.

const BODY_BONES := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftUpperLeg", "RightUpperLeg"]
## Where the arms are rooted (the shoulders, the muscle round them): an upper arm presses into
## these as it moves and is not tested against them (forearms and hands are).
const GIRDLE := ["UpperChest", "Neck"]
## Which way each bone runs: toward this joint (the head and anything else: on from its parent).
const NEXT := {"Hips": "Spine", "Spine": "Chest", "Chest": "UpperChest", "UpperChest": "Neck", "Neck": "Head",
		"LeftUpperLeg": "LeftLowerLeg", "RightUpperLeg": "RightLowerLeg", "LeftUpperArm": "LeftLowerArm",
		"RightUpperArm": "RightLowerArm", "LeftLowerArm": "LeftHand", "RightLowerArm": "RightHand",
		"LeftHand": "LeftMiddleProximal", "RightHand": "RightMiddleProximal"}
const SLICES := 3
## Directions round a slice's outline, and the share of its vertices each direction's
## reach takes in (seams and folds stand out of it).
const SECTORS := 16
const TAKE_IN := 0.9
## How far (m) flesh may press into flesh before it pushes back.
const SOFT := 0.02
## Where the points tested sit along the upper arm and the forearm (0 at its joint).
const UPPER_POINTS := [0.6, 0.85]
const LOWER_POINTS := [0.3, 0.65, 1.0]
## At most this far (radians) an arm turns in one pass; passes per arm per frame.
const STEP := deg_to_rad(25.0)
const PASSES := 4

var pinned := false

## [bone, frame (bone space, its y down the bone), [[y0, y1, middle (x, z), reach per sector], ...], girdle?,
## how far from the joint it reaches]
var _volumes: Array = []
## side -> [upper arm, lower arm, hand, upper radius, lower radius, hand radius, hand length, middle finger]
var _arms := {}

## Measurements by the meshes measured (CharacterModel builds the same hero again and again).
static var _measured := {}


## Measures the body and the arms from `meshes` (the visible skinned meshes, as worn).
func setup(skeleton: Skeleton3D, meshes: Array) -> void:
	var key := ",".join(meshes.map(func(m: MeshInstance3D) -> String: return str(m.mesh.get_rid().get_id())))
	if not _measured.has(key):
		_measured[key] = _measure(skeleton, meshes)
	var found: Dictionary = _measured[key]
	_volumes = found.volumes
	_arms = found.arms


static func _measure(skeleton: Skeleton3D, meshes: Array) -> Dictionary:
	var wanted := {}
	for name: String in BODY_BONES:
		wanted[skeleton.find_bone(name)] = name
	for side: String in ["Left", "Right"]:
		for part: String in ["UpperArm", "LowerArm", "Hand"]:
			wanted[skeleton.find_bone(side + part)] = side + part
	var points := {}  # bone -> PackedVector3Array, in the bone's rest frame
	wanted.erase(-1)
	for bone: int in wanted:
		points[bone] = PackedVector3Array()
	for mesh_instance: MeshInstance3D in meshes:
		var skin := mesh_instance.skin
		if skin == null:
			continue
		var binds := []
		for i in skin.get_bind_count():
			var bone := skin.get_bind_bone(i)
			if bone < 0:
				bone = skeleton.find_bone(skin.get_bind_name(i))
			binds.append(bone)
		for surface in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if vertices.is_empty() or bones.is_empty():
				continue
			var per := bones.size() / vertices.size()
			for v in vertices.size():
				var best := 0
				for k in range(1, per):
					if weights[v * per + k] > weights[v * per + best]:
						best = k
				var bind := bones[v * per + best]
				var bone: int = binds[bind]
				if points.has(bone):
					points[bone].append(skin.get_bind_pose(bind) * vertices[v])
	var volumes := []
	for bone: int in points:
		if not String(wanted[bone]) in BODY_BONES or points[bone].size() < 12:
			continue
		var frame := _bone_frame(skeleton, bone)
		var local := PackedVector3Array()
		for p in points[bone]:
			local.append(frame.inverse() * p)
		var low := INF
		var high := -INF
		for p in local:
			low = minf(low, p.y)
			high = maxf(high, p.y)
		var slices := []
		for s in SLICES:
			var y0 := lerpf(low, high, float(s) / SLICES)
			var y1 := lerpf(low, high, float(s + 1) / SLICES)
			var flat := PackedVector2Array()
			for p in local:
				if p.y >= y0 and p.y <= y1:
					flat.append(Vector2(p.x, p.z))
			if flat.size() < 8:
				continue
			# the middle: halfway across the outline's extent
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for p in flat:
				lo = lo.min(p)
				hi = hi.max(p)
			var middle := (lo + hi) * 0.5
			var reaches := []
			for k in SECTORS:
				reaches.append([])
			for p in flat:
				var d := p - middle
				reaches[int(fposmod(d.angle(), TAU) / TAU * SECTORS) % SECTORS].append(d.length())
			var outline := PackedFloat32Array()
			for k in SECTORS:
				var these: Array = reaches[k]
				these.sort()
				outline.append(these[int((these.size() - 1) * TAKE_IN)] if not these.is_empty() else -1.0)
			for k in SECTORS:  # a direction with no vertex takes its neighbours' reach
				if outline[k] < 0.0:
					outline[k] = maxf(maxf(outline[(k + SECTORS - 1) % SECTORS], outline[(k + 1) % SECTORS]), 0.0)
			slices.append([y0, y1, middle, outline])
		var bound := 0.0  # how far from the joint the volume reaches at most
		for slice: Array in slices:
			var widest := 0.0
			for reach: float in slice[3]:
				widest = maxf(widest, reach)
			bound = maxf(bound, Vector2(maxf(absf(slice[0]), absf(slice[1])), (slice[2] as Vector2).length() + widest).length())
		volumes.append([bone, frame, slices, String(wanted[bone]) in GIRDLE, bound])
	var arms := {}
	for side: String in ["Left", "Right"]:
		var parts := []
		var radii := []
		for part: String in ["UpperArm", "LowerArm", "Hand"]:
			var bone := skeleton.find_bone(side + part)
			parts.append(bone)
			radii.append(_thickness(skeleton, bone, points[bone]))
		var fingers := skeleton.find_bone(side + "MiddleProximal")
		if parts.has(-1) or fingers < 0:
			continue
		var hand_length := skeleton.get_bone_rest(fingers).origin.length() * 1.6
		arms[side] = parts + radii + [hand_length, fingers]
	return {"volumes": volumes, "arms": arms}


## A bone's frame in its own space: y down the bone (NEXT), x across as the rig's left lies,
## z ahead.
static func _bone_frame(skeleton: Skeleton3D, bone: int) -> Basis:
	var rest := skeleton.get_bone_global_rest(bone)
	var along := Vector3.UP
	var next := skeleton.find_bone(NEXT.get(skeleton.get_bone_name(bone), ""))
	if next >= 0:
		along = skeleton.get_bone_global_rest(next).origin - rest.origin
	else:
		along = rest.origin - skeleton.get_bone_global_rest(skeleton.get_bone_parent(bone)).origin
	along = along.normalized()
	var across := Vector3.RIGHT - along * along.x
	var ahead := across.normalized().cross(along).normalized()
	across = along.cross(ahead).normalized()
	# into the bone's own space
	return rest.basis.inverse() * Basis(across, along, ahead)


## How thick a limb part is: the median distance of its vertices from its bone's line.
static func _thickness(skeleton: Skeleton3D, bone: int, points: PackedVector3Array) -> float:
	if points.size() < 8:
		return 0.05
	var frame := _bone_frame(skeleton, bone)
	var distances := []
	for p in points:
		var q := frame.inverse() * p
		distances.append(Vector2(q.x, q.z).length())
	distances.sort()
	return distances[distances.size() / 2]


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or _volumes.is_empty():
		return
	var frames := _frames(skeleton)
	for side: String in _arms:
		for pass_index in PASSES:
			if not _settle(skeleton, side, frames):
				break


## How far, and which way, the forearms and hands must move to be out of the body, as now
## posed (TwoHandGrip brings the fists out by it).
func hands_push() -> Vector3:
	var skeleton := get_skeleton()
	if skeleton == null or _volumes.is_empty():
		return Vector3.ZERO
	var frames := _frames(skeleton)
	var worst := Vector3.ZERO
	for side: String in _arms:
		for test: Array in _tests(skeleton, side):
			if test[2] > 0:
				var push := _push_out(test[0], test[1], frames)
				if push.length_squared() > worst.length_squared():
					worst = push
	return worst


## How deep (m) the arms are in the body as now posed (after the skeleton's modifiers: a
## measure for tests), and where: [depth, "<side> <arm part> in <body bone>"].
func deepest() -> Array:
	var skeleton := get_skeleton()
	if skeleton == null or _volumes.is_empty():
		return [0.0, ""]
	var frames := _frames(skeleton)
	var worst := [0.0, ""]
	for side: String in _arms:
		for test: Array in _tests(skeleton, side):
			for i in _volumes.size():
				var depth := _push_out(test[0], test[1], frames, i, test[2] == 0).length()
				if depth > worst[0]:
					worst = [depth, "%s %s in %s" % [side, ["upper arm", "forearm", "hand"][test[2]], skeleton.get_bone_name(_volumes[i][0])]]
	return worst


## Each body volume's frame as posed (skeleton space), inverted.
func _frames(skeleton: Skeleton3D) -> Array:
	var frames := []
	for volume: Array in _volumes:
		var pose := skeleton.get_bone_global_pose(volume[0])
		frames.append(Transform3D(pose.basis.orthonormalized() * (volume[1] as Basis), pose.origin).affine_inverse())
	return frames


## The points tested down one arm: [point, radius, part: 0 upper arm, 1 forearm, 2 hand].
func _tests(skeleton: Skeleton3D, side: String) -> Array:
	var arm: Array = _arms[side]
	var shoulder := skeleton.get_bone_global_pose(arm[0]).origin
	var elbow := skeleton.get_bone_global_pose(arm[1]).origin
	var wrist := skeleton.get_bone_global_pose(arm[2]).origin
	var fingers := skeleton.get_bone_global_pose(arm[7]).origin - wrist
	var tests := []
	for t: float in UPPER_POINTS:
		tests.append([shoulder.lerp(elbow, t), arm[3], 0])
	for t: float in LOWER_POINTS:
		tests.append([elbow.lerp(wrist, t), arm[4], 1])
	tests.append([wrist + fingers.normalized() * arm[6] * 0.5, arm[5], 2])
	return tests


## One pass for one arm: the deepest point of it inside the body pushed out. False when
## no point is inside.
func _settle(skeleton: Skeleton3D, side: String, frames: Array) -> bool:
	var arm: Array = _arms[side]
	var shoulder := skeleton.get_bone_global_pose(arm[0]).origin
	var wrist := skeleton.get_bone_global_pose(arm[2]).origin
	var tests := _tests(skeleton, side)
	var worst := Vector3.ZERO
	var at := Vector3.ZERO
	var part := -1
	for test: Array in tests:
		var push := _push_out(test[0], test[1], frames, -1, test[2] == 0)
		if push.length_squared() > worst.length_squared():
			worst = push
			at = test[0]
			part = test[2]
	if part < 0 or worst.length() < 0.002:
		return false
	# swing the elbow about the shoulder-wrist line toward the push, the hand left in place
	var line := (wrist - shoulder).normalized()
	var spoke := at - (shoulder + line * line.dot(at - shoulder))
	var turned := false
	if part < 2 and spoke.length() > 0.02:
		var tangent := line.cross(spoke).normalized()
		var along := worst.dot(tangent)
		if absf(along) > worst.length() * 0.3:
			var angle := clampf(along / spoke.length(), -STEP, STEP)
			_swivel(skeleton, arm, Basis(line, angle))
			turned = true
	if not turned and not pinned:
		# out from the shoulder, the whole arm with it
		var from := at - shoulder
		var to := from + worst
		var swing := Quaternion(from.normalized(), to.normalized())
		if swing.get_angle() > STEP:
			swing = Quaternion(swing.get_axis(), STEP)
		var upper := skeleton.get_bone_global_pose(arm[0])
		upper.basis = Basis(swing) * upper.basis
		skeleton.set_bone_global_pose(arm[0], upper)
		turned = true
	return turned


## The arm turned by `turn` about its shoulder, the forearm with it, the hand kept as it was.
func _swivel(skeleton: Skeleton3D, arm: Array, turn: Basis) -> void:
	var hand_basis := skeleton.get_bone_global_pose(arm[2]).basis
	var lower_basis := skeleton.get_bone_global_pose(arm[1]).basis
	var upper := skeleton.get_bone_global_pose(arm[0])
	upper.basis = turn * upper.basis
	skeleton.set_bone_global_pose(arm[0], upper)
	var lower := skeleton.get_bone_global_pose(arm[1])
	lower.basis = turn * lower_basis
	skeleton.set_bone_global_pose(arm[1], lower)
	var hand := skeleton.get_bone_global_pose(arm[2])
	hand.basis = hand_basis
	skeleton.set_bone_global_pose(arm[2], hand)


## How far, and which way, `point` (a ball of `radius`) must move to leave the body (zero
## when it is outside): the deepest of the volumes it is in (or of volume `only`; `upper`:
## an upper arm's point, not tested against the GIRDLE).
func _push_out(point: Vector3, radius: float, frames: Array, only := -1, upper := false) -> Vector3:
	var deepest := Vector3.ZERO
	for i in _volumes.size():
		if (only >= 0 and i != only) or (upper and _volumes[i][3]):
			continue
		var inverse: Transform3D = frames[i]
		var local := inverse * point
		if local.length() > _volumes[i][4] + radius:
			continue
		for slice: Array in _volumes[i][2]:
			if local.y < slice[0] or local.y > slice[1]:
				continue
			var d := Vector2(local.x, local.z) - (slice[2] as Vector2)
			if d.length() < 0.001:
				d = Vector2(0.0, 0.001)  # (ahead, out of the middle)
			var at := fposmod(d.angle(), TAU) / TAU * SECTORS
			var outline: PackedFloat32Array = slice[3]
			var reach := lerpf(outline[int(at) % SECTORS], outline[(int(at) + 1) % SECTORS], at - floorf(at))
			var depth := reach + radius - SOFT - d.length()
			if depth <= 0.0:
				continue
			var out := d.normalized() * depth
			var push := inverse.basis.inverse() * Vector3(out.x, 0.0, out.y)
			if push.length_squared() > deepest.length_squared():
				deepest = push
	return deepest
