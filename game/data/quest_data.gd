class_name QuestData
extends Resource
## One quest. Add new ones as .tres files in data/quests/ and list them on the giver NPC.
## In texts, {name} is replaced by the player's name.

enum Kind { KILL, COLLECT }

@export var id: StringName
@export var title := ""
@export_multiline var offer_text := ""
@export_multiline var progress_text := ""
@export_multiline var complete_text := ""

@export_group("Objective")
@export var kind := Kind.KILL
## Creature type (EnemyData.id) to kill or loot.
@export var enemy_id: StringName
## Shown in the tracker, e.g. "Shardfang Wolf slain" or "Stolen Aether Shard".
@export var objective := ""
@export var required := 5
## COLLECT only: chance that a kill drops the quest item.
@export_range(0.0, 1.0) var drop_chance := 1.0

@export_group("Flow")
@export var xp_reward := 100
@export var reward_item: ItemData
## Reputation given on completion: one amount per faction, in the same order.
@export var reputation_factions: Array[FactionData] = []
@export var reputation_amounts := PackedInt32Array()
@export var min_level := 1
## Must be completed before this quest is offered.
@export var requires: QuestData
## NPC id to hand the quest in to; empty = back to the giver.
@export var turn_in_npc: StringName
