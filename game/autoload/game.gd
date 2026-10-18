extends Node
## Global game state and event bus (autoload "Game").
## Gameplay code reports what happened here; the UI and effects listen.
## Keeping rules apart from presentation is what lets us add multiplayer later.

signal zone_ready
signal unit_damaged(target: Unit, source: Unit, amount: int, crit: bool, color: Color)
signal unit_healed(target: Unit, source: Unit, amount: int, crit: bool)
signal unit_evaded(target: Unit, source: Unit)
signal unit_killed(unit: Unit, killer: Unit)
signal error_message(text: String)
signal system_message(text: String, color: Color)
signal chat_message(text: String, color: Color)
signal menu_requested
signal npc_interacted(npc: Npc)
signal loot_opened(enemy: Enemy)
signal mana_restored(unit: Unit, amount: int)

const MAX_LEVEL := 10
## XP needed to advance from a level to the next one (index = current level).
const XP_TABLE: Array[int] = [0, 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500]

const CHAT_SYSTEM := Color(1.0, 1.0, 0.55)
const CHAT_XP := Color(0.62, 0.55, 1.0)
const CHAT_QUEST := Color(1.0, 0.82, 0.0)
const CHAT_LOOT := Color(0.3, 0.9, 0.35)
const CHAT_REPUTATION := Color(0.5, 0.6, 1.0)

const AUTOSAVE_INTERVAL := 30.0

## Game clock in seconds. Follows Engine.time_scale and stops when the tree is paused.
var time := 0.0
var player: Player = null
var zone: Zone = null
## Where the character is saved. Test runs use their own file so they never touch a real save.
var save_path := "user://saves/character.json"

var _autosave_at := AUTOSAVE_INTERVAL


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	for arg in OS.get_cmdline_user_args():
		if arg == "--smoke-test" or arg.begins_with("--screenshot") or arg.begins_with("--scenery") or arg.begins_with("--model-shots") or arg.begins_with("--crowd") or arg.begins_with("--vfx-shots"):
			save_path = "user://saves/test.json"
			delete_save()
		if arg == "--smoke-test":
			add_child(load("res://tests/smoke_test.gd").new())
		elif arg.begins_with("--screenshot"):
			add_child(load("res://tests/screenshot.gd").new())
		elif arg.begins_with("--scenery"):
			add_child(load("res://tests/scenery.gd").new())
		elif arg.begins_with("--model-shots"):
			add_child(load("res://tests/model_shots.gd").new())
		elif arg.begins_with("--crowd"):
			add_child(load("res://tests/crowd.gd").new())
		elif arg.begins_with("--vfx-shots"):
			add_child(load("res://tests/vfx_shots.gd").new())


func _physics_process(delta: float) -> void:
	time += delta
	if time >= _autosave_at:
		_autosave_at = time + AUTOSAVE_INTERVAL
		save_game()


## Closing the window saves first (the menu's Quit button calls quit_game()).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func quit_game() -> void:
	save_game()
	get_tree().quit()


func save_game() -> bool:
	if not is_instance_valid(player):
		return false
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not save to %s (error %d)" % [save_path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(player.to_save_data(), "\t", false, true))
	return true


## Loads the saved character into the current player. Returns false when there is no save.
func load_game() -> bool:
	if not FileAccess.file_exists(save_path) or not is_instance_valid(player):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary:
		push_warning("The save file %s is damaged; starting a new character." % save_path)
		return false
	player.load_save_data(data)
	return true


func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


## Erases the save and starts over with a fresh character.
func new_character() -> void:
	delete_save()
	player = null
	get_tree().reload_current_scene()


func xp_to_next_level(level: int) -> int:
	if level >= MAX_LEVEL:
		return 0
	return XP_TABLE[level]


## Classic-style kill XP: a same-level creature gives level * 5 + 45,
## more for higher-level creatures, less (down to nothing) for lower ones.
func kill_xp(mob_level: int, player_level: int, elite := false) -> int:
	var base := float(mob_level * 5 + 45)
	var diff := mob_level - player_level
	var xp := 0.0
	if diff >= 0:
		xp = base * (1.0 + 0.05 * mini(diff, 4))
	elif mob_level <= gray_level(player_level):
		return 0
	else:
		xp = base * (1.0 - float(-diff) / zero_difference(player_level))
	if elite:
		xp *= 2.0
	return int(round(xp))


func zero_difference(player_level: int) -> float:
	if player_level < 8:
		return 5.0
	if player_level < 10:
		return 6.0
	return 7.0


## Highest creature level that is "gray" (trivial, no XP) for this player level.
func gray_level(player_level: int) -> int:
	if player_level <= 5:
		return 0
	return player_level - 5


## WoW-style difficulty color for a level compared with the player's level.
func level_color(unit_level: int, player_level: int) -> Color:
	var diff := unit_level - player_level
	if diff >= 5:
		return Color(1.0, 0.1, 0.1)
	if diff >= 3:
		return Color(1.0, 0.5, 0.25)
	if diff >= -2:
		return Color(1.0, 0.82, 0.0)
	if unit_level > gray_level(player_level):
		return Color(0.25, 0.75, 0.25)
	return Color(0.55, 0.55, 0.55)


## 12345 copper -> "1g 23s 45c".
func format_money(copper: int) -> String:
	var parts := PackedStringArray()
	if copper >= 10000:
		parts.append("%dg" % (copper / 10000))
	if copper >= 100:
		parts.append("%ds" % (copper / 100 % 100))
	if copper % 100 or parts.is_empty():
		parts.append("%dc" % (copper % 100))
	return " ".join(parts)


func chat(text: String, color := CHAT_SYSTEM) -> void:
	chat_message.emit(text, color)
