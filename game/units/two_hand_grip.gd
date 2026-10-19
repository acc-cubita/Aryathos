class_name TwoHandGrip
extends SkeletonModifier3D
## Both hands on a two-handed weapon's haft, held ready (WoW's two-handed stance): the
## right fist low at the right hip, the haft rising up and out to the right, the left fist
## just above the right. Each arm reaches its fist's place by two-bone IK, the hands turned
## so the weapon (carried by the right hand) lies along the haft, edge to the front, so it
## fits any build. `weight` (0..1) fades it in and out (a swing takes the arms).

## In the rig's frame (it faces +Z, its left is +X), from the hips: where the right fist's
## grip is, which way the haft rises, which way the edge looks.
const GRIP := Vector3(-0.22, 0.0, 0.22)
const HAFT := Vector3(-0.5, 0.85, 0.12)
const EDGE := Vector3(0.0, 0.0, 1.0)
## How far up the haft (m) the left fist holds, above the right.
const LEFT_UP := 0.13
## Which way each elbow bends: the right out and back, the left down across the body.
const RIGHT_POLE := Vector3(-1.0, -0.4, -0.6)
const LEFT_POLE := Vector3(0.6, -1.0, 0.1)

var weight := 0.0
## The weapon in the right hand's frame (CharacterModel._in_hand).
var in_hand := Transform3D.IDENTITY

var _hips := -1
var _arms := {}  # side -> [upper arm, lower arm, hand]
var _left_in_hand := Transform3D.IDENTITY  # the left fist's grip, as the weapon would sit in it


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_hips = skeleton.find_bone("Hips")
	for side: String in ["Left", "Right"]:
		_arms[side] = [skeleton.find_bone(side + "UpperArm"), skeleton.find_bone(side + "LowerArm"), skeleton.find_bone(side + "Hand")]
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
	if skeleton == null or weight <= 0.0 or _hips < 0:
		return
	# the rig's frame as the hips carry it (their turn and lean), at the hips
	var hips := skeleton.get_bone_global_pose(_hips)
	var body := hips.basis.orthonormalized() * skeleton.get_bone_global_rest(_hips).basis.orthonormalized().inverse()
	var haft := (body * HAFT).normalized()
	var edge := body * EDGE
	edge = (edge - haft * edge.dot(haft)).normalized()
	var weapon := Basis(haft.cross(-edge), haft, -edge)
	var right_grip := hips.origin + body * GRIP
	_hold(skeleton, "Right", Transform3D(weapon, right_grip), in_hand, body * RIGHT_POLE)
	_hold(skeleton, "Left", Transform3D(weapon, right_grip + haft * LEFT_UP), _left_in_hand, body * LEFT_POLE)



## One arm: its hand turned and brought so that `held` (a grip frame in the hand's frame)
## comes to `grip`, the elbow bending toward `pole`; all by `weight`.
func _hold(skeleton: Skeleton3D, side: String, grip: Transform3D, held: Transform3D, pole: Vector3) -> void:
	var bones: Array = _arms[side]
	var hand := skeleton.get_bone_global_pose(bones[2])
	var scale := hand.basis.get_scale()
	var turned := Basis((grip.basis * held.basis.orthonormalized().inverse()).get_rotation_quaternion())
	var wrist := grip.origin - turned.scaled(scale) * held.origin
	var now := hand.basis.get_rotation_quaternion()
	var want := now.slerp(turned.get_rotation_quaternion(), weight)
	_reach(skeleton, bones[0], bones[1], bones[2], hand.origin.lerp(wrist, weight), pole)
	var posed := skeleton.get_bone_global_pose(bones[2])
	skeleton.set_bone_global_pose(bones[2], Transform3D(Basis(want).scaled(scale), posed.origin))


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
