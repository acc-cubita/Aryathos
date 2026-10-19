class_name Fists
extends SkeletonModifier3D
## Closes the hands into fists, whatever the clip does with the fingers: each finger joint
## turns from its rest about the joint's bending axis (the clips' finger tracks barely close
## the MakeHuman hands once retargeted). `left` and `right` (0..1) say how closed each hand
## is: a weapon hand keeps the grip its clip gives it, hands open to cast.

const FINGERS := ["Index", "Middle", "Ring", "Little"]
## Degrees each joint of a finger turns in a full fist (proximal, intermediate, distal).
const CURL := [70.0, 95.0, 60.0]
const THUMB_CURL := [25.0, 35.0]
## The rest bone axis a finger bends about, and which way round closes it (found by eye).
const AXIS := Vector3.RIGHT
const SENSE := 1.0

var left := 1.0
var right := 1.0

var _joints := {"Left": [], "Right": []}  # [bone, degrees]


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for side: String in _joints:
		for finger: String in FINGERS:
			for i in 3:
				var bone := skeleton.find_bone(side + finger + ["Proximal", "Intermediate", "Distal"][i])
				if bone >= 0:
					_joints[side].append([bone, CURL[i]])
		for i in 2:
			var bone := skeleton.find_bone(side + "Thumb" + ["Proximal", "Distal"][i])
			if bone >= 0:
				_joints[side].append([bone, THUMB_CURL[i]])


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for side: String in _joints:
		var amount := left if side == "Left" else right
		if amount <= 0.0:
			continue
		for joint: Array in _joints[side]:
			var rest := skeleton.get_bone_rest(joint[0]).basis.get_rotation_quaternion()
			var curl := Quaternion(AXIS, deg_to_rad(joint[1]) * SENSE * amount)
			var now := skeleton.get_bone_pose_rotation(joint[0])
			skeleton.set_bone_pose_rotation(joint[0], now.slerp(rest * curl, amount))
