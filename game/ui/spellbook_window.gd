class_name SpellbookWindow
extends GameWindow
## Spellbook (P): every ability you know, including ones learned from talents.
## Drag an icon onto the action bar.

var _player: Player


func _init() -> void:
	super("Spellbook")


func setup(player: Player) -> void:
	_player = player
	player.talents_changed.connect(refresh)
	refresh()


func refresh() -> void:
	for child in content.get_children():
		child.queue_free()
	for ability in _player.abilities:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var icon := AbilityIcon.new(ability, 48)
		icon.draggable = true
		row.add_child(icon)
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", 0)
		text.add_child(Hud.make_label(ability.display_name, 15, Color.WHITE))
		text.add_child(Hud.make_label(AbilityIcon.rules_text(ability), 12, Color(0.75, 0.75, 0.75)))
		var description := Hud.make_label(ability.description, 12, Color(1, 0.82, 0))
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.custom_minimum_size.x = 320
		text.add_child(description)
		row.add_child(text)
		content.add_child(row)
	content.add_child(Hud.make_label("Drag a spell onto the action bar to place it there.", 12, Color(0.65, 0.65, 0.65)))
