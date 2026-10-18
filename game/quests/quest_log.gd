class_name QuestLog
extends RefCounted
## The player's quests: which are active, their progress, and which are done.
## Listens for kills, discoveries, gathering and crafting to advance objectives (quest
## items drop straight into the bags); quest objects report their use (use_object).

signal changed
signal quest_completed(quest: QuestData)

enum State { UNAVAILABLE, AVAILABLE, ACTIVE, READY, DONE }

const PROGRESS_COLOR := Color(1.0, 0.82, 0.0)

## Active quests in accept order: {"quest": QuestData, "giver": StringName, "count": int}.
var active: Array[Dictionary] = []

var _done := {}
var _player: Player


func _init(player: Player) -> void:
	_player = player
	Game.unit_killed.connect(_on_unit_killed)
	player.place_discovered.connect(_on_place_discovered)
	player.gathered.connect(func(item: ItemData, count: int) -> void: _on_item(QuestData.Kind.GATHER, item, count))
	player.crafted.connect(func(item: ItemData, count: int) -> void: _on_item(QuestData.Kind.CRAFT, item, count))


func state(quest: QuestData) -> State:
	if _done.has(quest.id):
		return State.DONE
	var entry := _entry(quest)
	if not entry.is_empty():
		return State.READY if int(entry["count"]) >= quest.required else State.ACTIVE
	if (quest.requires and not _done.has(quest.requires.id)) or _player.level < quest.min_level:
		return State.UNAVAILABLE
	return State.AVAILABLE


func progress(quest: QuestData) -> int:
	var entry := _entry(quest)
	return 0 if entry.is_empty() else int(entry["count"])


## Active quests that are handed in to this NPC.
func turn_ins_for(npc_id: StringName) -> Array[QuestData]:
	var result: Array[QuestData] = []
	for entry in active:
		var quest: QuestData = entry["quest"]
		var turn_in: StringName = quest.turn_in_npc if quest.turn_in_npc != &"" else entry["giver"]
		if turn_in == npc_id:
			result.append(quest)
	return result


func accept(quest: QuestData, giver: StringName) -> void:
	if state(quest) != State.AVAILABLE:
		return
	var count := 0
	if quest.kind == QuestData.Kind.EXPLORE:
		# places found before the quest count too
		count = quest.places.size() - Array(quest.places).filter(func(p: String) -> bool: return not _player.discovered.has(p)).size()
	active.append({"quest": quest, "giver": giver, "count": mini(count, quest.required)})
	Game.chat("Quest accepted: %s" % quest.title, Game.CHAT_QUEST)
	changed.emit()


func turn_in(quest: QuestData) -> void:
	if state(quest) != State.READY:
		return
	active.erase(_entry(quest))
	_done[quest.id] = true
	quest_completed.emit(quest)
	Game.chat("%s completed." % quest.title, Game.CHAT_QUEST)
	Game.chat("Experience gained: %d." % quest.xp_reward, Game.CHAT_XP)
	changed.emit()
	for i in mini(quest.reputation_factions.size(), quest.reputation_amounts.size()):
		_player.gain_reputation(quest.reputation_factions[i], quest.reputation_amounts[i])
	if quest.reward_item and _player.add_item(quest.reward_item):
		Game.chat("You receive item: [%s]." % quest.reward_item.display_name, Game.CHAT_LOOT)
	_player.gain_xp(quest.xp_reward)


func abandon(quest: QuestData) -> void:
	var entry := _entry(quest)
	if entry.is_empty():
		return
	active.erase(entry)
	Game.chat("Quest abandoned: %s" % quest.title, Game.CHAT_QUEST)
	changed.emit()


func to_save_data() -> Dictionary:
	var running := []
	for entry in active:
		running.append({"id": String((entry["quest"] as QuestData).id), "giver": String(entry["giver"]), "count": entry["count"]})
	var finished := []
	for id: StringName in _done:
		finished.append(String(id))
	return {"active": running, "done": finished}


func load_save_data(data: Dictionary) -> void:
	active.clear()
	_done.clear()
	for id: String in data.get("done", []):
		_done[StringName(id)] = true
	for entry: Dictionary in data.get("active", []):
		var quest := Database.quest(StringName(entry["id"]))
		if quest:
			active.append({"quest": quest, "giver": StringName(entry["giver"]), "count": int(entry["count"])})
	changed.emit()


## True while an active quest still needs this kind of quest object used.
func wants_object(object_id: StringName) -> bool:
	for entry in active:
		var quest: QuestData = entry["quest"]
		if quest.kind == QuestData.Kind.INTERACT and quest.object_id == object_id and int(entry["count"]) < quest.required:
			return true
	return false


## The player used a quest object: the first quest that wanted it moves on.
func use_object(object_id: StringName) -> bool:
	for entry in active:
		var quest: QuestData = entry["quest"]
		if quest.kind == QuestData.Kind.INTERACT and quest.object_id == object_id and int(entry["count"]) < quest.required:
			_advance(entry, 1)
			return true
	return false


func _advance(entry: Dictionary, amount: int) -> void:
	var quest: QuestData = entry["quest"]
	var count := mini(int(entry["count"]) + amount, quest.required)
	entry["count"] = count
	Game.system_message.emit(quest.objective_line(count), PROGRESS_COLOR)
	changed.emit()


func _on_place_discovered(place: String) -> void:
	for entry in active:
		var quest: QuestData = entry["quest"]
		if quest.kind == QuestData.Kind.EXPLORE and quest.places.has(place) and int(entry["count"]) < quest.required:
			_advance(entry, 1)


func _on_item(kind: QuestData.Kind, item: ItemData, amount: int) -> void:
	for entry in active:
		var quest: QuestData = entry["quest"]
		if quest.kind == kind and quest.item == item and int(entry["count"]) < quest.required:
			_advance(entry, amount)


func _entry(quest: QuestData) -> Dictionary:
	for entry in active:
		if entry["quest"] == quest:
			return entry
	return {}


func _on_unit_killed(unit: Unit, _killer: Unit) -> void:
	var enemy := unit as Enemy
	if enemy == null or enemy.tapped_by != _player:
		return
	for entry in active:
		var quest: QuestData = entry["quest"]
		var count: int = entry["count"]
		if quest.kind not in [QuestData.Kind.KILL, QuestData.Kind.COLLECT] or quest.enemy_id != enemy.data.id or count >= quest.required:
			continue
		if quest.kind == QuestData.Kind.COLLECT:
			if randf() >= quest.drop_chance:
				continue
			Game.chat("You receive loot: %s." % quest.objective, Game.CHAT_LOOT)
		_advance(entry, 1)
