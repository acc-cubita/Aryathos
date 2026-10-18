class_name GameWindow
extends PanelContainer
## Base for WoW-style panels (bags, character, spellbook...): a title bar with a
## close button above a content area. Esc closes open windows before the game menu.

## Which part of the screen the HUD places this window in.
enum Side { LEFT, CENTER, RIGHT }

var side := Side.LEFT
var content := VBoxContainer.new()

var _title := Hud.make_label("", 18, Hud.GOLD)


func _init(title: String, window_side := Side.LEFT) -> void:
	side = window_side
	add_to_group("game_windows")
	add_theme_stylebox_override("panel", Hud.panel_style())
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var bar := HBoxContainer.new()
	_title.text = title
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_title)
	var close := Button.new()
	close.text = " X "
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(hide)
	bar.add_child(close)
	box.add_child(bar)
	content.add_theme_constant_override("separation", 8)
	box.add_child(content)
	add_child(box)
	# Containers only ever grow; shrink back whenever the content gets smaller.
	minimum_size_changed.connect(func() -> void: fit_to_content.call_deferred())


## Resizes the window to exactly its content, keeping the screen edge it is attached to.
func fit_to_content() -> void:
	var needed := get_combined_minimum_size()
	match side:
		Side.LEFT:
			size = needed
		Side.RIGHT:
			offset_left = offset_right - needed.x
			offset_top = offset_bottom - needed.y
		Side.CENTER:
			offset_left = -needed.x * 0.5
			offset_right = needed.x * 0.5
			offset_top = -needed.y * 0.5
			offset_bottom = needed.y * 0.5


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()


func set_title(text: String) -> void:
	_title.text = text


## Re-reads the game state; called when the window opens.
func refresh() -> void:
	pass
