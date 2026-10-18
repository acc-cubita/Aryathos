class_name ReputationWindow
extends GameWindow
## Reputation (U): your standing with every faction, as WoW-colored progress bars.

var _player: Player
var _rows := VBoxContainer.new()


func _init() -> void:
	super("Reputation")


func setup(player: Player) -> void:
	_player = player
	_rows.add_theme_constant_override("separation", 14)
	_rows.custom_minimum_size.x = 380
	content.add_child(_rows)
	player.reputation_changed.connect(refresh)
	refresh()


func refresh() -> void:
	for child in _rows.get_children():
		child.queue_free()
	for faction in Database.factions():
		var value := _player.reputation_with(faction)
		var standing := FactionData.standing_for(value)
		var span := FactionData.standing_range(standing)
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		row.add_child(Hud.make_label(faction.display_name, 16, Hud.GOLD))
		var bar := StatBar.new(FactionData.STANDING_COLORS[standing], 18, 12)
		bar.show_values(value - span.x, span.y - span.x, "%s   %d / %d" % [FactionData.STANDING_NAMES[standing], value - span.x, span.y - span.x])
		row.add_child(bar)
		var about := Hud.make_label(faction.description, 12, Color(0.7, 0.7, 0.7))
		about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(about)
		var discount := FactionData.DISCOUNTS[standing]
		if discount > 0.0:
			row.add_child(Hud.make_label("Merchants of this faction give you %d%% off." % roundi(discount * 100), 12, Color(0.3, 1, 0.4)))
		_rows.add_child(row)
