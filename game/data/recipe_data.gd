class_name RecipeData
extends Resource
## A crafting recipe: reagents in, product out. Add new ones as .tres files in data/recipes/.

@export var id: StringName
@export var profession: ProfessionData
@export var required_skill := 1
@export var product: ItemData
@export var product_count := 1
## What is used up, one count per reagent, in the same order.
@export var reagents: Array[ItemData] = []
@export var reagent_counts := PackedInt32Array()
@export var craft_time := 2.0
