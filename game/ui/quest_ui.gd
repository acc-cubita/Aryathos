class_name QuestUi
extends Control
## The quest dialog shown when talking to an NPC (offer, progress, hand-in),
## and the objective tracker on the right side of the screen.

const CLOSE_DISTANCE := 9.0

var _player: Player
var _npc: Npc
var dialog := PanelContainer.new()
var _title := Hud.make_label("", 20, Hud.GOLD)
var _body := Hud.make_label("", 14, Color(0.95, 0.92, 0.85))
var _details := Hud.make_label("", 14, Color(1.0, 0.82, 0.0))
var _buttons := HBoxContainer.new()
var _tracker := VBoxContainer.new()


func setup(player: Player, tracker_parent: Control) -> void:
	_player = player
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	dialog.add_theme_stylebox_override("panel", Hud.panel_style())
	dialog.position = Vector2(16, 150)
	dialog.custom_minimum_size = Vector2(400, 0)
	dialog.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_buttons.add_theme_constant_override("separation", 8)
	for part: Control in [_title, _body, _details, _buttons]:
		box.add_child(part)
	dialog.add_child(box)
	add_child(dialog)

	_tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tracker_parent.add_child(_tracker)
	player.quest_log.changed.connect(_refresh_tracker)
	Game.npc_interacted.connect(open)


## Shows what this NPC has for the player: a hand-in first, then a new quest,
## then progress on a running quest, otherwise a greeting.
func open(npc: Npc) -> void:
	_npc = npc
	var quest_log := _player.quest_log
	var turn_ins := quest_log.turn_ins_for(npc.npc_id)
	for quest in turn_ins:
		if quest_log.state(quest) == QuestLog.State.READY:
			_show(quest.title, quest.complete_text, _reward_text(quest), [
				["Complete Quest", func() -> void: quest_log.turn_in(quest); close()],
			])
			return
	for quest in npc.quests:
		if quest_log.state(quest) == QuestLog.State.AVAILABLE:
			_show(quest.title, quest.offer_text, "Objective: %s  x%d\n%s" % [quest.objective, quest.required, _reward_text(quest)], [
				["Accept", func() -> void: quest_log.accept(quest, npc.npc_id); close()],
				["Decline", close],
			])
			return
	for quest in turn_ins:
		_show(quest.title, quest.progress_text, "%s: %d/%d" % [quest.objective, quest_log.progress(quest), quest.required], [["Goodbye", close]])
		return
	if not npc.teaches.is_empty():
		_show_trainer(npc)
	elif npc.vendor_items.is_empty():
		_show(npc.unit_name, npc.greeting, "", [["Goodbye", close]])


## A trainer offers every profession you do not know yet.
func _show_trainer(npc: Npc) -> void:
	var buttons := []
	var details := PackedStringArray()
	for profession in npc.teaches:
		details.append("%s: %s" % [profession.display_name, profession.description])
		if not _player.knows_profession(profession):
			buttons.append(["Learn " + profession.display_name, func() -> void:
				_player.learn_profession(profession)
				open(npc)])
	buttons.append(["Goodbye", close])
	_show(npc.unit_name, npc.greeting, "\n".join(details), buttons)


func _reward_text(quest: QuestData) -> String:
	var text := "Reward: %d experience" % quest.xp_reward
	if quest.reward_item:
		text += "  +  [%s]" % quest.reward_item.display_name
	for i in mini(quest.reputation_factions.size(), quest.reputation_amounts.size()):
		text += "\n+%d reputation with %s" % [quest.reputation_amounts[i], quest.reputation_factions[i].display_name]
	return text


func close() -> void:
	dialog.visible = false
	_npc = null


func _process(_delta: float) -> void:
	if dialog.visible and (_npc == null or _player.is_dead or _player.global_position.distance_to(_npc.global_position) > CLOSE_DISTANCE):
		close()


func _show(title: String, body: String, details: String, buttons: Array) -> void:
	_title.text = title
	_body.text = body.replace("{name}", _player.unit_name)
	_details.text = details
	_details.visible = details != ""
	for child in _buttons.get_children():
		child.queue_free()
	for entry: Array in buttons:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(130, 34)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(entry[1])
		_buttons.add_child(button)
	dialog.visible = true


func _refresh_tracker() -> void:
	for child in _tracker.get_children():
		child.queue_free()
	for entry in _player.quest_log.active:
		var quest: QuestData = entry["quest"]
		var count: int = entry["count"]
		var done := count >= quest.required
		_tracker.add_child(Hud.make_label(quest.title, 15, Hud.GOLD))
		var line := "  - %s: %d/%d%s" % [quest.objective, count, quest.required, "  (Complete)" if done else ""]
		_tracker.add_child(Hud.make_label(line, 13, Color(0.4, 1.0, 0.45) if done else Color(0.92, 0.92, 0.92)))
