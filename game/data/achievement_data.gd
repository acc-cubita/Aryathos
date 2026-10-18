class_name AchievementData
extends Resource
## One achievement. Add new ones as .tres files in data/achievements/.
## `target` and `count` mean different things per criteria (see the enum).

enum Criteria {
	KILL_ENEMY,       ## kill `count` creatures of type `target` (EnemyData.id)
	REACH_LEVEL,      ## reach level `count`
	COMPLETE_QUEST,   ## finish the quest `target` (QuestData.id)
	QUESTS_COMPLETED, ## finish `count` quests
	EXPLORE_ZONE,     ## discover `count` places
	REACH_STANDING,   ## reach standing `count` (FactionData.Standing) with faction `target`
	MONEY_LOOTED,     ## loot `count` copper in total
	EQUIP_QUALITY,    ## wear an item of quality `count` (ItemData.Quality) or better
	TALENT_POINTS,    ## spend `count` talent points
	DEATHS,           ## die `count` times
	POTIONS_USED,     ## drink `count` potions
	STAT,             ## the statistic `target` (e.g. "herbs_gathered") reaches `count`
}

const CATEGORIES: Array[String] = ["General", "Combat", "Quests", "Exploration", "Reputation", "Items", "Professions"]

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var points := 10
@export var category := 0
@export var icon_color := Color(0.8, 0.65, 0.25)
@export var icon_glyph := "?"

@export_group("Criteria")
@export var criteria := Criteria.KILL_ENEMY
@export var target: StringName
@export var count := 1
