class_name EnemyData
extends Resource
## A creature type. Add new ones as .tres files in data/enemies/.

@export var id: StringName
@export var display_name := ""
@export var min_level := 1
@export var max_level := 1
@export var is_elite := false

@export_group("Look")
## A rigged humanoid (made like the Arkanor bodies) animated by CharacterModel;
## it wins over model_scene.
@export_file("*.glb") var character := ""
## What the character holds in its right fist (a CharacterModel.WEAPONS key; empty: nothing).
@export var weapon := ""
## A four-legged beast animated by BeastModel (a BeastModel.BEASTS key: wolf, bear);
## it wins over model_scene. model_scale scales it too.
@export var beast := ""
## Real model scene; a placeholder is built while this, character and beast are empty.
@export var model_scene: PackedScene
@export var body: PlaceholderModel.Body = PlaceholderModel.Body.HUMANOID
@export var main_color := Color.GRAY
@export var glow_color := Color.CYAN
@export var model_scale := 1.0
## Music that plays while it fights the player (bosses); empty: the zone's music goes on.
@export_file("*.wav", "*.ogg", "*.mp3") var music := ""

@export_group("Stats")
@export var base_health := 60
@export var health_per_level := 14
@export var min_damage := 3
@export var max_damage := 6
@export var attack_interval := 2.0
@export var move_speed := 5.5
## Special attacks used in combat whenever they are off cooldown and in range.
@export var abilities: Array[AbilityData] = []

@export_group("Behaviour")
@export var aggro_radius := 10.0
## Creatures of the same type this close join the fight.
@export var social_radius := 8.0
## Distance from home at which the creature gives up and runs back.
@export var leash_radius := 35.0
@export var wander_radius := 5.0
## Walking pace while wandering (m/s); 0 means a third of move_speed.
@export var wander_speed := 0.0
@export var respawn_time := 30.0

@export_group("Reputation")
## Killing this creature raises reputation with this faction (its enemies).
@export var reputation_faction: FactionData
@export var reputation_on_kill := 0

@export_group("Loot")
## Copper dropped (100 copper = 1 silver, 100 silver = 1 gold).
@export var money_min := 0
@export var money_max := 0
@export var loot_items: Array[ItemData] = []
## Drop chance (0-1) for each entry in loot_items, in the same order.
@export var loot_chances := PackedFloat32Array()
