class_name AbilityIcon
extends Control
## A square ability icon with a WoW-style tooltip. In the spellbook it can be
## dragged onto the action bar.

var ability: AbilityData
var draggable := false


func _init(icon_ability: AbilityData = null, side := 44.0) -> void:
	ability = icon_ability
	custom_minimum_size = Vector2(side, side)
	tooltip_text = ability.display_name if ability else ""


func _draw() -> void:
	paint(self, ability, Rect2(Vector2.ZERO, size))


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not draggable or ability == null:
		return null
	set_drag_preview(AbilityIcon.new(ability))
	return {"entry": ability, "from_slot": -1}


func _make_custom_tooltip(_for_text: String) -> Object:
	return tooltip(ability) if ability else null


## Draws an ability's icon (or its color and letters while there is no art) into `rect`.
static func paint(canvas: CanvasItem, icon_ability: AbilityData, rect: Rect2) -> void:
	canvas.draw_rect(rect, Color(0, 0, 0, 0.7))
	if icon_ability:
		var inner := rect.grow(-3.0)
		if icon_ability.icon:
			canvas.draw_texture_rect(icon_ability.icon, inner, false)
		else:
			var font := ThemeDB.fallback_font
			canvas.draw_rect(inner, icon_ability.icon_color.darkened(0.4))
			canvas.draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.55)), icon_ability.icon_color)
			var baseline := Vector2(inner.position.x, inner.get_center().y + 7)
			canvas.draw_string_outline(font, baseline, icon_ability.icon_glyph, HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 20, 4, Color.BLACK)
			canvas.draw_string(font, baseline, icon_ability.icon_glyph, HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 20, Color.WHITE)
	canvas.draw_rect(rect, Color(0.55, 0.48, 0.35), false, 1.5)


static func tooltip(icon_ability: AbilityData) -> Control:
	var box := VBoxContainer.new()
	box.add_child(Hud.make_label(icon_ability.display_name, 15, Color.WHITE))
	box.add_child(Hud.make_label(rules_text(icon_ability), 13, Color(0.85, 0.85, 0.85)))
	var description := Hud.make_label(icon_ability.description, 13, Color(1, 0.82, 0))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 260
	box.add_child(description)
	return box


## "10 mana - Instant - Melee range - 8 sec cooldown"
static func rules_text(icon_ability: AbilityData) -> String:
	var parts := PackedStringArray()
	if icon_ability.mana_cost > 0:
		parts.append("%d mana" % icon_ability.mana_cost)
	parts.append("Instant" if icon_ability.cast_time <= 0.0 else "%.1f sec cast" % icon_ability.cast_time)
	parts.append("Melee range" if icon_ability.max_range <= Unit.MELEE_RANGE else "%d m range" % icon_ability.max_range)
	if icon_ability.cooldown > 0.0:
		parts.append("%d sec cooldown" % icon_ability.cooldown)
	return "  -  ".join(parts)
