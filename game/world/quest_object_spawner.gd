class_name QuestObjectSpawner
extends Marker3D
## Scatters quest objects (QuestObject) around this marker. Move it in the editor.

@export var object_id: StringName
@export var display_name := ""
@export var action := "Using"
@export var use_time := 1.5
@export var respawn_time := 45.0
@export var look := QuestObject.Look.GLOOMSHARD_CACHE
## false: it stays where it is once used (a carving is read, not carried off)
@export var vanishes := true
@export var count := 4
@export var radius := 10.0
## Spots steeper than this (0 flat .. 1 vertical) are passed over: the player must reach them.
const MAX_SLOPE := 0.25


func spawn(terrain: Terrain, parent: Node) -> void:
	for i in count:
		var x := global_position.x
		var z := global_position.z
		for attempt in 12:
			var angle := randf() * TAU
			var distance := radius * sqrt(randf())
			x = global_position.x + cos(angle) * distance
			z = global_position.z + sin(angle) * distance
			if terrain.get_slope(x, z) < MAX_SLOPE:
				break
		var thing := QuestObject.new()
		thing.object_id = object_id
		thing.display_name = display_name
		thing.action = action
		thing.use_time = use_time
		thing.respawn_time = respawn_time
		thing.look = look
		thing.vanishes = vanishes
		parent.add_child(thing)
		thing.global_position = Vector3(x, terrain.get_height(x, z), z)
		thing.rotation.y = randf() * TAU
