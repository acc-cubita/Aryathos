class_name TalentData
extends Resource
## One talent in a class talent tree. Add new ones as .tres files in data/talents/
## and list them on the player. In the description, {value} is replaced with the
## bonus at the talent's current rank.

enum Effect {
	ABILITY_DAMAGE,   ## +% damage of `ability` (or of all abilities when empty)
	ABILITY_CAST_TIME, ## -seconds cast time of `ability`
	ABILITY_COOLDOWN, ## -seconds cooldown of `ability`
	ABILITY_MANA,     ## -% mana cost of `ability`
	HEALING,          ## +% healing done
	CRIT,             ## +% critical strike chance
	MAX_HEALTH,       ## +% maximum health
	MAX_MANA,         ## +% maximum mana
	WEAPON_DAMAGE,    ## +% weapon (auto-attack) damage
	LEARN_ABILITY,    ## teaches `ability`
}

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var icon_color := Color(0.4, 0.4, 0.6)
@export var icon_glyph := "?"

@export_group("Position")
## Index into the player's talent tree names.
@export var tree := 0
## Row, starting at 1. Each row needs 3 more points spent in the same tree.
@export var tier := 1
@export var column := 0
@export var max_rank := 1

@export_group("Effect")
@export var effect := Effect.ABILITY_DAMAGE
@export var ability: AbilityData
@export var value_per_rank := 0.0


## Description for a rank (rank 0 shows what rank 1 would give).
func describe(rank: int) -> String:
	var value := value_per_rank * maxi(rank, 1)
	var text := str(int(value)) if is_equal_approx(value, roundf(value)) else String.num(value, 2)
	return description.replace("{value}", text)
