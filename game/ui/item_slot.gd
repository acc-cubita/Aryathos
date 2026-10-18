class_name ItemSlot
extends Control
## A square that shows one item (or an empty slot) with a quality-colored border,
## a stack count and a WoW-style tooltip. Emits `clicked` on left or right click.
## Bag slots with potions can be dragged onto the action bar.

signal clicked

var item: ItemData:
	set(value):
		item = value
		tooltip_text = item.display_name if item else placeholder
		queue_redraw()
var count := 1:
	set(value):
		count = value
		queue_redraw()
## Text shown in an empty slot (e.g. "Head").
var placeholder := ""
## True for bag slots: usable items can be dragged out of them.
var drag_source := false


func _init(side := 44.0) -> void:
	custom_minimum_size = Vector2(side, side)
	focus_mode = Control.FOCUS_NONE


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and not click.pressed and click.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		clicked.emit()
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not drag_source or item == null or not item.is_usable():
		return null
	var preview := ItemSlot.new()
	preview.item = item
	set_drag_preview(preview)
	return {"entry": item, "from_slot": -1}


func _draw() -> void:
	if item == null:
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Color(0, 0, 0, 0.6))
		draw_string(get_theme_default_font(), Vector2(0, size.y * 0.5 + 4), placeholder, HORIZONTAL_ALIGNMENT_CENTER, size.x, 10, Color(0.5, 0.5, 0.5))
		draw_rect(rect, Color(0.3, 0.28, 0.25), false, 1.0)
		return
	paint(self, item, Rect2(Vector2.ZERO, size), count)


func _make_custom_tooltip(_for_text: String) -> Object:
	return tooltip(item) if item else null


## Draws an item's icon (or its color and letters while there is no art), its
## quality border and, for stacks, the count in the bottom right corner.
static func paint(canvas: CanvasItem, slot_item: ItemData, rect: Rect2, stack := 1) -> void:
	var font := ThemeDB.fallback_font
	canvas.draw_rect(rect, Color(0, 0, 0, 0.6))
	var inner := rect.grow(-3.0)
	if slot_item.icon:
		canvas.draw_texture_rect(slot_item.icon, inner, false)
	else:
		canvas.draw_rect(inner, slot_item.icon_color.darkened(0.35))
		canvas.draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.5)), slot_item.icon_color)
		var baseline := Vector2(inner.position.x, inner.get_center().y + 6)
		canvas.draw_string_outline(font, baseline, slot_item.icon_glyph, HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 17, 4, Color.BLACK)
		canvas.draw_string(font, baseline, slot_item.icon_glyph, HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 17, Color.WHITE)
	canvas.draw_rect(rect, slot_item.quality_color(), false, 2.0)
	if stack > 1 or (stack == 0 and slot_item.max_stack > 1):
		var corner := Vector2(rect.position.x, rect.end.y - 4)
		canvas.draw_string_outline(font, corner, str(stack), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 4, 13, 4, Color.BLACK)
		canvas.draw_string(font, corner, str(stack), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 4, 13, Color.WHITE)


## Tooltip with the name in its quality color, like WoW.
static func tooltip(slot_item: ItemData) -> Control:
	var box := VBoxContainer.new()
	box.add_child(Hud.make_label(slot_item.display_name, 15, slot_item.quality_color()))
	for line in slot_item.detail_lines():
		var color := Color.WHITE
		if line.begins_with("+") or line.begins_with("Use:"):
			color = Color(0.12, 1, 0)
		elif line.begins_with("Requires"):
			var met := Game.player.standing_with(slot_item.required_faction) >= slot_item.required_standing
			color = Color.WHITE if met else Color(1, 0.25, 0.2)
		elif line.begins_with("\""):
			color = Color(1, 0.82, 0)
		box.add_child(Hud.make_label(line, 13, color))
	return box
