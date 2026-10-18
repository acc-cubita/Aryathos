extends Node
## Registers the default WoW-style key bindings at startup (autoload "Keybinds").
## Physical key codes are used so the bindings work with any keyboard layout
## (for example when the Persian layout is active).

const BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"turn_left": [KEY_A, KEY_LEFT],
	"turn_right": [KEY_D, KEY_RIGHT],
	"strafe_left": [KEY_Q],
	"strafe_right": [KEY_E],
	"toggle_walk": [KEY_KP_DIVIDE],
	"jump": [KEY_SPACE],
	"autorun": [KEY_NUMLOCK, KEY_R],
	"target_nearest": [KEY_TAB],
	"clear_target": [KEY_ESCAPE],
	"interact": [KEY_F],
	"toggle_bags": [KEY_B],
	"toggle_character": [KEY_C],
	"toggle_spellbook": [KEY_P],
	"toggle_talents": [KEY_N],
	"toggle_reputation": [KEY_U],
	"toggle_achievements": [KEY_Y],
	"toggle_professions": [KEY_K],
	"toggle_quest_log": [KEY_L],
	"toggle_map": [KEY_M],
	"toggle_help": [KEY_F1],
	"screenshot": [KEY_PRINT],
	"action_1": [KEY_1],
	"action_2": [KEY_2],
	"action_3": [KEY_3],
	"action_4": [KEY_4],
	"action_5": [KEY_5],
	"action_6": [KEY_6],
	"action_7": [KEY_7],
	"action_8": [KEY_8],
	"action_9": [KEY_9],
	"action_10": [KEY_0],
	"action_11": [KEY_MINUS],
	"action_12": [KEY_EQUAL],
}

## Bindings that need Alt held.
const ALT_BINDINGS := {
	"toggle_ui": [KEY_Z],
}

## Names shown in the Key Bindings window, in display order.
const LABELS := {
	"move_forward": "Move forward", "move_back": "Move backward",
	"turn_left": "Turn left", "turn_right": "Turn right",
	"strafe_left": "Strafe left", "strafe_right": "Strafe right", "toggle_walk": "Walk / run",
	"jump": "Jump", "autorun": "Autorun",
	"target_nearest": "Target nearest enemy", "clear_target": "Clear target / close / menu",
	"interact": "Interact with target",
	"action_1": "Action button 1", "action_2": "Action button 2", "action_3": "Action button 3",
	"action_4": "Action button 4", "action_5": "Action button 5", "action_6": "Action button 6",
	"action_7": "Action button 7", "action_8": "Action button 8", "action_9": "Action button 9",
	"action_10": "Action button 10", "action_11": "Action button 11", "action_12": "Action button 12",
	"toggle_bags": "Backpack", "toggle_character": "Character info", "toggle_spellbook": "Spellbook", "toggle_talents": "Talents", "toggle_reputation": "Reputation", "toggle_achievements": "Achievements", "toggle_professions": "Professions",
	"toggle_quest_log": "Quest log", "toggle_map": "World map",
	"toggle_ui": "Hide / show interface", "screenshot": "Screenshot", "toggle_help": "Controls help",
}

const KEY_NAMES := {"Minus": "-", "Equal": "=", "Print": "Print Screen", "NumLock": "Num Lock"}


func _ready() -> void:
	for action: String in BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	for action: String in ALT_BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in ALT_BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			event.alt_pressed = true
			InputMap.action_add_event(action, event)


## Short text for the first key bound to an action, e.g. "1", "-" or "Alt+Z".
func label_for(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return _key_text(event as InputEventKey)
	return ""


## Every key bound to an action, e.g. "W / Up".
func describe(action: String) -> String:
	var keys := PackedStringArray()
	if InputMap.has_action(action):
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				keys.append(_key_text(event as InputEventKey))
	return " / ".join(keys)


func _key_text(event: InputEventKey) -> String:
	var key := OS.get_keycode_string(event.physical_keycode)
	return ("Alt+" if event.alt_pressed else "") + str(KEY_NAMES.get(key, key))
