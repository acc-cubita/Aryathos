class_name FootPlanter
extends SkeletonModifier3D
## Plants an animated character's feet on uneven ground. The clips are made for a flat
## floor at the unit's feet, so on a slope one foot sinks into the hill and the other
## hangs in the air. After the animation is applied, this measures the ground under each
## foot, lowers the hips as far as the lower foot needs, and bends each leg (two-bone IK
## about the knee the clip already bends) so the foot keeps its height above the real
## ground. Each foot tilts to lie along the slope under it.

const LEGS := [["LeftUpperLeg", "LeftLowerLeg", "LeftFoot"], ["RightUpperLeg", "RightLowerLeg", "RightFoot"]]
## Highest step (m) the feet follow up or down; beyond it they stay where the clip puts them.
const MAX_STEP := 0.4
## How fast (1/s) the hips and feet follow a change of ground.
const FOLLOW := 12.0
## Share of the hips' rise and fall the run keeps (settle_weight fades this in while the
## character moves): the jog bounces them 26 cm, a leap at every step. The feet keep their
## heights, the legs folding or reaching to the calmer hips.
const BOB_KEEP := 0.4

## The unit standing on the ground (its origin is at its feet); null turns planting off.
var unit: Unit
var settle_weight := 0.0

var _bones: Array[PackedInt32Array] = []
var _hips := -1
var _offsets := [0.0, 0.0]
var _normals := [Vector3.UP, Vector3.UP]  # ground normal under each foot (world)
var _drop := 0.0
var _hips_mean := NAN  # the hips' height, averaged over the steps
## The hips' height as last posed (skeleton space, after settling).
var settled_height := 0.0


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for leg: Array in LEGS:
		_bones.append(PackedInt32Array([skeleton.find_bone(leg[0]), skeleton.find_bone(leg[1]), skeleton.find_bone(leg[2])]))
	_hips = skeleton.find_bone("Hips")


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or unit == null or _hips < 0:
		return
	# standing or walking on the ground (not dead, not in the air)
	var grounded := not unit.is_dead and absf(unit.velocity.y) < 0.5
	var to_world := skeleton.global_transform
	var up := (to_world.basis.inverse() * Vector3.UP).normalized()
	var base := unit.global_position.y
	var space := skeleton.get_world_3d().direct_space_state
	var follow := 1.0 - exp(-FOLLOW * delta)
	# how far the ground under each foot lies above (+) or below (-) the unit's own floor
	for side in 2:
		var want := 0.0
		var normal := Vector3.UP
		if grounded:
			var foot := to_world * skeleton.get_bone_global_pose(_bones[side][2]).origin
			var query := PhysicsRayQueryParameters3D.create(foot + Vector3.UP * MAX_STEP, foot - Vector3.UP * (MAX_STEP + 0.6), Unit.LAYER_WORLD)
			var hit := space.intersect_ray(query)
			if hit:
				want = clampf(float(hit.position.y) - base, -MAX_STEP, MAX_STEP)
				normal = hit.normal
		_offsets[side] = lerpf(_offsets[side], want, follow)
		_normals[side] = (_normals[side] as Vector3).lerp(normal, follow).normalized()
	# the hips come down as far as the lower foot needs; the higher leg folds
	_drop = lerpf(_drop, minf(minf(_offsets[0], _offsets[1]), 0.0), follow)
	var hips := skeleton.get_bone_global_pose(_hips)
	var height := hips.origin.dot(up)
	_hips_mean = height if is_nan(_hips_mean) else lerpf(_hips_mean, height, 1.0 - exp(-2.0 * delta))
	var settle := (_hips_mean - height) * (1.0 - BOB_KEEP) * settle_weight
	var lift := _drop + settle
	settled_height = height + lift
	if absf(lift) + absf(_offsets[0]) + absf(_offsets[1]) < 0.002 and _normals[0].y > 0.999 and _normals[1].y > 0.999:
		return
	hips.origin += up * lift
	skeleton.set_bone_global_pose(_hips, hips)
	for side in 2:
		# the leg already moved with the hips
		var tilt := _turn(up, to_world.basis.inverse() * (_normals[side] as Vector3))
		_place_foot(skeleton, _bones[side], up * (_offsets[side] - lift), tilt)


## Moves the foot by `shift` (skeleton space) from where the clip put it
## and tilts it by `tilt` (the turn from flat ground to the slope under it).
func _place_foot(skeleton: Skeleton3D, leg: PackedInt32Array, shift: Vector3, tilt: Basis) -> void:
	var upper := skeleton.get_bone_global_pose(leg[0])
	var lower := skeleton.get_bone_global_pose(leg[1])
	var foot := skeleton.get_bone_global_pose(leg[2])
	var a := upper.origin
	var b := lower.origin
	var c := foot.origin
	var target := c + shift
	var thigh := a.distance_to(b)
	var shin := b.distance_to(c)
	var reach := target - a
	var d := clampf(reach.length(), absf(thigh - shin) + 0.001, thigh + shin - 0.001)
	var along := reach.normalized()
	# the knee bends the way the clip bends it
	var bend := (b - a) - along * (b - a).dot(along)
	if bend.length_squared() < 1e-8:
		bend = (upper.basis * Vector3.FORWARD).normalized()
	bend = bend.normalized()
	var cos_a := clampf((thigh * thigh + d * d - shin * shin) / (2.0 * thigh * d), -1.0, 1.0)
	var knee := a + along * thigh * cos_a + bend * thigh * sqrt(1.0 - cos_a * cos_a)
	var turn_upper := _turn(b - a, knee - a)
	var new_upper := Transform3D(turn_upper * upper.basis, a)
	var new_lower_basis := turn_upper * lower.basis
	var end := a + along * d
	var turn_lower := _turn(turn_upper * (c - b), end - knee)
	skeleton.set_bone_global_pose(leg[0], new_upper)
	skeleton.set_bone_global_pose(leg[1], Transform3D(turn_lower * new_lower_basis, knee))
	skeleton.set_bone_global_pose(leg[2], Transform3D(tilt * foot.basis, end))


## The shortest rotation taking direction `from` onto direction `to`.
static func _turn(from: Vector3, to: Vector3) -> Basis:
	var f := from.normalized()
	var t := to.normalized()
	var axis := f.cross(t)
	if axis.length_squared() < 1e-10:
		return Basis.IDENTITY
	return Basis(axis.normalized(), acos(clampf(f.dot(t), -1.0, 1.0)))
