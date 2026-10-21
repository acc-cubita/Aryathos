extends Node
## Performance check for rigged characters: spawns a crowd of Arkanor models
## around the player and prints frame time + drawn primitives with mesh LOD on
## and off. Run windowed (vsync is turned off for the measurement):
##   Godot.exe --path game -- --crowd=40


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var count := 40
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--crowd="):
			count = int(arg.get_slice("=", 1))
	if Game.zone == null:
		await Game.zone_ready
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var player := Game.player
	var forward := -player.global_transform.basis.z
	var side := player.global_transform.basis.x
	for i in count:
		var path := CharacterModel.HERO_MALE if i % 2 == 0 else CharacterModel.HERO_FEMALE
		var model := CharacterModel.create(path, Color(0.4, 0.85, 1.0), "sword" if i % 2 == 0 else "")
		get_tree().root.add_child(model)
		# rows from 6 m to ~60 m in front of the camera
		var row := i / 8
		var spot := player.global_position + forward * (6.0 + row * 12.0) + side * ((i % 8) - 3.5) * 2.5
		model.global_position = Vector3(spot.x, Game.zone.terrain.get_height(spot.x, spot.z), spot.z)
	await _wait(2.0)
	var viewport := get_viewport()
	for lod_threshold: float in [1.0, 0.0]:
		viewport.mesh_lod_threshold = lod_threshold
		await _wait(1.0)
		var frames := 0
		var primitives := 0
		var start := Time.get_ticks_usec()
		while Time.get_ticks_usec() - start < 3_000_000:
			await RenderingServer.frame_post_draw
			frames += 1
			primitives += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		var ms := (Time.get_ticks_usec() - start) / 1000.0 / frames
		print("[crowd] %d characters, lod_threshold %.1f: %.2f ms/frame (%.0f fps), %d k primitives/frame" % [
				count, lod_threshold, ms, 1000.0 / ms, primitives / frames / 1000])
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
