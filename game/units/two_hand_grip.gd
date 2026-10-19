class_name TwoHandGrip
extends SkeletonModifier3D
## Both hands on a two-handed weapon's haft, held ready (WoW's two-handed stance): the fists
## before the body (the shoulders turned a little right bring them to the right side), the
## haft rising up and out to the right, the right fist above the left, the left near the
## haft's end, as a right-handed fighter holds it. Each arm reaches its fist's place by
## two-bone IK, the hands turned
## so the weapon (carried by the right hand) lies along the haft, edge to the front, so it
## fits any build; the collarbones follow the hands a little (up, forward, across), as
## shoulders do. `weight` (0..1) fades it in and out. A two-handed swing (strike()) moves
## the weapon along one of STRIKES's paths, the hands with it.
##
## Places are in the chest's frame: from the UpperChest joint, the rig's axes turned the way
## the chest faces (+Z ahead, +X to the left) but kept upright (+Y up; the chest leans 30
## degrees and more), so the body's turn swings the weapon round and the arms only reach,
## as a fighter's do.

## Ready: where the right fist's grip is, which way the haft rises, which way the edge looks.
const GRIP := Vector3(-0.06, 0.06, 0.44)
const HAFT := Vector3(-0.55, 0.83, 0.05)
const EDGE := Vector3(0.0, 0.0, 1.0)
## How far down the haft (m) the left fist holds, below the right. (Every place keeps both
## wrists within the arms' reach, 0.57 m from the shoulder, and before the body: past
## either, an arm would pass through it. The wrists sit some 8 cm behind the fists' grip.)
const LEFT_DOWN := 0.13
## The front of the chest and belly (with the tunic over them): within TORSO.x of the
## middle, from TORSO.y below the chest joint up to it, the body reaches TORSO.z ahead
## (measured on the hero); a wrist keeps WRIST_CLEAR before it, the fists pushed out if not.
const TORSO := Vector3(0.2, 0.5, 0.23)
const WRIST_CLEAR := 0.06
## Which way each elbow bends: both out to their sides and down.
const RIGHT_POLE := Vector3(-1.0, -0.5, -0.4)
const LEFT_POLE := Vector3(0.8, -0.8, 0.2)
## Two-handed swings (studied from a reference; the body's turn is hero_moves.py's clip of
## the same times): keys of [seconds, grip, haft, edge, right pole, left pole]. "sweep":
## up to the right shoulder as the body coils right, the head laid back behind it; then the
## body unwinds and the arms reach out straight through a flat blow (square to the front at
## 0.31 s), the shoulders thrown forward, the leading left arm straight, then on round to
## the left side (no further: the head stops beside the body), hold, and come back to ready. (A sweeping edge looks the way the head
## travels: round the body.)
const STRIKES := {
	"sweep": [
		[0.0, GRIP, HAFT, EDGE, RIGHT_POLE, LEFT_POLE],
		[0.14, Vector3(-0.12, 0.16, 0.46), Vector3(-0.2, 0.95, -0.15), Vector3(0, 0.2, 1), Vector3(-1, -0.6, -0.3), Vector3(0.2, -1, 0.3)],
		[0.23, Vector3(-0.28, 0.18, 0.36), Vector3(-0.55, 0.3, -0.75), Vector3(-0.75, 0.3, 0.55), Vector3(-1, -0.7, -0.2), Vector3(0.2, -1, 0.4)],
		[0.27, Vector3(-0.18, 0.08, 0.6), Vector3(-0.9, 0.05, 0.4), Vector3(0.4, 0, 0.9), Vector3(-0.6, -1, 0), Vector3(0.3, -1, 0.2)],
		[0.31, Vector3(-0.08, 0.08, 0.55), Vector3(0.15, -0.08, 1.0), Vector3(1, 0, -0.15), Vector3(-0.4, -1, 0), Vector3(0.4, -1, 0)],
		[0.36, Vector3(0.06, 0.06, 0.46), Vector3(0.9, -0.1, 0.3), Vector3(0.3, 0, -0.9), Vector3(-0.2, -1, 0.3), Vector3(0.8, -0.8, -0.2)],
		[0.46, Vector3(0.04, 0.04, 0.36), Vector3(0.85, -0.3, 0.25), Vector3(0.25, 0, -0.85), Vector3(-0.2, -1, 0.4), Vector3(1, -0.6, -0.4)],
		[0.7, Vector3(0.04, 0.02, 0.34), Vector3(0.85, -0.25, 0.25), Vector3(0.25, 0, -0.85), Vector3(-0.2, -1, 0.4), Vector3(1, -0.6, -0.4)],
		[1.0, GRIP, HAFT, EDGE, RIGHT_POLE, LEFT_POLE],
	],
}
## The collarbones: how far (radians per m the hand is past an easy reach, least, most) they
## lift for a hand raised and come forward for one reaching out or across the body.
const SHRUG := Vector3(deg_to_rad(45.0), deg_to_rad(-5.0), deg_to_rad(22.0))
const REACH := Vector3(deg_to_rad(80.0), deg_to_rad(-5.0), deg_to_rad(25.0))
## An easy reach: the hand this far from its shoulder (in the chest's frame, the side's x
## toward the body's middle).
const EASY := Vector3(0.0, -0.4, 0.2)

var weight := 0.0
## The weapon in the right hand's frame (CharacterModel._in_hand).
var in_hand := Transform3D.IDENTITY
## The body's surface (BodyContact): a forearm or hand held in the body brings both fists
## out by as much, and the arms reach again (CLEAR_TRIES in all), the same frame; how far
## they came out carries on to the next frame, eased back once clear.
var contact: BodyContact
const CLEAR_TRIES := 6

var _clear := Vector3.ZERO  # how far the fists are moved for the body's sake (skeleton space)
## How far (m) a fist was off the haft at worst (one out of reach): a measure for tests.
var gap := 0.0

var _chest := -1
var _arms := {}  # side -> [collarbone, upper arm, lower arm, hand]
var _left_in_hand := Transform3D.IDENTITY  # the left fist's grip, as the weapon would sit in it
var _strike: Array = []  # the swing under way (STRIKES), and how far into it (s)
var _strike_time := 0.0


## Starts a two-handed swing along STRIKES[path].
func strike(path: String) -> void:
	_strike = STRIKES[path]
	_strike_time = 0.0


func striking() -> bool:
	return not _strike.is_empty()


## The swing's clock (CharacterModel moves it on every frame).
func advance(delta: float) -> void:
	if striking():
		_strike_time += delta
		if _strike_time >= _strike[-1][0]:
			_strike = []


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_chest = skeleton.find_bone("UpperChest")
	for side: String in ["Left", "Right"]:
		_arms[side] = [skeleton.find_bone(side + "Shoulder"), skeleton.find_bone(side + "UpperArm"),
				skeleton.find_bone(side + "LowerArm"), skeleton.find_bone(side + "Hand")]
	# the left fist's grip frame like the right's (CharacterModel._grip): along its grip
	# markers toward the thumb, the fingers' way as the edge's
	var hand := skeleton.get_bone_global_rest(skeleton.find_bone("LeftHand"))
	var grip := skeleton.get_bone_global_rest(skeleton.find_bone("LeftGrip")).origin
	var tip := skeleton.get_bone_global_rest(skeleton.find_bone("LeftGripTip")).origin
	var fingers := skeleton.get_bone_global_rest(skeleton.find_bone("LeftMiddleProximal")).origin - hand.origin
	var handle := (tip - grip).normalized()
	var blade := (fingers - handle * fingers.dot(handle)).normalized()
	_left_in_hand = hand.affine_inverse() * Transform3D(Basis(handle.cross(-blade), handle, -blade), grip)


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or weight <= 0.0 or _chest < 0:
		return
	# the rig's frame turned as the upper chest faces, upright
	var chest := skeleton.get_bone_global_pose(_chest)
	var facing := chest.basis.orthonormalized() * skeleton.get_bone_global_rest(_chest).basis.orthonormalized().inverse() * Vector3.BACK
	var ahead := Vector3(facing.x, 0.0, facing.z).normalized()
	var body := Basis(Vector3.UP.cross(ahead), Vector3.UP, ahead)
	var key: Array = _sample() if striking() else [0.0, GRIP, HAFT, EDGE, RIGHT_POLE, LEFT_POLE]
	var haft: Vector3 = (body * key[2]).normalized()
	var edge: Vector3 = body * key[3]
	edge = (edge - haft * edge.dot(haft)).normalized()
	var weapon := Basis(haft.cross(-edge), haft, -edge)
	var right_grip: Vector3 = chest.origin + body * key[1]
	# no wrist inside the body (the curve between the keys may cut a corner)
	var out := 0.0
	for fist: Array in [[Vector3.ZERO, in_hand], [-haft * LEFT_DOWN, _left_in_hand]]:
		var wrist: Vector3 = body.inverse() * (_wrist(Transform3D(weapon, right_grip + fist[0]), fist[1]) - chest.origin)
		if absf(wrist.x) < TORSO.x and wrist.y > -TORSO.y and wrist.y < 0.25:
			out = maxf(out, TORSO.z + WRIST_CLEAR - wrist.z)
	right_grip += body * Vector3.BACK * out
	# then reach, and if a forearm or hand is in the body, bring the fists out and reach again
	var poses := []
	for side: String in _arms:
		for bone: int in _arms[side]:
			poses.append([bone, skeleton.get_bone_pose(bone)])
	var clear := _clear
	for attempt in CLEAR_TRIES:
		_hold(skeleton, body, "Right", Transform3D(weapon, right_grip + clear), in_hand, body * key[4])
		_hold(skeleton, body, "Left", Transform3D(weapon, right_grip + clear - haft * LEFT_DOWN), _left_in_hand, body * key[5])
		# a fist short of its place on the haft (out of the arm's reach) brings the weapon to it
		var miss := Vector3.ZERO
		for fist: Array in [["Right", Vector3.ZERO, in_hand], ["Left", -haft * LEFT_DOWN, _left_in_hand]]:
			var hand := skeleton.get_bone_global_pose(_arms[fist[0]][3])
			var off: Vector3 = hand * (fist[2] as Transform3D).origin - (right_grip + clear + fist[1])
			if off.length() > miss.length():
				miss = off
		var push := contact.hands_push() if contact else Vector3.ZERO
		if push.length() < 0.003 and miss.length() < 0.01:
			if attempt == 0:
				clear *= 0.94  # clear of the body and in reach: ease back to the swing's own path
			break
		clear += push * 1.1 + miss
		if attempt == CLEAR_TRIES - 1:
			break
		for pose: Array in poses:
			skeleton.set_bone_pose(pose[0], pose[1])
	_clear = clear
	if weight >= 0.99:  # (fading in, the fists are on their way)
		for fist: Array in [["Right", Vector3.ZERO, in_hand], ["Left", -haft * LEFT_DOWN, _left_in_hand]]:
			var hand := skeleton.get_bone_global_pose(_arms[fist[0]][3])
			gap = maxf(gap, (hand * (fist[2] as Transform3D).origin - (right_grip + clear + fist[1])).length())


## Where a hand's wrist goes for `held` (a grip frame in the hand's frame) to be at `grip`.
func _wrist(grip: Transform3D, held: Transform3D) -> Vector3:
	return grip.origin - Basis((grip.basis * held.basis.orthonormalized().inverse()).get_rotation_quaternion()) * held.origin



## The swing's key at its clock: each value on a Catmull-Rom curve through the keys.
func _sample() -> Array:
	var i := 0
	while i < _strike.size() - 2 and _strike_time >= _strike[i + 1][0]:
		i += 1
	var a: Array = _strike[maxi(i - 1, 0)]
	var b: Array = _strike[i]
	var c: Array = _strike[i + 1]
	var d: Array = _strike[mini(i + 2, _strike.size() - 1)]
	var u := clampf((_strike_time - b[0]) / maxf(c[0] - b[0], 0.001), 0.0, 1.0)
	var out := [_strike_time]
	for k in range(1, 6):
		out.append((b[k] as Vector3).cubic_interpolate(c[k], a[k], d[k], u))
	return out


## One arm: its collarbone turned a little toward where the hand goes, its hand turned and
## brought so that `held` (a grip frame in the hand's frame) comes to `grip`, the elbow
## bending toward `pole`; all by `weight`.
func _hold(skeleton: Skeleton3D, body: Basis, side: String, grip: Transform3D, held: Transform3D, pole: Vector3) -> void:
	var bones: Array = _arms[side]
	var hand := skeleton.get_bone_global_pose(bones[3])
	var scale := hand.basis.get_scale()
	var turned := Basis((grip.basis * held.basis.orthonormalized().inverse()).get_rotation_quaternion())
	var wrist := grip.origin - turned.scaled(scale) * held.origin
	var target := hand.origin.lerp(wrist, weight)
	_shrug(skeleton, body, bones, target, -1.0 if side == "Right" else 1.0)
	var want := hand.basis.get_rotation_quaternion().slerp(turned.get_rotation_quaternion(), weight)
	_reach(skeleton, bones[1], bones[2], bones[3], target, pole)
	var posed := skeleton.get_bone_global_pose(bones[3])
	skeleton.set_bone_global_pose(bones[3], Transform3D(Basis(want).scaled(scale), posed.origin))


## The collarbone lifted for a hand above an easy reach, brought forward for one reaching
## out or across the body (`out` is the side the shoulder is on: -1 right, +1 left).
func _shrug(skeleton: Skeleton3D, body: Basis, bones: Array, target: Vector3, out: float) -> void:
	var collar := skeleton.get_bone_global_pose(bones[0])
	var shoulder := skeleton.get_bone_global_pose(bones[1]).origin
	var off := body.inverse() * (target - shoulder) - Vector3(-out * EASY.x, EASY.y, EASY.z)
	var lift := clampf(off.y * SHRUG.x, SHRUG.y, SHRUG.z) * weight
	var forward := clampf((off.z + maxf(-out * off.x, 0.0)) * REACH.x, REACH.y, REACH.z) * weight
	# up: a turn about the body's ahead axis (the right collarbone points -X, so it lifts by
	# a turn about -ahead); forward: about the up axis (the left one about -up)
	var turn := Basis(body * Vector3.UP, forward * -out) * Basis(body * Vector3.BACK, lift * out)
	collar.basis = turn * collar.basis
	skeleton.set_bone_global_pose(bones[0], collar)


## Two-bone IK: the upper and lower bones turned so the end bone's joint comes to `target`
## (as near as the limb reaches), the middle joint bending toward `pole` (fading from where
## it bends now as weight comes in).
func _reach(skeleton: Skeleton3D, upper: int, lower: int, end: int, target: Vector3, pole: Vector3) -> void:
	var top := skeleton.get_bone_global_pose(upper)
	var middle := skeleton.get_bone_global_pose(lower).origin
	var tip := skeleton.get_bone_global_pose(end).origin
	var a := top.origin.distance_to(middle)
	var b := middle.distance_to(tip)
	var to := target - top.origin
	var reach := clampf(to.length(), absf(a - b) + 0.001, a + b - 0.001)
	var dir := to.normalized()
	var bend_now := middle - top.origin
	bend_now -= dir * bend_now.dot(dir)
	var bend := pole - dir * pole.dot(dir)
	bend = bend_now.normalized().lerp(bend.normalized(), weight).normalized() if bend_now.length() > 0.001 else bend.normalized()
	var cos_a := clampf((a * a + reach * reach - b * b) / (2.0 * a * reach), -1.0, 1.0)
	var elbow := top.origin + dir * (a * cos_a) + bend * (a * sqrt(1.0 - cos_a * cos_a))
	top.basis = Basis(Quaternion((middle - top.origin).normalized(), (elbow - top.origin).normalized())) * top.basis
	skeleton.set_bone_global_pose(upper, top)
	var low := skeleton.get_bone_global_pose(lower)
	tip = skeleton.get_bone_global_pose(end).origin
	var wrist := top.origin + dir * reach
	low.basis = Basis(Quaternion((tip - low.origin).normalized(), (wrist - low.origin).normalized())) * low.basis
	skeleton.set_bone_global_pose(lower, low)
