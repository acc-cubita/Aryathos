class_name Minimap
extends Control
## WoW-style round minimap (north up). Shows the terrain around the player,
## enemies (red, elites orange), NPCs (yellow) with their quest markers, herbs (green),
## and the player as an arrow. Mouse wheel over it zooms.

const SIZE := 190.0
const MIN_RANGE := 30.0
const MAX_RANGE := 120.0

const MASK_SHADER := """
shader_type canvas_item;
uniform sampler2D map_texture : filter_linear;
uniform vec2 center = vec2(0.5);
uniform float view = 0.4;

void fragment() {
	vec2 offset = UV - vec2(0.5);
	float dist = length(offset);
	if (dist > 0.5) {
		discard;
	}
	vec2 map_uv = center + offset * view;
	vec4 color = texture(map_texture, map_uv);
	if (map_uv.x < 0.0 || map_uv.y < 0.0 || map_uv.x > 1.0 || map_uv.y > 1.0) {
		color = vec4(0.05, 0.05, 0.07, 1.0);
	}
	COLOR = mix(color, vec4(0.86, 0.7, 0.35, 1.0), smoothstep(0.465, 0.49, dist));
}
"""

## Meters from the center to the edge of the map.
var view_range := 60.0

var _player: Player
var _map_size := 1.0
var _map := ColorRect.new()
var _material := ShaderMaterial.new()
var _overlay := Control.new()


func setup(player: Player, map_texture: Texture2D) -> void:
	_player = player
	_map_size = map_texture.get_width()
	add_to_group("minimap")
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	var shader := Shader.new()
	shader.code = MASK_SHADER
	_material.shader = shader
	_material.set_shader_parameter("map_texture", map_texture)
	_map.material = _material
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_map)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


func _gui_input(event: InputEvent) -> void:
	var wheel := event as InputEventMouseButton
	if wheel and wheel.pressed and wheel.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var step := -10.0 if wheel.button_index == MOUSE_BUTTON_WHEEL_UP else 10.0
		view_range = clampf(view_range + step, MIN_RANGE, MAX_RANGE)
		accept_event()


func _process(_delta: float) -> void:
	if _player == null:
		return
	var p := _player.global_position
	_material.set_shader_parameter("center", Vector2(p.x / _map_size + 0.5, p.z / _map_size + 0.5))
	_material.set_shader_parameter("view", view_range * 2.0 / _map_size)
	_overlay.queue_redraw()


func _draw_overlay() -> void:
	var center := Vector2(SIZE, SIZE) * 0.5
	var scale_factor := (SIZE * 0.5) / view_range
	var font := get_theme_default_font()
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit
		if unit == _player or unit.is_dead:
			continue
		var offset := Vector2(unit.global_position.x - _player.global_position.x, unit.global_position.z - _player.global_position.z) * scale_factor
		if offset.length() > SIZE * 0.5 - 8.0:
			continue
		var npc := unit as Npc
		if npc:
			var marker := npc.quest_marker_text()
			if marker != "":
				_overlay.draw_string_outline(font, center + offset + Vector2(-5, 7), marker, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color.BLACK)
				_overlay.draw_string(font, center + offset + Vector2(-5, 7), marker, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Npc.QUEST_YELLOW)
			else:
				_overlay.draw_circle(center + offset, 3.5, Color(1, 0.85, 0.2))
		elif unit.is_elite:
			_overlay.draw_circle(center + offset, 5.0, Color(1, 0.5, 0.1))
		else:
			_overlay.draw_circle(center + offset, 3.0, Color(0.95, 0.15, 0.1))
	# Herbs, for herbalists (like WoW's Find Herbs tracking).
	for node in get_tree().get_nodes_in_group("gather_nodes"):
		var herb := node as GatherNode
		if not herb.available or not _player.knows_profession(herb.data.profession):
			continue
		var herb_offset := Vector2(herb.global_position.x - _player.global_position.x, herb.global_position.z - _player.global_position.z) * scale_factor
		if herb_offset.length() <= SIZE * 0.5 - 8.0:
			_overlay.draw_circle(center + herb_offset, 2.5, Color(0.55, 1, 0.45))
	# The player: an arrow pointing where the character faces (north is up).
	var yaw := _player.rotation.y
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-forward.y, forward.x)
	var arrow := PackedVector2Array([center + forward * 9.0, center - forward * 6.0 + side * 6.0, center - forward * 3.0, center - forward * 6.0 - side * 6.0])
	_overlay.draw_colored_polygon(arrow, Color.WHITE)
	_overlay.draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color.BLACK, 1.5)
	_overlay.draw_string_outline(font, Vector2(center.x - 5, 16), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color.BLACK)
	_overlay.draw_string(font, Vector2(center.x - 5, 16), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Hud.GOLD)
