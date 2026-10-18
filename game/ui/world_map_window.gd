class_name WorldMapWindow
extends GameWindow
## World map (M): the whole zone with you, NPCs and their quest markers,
## places of interest, and yellow areas where active quest targets live.

const MAP_SIZE := 560.0

var _player: Player
var _world_size := 1.0
var _map := TextureRect.new()
var _overlay := Control.new()
var _coords := Hud.make_label("", 13, Color(0.95, 0.92, 0.85))
## [name, position] of every point of interest.
var _places: Array[Array] = []
## [enemy id, position, radius] of every creature camp.
var _camps: Array[Array] = []


func _init() -> void:
	super("World Map", Side.CENTER)


func setup(player: Player, map_texture: Texture2D, zone: Zone) -> void:
	_player = player
	_world_size = map_texture.get_width()
	set_title("World Map  -  %s" % zone.zone_name)
	_map.texture = map_texture
	_map.custom_minimum_size = Vector2(MAP_SIZE, MAP_SIZE)
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_SCALE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_map.add_child(_overlay)
	content.add_child(_map)
	content.add_child(_coords)
	for marker: Node3D in zone.get_node("PointsOfInterest").get_children():
		_places.append([String(marker.name), marker.global_position])
	for spawner: EnemySpawner in zone.get_node("Spawners").get_children():
		_camps.append([spawner.enemy_data.id, spawner.global_position, spawner.radius + 8.0])


func _process(_delta: float) -> void:
	if not visible:
		return
	_overlay.queue_redraw()
	var p := _player.global_position
	var text := "Player: %d, %d" % [roundi(p.x), roundi(p.z)]
	var mouse := _map.get_local_mouse_position()
	if Rect2(Vector2.ZERO, _map.size).has_point(mouse):
		var world := (mouse / _map.size - Vector2(0.5, 0.5)) * _world_size
		text += "        Cursor: %d, %d" % [roundi(world.x), roundi(world.y)]
	_coords.text = text


func _to_map(world: Vector3) -> Vector2:
	return (Vector2(world.x, world.z) / _world_size + Vector2(0.5, 0.5)) * _map.size


func _draw_overlay() -> void:
	var font := get_theme_default_font()
	var pixels_per_meter := _map.size.x / _world_size
	# Where the creatures for unfinished quests live.
	for entry in _player.quest_log.active:
		var quest: QuestData = entry["quest"]
		if _player.quest_log.state(quest) != QuestLog.State.ACTIVE:
			continue
		for camp in _camps:
			if camp[0] == quest.enemy_id:
				_overlay.draw_circle(_to_map(camp[1]), camp[2] * pixels_per_meter, Color(1, 0.82, 0, 0.22))
				_overlay.draw_arc(_to_map(camp[1]), camp[2] * pixels_per_meter, 0, TAU, 32, Color(1, 0.82, 0, 0.7), 1.5)
	for place in _places:
		var at := _to_map(place[1])
		_overlay.draw_string_outline(font, at - Vector2(80, 0), place[0], HORIZONTAL_ALIGNMENT_CENTER, 160, 14, 4, Color.BLACK)
		_overlay.draw_string(font, at - Vector2(80, 0), place[0], HORIZONTAL_ALIGNMENT_CENTER, 160, 14, Color(1, 0.92, 0.7))
	for node in get_tree().get_nodes_in_group("npcs"):
		var npc := node as Npc
		var at := _to_map(npc.global_position)
		var marker := npc.quest_marker_text()
		if marker != "":
			_overlay.draw_string_outline(font, at + Vector2(-5, -6), marker, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color.BLACK)
			_overlay.draw_string(font, at + Vector2(-5, -6), marker, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Npc.QUEST_YELLOW)
		else:
			_overlay.draw_circle(at, 3.0, Color(1, 0.85, 0.2))
	# The player arrow.
	var center := _to_map(_player.global_position)
	var forward := Vector2(-sin(_player.rotation.y), -cos(_player.rotation.y))
	var side := Vector2(-forward.y, forward.x)
	var arrow := PackedVector2Array([center + forward * 11.0, center - forward * 7.0 + side * 7.0, center - forward * 3.0, center - forward * 7.0 - side * 7.0])
	_overlay.draw_colored_polygon(arrow, Color.WHITE)
	_overlay.draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color.BLACK, 1.5)
