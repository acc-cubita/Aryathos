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
}
const FRAMES := 10
const START := Vector3(-4, 0, -24)  # on the road north of the camp, open ground ahead

var _camera := Camera3D.new()
var _gait := ""


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
		await _wait(0.4)
		for action: String in GAITS[gait]:
			Input.action_press(action)
		await _wait(0.9)
		if gait == "jump":
			var leap := InputEventAction.new()  # (the hero jumps on the key's event)
			leap.action = "jump"
			leap.pressed = true
			Input.parse_input_event(leap)
		var sways := Vector2(INF, -INF)
		var slides := PackedFloat32Array()
		for frame in FRAMES:
			await _follow(player, 1.0 / 12.0, slides)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(folder.path_join("%s_%d.png" % [gait, frame]))
			var tilt := rad_to_deg(player.model._upright.swaying)
			sways = Vector2(minf(sways.x, tilt), maxf(sways.y, tilt))
		for action: String in GAITS[gait]:
			Input.action_release(action)
		if player.has_method("set_walking"):
			player.set_walking(false)
		var slide := 0.0
		for s in slides:
			slide += s
		print("gait %s: speed %.1f m/s, torso sway %.1f..%.1f deg, state %s" % [gait,
				Vector2(player.velocity.x, player.velocity.z).length(), sways.x, sways.y, player.model._state])
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
		if _gait.ends_with("_front") and motion.length() > 0.5:
			_camera.global_position = player.global_position + motion.normalized() * 6.0 + Vector3.UP * 1.4
		if motion.length() < 0.5 and _gait == "stand":  # from straight behind
			_camera.global_position = player.global_position + player.global_transform.basis.z * 3.4 + Vector3.UP * 1.4
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
	for clip: String in ["ual1/Walk", "ual1/Walk_Formal", "ual1/Jog_Fwd", "ual1/Sprint"]:
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


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
