class_name QuestLogWindow
extends GameWindow
## Quest log (L): your active quests on the left; the selected quest's story,
## objective and reward on the right, with an Abandon button.

var _player: Player
var _selected: QuestData
var _list := VBoxContainer.new()
var _quest_title := Hud.make_label("", 18, Hud.GOLD)
var _body := Hud.make_label("", 13, Color(0.95, 0.92, 0.85))
var _objective := Hud.make_label("", 14, Color.WHITE)
var _reward := Hud.make_label("", 13, Color(1, 0.82, 0))
var _abandon := Button.new()


func _init() -> void:
	super("Quest Log")


func setup(player: Player) -> void:
	_player = player
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	_list.custom_minimum_size.x = 210
	columns.add_child(_list)
	var details := VBoxContainer.new()
	details.custom_minimum_size.x = 380
	details.add_theme_constant_override("separation", 10)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for part: Control in [_quest_title, _body, _objective, _reward]:
		details.add_child(part)
	_abandon.text = "Abandon Quest"
	_abandon.focus_mode = Control.FOCUS_NONE
	_abandon.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_abandon.pressed.connect(func() -> void: _player.quest_log.abandon(_selected))
	details.add_child(_abandon)
	columns.add_child(details)
	content.add_child(columns)
	player.quest_log.changed.connect(refresh)


func refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	var quests: Array[QuestData] = []
	for entry in _player.quest_log.active:
		quests.append(entry["quest"])
	if not quests.has(_selected):
		_selected = quests[0] if not quests.is_empty() else null
	for quest in quests:
		var button := Button.new()
		var ready := _player.quest_log.state(quest) == QuestLog.State.READY
		button.text = quest.title + ("  (Complete)" if ready else "")
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.button_pressed = quest == _selected
		button.pressed.connect(func() -> void:
			_selected = quest
			refresh())
		_list.add_child(button)
	_show_selected()


func _show_selected() -> void:
	_abandon.visible = _selected != null
	_objective.visible = _selected != null
	_reward.visible = _selected != null
	if _selected == null:
		_quest_title.text = "No active quests"
		_body.text = "Look for characters with a yellow ! above their heads."
		return
	var quest := _selected
	_quest_title.text = quest.title
	_body.text = quest.offer_text.replace("{name}", _player.unit_name)
	_objective.text = "- " + quest.objective_line(_player.quest_log.progress(quest))
	_reward.text = "Reward: %d experience%s" % [quest.xp_reward, "  +  [%s]" % quest.reward_item.display_name if quest.reward_item else ""]


func _process(_delta: float) -> void:
	# Progress changes while the log is open (kills), so keep the counter fresh.
	if visible and _selected:
		_objective.text = "- " + _selected.objective_line(_player.quest_log.progress(_selected))
