class_name SpineUpright
extends SkeletonModifier3D
## Keeps a moving warrior's bearing. The library's run clips throw the torso about: the
## sprint leans it far forward, and the jog rocks it 38 degrees from side to side (a
## child's run, not a warrior's). After the animation this measures the torso (hips to
## neck) and turns the spine and chest back until it leans forward no more than MAX_LEAN
## and sways no more than MAX_SWAY, then levels the head. `weight` (0..1) fades the lean
## in with running speed; `sway_weight` the sway and the head while the character moves
## on the ground, so standing, swings and death keep the clip's own posture.

## Forward lean (radians) left to a runner.
const MAX_LEAN := deg_to_rad(15.0)
## Side to side sway (radians) left to anyone moving.
const MAX_SWAY := deg_to_rad(4.0)
## Share of the straightening done by each bone, from the waist up.
const BONES := {"Spine": 0.5, "Chest": 0.5}

var weight := 0.0
var sway_weight := 0.0
## The torso's forward lean (radians) as last posed, after straightening.
var leaning := 0.0
## And its sideways tilt (radians, + toward the rig's left).
var swaying := 0.0

var _hips := -1
var _neck := -1
var _head := -1
var _shares := {}  # bone index -> share


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_hips = skeleton.find_bone("Hips")
	_neck = skeleton.find_bone("Neck")
	_head = skeleton.find_bone("Head")
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
		var now := sway()
		_straighten(skeleton, sway, lerpf(now, clampf(now, -MAX_SWAY, MAX_SWAY), sway_weight), Vector3.BACK, 1.0)
		# and the head level, whatever the shoulders do
		var head := skeleton.get_bone_global_pose(_head)
		var tilt := atan2(head.basis.y.x, head.basis.y.y) * sway_weight
		var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(_head))
		skeleton.set_bone_pose_rotation(_head, (parent.basis.inverse() * (Basis(Vector3.BACK, tilt) * head.basis)).get_rotation_quaternion())
	leaning = lean()
	swaying = sway()


## Turns the spine and chest about `axis` (through their own joints) until measure()
## comes to `target`; `sense` says which way round undoes a positive measure. The bones
## turn above the hips, so the hips-to-neck line straightens less than they turn: a few
## passes close the gap.
func _straighten(skeleton: Skeleton3D, measure: Callable, target: float, axis: Vector3, sense: float) -> void:
	for attempt in 3:
		var excess: float = measure.call() - target
		if absf(excess) < deg_to_rad(0.5):
			break
		for bone: int in _shares:
			var pose := skeleton.get_bone_global_pose(bone)
			var straightened := Basis(axis, sense * excess * _shares[bone]) * pose.basis
			var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone))
			skeleton.set_bone_pose_rotation(bone, (parent.basis.inverse() * straightened).get_rotation_quaternion())
