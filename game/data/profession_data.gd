class_name ProfessionData
extends Resource
## A profession (Herbalism, Alchemy...). Add new ones as .tres files in data/professions/.
## Skill goes from 1 to max_skill; gathering and crafting things raise it.

enum Kind { GATHERING, CRAFTING }
## How hard something is for your current skill, WoW's orange/yellow/green/gray.
enum Difficulty { ORANGE, YELLOW, GREEN, GRAY }

const DIFFICULTY_COLORS: Array[Color] = [Color(1, 0.5, 0.25), Color(1, 1, 0), Color(0.25, 0.75, 0.25), Color(0.5, 0.5, 0.5)]
## Chance of a skill-up at each difficulty.
const SKILL_UP_CHANCE: Array[float] = [1.0, 0.6, 0.25, 0.0]

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var kind := Kind.GATHERING
@export var max_skill := 100


## Orange right at the required skill, then yellow, green and finally gray.
static func difficulty(skill: int, required: int) -> Difficulty:
	var above := skill - required
	if above < 15:
		return Difficulty.ORANGE
	if above < 30:
		return Difficulty.YELLOW
	if above < 45:
		return Difficulty.GREEN
	return Difficulty.GRAY
