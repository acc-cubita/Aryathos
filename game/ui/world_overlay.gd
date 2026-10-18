class_name WorldOverlay
extends Control
## 2D elements pinned to 3D positions: nameplates above units and
## floating combat text (damage, heals) that drifts up and fades.

const NAMEPLATE_RANGE := 45.0
const TEXT_LIFETIME := 1.3

var _player: Player
var _camera: Camera3D
var _plates := {}
var _texts: Array[Dictionary] = []


func setup(player: Player, camera: Camera3D) -> void:
	_player = player
	_camera = camera
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func float_text(unit: Unit, text: String, color: Color, big := false) -> void:
	var label := Hud.make_label(text, 30 if big else 20, color)
	add_child(label)
	_texts.append({"unit": unit, "label": label, "age": 0.0, "x": randf_range(-30.0, 30.0)})


func _process(delta: float) -> void:
	_update_plates()
	_update_texts(delta)


func _update_plates() -> void:
	# Drop the plates of units that were removed from the world.
	for unit in _plates.keys():
		if not is_instance_valid(unit):
			(_plates[unit] as Control).queue_free()
			_plates.erase(unit)
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if unit == _player:
			continue
		var plate: Control = _plates.get(unit)
		if plate == null:
			plate = _make_plate()
			add_child(plate)
			move_child(plate, 0)
			_plates[unit] = plate
		var head := unit.get_global_transform_interpolated().origin + Vector3.UP * (unit.body_height + 0.5)
		plate.visible = not unit.is_dead and not _camera.is_position_behind(head) \
				and _camera.global_position.distance_to(head) < NAMEPLATE_RANGE
		if not plate.visible:
			continue
		plate.position = _camera.unproject_position(head) - Vector2(plate.size.x * 0.5, plate.size.y)
		plate.modulate.a = 1.0 if unit == _player.target else 0.75
		var hostile := unit.is_hostile_to(_player)
		var label := plate.get_child(0) as Label
		label.text = unit.unit_name
		label.add_theme_color_override("font_color", Color(1, 0.35, 0.3) if hostile else Color(0.4, 1, 0.45))
		var bar := plate.get_child(1) as StatBar
		bar.set_color(UnitFrame.HOSTILE if hostile else UnitFrame.FRIENDLY)
		bar.show_values(unit.health, unit.max_health)


func _make_plate() -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(120, 0)
	box.add_theme_constant_override("separation", 1)
	var label := Hud.make_label("", 13, Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	box.add_child(StatBar.new(Color.RED, 7, 1))
	return box


func _update_texts(delta: float) -> void:
	for i in range(_texts.size() - 1, -1, -1):
		var entry := _texts[i]
		var label: Label = entry["label"]
		var age: float = entry["age"] + delta
		entry["age"] = age
		if age >= TEXT_LIFETIME or not is_instance_valid(entry["unit"]):
			label.queue_free()
			_texts.remove_at(i)
			continue
		var unit: Unit = entry["unit"]
		var anchor := unit.get_global_transform_interpolated().origin + Vector3.UP * (unit.body_height + 0.3)
		label.visible = not _camera.is_position_behind(anchor)
		var offset := Vector2(entry["x"], -age * 55.0)
		label.position = _camera.unproject_position(anchor) + offset - label.size * 0.5
		label.modulate.a = 1.0 - smoothstep(0.6, 1.0, age / TEXT_LIFETIME)
