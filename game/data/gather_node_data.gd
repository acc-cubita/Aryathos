class_name GatherNodeData
extends Resource
## Something that can be gathered in the world, like an herb. Add new ones as
## .tres files in data/gathering/ and place them with a GatherSpawner.

@export var id: StringName
@export var display_name := ""
@export var profession: ProfessionData
@export var required_skill := 1
## What you get, and how many.
@export var item: ItemData
@export var min_count := 1
@export var max_count := 2
@export var respawn_time := 60.0
@export var gather_time := 1.5

@export_group("Look")
@export var leaf_color := Color(0.3, 0.6, 0.3)
@export var bloom_color := Color(0.9, 0.9, 1.0)
