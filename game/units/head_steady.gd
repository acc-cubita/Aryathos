class_name HeadSteady
extends SkeletonModifier3D
## Holds a head steady, as a warrior's is. The library's clips nod it 13-17 degrees and
## tilt it at every step: a twitch. After the look-at (so it still turns to what the
## character watches), this keeps the head's look low-passed in the body's frame (slow
## turns pass, the per-step jolts do not) and the head level with the world.

## How fast (1/s) the steady look follows the head's own: lower is calmer.
const FOLLOW := 5.0

## 0..1: dead characters' heads go where the clip takes them.
var weight := 1.0

var _head := -1
var _face := Vector3.BACK  # the way the face looks, in the head bone's frame
var _crown := Vector3.UP  # and up through the crown
var _look := Vector3.ZERO  # the steady look, skeleton space


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_head = skeleton.find_bone("Head")
	# the rig faces +Z: at rest the face looks that way, the crown up
	var rest := skeleton.get_bone_global_rest(_head).basis.inverse()
	_face = (rest * Vector3.BACK).normalized()
	_crown = (rest * Vector3.UP).normalized()


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or _head < 0 or weight <= 0.0:
		_look = Vector3.ZERO
		return
	var head := skeleton.get_bone_global_pose(_head)
	var look := (head.basis * _face).normalized()
	var crown := (head.basis * _crown).normalized()
	_look = look if _look == Vector3.ZERO else _look.slerp(look, 1.0 - exp(-FOLLOW * delta)).normalized()
	var level := (skeleton.global_transform.basis.inverse() * Vector3.UP).normalized()
	var turn := _frame(_look, level) * _frame(look, crown).inverse()
	var steady := head.basis.slerp(turn * head.basis, weight)
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(_head))
	skeleton.set_bone_pose_rotation(_head, (parent.basis.inverse() * steady).get_rotation_quaternion())


## An orthonormal frame looking along `ahead` with `up` as near its up as it can be.
static func _frame(ahead: Vector3, up: Vector3) -> Basis:
	var forward := ahead.normalized()
	var top := (up - forward * up.dot(forward)).normalized()
	return Basis(top.cross(forward), top, forward)
