class_name AchievementLog
extends RefCounted
## Tracks statistics (kills, deaths, money looted...) and awards achievements
## the moment their criteria are met.

signal earned(achievement: AchievementData)
signal changed

const CHAT_COLOR := Color(1.0, 0.75, 0.2)

## Counters shown on the Statistics list, e.g. "kills", "kill:shardfang_wolf", "deaths".
var stats := {}

var _earned := {}
var _all: Array[AchievementData] = []
var _player: Player


func _init(player: Player) -> void:
	_player = player
	_all = Database.achievements()
	_all.sort_custom(func(a: AchievementData, b: AchievementData) -> bool:
		return a.category < b.category or (a.category == b.category and a.points < b.points))
	Game.unit_killed.connect(_on_unit_killed)
	player.quest_log.quest_completed.connect(func(_quest: QuestData) -> void: add_stat("quests_completed"))
	player.died.connect(func(_killer: Unit) -> void: add_stat("deaths"))
	player.money_looted.connect(func(amount: int) -> void: add_stat("money_looted", amount))
	player.item_used.connect(func(_item: ItemData) -> void: add_stat("potions_used"))
	player.gathered.connect(func(_item: ItemData, amount: int) -> void: add_stat("herbs_gathered", amount))
	player.crafted.connect(func(_item: ItemData, amount: int) -> void: add_stat("items_crafted", amount))
	for state_signal: Signal in [player.leveled_up, player.reputation_changed, player.inventory_changed,
			player.talents_changed, player.place_discovered]:
		state_signal.connect(func(_a: Variant = null) -> void: evaluate())


func all() -> Array[AchievementData]:
	return _all


func is_earned(achievement: AchievementData) -> bool:
	return _earned.has(achievement.id)


## The day it was earned, e.g. "2026-10-15" ("" if not yet).
func earned_on(achievement: AchievementData) -> String:
	return _earned.get(achievement.id, "")


func points() -> int:
	var total := 0
	for achievement in _all:
		if is_earned(achievement):
			total += achievement.points
	return total


func stat(key: String) -> int:
	return int(stats.get(key, 0))


func add_stat(key: String, amount := 1) -> void:
	stats[key] = stat(key) + amount
	evaluate()


## (current, needed) for an achievement's criteria.
func progress(achievement: AchievementData) -> Vector2i:
	var needed := achievement.count
	match achievement.criteria:
		AchievementData.Criteria.KILL_ENEMY:
			return Vector2i(stat("kill:" + String(achievement.target)), needed)
		AchievementData.Criteria.REACH_LEVEL:
			return Vector2i(_player.level, needed)
		AchievementData.Criteria.COMPLETE_QUEST:
			var quest := Database.quest(achievement.target)
			var done := quest != null and _player.quest_log.state(quest) == QuestLog.State.DONE
			return Vector2i(1 if done else 0, 1)
		AchievementData.Criteria.QUESTS_COMPLETED:
			return Vector2i(stat("quests_completed"), needed)
		AchievementData.Criteria.EXPLORE_ZONE:
			return Vector2i(_player.discovered.size(), needed)
		AchievementData.Criteria.REACH_STANDING:
			var faction := Database.faction(achievement.target)
			var goal := FactionData.THRESHOLDS[needed]
			return Vector2i(mini(_player.reputation_with(faction), goal) if faction else 0, goal)
		AchievementData.Criteria.MONEY_LOOTED:
			return Vector2i(stat("money_looted"), needed)
		AchievementData.Criteria.EQUIP_QUALITY:
			var best := -1
			for item: ItemData in _player.equipment.values():
				best = maxi(best, item.quality)
			return Vector2i(1 if best >= needed else 0, 1)
		AchievementData.Criteria.TALENT_POINTS:
			return Vector2i(_player.talent_points_total() - _player.talent_points_free(), needed)
		AchievementData.Criteria.DEATHS:
			return Vector2i(stat("deaths"), needed)
		AchievementData.Criteria.POTIONS_USED:
			return Vector2i(stat("potions_used"), needed)
		AchievementData.Criteria.STAT:
			return Vector2i(stat(String(achievement.target)), needed)
	return Vector2i(0, needed)


## Awards every achievement whose criteria are now met. `announce` = false loads silently.
func evaluate(announce := true) -> void:
	for achievement in _all:
		if is_earned(achievement):
			continue
		var p := progress(achievement)
		if p.x >= p.y:
			_earned[achievement.id] = Time.get_date_string_from_system()
			if announce:
				Game.chat("%s has earned the achievement [%s]!" % [_player.unit_name, achievement.display_name], CHAT_COLOR)
				earned.emit(achievement)
	changed.emit()


func to_save_data() -> Dictionary:
	var earned_days := {}
	for id: StringName in _earned:
		earned_days[String(id)] = _earned[id]
	return {"earned": earned_days, "stats": stats.duplicate()}


func load_save_data(data: Dictionary) -> void:
	_earned.clear()
	stats.clear()
	var earned_days: Dictionary = data.get("earned", {})
	for id: String in earned_days:
		_earned[StringName(id)] = earned_days[id]
	var saved_stats: Dictionary = data.get("stats", {})
	for key: String in saved_stats:
		stats[key] = int(saved_stats[key])
	evaluate(false)


func _on_unit_killed(unit: Unit, _killer: Unit) -> void:
	var enemy := unit as Enemy
	if enemy and enemy.tapped_by == _player:
		stats["kills"] = stat("kills") + 1
		add_stat("kill:" + String(enemy.data.id))
