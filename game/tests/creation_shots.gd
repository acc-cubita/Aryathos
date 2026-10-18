extends Node
## Screenshots of the character creation screen with a few looks. Run:
##   Godot.exe --path game -- --creation-shots=<output folder>

const LOOKS := [
	{"gender": "male", "hair": 0, "hair_color": 1, "skin": 0, "beard": 0},
	{"gender": "male", "hair": 1, "hair_color": 0, "skin": 2, "beard": 1},
	{"gender": "male", "hair": 2, "hair_color": 3, "skin": 1, "beard": 2},
	{"gender": "male", "hair": 3, "hair_color": 4, "skin": 3, "beard": 3},
	{"gender": "female", "hair": 0, "hair_color": 1, "skin": 0, "beard": 0},
	{"gender": "female", "hair": 1, "hair_color": 0, "skin": 1, "beard": 0},
	{"gender": "female", "hair": 2, "hair_color": 2, "skin": 2, "beard": 0},
	{"gender": "female", "hair": 3, "hair_color": 3, "skin": 3, "beard": 0},
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the screen pauses the game
	_run.call_deferred()


func _run() -> void:
	var folder := "res://tests/output"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--creation-shots="):
			folder = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(folder)
	if Game.zone == null:
		await Game.zone_ready
	var screen: CharacterCreation = Game.zone.hud.open_character_creation()
	for i in LOOKS.size():
		screen.look = LOOKS[i].duplicate()
		screen._refresh()
		await get_tree().create_timer(1.0, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(folder.path_join("creation_%d.png" % i))
	get_tree().quit()
