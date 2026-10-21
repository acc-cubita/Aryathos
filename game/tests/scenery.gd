extends Node
## Saves UI-free views of the zone for art work. Run from the project folder:
##   Godot.exe --path game -- --scenery=<output folder>
## (--graphics=Low|Medium|High|Ultra picks the graphics preset, e.g. with --scenery-fps.)

## name: [player position, camera yaw, pitch, distance]
const VIEWS := {
	"camp": [Vector3(0, 0, 9), 0.0, -0.25, 12.0],
	"lake": [Vector3(-40, 0, 30), 0.9, -0.2, 14.0],
	"hills": [Vector3(-8, 0, -30), 0.2, -0.12, 10.0],
	"crystals": [Vector3(66, 0, 12), -0.9, -0.22, 12.0],
	"den": [Vector3(-55, 0, -80), 0.4, -0.18, 12.0],
	"close": [Vector3(4, 0, 12), 2.6, -0.15, 5.0],
	"gloomshard": [Vector3(78, 0, 21), 0.0, -0.28, 12.0],
	"digsite": [Vector3(50, 0, -86), 0.0, -0.3, 12.0],
	"caches": [Vector3(50, 0, -112), 0.3, -0.35, 9.0],
	"den_top": [Vector3(-62, 0, -100), 0.0, -1.3, 55.0],
	"forest": [Vector3(30, 0, -40), 0.6, -0.1, 7.0],
	# from the open camp toward the border mountains
	"north": [Vector3(0, 0, -12), 0.0, 0.08, 8.0],
	"south": [Vector3(0, 0, 12), PI, 0.08, 8.0],
	# camp props up close: tent and campfire, then chests and barrel
	"tent": [Vector3(-6, 0, -4), 0.25, -0.18, 5.0],
	"crates": [Vector3(-6.5, 0, 6), PI * 0.5, -0.22, 4.0],
	# next to the first herb (placed at run time, so filled in by _run)
	"herb": [Vector3.ZERO, 0.0, -0.35, 2.6],
	# the road east into the mountain pass to the Crystal Canyons
	"pass": [Vector3(100, 0, 4), -PI * 0.5, -0.12, 9.0],
}
## Views of the other zones, by zone name (start one with --zone=<file name>).
const ZONE_VIEWS := {
	"Crystal Canyons": {
		"entrance": [Vector3(-150, 0, 20), -PI * 0.5, -0.1, 9.0],
		"hold": [Vector3(-126, 0, 18), -PI * 0.5, -0.22, 14.0],
		"gate": [Vector3(-108, 0, 18), PI, -0.05, 16.0],
		"thane": [Vector3(-106.6, 0, 29.6), PI - 0.3, -0.05, 2.6],
		"forge": [Vector3(-100.3, 0, 28.6), -1.95, -0.05, 2.6],
		"mine": [Vector3(-72, 0, -86), -0.73, -0.25, 14.0],
		"mesas": [Vector3(-25, 0, 28), -0.99, -0.12, 10.0],
		"gorge": [Vector3(45, 0, 40), -2.5, -0.1, 9.0],
		"seal": [Vector3(110, 0, 110), -2.36, -0.2, 12.0],
		"flats": [Vector3(62, 0, -48), -0.6, -0.15, 10.0],
		"overview": [Vector3(0, 0, 10), 0.4, -1.1, 140.0],
	},
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var folder := "res://tests/output/scenery"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenery="):
			folder = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(folder)
	if Game.zone == null:
		await Game.zone_ready
	var views: Dictionary = ZONE_VIEWS.get(Game.zone.zone_name, VIEWS)
	Game.zone.hud.visible = false
	# --scenery-off=grass,ssao,msaa,fog,glow,shadows turns features off to measure their cost.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenery-off="):
			_turn_off(arg.get_slice("=", 1).split(","))
	var player := Game.player
	# --scenery-fps[=view]: stand at one view for a while and print the frame rate each second.
	var fps_view := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenery-fps"):
			fps_view = arg.get_slice("=", 1) if "=" in arg else "lake"
	if fps_view != "":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)  # not held to the screen's rate
		var view: Array = views[fps_view]
		var spot: Vector3 = view[0]
		spot.y = Game.zone.terrain.get_height(spot.x, spot.z) + 0.2
		player.teleport(spot, view[1])
		player.camera_rig.set_view(view[1], view[2], view[3])
		var samples := PackedInt32Array()
		for second in 8:
			await get_tree().create_timer(1.0).timeout
			samples.append(Engine.get_frames_per_second())
		print("fps per second: ", samples)
		get_tree().quit()
		return
	# --scenery-only=a,b: just those views
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenery-only="):
			only = arg.get_slice("=", 1).split(",")
	for view_name: String in views:
		if not only.is_empty() and not only.has(view_name):
			continue
		var view: Array = views[view_name]
		var at: Vector3 = view[0]
		if view_name == "herb":
			var herbs := get_tree().get_nodes_in_group("gather_nodes")
			if herbs.is_empty():
				continue
			at = (herbs[0] as Node3D).global_position + Vector3(1.0, 0, 1.8)
		at.y = Game.zone.terrain.get_height(at.x, at.z) + 0.2
		player.teleport(at, view[1])
		player.camera_rig.set_view(view[1], view[2], view[3])
		await get_tree().create_timer(1.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(folder.path_join(view_name + ".png"))
		print("saved %s  (%d fps)" % [view_name, Engine.get_frames_per_second()])
	get_tree().quit()


func _turn_off(features: PackedStringArray) -> void:
	var environment: Environment = Game.zone.get_node("WorldEnvironment").environment
	for feature in features:
		match feature:
			"grass": Game.zone.get_node("Grass").visible = false
			"ssao": environment.ssao_enabled = false
			"ssil": environment.ssil_enabled = false
			"trees":
				for node in Game.zone.get_node("Decorator").get_children():
					if node is MultiMeshInstance3D and ("Crowns" in node.name or "Bushes" in node.name):
						node.visible = false
			"fog": environment.fog_enabled = false
			"glow": environment.glow_enabled = false
			"msaa": get_viewport().msaa_3d = Viewport.MSAA_DISABLED
			"shadows": Game.zone.get_node("Sun").shadow_enabled = false
			"terrain":
				var plain := StandardMaterial3D.new()
				plain.albedo_color = Terrain.GRASS_DARK
				Game.zone.terrain.get_node("Mesh").material_override = plain
			"sky":
				environment.sky.sky_material = ProceduralSkyMaterial.new()
			"water":
				for node in Game.zone.terrain.get_children():
					if node.name.begins_with("Water"):
						node.visible = false
	print("off: ", features)
