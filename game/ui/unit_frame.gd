class_name UnitFrame
extends PanelContainer
## Name, level, health and mana of one unit (the player or the current target).
## Clicking the frame targets that unit.

const HOSTILE := Color(0.8, 0.15, 0.1)
const FRIENDLY := Color(0.15, 0.72, 0.2)

var unit: Unit

var _style := Hud.panel_style()
var _name: Label
var _level: Label
var _health := StatBar.new(FRIENDLY, 20, 13)
var _mana := StatBar.new(Color(0.15, 0.35, 0.95), 12, 10)
## Shows what the unit is casting, so you can react (e.g. step out of a roar).
var _cast := StatBar.new(Color(0.95, 0.55, 0.1), 14, 11)


func _init() -> void:
	custom_minimum_size = Vector2(250, 0)
	add_theme_stylebox_override("panel", _style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_name = Hud.make_label("", 15, Color.WHITE)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.clip_text = true
	header.add_child(_name)
	_level = Hud.make_label("", 15, Hud.GOLD)
	header.add_child(_level)
	box.add_child(_health)
	box.add_child(_mana)
	box.add_child(_cast)


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and unit:
		Game.player.set_target(unit)
		accept_event()


func _process(_delta: float) -> void:
	visible = unit != null
	if not visible:
		return
	var player := Game.player
	var hostile := unit.is_hostile_to(player)
	_name.text = unit.unit_name
	_name.add_theme_color_override("font_color", Color(1, 0.35, 0.3) if hostile else Color.WHITE)
	_level.text = ("Elite " if unit.is_elite else "") + str(unit.level)
	_level.add_theme_color_override("font_color", Hud.GOLD if unit == player else Game.level_color(unit.level, player.level))
	_health.set_color(HOSTILE if hostile else FRIENDLY)
	_health.show_values(unit.health, unit.max_health, "Dead" if unit.is_dead else "%d / %d" % [unit.health, unit.max_health])
	_mana.visible = unit.max_mana > 0
	_mana.show_values(unit.mana, unit.max_mana, "%d / %d" % [unit.mana, unit.max_mana])
	_style.border_color = Hud.GOLD if unit.is_elite else Color(0.45, 0.42, 0.38)
	_cast.visible = unit.casting != null and unit != player
	if _cast.visible:
		var total := unit.cast_duration
		_cast.show_values(total - unit.cast_remaining(), total, unit.casting.display_name)
