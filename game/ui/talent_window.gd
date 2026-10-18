class_name TalentWindow
extends GameWindow
## Talents (N): the class's talent trees side by side. Click a talent to spend a
## point in it. Each row opens after 3 points in that tree; Reset gives every point back.

const BUTTON_SIZE := 50.0

var _player: Player
var _points := Hud.make_label("", 15, Hud.GOLD)
var _tree_labels: Array[Label] = []
var _buttons := {}


func _init() -> void:
	super("Talents")


func setup(player: Player) -> void:
	_player = player
	var trees := HBoxContainer.new()
	trees.add_theme_constant_override("separation", 12)
	for tree in player.talent_trees.size():
		trees.add_child(_build_tree(tree))
	content.add_child(trees)
	var footer := HBoxContainer.new()
	_points.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_points)
	var reset := Button.new()
	reset.text = "Reset Talents"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(player.reset_talents)
	footer.add_child(reset)
	content.add_child(footer)
	player.talents_changed.connect(refresh)
	player.leveled_up.connect(func(_level: int) -> void: refresh())
	refresh()


func refresh() -> void:
	_points.text = "Talent points available: %d" % _player.talent_points_free()
	for tree in _tree_labels.size():
		_tree_labels[tree].text = "%s  (%d)" % [_player.talent_trees[tree], _player.points_in_tree(tree)]
	for talent: TalentData in _buttons:
		(_buttons[talent] as Control).queue_redraw()


func _build_tree(tree: int) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.14, 0.9)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	var title := Hud.make_label("", 16, Hud.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tree_labels.append(title)
	box.add_child(title)
	var max_tier := 0
	for talent in _player.talents:
		if talent.tree == tree:
			max_tier = maxi(max_tier, talent.tier)
	for tier in range(1, max_tier + 1):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 22)
		row.custom_minimum_size = Vector2(150, BUTTON_SIZE)
		var in_row := _player.talents.filter(func(t: TalentData) -> bool: return t.tree == tree and t.tier == tier)
		in_row.sort_custom(func(a: TalentData, b: TalentData) -> bool: return a.column < b.column)
		for talent: TalentData in in_row:
			row.add_child(_talent_button(talent))
		box.add_child(row)
	panel.add_child(box)
	return panel


func _talent_button(talent: TalentData) -> Control:
	var button := Control.new()
	button.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	button.tooltip_text = talent.display_name
	button.draw.connect(_draw_talent.bind(button, talent))
	button.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click and not click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_player.learn_talent(talent))
	_buttons[talent] = button
	return button


func _tooltip_text(talent: TalentData) -> String:
	var rank := _player.talent_rank(talent) if _player else 0
	return "%s\nRank %d/%d\n%s" % [talent.display_name, rank, talent.max_rank, talent.describe(rank)]


## Gray = locked, green border = can learn, gold border = fully learned.
func _draw_talent(button: Control, talent: TalentData) -> void:
	var rect := Rect2(Vector2.ZERO, button.size)
	var rank := _player.talent_rank(talent)
	var blocked := _player.talent_block_reason(talent)
	var locked := rank == 0 and blocked != "" and blocked != "No talent points left."
	var font := ThemeDB.fallback_font
	button.draw_rect(rect, Color(0, 0, 0, 0.7))
	var inner := rect.grow(-3.0)
	var color := talent.icon_color.darkened(0.6) if locked else talent.icon_color
	button.draw_rect(inner, color.darkened(0.35))
	button.draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.55)), color)
	var baseline := Vector2(inner.position.x, inner.get_center().y + 7)
	button.draw_string_outline(font, baseline, talent.icon_glyph, HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 18, 4, Color.BLACK)
	button.draw_string(font, baseline, talent.icon_glyph, HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 18, Color(0.6, 0.6, 0.6) if locked else Color.WHITE)
	var border := Color(0.35, 0.35, 0.35)
	if rank >= talent.max_rank:
		border = Hud.GOLD
	elif blocked == "":
		border = Color(0.2, 0.9, 0.2)
	button.draw_rect(rect, border, false, 2.0)
	var rank_text := "%d/%d" % [rank, talent.max_rank]
	var corner := Vector2(rect.position.x, rect.end.y + 13)
	button.draw_string_outline(font, corner, rank_text, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x, 12, 4, Color.BLACK)
	button.draw_string(font, corner, rank_text, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x, 12, border if rank > 0 else Color(0.85, 0.85, 0.85))
	button.tooltip_text = _tooltip_text(talent)
