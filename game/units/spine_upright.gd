class_name SpineUpright
extends SkeletonModifier3D
## Straightens a running torso. The sprint clip leans the body far forward, a sprinter
## at full stretch; a hero running at an easy pace should stay upright. After the
## animation, this measures how far the torso (hips to neck) leans forward and turns the
## spine and chest back until it leans no more than MAX_LEAN. `weight` (0..1) fades it in
## with running speed, so standing, walking, swings and death keep the clip's posture.

## Forward lean (radians) left to a runner.
const MAX_LEAN := deg_to_rad(15.0)
## Share of the straightening done by each bone, from the waist up.
const BONES := {"Spine": 0.5, "Chest": 0.5}

var weight := 0.0
## The torso's forward lean (radians) as last posed, after straightening.
var leaning := 0.0

var _hips := -1
var _neck := -1
var _shares := {}  # bone index -> share


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_hips = skeleton.find_bone("Hips")
	_neck = skeleton.find_bone("Neck")
	for bone_name: String in BONES:
		_shares[skeleton.find_bone(bone_name)] = BONES[bone_name]


## Forward lean of the torso in the current pose (radians; the rig faces +Z, so leaning
## forward tips the hips-to-neck line from +Y toward +Z).
func lean() -> float:
	var skeleton := get_skeleton()
	var torso := skeleton.get_bone_global_pose(_neck).origin - skeleton.get_bone_global_pose(_hips).origin
	return atan2(torso.z, torso.y)


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or _hips < 0 or _neck < 0:
		return
	if weight <= 0.0:
		leaning = lean()
		return
	var target := lerpf(lean(), minf(lean(), MAX_LEAN), weight)
	# the bones turn about their own joints, above the hips, so the hips-to-neck line
	# straightens less than they turn: a few passes close the gap
	for attempt in 3:
		var excess := lean() - target
		if excess < deg_to_rad(0.5):
			break
		for bone: int in _shares:
			# turn the bone back about the rig's side axis, through its own joint
			var pose := skeleton.get_bone_global_pose(bone)
			var straightened := Basis(Vector3.RIGHT, -excess * _shares[bone]) * pose.basis
			var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone))
			skeleton.set_bone_pose_rotation(bone, (parent.basis.inverse() * straightened).get_rotation_quaternion())
	leaning = lean()
