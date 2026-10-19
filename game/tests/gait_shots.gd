extends Node
## Film strips of the hero's gaits, seen from the side, and how far the planted foot
## slides (m/s; 0 when the clip's pace matches the ground speed). Run:
##   Godot.exe --path game -- --gait-shots=<output folder> [--gaits=run,strafe,...] [--hero=<class>[,female]]
## Saves <gait>_<frame>.png, frames 1/12 s apart.

## gait: actions held
const GAITS := {
	"run": ["move_forward"],
	"strafe": ["strafe_right"],
	"diagonal": ["move_forward", "strafe_right"],
	"back": ["move_back"],
	"back_diagonal": ["move_back", "strafe_right"],
	"walk": ["move_forward"],  # with walking on
	"turn": ["turn_left"],     # turning on the spot
	"jump": ["move_forward"],  # a running jump
	"stand": [],  # standing, seen from behind (the sheathed weapon)
	"run_front": ["move_forward"],  # running, seen from ahead (the sway)
	"run_close": ["move_forward"],  # running, close beside (the hands)
	"run_back": ["move_forward"],  # running, seen from behind
	"stand_front": [],  # standing, seen from ahead (the build of the body)
	"stand_side": [],  # standing, seen from the side (the shoulders over the chest)
	"ready_front": [],  # the weapon out, held ready, seen from ahead
	"ready_side": [],  # and from the side
	"strike_front": [],  # a swing from the ready stance, seen from ahead
	"strike_side": [],  # and from the side
	"ready_close": [],  # held ready, close, from ahead and to its left (the arms by the body)
	"strike_close": [],  # a swing, close, from ahead and to its left
	"ready_rclose": [],  # held ready, close, from ahead and to its right
}
const FRAMES := 16
const START := Vector3(-4, 0, -24)  # on the road north of the camp, open ground ahead

var _camera := Camera3D.new()
var _gait := ""


## Reads the head as finally posed (last of the skeleton's modifiers): its nod (pitch),
## turn (yaw), tilt (roll) in the rig's frame (deg) and its height, every frame.
class HeadProbe extends SkeletonModifier3D:
	var samples: Array[Vector4] = []
	## and the body: torso lean (deg), pelvis tilt and turn (deg)
	var body: Array[Vector3] = []

	func _process_modification() -> void:
		var skeleton := get_skeleton()
		var bone := skeleton.find_bone("Head")
		var head := skeleton.get_bone_global_pose(bone)
		var rest := skeleton.get_bone_global_rest(bone).basis.inverse()
		var ahead := head.basis * (rest * Vector3.BACK)  # the face (the rig faces +Z)
		var up := head.basis * (rest * Vector3.UP)
		samples.append(Vector4(rad_to_deg(atan2(up.z, up.y)), rad_to_deg(atan2(ahead.x, ahead.z)),
				rad_to_deg(atan2(up.x, up.y)), head.origin.y))
		var hips_bone := skeleton.find_bone("Hips")
		var hips := skeleton.get_bone_global_pose(hips_bone)
		var torso := skeleton.get_bone_global_pose(skeleton.find_bone("Neck")).origin - hips.origin
		var side := hips.basis * (skeleton.get_bone_global_rest(hips_bone).basis.inverse() * Vector3.RIGHT)
		body.append(Vector3(rad_to_deg(atan2(torso.z, torso.y)), rad_to_deg(atan2(side.y, Vector2(side.x, side.z).length())),
				rad_to_deg(atan2(side.z, side.x))))


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var folder := "res://tests/output/gaits"
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--gait-shots="):
			folder = arg.get_slice("=", 1)
		if arg.begins_with("--gaits="):
			only = arg.get_slice("=", 1).split(",")
	DirAccess.make_dir_recursive_absolute(folder)
	if Game.zone == null:
		await Game.zone_ready
	Game.zone.hud.visible = false
	if OS.get_cmdline_user_args().has("--clip-phases"):
		_clip_phases()
		get_tree().quit()
		return
	var player := Game.player
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hero="):  # <class>[,female]
			var parts := arg.get_slice("=", 1).split(",")
			player.set_class(Database.hero_class(StringName(parts[0])))
			if parts.has("female"):
				player.set_look({"gender": "female"})
	get_tree().root.add_child(_camera)
	_camera.fov = 40.0
	_camera.make_current()
	for gait: String in GAITS:
		if not only.is_empty() and not only.has(gait):
			continue
		_gait = gait
		var spot := START
		spot.y = Game.zone.terrain.get_height(spot.x, spot.z) + 0.1
		player.teleport(spot, 0.0)
		if gait == "walk" and player.has_method("set_walking"):
			player.set_walking(true)
		player.model._drawn_until = Game.time + 60.0 if gait.begins_with("ready") or gait.begins_with("strike") else -1.0
		await _wait(0.4)
		for action: String in GAITS[gait]:
			Input.action_press(action)
		await _wait(0.9)
		if gait == "jump":
			var leap := InputEventAction.new()  # (the hero jumps on the key's event)
			leap.action = "jump"
			leap.pressed = true
			Input.parse_input_event(leap)
		if gait.begins_with("strike"):
			Engine.time_scale = 0.25  # slow motion: a swing is over in a few frames
			player.model._on_attacked()  # (as a swing of the auto attack would)
		var probe := HeadProbe.new()
		player.model._skeleton.add_child(probe)
		var sways := Vector2(INF, -INF)
		var bends := Vector2(INF, -INF)
		var drops := Vector2(INF, -INF)
		var shoulders := Vector2(INF, -INF)
		var pelvis := Vector2(INF, -INF)
		var spread := 0.0
		var bob := Vector2(INF, -INF)
		var raw_bob := Vector2(INF, -INF)
		var inner_lean := Vector2(INF, -INF)
		var drops_range := Vector2(INF, -INF)
		var slides := PackedFloat32Array()
		for frame in FRAMES:
			await _follow(player, 1.0 / 12.0, slides)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(folder.path_join("%s_%d.png" % [gait, frame]))
			var tilt := rad_to_deg(player.model._upright.swaying)
			sways = Vector2(minf(sways.x, tilt), maxf(sways.y, tilt))
			var skeleton: Skeleton3D = player.model._skeleton
			for side: String in ["Left", "Right"]:
				var upper := skeleton.get_bone_global_pose(skeleton.find_bone(side + "UpperArm")).origin
				var elbow := skeleton.get_bone_global_pose(skeleton.find_bone(side + "LowerArm")).origin
				var wrist := skeleton.get_bone_global_pose(skeleton.find_bone(side + "Hand")).origin
				var angle := rad_to_deg((elbow - upper).angle_to(wrist - elbow))
				bends = Vector2(minf(bends.x, angle), maxf(bends.y, angle))
				drops = Vector2(minf(drops.x, upper.y - wrist.y), maxf(drops.y, upper.y - wrist.y))
			# how far the halves of the body turn back and forth (yaw of the shoulder line and
			# of the hips' side axis, in the rig, which faces +Z), how far apart the feet get
			# (along the way), how much the hips rise and fall
			var line := skeleton.get_bone_global_pose(skeleton.find_bone("LeftUpperArm")).origin 					- skeleton.get_bone_global_pose(skeleton.find_bone("RightUpperArm")).origin
			var yaw := rad_to_deg(player.model._upright.twisting)  # (as posed: read after the modifiers)
			shoulders = Vector2(minf(shoulders.x, yaw), maxf(shoulders.y, yaw))
			var hip_axis := skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).basis * Vector3.RIGHT
			var hip_yaw := rad_to_deg(atan2(hip_axis.z, hip_axis.x))
			pelvis = Vector2(minf(pelvis.x, hip_yaw), maxf(pelvis.y, hip_yaw))
			var feet := skeleton.get_bone_global_pose(skeleton.find_bone("LeftFoot")).origin 					- skeleton.get_bone_global_pose(skeleton.find_bone("RightFoot")).origin
			spread = maxf(spread, absf(feet.z))
			var hip_y: float = player.model._planter.settled_height
			bob = Vector2(minf(bob.x, hip_y), maxf(bob.y, hip_y))
			var raw_y: float = player.model._planter.raw_height
			var ground_drop: float = player.model._planter._drop
			drops_range = Vector2(minf(drops_range.x, ground_drop), maxf(drops_range.y, ground_drop))
			var inner := rad_to_deg(player.model._upright.leaning)
			inner_lean = Vector2(minf(inner_lean.x, inner), maxf(inner_lean.y, inner))
			raw_bob = Vector2(minf(raw_bob.x, raw_y), maxf(raw_bob.y, raw_y))
		Engine.time_scale = 1.0
		for action: String in GAITS[gait]:
			Input.action_release(action)
		if player.has_method("set_walking"):
			player.set_walking(false)
		var slide := 0.0
		for s in slides:
			slide += s
		print("gait %s: speed %.1f m/s, torso sway %.1f..%.1f deg, elbows %.0f..%.0f deg, hands %.2f..%.2f m below shoulders, state %s" % [gait,
				Vector2(player.velocity.x, player.velocity.z).length(), sways.x, sways.y, bends.x, bends.y, drops.x, drops.y, player.model._state])
		print("    body: shoulders turn %.0f..%.0f deg, hips %.0f..%.0f deg, feet up to %.2f m apart, hips bob %.2f m (clip %.2f, %.2f..%.2f)" % [
				shoulders.x, shoulders.y, pelvis.x, pelvis.y, spread, bob.y - bob.x, raw_bob.y - raw_bob.x, raw_bob.x, raw_bob.y])
		# the head: how far each angle ranges, and how jerky it is (mean change per frame)
		var lo := Vector4(INF, INF, INF, INF)
		var hi := Vector4(-INF, -INF, -INF, -INF)
		var jerk := Vector4.ZERO
		for i in probe.samples.size():
			lo = lo.min(probe.samples[i])
			hi = hi.max(probe.samples[i])
			if i > 0:
				jerk += (probe.samples[i] - probe.samples[i - 1]).abs()
		jerk /= maxf(probe.samples.size() - 1, 1)
		print("    head: nod %.1f..%.1f, turn %.1f..%.1f, tilt %.1f..%.1f deg, height %.3f m; per frame %.2f / %.2f / %.2f deg, %.4f m" % [
				lo.x, hi.x, lo.y, hi.y, lo.z, hi.z, hi.w - lo.w, jerk.x, jerk.y, jerk.z, jerk.w])
		var b_lo := Vector3(INF, INF, INF)
		var b_hi := Vector3(-INF, -INF, -INF)
		for v: Vector3 in probe.body:
			b_lo = b_lo.min(v)
			b_hi = b_hi.max(v)
		print("    posed body: torso lean %.1f..%.1f, pelvis tilt %.1f..%.1f, pelvis turn %.1f..%.1f deg" % [
				b_lo.x, b_hi.x, b_lo.y, b_hi.y, b_lo.z, b_hi.z])
		var sk: Skeleton3D = player.model._skeleton
		var rest_torso := sk.get_bone_global_rest(sk.find_bone("Neck")).origin - sk.get_bone_global_rest(sk.find_bone("Hips")).origin
		print("    (rest lean %.1f deg; lean as SpineUpright left it %.1f..%.1f; ground drop %.3f..%.3f m)" % [rad_to_deg(atan2(rest_torso.z, rest_torso.y)), inner_lean.x, inner_lean.y, drops_range.x, drops_range.y])
		probe.queue_free()
	get_tree().quit()


## Keeps the camera at the hero's side for `seconds`, measuring the planted foot's slide.
func _follow(player: Player, seconds: float, slides: PackedFloat32Array) -> void:
	var skeleton: Skeleton3D = player.model._skeleton
	var feet := [skeleton.find_bone("LeftFoot"), skeleton.find_bone("RightFoot")]
	var last := []
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		# beside the way the hero moves (beside the hero when standing)
		var motion := Vector3(player.velocity.x, 0.0, player.velocity.z)
		var side := motion.normalized().cross(Vector3.UP) if motion.length() > 0.5 else player.global_transform.basis.x
		_camera.global_position = player.global_position + side * 5.5 + Vector3.UP * 1.3
		if _gait.ends_with("_close") and motion.length() > 0.5:
			_camera.global_position = player.global_position + side * 2.2 + Vector3.UP * 1.1
		if _gait.ends_with("_front") and motion.length() > 0.5:
			_camera.global_position = player.global_position + motion.normalized() * 6.0 + Vector3.UP * 1.4
		if _gait.ends_with("_back") and motion.length() > 0.5:
			_camera.global_position = player.global_position - motion.normalized() * 6.0 + Vector3.UP * 1.4
		if motion.length() < 0.5 and _gait == "stand":  # from straight behind
			_camera.global_position = player.global_position + player.global_transform.basis.z * 3.4 + Vector3.UP * 1.4
		if motion.length() < 0.5 and _gait.ends_with("close"):  # close, ahead and to its left (rclose: right)
			_camera.global_position = player.global_position - player.global_transform.basis.z * 1.7 					+ player.global_transform.basis.x * (1.1 if _gait.ends_with("rclose") else -1.1) + Vector3.UP * 1.3
		if motion.length() < 0.5 and _gait.ends_with("_front"):  # from straight ahead
			_camera.global_position = player.global_position - player.global_transform.basis.z * 3.4 + Vector3.UP * 1.4
		_camera.look_at(player.global_position + Vector3.UP * 0.95)
		await get_tree().process_frame
		# each foot as the clip moves it about the body (turned to the world), so the body's
		# own travel is added exactly: a planted foot's ground speed is that plus the body's
		var now := []
		for foot: int in feet:
			now.append(skeleton.global_transform.basis * skeleton.get_bone_global_pose(foot).origin)
		var dt := get_process_delta_time()
		if last.size() == 2 and dt > 0.0:
			var low := 0 if now[0].y < now[1].y else 1
			var ground: Vector3 = (now[low] - last[low]) / dt + player.velocity
			slides.append(Vector2(ground.x, ground.z).length())
		last = now


## For each locomotion clip: its length, where in its cycle (0..1) each foot is furthest
## forward (about where it lands), and how fast a planted foot moves back under the body
## (the ground speed the clip is made for, for this hero's legs).
func _clip_phases() -> void:
	var hero := CharacterModel.create_hero(CharacterModel.DEFAULT_LOOK, Color.WHITE, "")
	add_child(hero)
	var tree: AnimationTree = hero.find_children("*", "AnimationTree", true, false)[0]
	tree.active = false
	var player: AnimationPlayer = hero.find_children("*", "AnimationPlayer", true, false)[0]
	var skeleton: Skeleton3D = hero._skeleton
	var feet := [skeleton.find_bone("LeftFoot"), skeleton.find_bone("RightFoot")]
	for clip: String in ["ual1/Idle", "ual1/Walk", "ual1/Walk_Formal", "ual1/Jog_Fwd", "ual1/Sprint", "ual1/Punch_Jab", "ual1/Sword_Idle"]:
		var length := player.get_animation(clip).length
		player.play(clip)
		var samples := 60
		var points := []
		for i in samples + 1:
			player.seek(length * i / samples, true)
			points.append([skeleton.get_bone_global_pose(feet[0]).origin, skeleton.get_bone_global_pose(feet[1]).origin])
		var front := [0, 0]
		var speeds := []
		var floor_y := INF
		for p: Array in points:
			floor_y = minf(floor_y, minf(p[0].y, p[1].y))
		for i in samples:
			for side in 2:
				if points[i][side].z > points[front[side]][side].z:
					front[side] = i
				# planted: near the floor, moving back under the body (+Z is ahead in the rig)
				if points[i][side].y < floor_y + 0.04 and points[i + 1][side].y < floor_y + 0.04:
					speeds.append(-(points[i + 1][side].z - points[i][side].z) / (length / samples))
		var speed := 0.0
		for v: float in speeds:
			speed += v
		print("clip %s: %.3f s, left foot ahead at %.2f, right at %.2f, planted foot speed %.2f m/s (%d samples)" % [
				clip, length, float(front[0]) / samples, float(front[1]) / samples, speed / maxf(speeds.size(), 1), speeds.size()])
		# sideways sway: the torso's tilt (hips to neck) and the head's, side to side (deg)
		var hips := skeleton.find_bone("Hips")
		var neck := skeleton.find_bone("Neck")
		var head := skeleton.find_bone("Head")
		var torso_roll := Vector2(INF, -INF)
		var head_roll := Vector2(INF, -INF)
		for i in samples:
			player.seek(length * i / samples, true)
			var torso := skeleton.get_bone_global_pose(neck).origin - skeleton.get_bone_global_pose(hips).origin
			var t := rad_to_deg(atan2(torso.x, torso.y))
			var up := skeleton.get_bone_global_pose(head).basis.y
			var h := rad_to_deg(atan2(up.x, up.y))
			torso_roll = Vector2(minf(torso_roll.x, t), maxf(torso_roll.y, t))
			head_roll = Vector2(minf(head_roll.x, h), maxf(head_roll.y, h))
		print("    sway: torso %.1f..%.1f deg, head %.1f..%.1f deg" % [torso_roll.x, torso_roll.y, head_roll.x, head_roll.y])
		# the arms: how bent the elbows get, and how high the hands come (m below the shoulder)
		var bend := Vector2(INF, -INF)
		var hand_drop := Vector2(INF, -INF)
		for i in samples:
			player.seek(length * i / samples, true)
			for side: String in ["Left", "Right"]:
				var upper := skeleton.get_bone_global_pose(skeleton.find_bone(side + "UpperArm")).origin
				var elbow := skeleton.get_bone_global_pose(skeleton.find_bone(side + "LowerArm")).origin
				var wrist := skeleton.get_bone_global_pose(skeleton.find_bone(side + "Hand")).origin
				var angle := rad_to_deg((elbow - upper).angle_to(wrist - elbow))
				bend = Vector2(minf(bend.x, angle), maxf(bend.y, angle))
				var drop := upper.y - wrist.y
				hand_drop = Vector2(minf(hand_drop.x, drop), maxf(hand_drop.y, drop))
		print("    arms: elbows bent %.0f..%.0f deg, hands %.2f..%.2f m below the shoulders" % [bend.x, bend.y, hand_drop.x, hand_drop.y])
		# the pelvis: side to side tilt (roll) and twist (yaw) (deg)
		var roll := Vector2(INF, -INF)
		var twist := Vector2(INF, -INF)
		for i in samples:
			player.seek(length * i / samples, true)
			var side_axis := skeleton.get_bone_global_pose(hips).basis * Vector3.RIGHT
			var r := rad_to_deg(atan2(side_axis.y, Vector2(side_axis.x, side_axis.z).length()))
			var t := rad_to_deg(atan2(side_axis.z, side_axis.x))
			roll = Vector2(minf(roll.x, r), maxf(roll.y, r))
			twist = Vector2(minf(twist.x, t), maxf(twist.y, t))
		print("    pelvis: tilt %.1f..%.1f deg, twist %.1f..%.1f deg" % [roll.x, roll.y, twist.x, twist.y])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
