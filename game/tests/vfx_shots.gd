extends Node
## Screenshots of the combat effects in the real zone (axe arc, hit, cast, missiles,
## nova, heal), each caught mid-effect. Run windowed:
##   Godot.exe --path game -- --vfx-shots=<output folder>

const SHARD := preload("res://data/abilities/aether_shard.tres")
const SURGE := preload("res://data/abilities/storm_surge.tres")
const NOVA := preload("res://data/abilities/storm_nova.tres")

var _camera := Camera3D.new()
var _folder := "res://tests/output"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--vfx-shots="):
			_folder = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_folder)
	if Game.zone == null:
		await Game.zone_ready
	Game.zone.hud.visible = false
	var player := Game.player
	get_tree().root.add_child(_camera)
	_camera.fov = 45.0
	_camera.make_current()
	await _wait(1.5)
	# a target 7 m in front of the player
	var foe: Unit = null
	for node in get_tree().get_nodes_in_group("units"):
		if node is Enemy and not (node as Unit).is_dead:
			foe = node
			break
	var front := -player.global_transform.basis.z
	var spot := player.global_position + front * 7.0
	foe.global_position = Vector3(spot.x, Game.zone.terrain.get_height(spot.x, spot.z), spot.z)
	foe.reset_physics_interpolation()
	foe.process_mode = Node.PROCESS_MODE_DISABLED  # stands still for the pictures
	foe.max_health = 100000
	foe.health = 100000

	_frame(player, foe, 3.2)
	for swing in 3:  # each swing once, caught as the blade comes through
		player.attacked.emit()
		await _wait(0.56)
		await _snap("axe_arc%d" % (swing + 1))
		await _wait(0.9)
	await _wait(0.6)
	Vfx.impact(Game.zone, player.global_position + front * 1.2 + Vector3.UP * 1.2, -front, player.glow_color, 1.2, true)
	await _wait(0.05)
	await _snap("hit_crit")
	await _wait(0.6)
	player.cast_started.emit(SHARD)
	await _wait(0.7)
	await _snap("casting")
	player.cast_ended.emit(true)
	await _wait(0.3)
	_frame(player, foe, 5.0, 0.5)
	Projectile.launch(player, foe, SHARD, 1, false)
	await _wait(0.12)
	await _snap("shard_flight")
	await _wait(0.3)
	await _snap("shard_impact")
	await _wait(0.6)
	Projectile.launch(player, foe, SURGE, 1, true)
	await _wait(0.06)
	await _snap("lightning")
	await _wait(0.8)
	_frame(player, null, 9.0)
	Vfx.nova(Game.zone, player.global_position, NOVA.color, NOVA.radius)
	await _wait(0.15)
	await _snap("nova")
	await _wait(0.8)
	_frame(player, null, 3.5)
	Vfx.heal(Game.zone, player, CombatVfx.HEAL_LIGHT)
	await _wait(0.35)
	await _snap("heal")
	get_tree().quit()


## Camera off to the player's front right, looking between the player and `other`.
func _frame(player: Unit, other: Unit, distance: float, toward_other := 0.3) -> void:
	var basis := player.global_transform.basis
	var look := player.global_position + Vector3.UP * 1.1
	if other:
		look = look.lerp(other.global_position + Vector3.UP * 1.1, toward_other)
	var eye := look - basis.z * distance * 0.55 + basis.x * distance * 0.85 + Vector3.UP * distance * 0.25
	_camera.look_at_from_position(eye, look)


func _snap(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_folder.path_join(shot_name + ".png"))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
