extends Node
## Close-up shots of the player model's animations in the real zone. Run:
##   Godot.exe --path game -- --model-shots=<output folder>

var _camera := Camera3D.new()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var folder := "res://tests/output"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model-shots="):
			folder = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(folder)
	if Game.zone == null:
		await Game.zone_ready
	var player := Game.player
	get_tree().root.add_child(_camera)
	_camera.fov = 40.0
	_camera.make_current()
	await _wait(1.5)
	await _shot(Game.zone.get_node("NPCs/HerbalistMira"), folder, "mira", 2.6)
	for npc_name in ["WardenThalos", "MagisterIvren", "QuartermasterBren"]:
		await _shot(Game.zone.get_node("NPCs/" + npc_name), folder, npc_name.to_lower(), 2.6)
		await _shot(Game.zone.get_node("NPCs/" + npc_name), folder, npc_name.to_lower() + "_face", 0.9, 1.6)
	var scavenger := _enemy(&"gloomshard_scavenger")
	if scavenger:
		await _shot(scavenger, folder, "scavenger", 2.6)
		scavenger.attacked.emit()  # a swing of the pick
		await _wait(0.42)
		await _shot(scavenger, folder, "scavenger_strike", 2.8)
	var wolf := _enemy(&"shardfang_wolf")
	if wolf:
		await _shot(wolf, folder, "wolf", 2.6)
		wolf.attacked.emit()  # a bite
		await _wait(0.36)
		await _shot(wolf, folder, "wolf_bite", 2.6)
	var acolyte := _enemy(&"eclipse_acolyte")
	if acolyte:
		acolyte.rotation.y = PI  # facing the open meadow south of the den
		await _wait(0.1)
		await _shot(acolyte, folder, "acolyte", 2.6)
		var bolt: AbilityData = acolyte.data.abilities[0]
		acolyte.casting = bolt  # an Eclipse Bolt gathering in her hands
		acolyte._cast_target = player
		acolyte._cast_end = Game.time + 30.0
		acolyte.cast_started.emit(bolt)
		await _wait(0.8)
		await _shot(acolyte, folder, "acolyte_cast", 2.6)
		acolyte.interrupt_cast()
	var sigils := get_tree().get_nodes_in_group("quest_objects").filter(func(o: QuestObject) -> bool: return o.object_id == &"eclipse_sigil")
	if not sigils.is_empty():
		(sigils[0] as Node3D).rotation.y = PI  # seen from the meadow, the cliff behind it
		await _shot(sigils[0], folder, "sigil", 6.0)
	var boss := _enemy(&"grimjaw")
	if boss:
		await _shot(boss, folder, "grimjaw", 5.5)
		boss.rotate_y(2.2)  # its crystal-studded back
		await _wait(0.1)
		await _shot(boss, folder, "grimjaw_back", 5.5)
		boss.rotate_y(-2.2)
		boss.attacked.emit()  # a paw swipe
		await _wait(0.75)
		await _shot(boss, folder, "grimjaw_swipe", 5.5)
		await _wait(1.6)
		var roar: AbilityData = boss.data.abilities[1]
		boss.casting = roar  # rears up on its hind legs for the roar
		boss._cast_target = player
		boss._cast_end = Game.time + 30.0
		boss.cast_started.emit(roar)
		await _wait(3.2)
		await _shot(boss, folder, "grimjaw_roar", 6.0)
		boss.interrupt_cast()
	if wolf:
		wolf.die(null)
		await _wait(1.6)
		await _shot(wolf, folder, "wolf_death", 2.6)
	await _shot(player, folder, "idle", 2.8)
	player.autorun = true
	await _wait(0.9)
	await _shot(player, folder, "run", 3.6)
	player.autorun = false
	await _wait(0.8)
	player.attacked.emit()
	await _wait(0.28)
	await _shot(player, folder, "attack_windup", 2.8)
	await _wait(0.12)
	await _shot(player, folder, "attack_strike", 2.8)
	for swing in 2:  # the next two swings in the rotation
		await _wait(0.9)
		player.attacked.emit()
		await _wait(0.42)
		await _shot(player, folder, "attack%d_strike" % (swing + 2), 2.8)
	await _wait(0.8)
	player.casting = player.abilities[1]
	player._cast_target = player
	player._cast_end = Game.time + 30.0
	await _wait(0.8)
	await _shot(player, folder, "cast", 2.8)
	player.interrupt_cast()
	# the head turns toward a target standing off to the side
	var npc := Game.zone.get_node("NPCs/HerbalistMira") as Unit
	player.target = npc
	player.look_at(npc.global_position + (npc.global_position - player.global_position).cross(Vector3.UP).normalized() * 6.0, Vector3.UP)
	await _wait(1.0)
	await _shot(player, folder, "look", 2.4)
	player.target = null
	# standing across a slope: the feet should rest on the ground, not in it or above it
	var slope := _find_slope()
	if slope.is_finite():
		player.teleport(slope, 0.0)
		await _wait(1.2)
		await _shot(player, folder, "slope", 2.6)
		var skeleton := player.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		await skeleton.skeleton_updated  # after the modifiers (feet planted)
		var gaps := []
		for foot_name in ["LeftFoot", "RightFoot", "LeftToes", "RightToes"]:
			var p := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(foot_name)).origin
			gaps.append(snappedf(p.y - Game.zone.terrain.get_height(p.x, p.z), 0.005))
		print("slope %.2f: ankle / toe heights above the ground (m) L, R, L toe, R toe: %s" % [Game.zone.terrain.get_slope(slope.x, slope.z), gaps])
		# running on from there in the open: about 2.5 steps a second should be heard
		var steps_before := _steps_heard()
		var start := player.global_position
		player.autorun = true
		await _wait(3.0)
		player.autorun = false
		print("footsteps heard running 3 s (%.1f m): %d" % [player.global_position.distance_to(start), _steps_heard() - steps_before])
	player.die(null)
	await _wait(1.8)
	await _shot(player, folder, "death", 3.4)
	get_tree().quit()


func _shot(unit: Node3D, folder: String, view_name: String, distance: float, height := 1.0) -> void:
	# front three-quarter view of the unit, chest height (or `height`: 1.6 for a face)
	var basis := unit.global_transform.basis
	var front := -basis.z
	var eye := unit.global_position + front * distance + basis.x * distance * 0.45 + Vector3.UP * (height + 0.3)
	_camera.look_at_from_position(eye, unit.global_position + Vector3.UP * height)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(view_name + ".png"))


## A walkable spot near the camp where the ground tilts noticeably (side to side).
func _find_slope() -> Vector3:
	var terrain: Terrain = Game.zone.terrain
	for r in range(25, 90, 5):
		for step in 24:
			var a := step * TAU / 24.0
			var x := cos(a) * r
			var z := sin(a) * r
			var slope := terrain.get_slope(x, z)
			if slope > 0.08 and slope < 0.2 and terrain.get_height(x, z) > terrain.water_level + 0.5:
				return Vector3(x, terrain.get_height(x, z) + 0.3, z)
	return Vector3.INF


func _steps_heard() -> int:
	var count := 0
	for set_name: String in Audio.played:
		if set_name.begins_with("step_"):
			count += Audio.played[set_name]
	return count


func _enemy(id: StringName) -> Enemy:
	for node in get_tree().get_nodes_in_group("enemies"):
		if (node as Enemy).data.id == id:
			return node
	return null


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
