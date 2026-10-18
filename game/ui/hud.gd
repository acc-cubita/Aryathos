class_name Hud
extends CanvasLayer
## The WoW-style interface: unit frames, action bar, cast bar, XP bar, nameplates,
## floating combat text, chat, quest dialog/tracker, messages, death panel and menu,
## plus the WoW windows: backpack (B), character (C), spellbook (P), quest log (L),
## world map (M) and key bindings, opened by key or from the micro menu (bottom right).

const GOLD := Color(0.86, 0.7, 0.35)
const CAST_COLOR := Color(0.95, 0.75, 0.15)

const HELP_TEXT := """Movement
W / S  -  run / backpedal
A / D  -  turn  (strafe while holding right mouse)
Q / E  -  strafe      Space  -  jump
R or NumLock  -  autorun
Left drag  -  look      Right drag  -  look + steer
Both mouse buttons  -  run      Wheel  -  zoom

Combat
Tab  -  target nearest enemy      Left click  -  select
Right click enemy  -  attack
Right click NPC (or F)  -  talk / quests
Right click corpse (or F)  -  loot
1 - 0, -, =  -  action bar (hover for details)

Windows
B  bags    C  character    P  spellbook    N  talents    U  reputation    Y  achievements    K  professions
L  quest log    M  world map    Esc  menu
Alt+Z  hide interface    Print Screen  screenshot
F1  -  show / hide this panel"""

var _player: Player
var _root: Control
var _overlay: WorldOverlay
var _target_frame: UnitFrame
var _zone_label: Label
var _zone_name := ""
var _help: PanelContainer
var _cast_panel: PanelContainer
var _cast_bar := StatBar.new(CAST_COLOR, 20, 13)
var _cast_name := ""
var _cast_fade := 0.0
var _xp_bar := StatBar.new(Color(0.55, 0.2, 0.85), 12, 10)
var _error: Label
var _error_tween: Tween
var _message: Label
var _message_tween: Tween
var _right_column := VBoxContainer.new()
var _bags := BagWindow.new()
var _character := CharacterWindow.new()
var _spellbook := SpellbookWindow.new()
var _quest_log := QuestLogWindow.new()
var _world_map := WorldMapWindow.new()
var _keybindings := KeybindingsWindow.new()
var _sound := SoundWindow.new()
var _merchant := MerchantWindow.new()
var _talents := TalentWindow.new()
var _reputation := ReputationWindow.new()
var _achievements := AchievementWindow.new()
var _professions := ProfessionWindow.new()
var _toast := PanelContainer.new()
var _toast_name := make_label("", 20, Color.WHITE)
var _toast_queue: Array[AchievementData] = []
## Left-side windows in the order they were opened; they line up side by side.
var _left_open: Array[GameWindow] = []
var _quest_ui: QuestUi
var _loot: LootWindow
var _tooltip := PanelContainer.new()
var _tooltip_lines := VBoxContainer.new()
var _micro_menu := HBoxContainer.new()
var _death_panel: Control
var _menu_panel: Control


func setup(player: Player, zone_name: String, map_texture: Texture2D) -> void:
	_player = player
	_zone_name = zone_name
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_overlay = WorldOverlay.new()
	_overlay.setup(player, player.camera_rig.camera)
	_root.add_child(_overlay)

	var player_frame := UnitFrame.new()
	player_frame.unit = player
	player_frame.position = Vector2(16, 16)
	_root.add_child(player_frame)
	_target_frame = UnitFrame.new()
	_target_frame.position = Vector2(284, 16)
	_root.add_child(_target_frame)

	_build_action_bar()
	_build_zone_info()

	var minimap := Minimap.new()
	_root.add_child(minimap)
	minimap.setup(player, map_texture)
	minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	minimap.offset_left = -16 - Minimap.SIZE
	minimap.offset_right = -16
	minimap.offset_top = 38
	minimap.offset_bottom = 38 + Minimap.SIZE

	var chat := ChatLog.new()
	_root.add_child(chat)
	chat.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	chat.offset_left = 16
	chat.offset_top = -186
	chat.offset_right = 426
	chat.offset_bottom = -16

	_quest_ui = QuestUi.new()
	_root.add_child(_quest_ui)
	_quest_ui.setup(player, _right_column)

	_loot = LootWindow.new()
	_root.add_child(_loot)
	_loot.setup(player)

	_build_windows(map_texture)
	_build_achievement_toast()
	_build_micro_menu()
	_build_unit_tooltip()

	_message = make_label("", 26, GOLD)
	_message.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_message.offset_top = 80
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_message)

	_error = make_label("", 18, Color(1, 0.25, 0.2))
	_error.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_error.offset_top = 120
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_error)

	_death_panel = _center_panel("You have died.", [["Release Spirit", _player.release_spirit]])
	_menu_panel = _center_panel("Game Menu", [
		["Resume", func() -> void: _menu_panel.visible = false],
		["Key Bindings", func() -> void:
			_menu_panel.visible = false
			_keybindings.toggle()],
		["Sound", func() -> void:
			_menu_panel.visible = false
			_sound.toggle()],
		["New Character (erase save)", Game.new_character],
		["Quit Game", Game.quit_game],
	])

	Game.unit_damaged.connect(_on_unit_damaged)
	Game.unit_healed.connect(_on_unit_healed)
	Game.mana_restored.connect(func(unit: Unit, amount: int) -> void: _overlay.float_text(unit, "+%d mana" % amount, Color(0.4, 0.6, 1)))
	Game.unit_evaded.connect(func(unit: Unit, _source: Unit) -> void: _overlay.float_text(unit, "Evade", Color.WHITE))
	Game.error_message.connect(show_error)
	Game.system_message.connect(show_message)
	Game.menu_requested.connect(func() -> void: _menu_panel.visible = not _menu_panel.visible)
	player.target_changed.connect(func(unit: Unit) -> void: _target_frame.unit = unit)
	player.died.connect(func(_killer: Unit) -> void: _death_panel.visible = true)
	player.revived.connect(func() -> void: _death_panel.visible = false)
	player.cast_started.connect(func(ability: AbilityData) -> void: _cast_name = ability.display_name)
	player.cast_ended.connect(_on_cast_ended)
	player.activity_started.connect(func(text: String) -> void: _cast_name = text)
	player.activity_ended.connect(_on_cast_ended)


func show_error(text: String) -> void:
	_error.text = text
	_error.modulate.a = 1.0
	if _error_tween:
		_error_tween.kill()
	_error_tween = create_tween()
	_error_tween.tween_property(_error, "modulate:a", 0.0, 0.8).set_delay(1.5)


## Big centered message (level up, quest progress).
func show_message(text: String, color: Color) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_message.modulate.a = 1.0
	if _message_tween:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_property(_message, "modulate:a", 0.0, 1.0).set_delay(2.0)


func _process(delta: float) -> void:
	if _player == null:
		return
	var p := _player.global_position
	_zone_label.text = "%s  (%d, %d)" % [_zone_name, roundi(p.x), roundi(p.z)]
	_update_unit_tooltip()
	if _bags.visible:
		_help.visible = false  # the backpack covers the help panel's corner
	var needed := Game.xp_to_next_level(_player.level)
	_xp_bar.show_values(_player.xp, needed, "XP  %d / %d" % [_player.xp, needed] if needed > 0 else "Max level")
	if _player.casting or _player.activity != "":
		var total := _player.cast_duration if _player.casting else _player.activity_duration
		var left := _player.cast_remaining() if _player.casting else _player.activity_remaining()
		_cast_bar.set_color(CAST_COLOR)
		_cast_bar.show_values(total - left, total, "%s   %.1f" % [_cast_name, left])
		_cast_panel.modulate.a = 1.0
		_cast_fade = 0.5
	elif _cast_fade > 0.0:
		_cast_fade -= delta
		_cast_panel.modulate.a = clampf(_cast_fade / 0.5, 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		_help.visible = not _help.visible
	elif event.is_action_pressed("toggle_ui"):
		_root.visible = not _root.visible
	elif event.is_action_pressed("screenshot"):
		take_screenshot()
	elif event.is_action_pressed("clear_target") and close_all_windows():
		# Esc closes open windows first, like WoW; only then does it reach the player.
		get_viewport().set_input_as_handled()
	else:
		for action: String in WINDOW_ACTIONS:
			if event.is_action_pressed(action):
				toggle_window(action)


const WINDOW_ACTIONS: Array[String] = ["toggle_bags", "toggle_character", "toggle_spellbook", "toggle_talents", "toggle_reputation", "toggle_achievements", "toggle_professions", "toggle_quest_log", "toggle_map"]


func toggle_window(action: String) -> void:
	var window: GameWindow = {
		"toggle_bags": _bags, "toggle_character": _character, "toggle_spellbook": _spellbook, "toggle_talents": _talents, "toggle_reputation": _reputation, "toggle_achievements": _achievements, "toggle_professions": _professions,
		"toggle_quest_log": _quest_log, "toggle_map": _world_map,
	}[action]
	window.toggle()
	_arrange_left_windows()


## Closes every open window and dialog. Returns false when nothing was open.
func close_all_windows() -> bool:
	var closed := false
	for node in get_tree().get_nodes_in_group("game_windows"):
		var window := node as GameWindow
		closed = closed or window.visible
		window.visible = false
	for panel: Control in [_loot, _menu_panel, _quest_ui.dialog]:
		closed = closed or panel.visible
		panel.visible = false
	_left_open.clear()
	return closed


## Saves the current frame to the user folder (Print Screen).
func take_screenshot() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	var path := "user://screenshots/screenshot_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	get_viewport().get_texture().get_image().save_png(path)
	Game.chat("Screen captured: %s" % ProjectSettings.globalize_path(path))


func _on_cast_ended(success: bool) -> void:
	if success:
		_cast_bar.set_color(Color(0.3, 0.9, 0.3))
		_cast_bar.show_values(1.0, 1.0, _cast_name)
	else:
		_cast_bar.set_color(Color(0.85, 0.15, 0.1))
		_cast_bar.show_values(_cast_bar.value, _cast_bar.max_value, "Interrupted")
	_cast_fade = 0.5


## Damage you deal shows over the enemy; damage you take shows over you in red.
func _on_unit_damaged(target: Unit, source: Unit, amount: int, crit: bool, color: Color) -> void:
	if target == _player:
		_overlay.float_text(target, "-%d" % amount, Color(1, 0.25, 0.2), crit)
	elif source == _player:
		_overlay.float_text(target, "%d%s" % [amount, "!" if crit else ""], color, crit)


func _on_unit_healed(target: Unit, source: Unit, amount: int, crit: bool) -> void:
	if target == _player or source == _player:
		_overlay.float_text(target, "+%d" % amount, Color(0.3, 1, 0.4), crit)


func _build_action_bar() -> void:
	var bottom := VBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 10)
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -16
	bottom.offset_bottom = -16
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(bottom)

	_cast_panel = PanelContainer.new()
	_cast_panel.add_theme_stylebox_override("panel", panel_style())
	_cast_panel.custom_minimum_size.x = 320
	_cast_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cast_panel.modulate.a = 0.0
	_cast_panel.add_child(_cast_bar)
	bottom.add_child(_cast_panel)

	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", 6)
	for i in Player.ACTION_SLOTS:
		var button := ActionButton.new()
		button.setup(_player, i)
		bar.add_child(button)
	bottom.add_child(bar)
	_xp_bar.custom_minimum_size.x = Player.ACTION_SLOTS * 54 + (Player.ACTION_SLOTS - 1) * 6
	_xp_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_xp_bar)


func _build_zone_info() -> void:
	_zone_label = make_label("", 16, GOLD)
	_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_zone_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_zone_label.offset_left = -400
	_zone_label.offset_right = -16
	_zone_label.offset_top = 12
	_root.add_child(_zone_label)

	# Right column: controls help (F1), then the quest tracker below it.
	_right_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right_column.add_theme_constant_override("separation", 12)
	_root.add_child(_right_column)
	_right_column.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_right_column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_right_column.offset_right = -16
	_right_column.offset_top = 38 + Minimap.SIZE + 12
	_help = PanelContainer.new()
	_help.add_theme_stylebox_override("panel", panel_style())
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.add_child(make_label(HELP_TEXT, 13, Color(0.95, 0.92, 0.85)))
	_right_column.add_child(_help)
	# The help panel tucks itself away after a while; F1 brings it back.
	create_tween().tween_callback(func() -> void: _help.visible = false).set_delay(25.0)

	# WoW-style zone title: shows on arrival, then fades out.
	var title := make_label(_zone_name, 44, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 170
	_root.add_child(title)
	title.create_tween().tween_property(title, "modulate:a", 0.0, 2.0).set_delay(3.0)


func _build_windows(map_texture: Texture2D) -> void:
	_bags.setup(_player)
	_character.setup(_player)
	_spellbook.setup(_player)
	_quest_log.setup(_player)
	_world_map.setup(_player, map_texture, Game.zone)
	_keybindings.setup()
	_sound.setup()
	_merchant.setup(_player, _bags)
	_talents.setup(_player)
	_reputation.setup(_player)
	_achievements.setup(_player)
	_professions.setup(_player)
	_bags.merchant = _merchant
	for window: GameWindow in [_character, _spellbook, _talents, _reputation, _professions, _quest_log, _merchant, _world_map, _achievements, _keybindings, _sound, _bags]:
		_root.add_child(window)
		match window.side:
			GameWindow.Side.CENTER:
				window.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
				window.grow_horizontal = Control.GROW_DIRECTION_BOTH
				window.grow_vertical = Control.GROW_DIRECTION_BOTH
			GameWindow.Side.RIGHT:
				window.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
				window.grow_horizontal = Control.GROW_DIRECTION_BEGIN
				window.grow_vertical = Control.GROW_DIRECTION_BEGIN
				window.offset_right = -16
				window.offset_bottom = -64
		window.visibility_changed.connect(_arrange_left_windows)


## Left-side windows sit next to each other in the order they were opened.
func _arrange_left_windows() -> void:
	for window: GameWindow in [_character, _spellbook, _talents, _reputation, _professions, _quest_log, _merchant]:
		if window.visible and not _left_open.has(window):
			_left_open.append(window)
		elif not window.visible:
			_left_open.erase(window)
	var x := 16.0
	for window in _left_open:
		window.position = Vector2(x, 110)
		x += window.get_combined_minimum_size().x + 10


## The golden "Achievement Earned" banner above the action bar; several queue up.
func _build_achievement_toast() -> void:
	var style := panel_style()
	style.border_color = GOLD
	style.set_border_width_all(3)
	style.set_content_margin_all(12)
	_toast.add_theme_stylebox_override("panel", style)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	var box := VBoxContainer.new()
	var heading := make_label("Achievement Earned!", 15, GOLD)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	box.add_child(_toast_name)
	_toast.add_child(box)
	_root.add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.custom_minimum_size.x = 360
	_toast.offset_bottom = -200
	_player.achievements.earned.connect(func(achievement: AchievementData) -> void:
		_toast_queue.append(achievement)
		if not _toast.visible:
			_show_next_toast())


func _show_next_toast() -> void:
	if _toast_queue.is_empty():
		_toast.visible = false
		return
	var achievement: AchievementData = _toast_queue.pop_front()
	_toast_name.text = "%s   (%d points)" % [achievement.display_name, achievement.points]
	_toast.visible = true
	_toast.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_toast, "modulate:a", 0.0, 0.6).set_delay(3.5)
	tween.tween_callback(_show_next_toast)


## WoW's row of small menu buttons in the bottom right corner.
func _build_micro_menu() -> void:
	_micro_menu.add_theme_constant_override("separation", 3)
	_root.add_child(_micro_menu)
	var entries := [
		["Ch", "Character Info", "toggle_character"], ["Sp", "Spellbook", "toggle_spellbook"],
		["Ta", "Talents", "toggle_talents"], ["Re", "Reputation", "toggle_reputation"], ["Ac", "Achievements", "toggle_achievements"], ["Pr", "Professions", "toggle_professions"],
		["Qu", "Quest Log", "toggle_quest_log"], ["Map", "World Map", "toggle_map"],
		["Bag", "Backpack", "toggle_bags"],
	]
	for entry: Array in entries:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(34, 34)
		button.add_theme_font_size_override("font_size", 12)
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = "%s (%s)" % [entry[1], Keybinds.describe(entry[2])]
		button.pressed.connect(toggle_window.bind(entry[2]))
		_micro_menu.add_child(button)
	var menu := Button.new()
	menu.text = "Esc"
	menu.custom_minimum_size = Vector2(34, 34)
	menu.add_theme_font_size_override("font_size", 12)
	menu.focus_mode = Control.FOCUS_NONE
	menu.tooltip_text = "Game Menu (Esc)"
	menu.pressed.connect(func() -> void: _menu_panel.visible = not _menu_panel.visible)
	_micro_menu.add_child(menu)
	_micro_menu.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_micro_menu.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_micro_menu.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_micro_menu.offset_right = -16
	_micro_menu.offset_bottom = -16


func _build_unit_tooltip() -> void:
	_tooltip.add_theme_stylebox_override("panel", panel_style())
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.visible = false
	_tooltip.add_child(_tooltip_lines)
	_root.add_child(_tooltip)


## WoW shows who is under the mouse in the bottom right, above the bags.
func _update_unit_tooltip() -> void:
	var unit: Unit = null
	var herb: GatherNode = null
	var thing: QuestObject = null
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _root.visible:
		var mouse := _root.get_global_mouse_position()
		unit = _player.pick_unit(mouse)
		if unit == null:
			herb = _player.pick_gather_node(mouse)
		if unit == null and herb == null:
			thing = _player.pick_quest_object(mouse)
	_tooltip.visible = unit != null or herb != null or thing != null
	if not _tooltip.visible:
		return
	for child in _tooltip_lines.get_children():
		child.queue_free()
	if thing:
		_tooltip_lines.add_child(make_label(thing.display_name, 16, Color.WHITE))
		_tooltip_lines.add_child(make_label("Quest object (right-click)", 13, GOLD))
		_place_tooltip()
		return
	if herb:
		var data := herb.data
		var skill := _player.profession_skill(data.profession)
		var color := Color(1, 0.3, 0.25) if skill < data.required_skill else ProfessionData.DIFFICULTY_COLORS[ProfessionData.difficulty(skill, data.required_skill)]
		_tooltip_lines.add_child(make_label(data.display_name, 16, Color.WHITE))
		_tooltip_lines.add_child(make_label("Requires %s (%d)" % [data.profession.display_name, data.required_skill], 13, color))
		_place_tooltip()
		return
	var color := Color(0.6, 0.6, 0.6) if unit.is_dead else (Color(1, 0.3, 0.25) if unit.is_hostile_to(_player) else Color(0.35, 1, 0.4))
	_tooltip_lines.add_child(make_label(unit.unit_name, 16, color))
	var kind := "Humanoid"
	var npc := unit as Npc
	var enemy := unit as Enemy
	if npc and npc.title != "":
		_tooltip_lines.add_child(make_label("<%s>" % npc.title, 13, Color(0.9, 0.9, 0.9)))
	if enemy and enemy.data.body == PlaceholderModel.Body.BEAST:
		kind = "Beast"
	var level_text := "Level %d %s%s" % [unit.level, kind, " (Elite)" if unit.is_elite else ""]
	_tooltip_lines.add_child(make_label(level_text, 13, Game.level_color(unit.level, _player.level)))
	if unit.is_dead:
		_tooltip_lines.add_child(make_label("Corpse" + ("  -  right-click to loot" if enemy and enemy.has_loot() else ""), 13, Color(0.8, 0.8, 0.8)))
	_place_tooltip()


func _place_tooltip() -> void:
	var bottom := _bags.global_position.y if _bags.visible else _micro_menu.global_position.y
	_tooltip.reset_size()
	_tooltip.global_position = Vector2(_root.size.x - 16 - _tooltip.size.x, bottom - 8 - _tooltip.size.y)


## A centered dialog with a title and buttons ([text, callable] pairs); starts hidden.
func _center_panel(title: String, buttons: Array) -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.visible = false
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var heading := make_label(title, 22, GOLD)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	for entry: Array in buttons:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(220, 36)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(entry[1])
		box.add_child(button)
	panel.add_child(box)
	center.add_child(panel)
	_root.add_child(center)
	return center


static func make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.85)
	style.border_color = Color(0.45, 0.42, 0.38)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	return style
