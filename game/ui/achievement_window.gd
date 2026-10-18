class_name AchievementWindow
extends GameWindow
## Achievements (Y): every achievement by category with progress, total points,
## and a Statistics list at the bottom.

const STAT_NAMES := [
	["kills", "Creatures killed"], ["kill:shardfang_wolf", "Shardfang Wolves killed"],
	["kill:gloomshard_scavenger", "Gloomshard Scavengers killed"], ["kill:grimjaw", "Grimjaw defeated"],
	["quests_completed", "Quests completed"], ["deaths", "Deaths"], ["potions_used", "Potions drunk"],
	["herbs_gathered", "Herbs gathered"], ["items_crafted", "Items crafted"],
]

var _player: Player
var _points := Hud.make_label("", 16, Hud.GOLD)
var _list := VBoxContainer.new()


func _init() -> void:
	super("Achievements", Side.CENTER)


func setup(player: Player) -> void:
	_player = player
	content.add_child(_points)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	content.add_child(scroll)
	player.achievements.changed.connect(func() -> void:
		if visible:
			refresh())


func refresh() -> void:
	var tracker := _player.achievements
	var earned_count := tracker.all().filter(func(a: AchievementData) -> bool: return tracker.is_earned(a)).size()
	_points.text = "Achievement Points: %d        Earned: %d / %d" % [tracker.points(), earned_count, tracker.all().size()]
	for child in _list.get_children():
		child.queue_free()
	var category := -1
	for achievement in tracker.all():
		if achievement.category != category:
			category = achievement.category
			_list.add_child(Hud.make_label(AchievementData.CATEGORIES[category], 17, Hud.GOLD))
		_list.add_child(_row(achievement))
	_list.add_child(Hud.make_label("Statistics", 17, Hud.GOLD))
	for entry: Array in STAT_NAMES:
		_list.add_child(_stat_row(entry[1], str(tracker.stat(entry[0]))))
	_list.add_child(_stat_row("Money looted", Game.format_money(tracker.stat("money_looted"))))
	_list.add_child(_stat_row("Places discovered", str(_player.discovered.size())))


func _row(achievement: AchievementData) -> Control:
	var tracker := _player.achievements
	var earned := tracker.is_earned(achievement)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(40, 40)
	icon.color = achievement.icon_color if earned else achievement.icon_color.darkened(0.7)
	var glyph := Hud.make_label(achievement.icon_glyph, 16, Color.WHITE if earned else Color(0.5, 0.5, 0.5))
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_child(glyph)
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 1)
	text.add_child(Hud.make_label(achievement.display_name, 15, Hud.GOLD if earned else Color(0.85, 0.85, 0.85)))
	text.add_child(Hud.make_label(achievement.description, 12, Color(0.75, 0.75, 0.75)))
	var p := tracker.progress(achievement)
	if earned:
		text.add_child(Hud.make_label("Earned %s" % tracker.earned_on(achievement), 11, Color(0.4, 1, 0.45)))
	elif p.y > 1:
		var bar := StatBar.new(Color(0.25, 0.55, 0.2), 12, 10)
		bar.custom_minimum_size.x = 260
		bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		bar.show_values(p.x, p.y, "%d / %d" % [p.x, p.y])
		text.add_child(bar)
	row.add_child(text)
	row.add_child(Hud.make_label("%d" % achievement.points, 18, Hud.GOLD if earned else Color(0.5, 0.5, 0.5)))
	return row


func _stat_row(label: String, value: String) -> Control:
	var row := HBoxContainer.new()
	var name_label := Hud.make_label(label, 13, Color(0.85, 0.85, 0.85))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(Hud.make_label(value, 13, Color.WHITE))
	return row
