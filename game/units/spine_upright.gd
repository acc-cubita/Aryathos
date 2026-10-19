class_name SpineUpright
extends SkeletonModifier3D
## Keeps a moving warrior's bearing. The library's run clips throw the torso about: the
## sprint leans it far forward, and the jog rocks it 38 degrees from side to side (a
## child's run, not a warrior's). After the animation this measures the torso (hips to
## neck) and turns the spine and chest back until it leans forward no more than MAX_LEAN
## and sways no more than MAX_SWAY, its shoulders turn no more than MAX_TWIST, then levels
## the head. `weight` (0..1) fades the lean
## in with running speed; `sway_weight` the sway and the head while the character moves
## on the ground, so standing, swings and death keep the clip's own posture.

## Forward lean (radians) left to a runner.
const MAX_LEAN := deg_to_rad(15.0)
## Side to side sway (radians) left to anyone moving.
const MAX_SWAY := deg_to_rad(4.0)
## How far the shoulders may turn back and forth (radians): the jog swings them 40
## degrees each way, the two halves of the body see-sawing.
const MAX_TWIST := deg_to_rad(12.0)
## On the move the torso holds this forward lean (radians, hips to neck; standing it is
## 15-20): the jog rocks it 17-27 degrees at every step.
const LEAN_BAND := Vector2(deg_to_rad(10.0), deg_to_rad(24.0))
## And the pelvis stays level and square (radians): no rolling of the hips.
const PELVIS_TILT := deg_to_rad(1.0)
const PELVIS_TURN := deg_to_rad(3.0)
## Share of the straightening done by each bone, from the waist up.
const BONES := {"Spine": 0.5, "Chest": 0.5}

var weight := 0.0
var sway_weight := 0.0
## The torso's forward lean (radians) as last posed, after straightening.
var leaning := 0.0
## And its sideways tilt (radians, + toward the rig's left), and the shoulders' turn.
var swaying := 0.0
var twisting := 0.0

var _hips := -1
var _neck := -1
var _head := -1
var _shoulders := [-1, -1]  # left, right upper arms
var _hips_side := Vector3.RIGHT  # the rig's side axis in the hips bone's frame
var _shares := {}  # bone index -> share


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_hips = skeleton.find_bone("Hips")
	_neck = skeleton.find_bone("Neck")
	_head = skeleton.find_bone("Head")
	_shoulders = [skeleton.find_bone("LeftUpperArm"), skeleton.find_bone("RightUpperArm")]
	_hips_side = (skeleton.get_bone_global_rest(_hips).basis.inverse() * Vector3.RIGHT).normalized()
	for bone_name: String in BONES:
		_shares[skeleton.find_bone(bone_name)] = BONES[bone_name]


## The torso (hips to neck) in the current pose, in the rig's frame (it faces +Z, its
## left is +X).
func _torso() -> Vector3:
	var skeleton := get_skeleton()
	return skeleton.get_bone_global_pose(_neck).origin - skeleton.get_bone_global_pose(_hips).origin


## Forward lean of the torso in the current pose (radians).
func lean() -> float:
	var torso := _torso()
	return atan2(torso.z, torso.y)


## How far the shoulder line is turned from square (radians; + the left shoulder ahead).
func twist() -> float:
	var skeleton := get_skeleton()
	var line := skeleton.get_bone_global_pose(_shoulders[0]).origin - skeleton.get_bone_global_pose(_shoulders[1]).origin
	return atan2(line.z, line.x)


## Sideways tilt of the torso in the current pose (radians).
func sway() -> float:
	var torso := _torso()
	return atan2(torso.x, torso.y)


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or _hips < 0 or _neck < 0:
		return
	if weight > 0.0:
		# only a forward lean is too much; leaning back stays as the clip has it
		var now := lean()
		_straighten(skeleton, lean, lerpf(now, minf(now, MAX_LEAN), weight), Vector3.RIGHT, -1.0)
	if sway_weight > 0.0:
		# pelvis, then the twist (turning about the vertical swings a leaning torso's lean),
		# then the lean, then the sway
		_steady_pelvis(skeleton)
		var turned := twist()
		_straighten(skeleton, twist, lerpf(turned, clampf(turned, -MAX_TWIST, MAX_TWIST), sway_weight), Vector3.UP, 1.0)
		var leaning_now := lean()
		_straighten(skeleton, lean, lerpf(leaning_now, clampf(leaning_now, LEAN_BAND.x, LEAN_BAND.y), sway_weight), Vector3.RIGHT, -1.0)
		var now := sway()
		_straighten(skeleton, sway, lerpf(now, clampf(now, -MAX_SWAY, MAX_SWAY), sway_weight), Vector3.BACK, 1.0)
		# and the head level, whatever the shoulders do
		var head := skeleton.get_bone_global_pose(_head)
		var tilt := atan2(head.basis.y.x, head.basis.y.y) * sway_weight
		var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(_head))
		skeleton.set_bone_pose_rotation(_head, (parent.basis.inverse() * (Basis(Vector3.BACK, tilt) * head.basis)).get_rotation_quaternion())
	leaning = lean()
	swaying = sway()
	twisting = twist()


## The hips level and square: their tilt and turn (of the rig's side axis) held within
## PELVIS_TILT and PELVIS_TURN, turning about the hips' own joint.
func _steady_pelvis(skeleton: Skeleton3D) -> void:
	var hips := skeleton.get_bone_global_pose(_hips)
	var side := hips.basis * _hips_side
	var tilt := atan2(side.y, Vector2(side.x, side.z).length())
	var turn := atan2(side.z, side.x)
	# the side axis tips up toward +Y by a turn about +Z (the rig's ahead); swings toward
	# +Z by a turn about -Y
	var fix := Basis(Vector3.BACK, -(tilt - clampf(tilt, -PELVIS_TILT, PELVIS_TILT)) * sway_weight) 			* Basis(Vector3.UP, (turn - clampf(turn, -PELVIS_TURN, PELVIS_TURN)) * sway_weight)
	hips.basis = fix * hips.basis
	skeleton.set_bone_global_pose(_hips, hips)


## Turns the spine and chest about `axis` (through their own joints) until measure()
## comes to `target`; `sense` says which way round undoes a positive measure. The bones
## turn above the hips, so the hips-to-neck line straightens less than they turn: a few
## passes (each turning a third more than the gap) close it.
func _straighten(skeleton: Skeleton3D, measure: Callable, target: float, axis: Vector3, sense: float) -> void:
	for attempt in 6:
		var excess: float = measure.call() - target
		if absf(excess) < deg_to_rad(0.5):
			break
		for bone: int in _shares:
			var pose := skeleton.get_bone_global_pose(bone)
			var straightened := Basis(axis, sense * excess * 1.3 * _shares[bone]) * pose.basis
			var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone))
			skeleton.set_bone_pose_rotation(bone, (parent.basis.inverse() * straightened).get_rotation_quaternion())
