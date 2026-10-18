class_name GraphicsWindow
extends GameWindow
## Graphics (from the game menu): a quality preset (Low to Ultra) and every setting on its
## own, applied at once and kept (the Graphics autoload). Changing a quality setting by
## hand makes the preset "Custom".

const DISPLAY := ["window", "vsync", "max_fps", "fps_counter", "scale"]
const QUALITY := ["aa", "shadows", "ao", "glow", "grass", "detail"]

var _preset_buttons := {}
var _preset_label := Hud.make_label("", 15, Hud.GOLD)
var _pickers := {}


func _init() -> void:
	super("Graphics", Side.CENTER)


func setup() -> void:
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 6)
	presets.add_child(_label("Preset"))
	for preset: String in Graphics.PRESETS:
		var button := Button.new()
		button.text = preset
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size.x = 76.0
		button.pressed.connect(func() -> void: Graphics.use_preset(preset))
		_preset_buttons[preset] = button
		presets.add_child(button)
	presets.add_child(_preset_label)
	content.add_child(presets)
	content.add_child(_section("Display", DISPLAY))
	content.add_child(_section("Quality", QUALITY))
	content.add_child(Hud.make_label("Lower shadows, grass and render scale help the most on slower graphics cards.",
			13, Color(0.65, 0.66, 0.7)))
	Graphics.changed.connect(refresh)


func refresh() -> void:
	var current := Graphics.preset_name()
	for preset: String in _preset_buttons:
		(_preset_buttons[preset] as Button).set_pressed_no_signal(preset == current)
	_preset_label.text = "  Custom" if current == "Custom" else ""
	for key: String in _pickers:
		(_pickers[key] as OptionButton).select(Graphics.get_setting(key))


func _section(heading: String, keys: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_child(Hud.make_label(heading, 16, Hud.GOLD))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	for key: String in keys:
		grid.add_child(_label(Graphics.OPTIONS[key][0]))
		var picker := OptionButton.new()
		picker.focus_mode = Control.FOCUS_NONE
		picker.custom_minimum_size.x = 210.0
		for option: String in Graphics.OPTIONS[key][1]:
			picker.add_item(option)
		picker.item_selected.connect(func(index: int) -> void: Graphics.set_setting(key, index))
		_pickers[key] = picker
		grid.add_child(picker)
	box.add_child(grid)
	return box


func _label(text: String) -> Label:
	var label := Hud.make_label(text, 15, Color.WHITE)
	label.custom_minimum_size.x = 150.0
	return label
