extends Node
## Saves UI-free views of the zone for art work. Run from the project folder:
##   Godot.exe --path game -- --scenery=<output folder>

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
	"forest": [Vector3(30, 0, -40), 0.6, -0.1, 7.0],
	# from the open camp toward the border mountains
	"north": [Vector3(0, 0, -12), 0.0, 0.08, 8.0],
	"south": [Vector3(0, 0, 12), PI, 0.08, 8.0],
	# camp props up close: tent and campfire, then chests and barrel
	"tent": [Vector3(-6, 0, -4), 0.25, -0.18, 5.0],
	"crates": [Vector3(-6.5, 0, 6), PI * 0.5, -0.22, 4.0],
	# next to the first herb (placed at run time, so filled in by _run)
	"herb": [Vector3.ZERO, 0.0, -0.35, 2.6],
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
	var hide_ui := InputEventAction.new()
	hide_ui.action = "toggle_ui"
	hide_ui.pressed = true
	Input.parse_input_event(hide_ui)
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
		var view: Array = VIEWS[fps_view]
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
	for view_name: String in VIEWS:
		var view: Array = VIEWS[view_name]
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
