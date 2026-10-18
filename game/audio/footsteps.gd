class_name Footsteps
extends RefCounted
## Hears an animated model's feet: a foot that has lifted off makes a step where it lands
## (Audio.step), as soon as it is back down at the height it last stood at; on a rising
## slope, where it lands higher than that, the step comes when it starts its next lift.
## Only worked out while the unit moves on the ground and the camera is close enough.

## A foot is off the ground this far (m) above where it last stood, and down again within
## CONTACT of it; LATE is how far it rises from its lowest before a missed landing counts.
const LIFT := 0.06
const CONTACT := 0.04
const LATE := 0.03
## A landing so far above its last stand is no landing (the foot only paused in the air).
const NEAR := 0.22
## Each frame the height follows the bone this much (smooths out the pose's jitter).
const SMOOTH := 0.6
## Steps are only listened for this close (m) to the camera.
const RANGE := 25.0

var _bones := PackedInt32Array()
var _heights := PackedFloat32Array()
var _stood := PackedFloat32Array()
var _peak := PackedFloat32Array()
var _lowest := PackedFloat32Array()  # since the peak
var _lifted: Array[bool] = []
var _started := false


## feet: the bones that touch the ground (ankles, paws).
func _init(skeleton: Skeleton3D, feet: Array) -> void:
	for foot: String in feet:
		var bone := skeleton.find_bone(foot)
		if bone >= 0:
			_bones.append(bone)
	_heights.resize(_bones.size())
	_stood.resize(_bones.size())
	_peak.resize(_bones.size())
	_lowest.resize(_bones.size())
	_lifted.resize(_bones.size())
	_lifted.fill(false)


func update(skeleton: Skeleton3D, unit: Unit, _delta: float) -> void:
	if Vector2(unit.velocity.x, unit.velocity.z).length() < 0.3 or not unit.is_on_floor():
		_started = false
		return
	var camera := skeleton.get_viewport().get_camera_3d()
	if camera != null and camera.global_position.distance_squared_to(unit.global_position) > RANGE * RANGE:
		_started = false
		return
	var base := unit.global_position.y
	for i in _bones.size():
		var at := skeleton.global_transform * skeleton.get_bone_global_pose(_bones[i]).origin
		var raw := at.y - base
		if not _started:
			_heights[i] = raw
			_stood[i] = raw
			_lifted[i] = false
		var height := lerpf(_heights[i], raw, SMOOTH)
		_heights[i] = height
		if not _lifted[i]:
			if height > _stood[i] + LIFT:
				_lifted[i] = true
				_peak[i] = height
				_lowest[i] = height
			else:
				_stood[i] = minf(_stood[i], height)
		else:
			if height > _peak[i]:
				_peak[i] = height
				_lowest[i] = height
			_lowest[i] = minf(_lowest[i], height)
			var down := height < _stood[i] + CONTACT
			# came well down from its peak and is rising again: it stood, higher than before
			var late := height > _lowest[i] + LATE and _peak[i] - _lowest[i] > LIFT and _lowest[i] < _stood[i] + NEAR
			if down or late:
				_lifted[i] = false
				_stood[i] = height if down else _lowest[i]
				Audio.step(unit, at)
	_started = true
