class_name LootWindow
extends PanelContainer
## Lists the items on a corpse. Click an item to take it, or use "Loot All".

const CLOSE_DISTANCE := 8.0

var _player: Player
var _corpse: Enemy
var _rows := VBoxContainer.new()


func setup(player: Player) -> void:
	_player = player
	add_theme_stylebox_override("panel", Hud.panel_style())
	custom_minimum_size = Vector2(260, 0)
	position = Vector2(440, 260)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(Hud.make_label("Loot", 18, Hud.GOLD))
	_rows.add_theme_constant_override("separation", 4)
	box.add_child(_rows)
	var loot_all := Button.new()
	loot_all.text = "Loot All"
	loot_all.focus_mode = Control.FOCUS_NONE
	loot_all.pressed.connect(_loot_all)
	box.add_child(loot_all)
	add_child(box)
	Game.loot_opened.connect(open)


func open(corpse: Enemy) -> void:
	_corpse = corpse
	visible = true
	_rebuild()


func _process(_delta: float) -> void:
	if visible and (_corpse == null or not _corpse.has_loot() or _player.is_dead \
			or _player.global_position.distance_to(_corpse.global_position) > CLOSE_DISTANCE):
		visible = false
		_corpse = null


func _rebuild() -> void:
	for child in _rows.get_children():
		child.queue_free()
	for i in _corpse.loot_items.size():
		var item := _corpse.loot_items[i]
		var row := HBoxContainer.new()
		var slot := ItemSlot.new(40)
		slot.item = item
		slot.clicked.connect(_take.bind(i))
		row.add_child(slot)
		var label := Hud.make_label(item.display_name, 14, item.quality_color())
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
		_rows.add_child(row)


func _take(index: int) -> void:
	_player.take_loot(_corpse, index)
	if _corpse.has_loot():
		_rebuild()


func _loot_all() -> void:
	while _corpse and not _corpse.loot_items.is_empty():
		var before := _corpse.loot_items.size()
		_player.take_loot(_corpse, 0)
		if _corpse.loot_items.size() == before:
			break
	if _corpse and _corpse.has_loot():
		_rebuild()
