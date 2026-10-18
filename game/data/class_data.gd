class_name ClassData
extends Resource
## A playable class: the abilities it starts with, its talent trees, the weapon it starts
## with, its glow, and how its health and mana grow. Add new ones as .tres files
## in data/classes/ (character creation lists them all).

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
## Place in character creation's class list.
@export var sort_order := 0
## Known from the start, in action bar order.
@export var abilities: Array[AbilityData] = []
## Names of the talent trees (TalentData.tree indexes into this).
@export var talent_trees: Array[String] = []
@export var talents: Array[TalentData] = []
@export var starting_weapon: ItemData
## Swing arcs, hand glow while casting.
@export var glow_color := Color(0.3, 0.7, 1.0)
@export_group("Stats")
@export var base_health := 140
@export var health_per_level := 25
@export var base_mana := 120
@export var mana_per_level := 20
