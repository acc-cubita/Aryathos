class_name StatBar
extends ProgressBar
## A colored bar with centered text (health, mana, cast progress...).

var _fill := StyleBoxFlat.new()
var _label: Label


func _init(color := Color.WHITE, height := 18.0, font_size := 12) -> void:
	custom_minimum_size = Vector2(0, height)
	show_percentage = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.bg_color = color
	_fill.set_corner_radius_all(2)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0, 0, 0, 0.65)
	background.set_corner_radius_all(2)
	add_theme_stylebox_override("fill", _fill)
	add_theme_stylebox_override("background", background)
	_label = Hud.make_label("", font_size, Color.WHITE)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)


func show_values(current: float, maximum: float, text := "") -> void:
	max_value = maxf(maximum, 1.0)
	value = current
	_label.text = text


func set_color(color: Color) -> void:
	_fill.bg_color = color
