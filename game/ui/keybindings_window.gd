class_name KeybindingsWindow
extends GameWindow
## Key Bindings (from the game menu): every key and mouse control in the game.

const MOUSE_CONTROLS := [
	["Look around", "Left mouse drag"], ["Look and steer", "Right mouse drag"],
	["Run forward", "Both mouse buttons"], ["Zoom", "Mouse wheel"],
	["Select target", "Left click"], ["Attack / talk / loot", "Right click"],
]


func _init() -> void:
	super("Key Bindings", Side.CENTER)


func setup() -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	for action: String in Keybinds.LABELS:
		_row(grid, Keybinds.LABELS[action], Keybinds.describe(action))
	for control: Array in MOUSE_CONTROLS:
		_row(grid, control[0], control[1])
	scroll.add_child(grid)
	content.add_child(scroll)


func _row(grid: GridContainer, label: String, keys: String) -> void:
	grid.add_child(Hud.make_label(label, 14, Color(0.95, 0.92, 0.85)))
	grid.add_child(Hud.make_label(keys, 14, Hud.GOLD))
