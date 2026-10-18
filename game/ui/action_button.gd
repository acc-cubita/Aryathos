class_name ActionButton
extends Control
## One action bar button: an ability or a potion, with key label, cooldown sweep
## and range/mana tint. Click it or press its key to use it. Drag spells from the
## spellbook or potions from the bags onto it, drag between buttons to swap,
## or drag off the bar to remove.

var _player: Player
var _slot := 0
var _key := ""


func setup(player: Player, slot: int) -> void:
	_player = player
	_slot = slot
	_key = Keybinds.label_for("action_%d" % (slot + 1))
	custom_minimum_size = Vector2(54, 54)
	focus_mode = Control.FOCUS_NONE


func _entry() -> Resource:
	return _player.action_bar[_slot]


func _ability() -> AbilityData:
	return _entry() as AbilityData


## Uses the ability on release, so starting a drag never casts it.
func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and not click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_player.use_action_slot(_slot)
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	var entry := _entry()
	if entry == null:
		return null
	# Like WoW: it is picked up off the button; dropping it nowhere removes it.
	_player.action_bar[_slot] = null
	if entry is AbilityData:
		set_drag_preview(AbilityIcon.new(entry))
	else:
		var preview := ItemSlot.new()
		preview.item = entry
		set_drag_preview(preview)
	return {"entry": entry, "from_slot": _slot}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("entry")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_player.place_on_action_bar(data["entry"], _slot, data.get("from_slot", -1))


func _make_custom_tooltip(_for_text: String) -> Object:
	var entry := _entry()
	if entry is AbilityData:
		return AbilityIcon.tooltip(entry)
	if entry is ItemData:
		return ItemSlot.tooltip(entry)
	return null


func _process(_delta: float) -> void:
	var entry := _entry()
	tooltip_text = entry.get("display_name") if entry else ""
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var item := _entry() as ItemData
	if item:
		_draw_item(item, rect)
		return
	var ability := _ability()
	AbilityIcon.paint(self, ability, rect)
	var font := get_theme_default_font()
	if ability:
		var inner := rect.grow(-3.0)
		if _player.mana < _player.ability_mana_cost(ability):
			draw_rect(inner, Color(0.1, 0.2, 0.9, 0.45))
		elif not _player.in_ability_range(ability):
			draw_rect(inner, Color(0.9, 0.1, 0.1, 0.4))
		var left := _player.cooldown_left(ability)
		var total := _player.ability_cooldown(ability)
		if ability.triggers_gcd and _player.gcd_left() > left:
			left = _player.gcd_left()
			total = Unit.GCD
		if left > 0.0:
			_draw_sweep(inner, left / total)
			if left > Unit.GCD:
				var baseline := Vector2(inner.position.x, inner.get_center().y + 8)
				draw_string_outline(font, baseline, str(ceili(left)), HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 22, 4, Color.BLACK)
				draw_string(font, baseline, str(ceili(left)), HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 22, Color(1, 0.9, 0.4))
		if _player.casting == ability:
			draw_rect(rect, Hud.GOLD, false, 3.0)
	draw_string_outline(font, Vector2(4, 15), _key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color.BLACK)
	draw_string(font, Vector2(4, 15), _key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.92, 0.92, 0.92))


## A potion on the bar: how many are left, grayed out at zero, and its cooldown.
func _draw_item(item: ItemData, rect: Rect2) -> void:
	var have := _player.count_item(item)
	ItemSlot.paint(self, item, rect, have)
	var inner := rect.grow(-3.0)
	if have == 0:
		draw_rect(inner, Color(0.1, 0.1, 0.1, 0.7))
	var left := _player.item_cooldown_left(item)
	if left > 0.0:
		_draw_sweep(inner, left / maxf(item.use_cooldown, 0.01))
	var font := get_theme_default_font()
	draw_string_outline(font, Vector2(4, 15), _key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color.BLACK)
	draw_string(font, Vector2(4, 15), _key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.92, 0.92, 0.92))


## WoW-style clockwise cooldown sweep; `remaining` goes from 1 down to 0.
func _draw_sweep(rect: Rect2, remaining: float) -> void:
	if remaining < 0.02:
		return
	if remaining > 0.98:
		draw_rect(rect, Color(0, 0, 0, 0.6))
		return
	var center := rect.get_center()
	var half := rect.size * 0.5
	var start := -PI * 0.5 + (1.0 - remaining) * TAU
	var points := PackedVector2Array([center])
	var steps := 40
	for i in steps + 1:
		var angle := lerpf(start, PI * 1.5, float(i) / steps)
		var dir := Vector2(cos(angle), sin(angle))
		# Push each point out to the edge of the square.
		points.append(center + dir * minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001)))
	draw_colored_polygon(points, Color(0, 0, 0, 0.6))
