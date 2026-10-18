class_name Database
extends RefCounted
## Finds game data (.tres files) by id, so saves can store short ids instead of paths.
## Each folder is scanned once, the first time it is asked for.

static var _tables := {}


static func item(id: StringName) -> ItemData:
	return _find("res://data/items", id) as ItemData


static func ability(id: StringName) -> AbilityData:
	return _find("res://data/abilities", id) as AbilityData


static func quest(id: StringName) -> QuestData:
	return _find("res://data/quests", id) as QuestData


static func faction(id: StringName) -> FactionData:
	return _find("res://data/factions", id) as FactionData


static func factions() -> Array[FactionData]:
	var result: Array[FactionData] = []
	result.assign(_all("res://data/factions"))
	return result


static func profession(id: StringName) -> ProfessionData:
	return _find("res://data/professions", id) as ProfessionData


static func recipe(id: StringName) -> RecipeData:
	return _find("res://data/recipes", id) as RecipeData


static func professions() -> Array[ProfessionData]:
	var result: Array[ProfessionData] = []
	result.assign(_all("res://data/professions"))
	return result


static func recipes() -> Array[RecipeData]:
	var result: Array[RecipeData] = []
	result.assign(_all("res://data/recipes"))
	result.sort_custom(func(a: RecipeData, b: RecipeData) -> bool: return a.required_skill < b.required_skill)
	return result


static func gather_nodes() -> Array[GatherNodeData]:
	var result: Array[GatherNodeData] = []
	result.assign(_all("res://data/gathering"))
	return result


static func achievements() -> Array[AchievementData]:
	var result: Array[AchievementData] = []
	result.assign(_all("res://data/achievements"))
	return result


static func _all(folder: String) -> Array:
	_find(folder, &"")
	return _tables[folder].values()


static func _find(folder: String, id: StringName) -> Resource:
	if not _tables.has(folder):
		var table := {}
		for file in DirAccess.get_files_at(folder):
			# Exported games list converted resources as "name.tres.remap".
			file = file.trim_suffix(".remap")
			if file.ends_with(".tres") or file.ends_with(".res"):
				var resource := load(folder.path_join(file))
				if resource and "id" in resource:
					table[resource.id] = resource
		_tables[folder] = table
	return _tables[folder].get(id)
