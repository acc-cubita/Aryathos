class_name QuestObject
extends Node3D
## Something in the world a quest asks the player to use (right-click it): a cache of cut
## gloomshard to smash, a sigil to read... It only sparkles and takes clicks while the
## player has an unfinished quest for it (QuestData.Kind.INTERACT, by object_id); once
## used it is gone for a while.

enum Look { GLOOMSHARD_CACHE }

const GLOOM := Color(0.62, 0.4, 1.0)

## Which quests count it (QuestData.object_id).
var object_id: StringName
var display_name := ""
## The cast bar while using it, and how long it takes.
var action := "Using"
var use_time := 1.5
var respawn_time := 45.0
var look := Look.GLOOMSHARD_CACHE
var available := true

var _model: Node3D
var _click_area := Area3D.new()
var _sparkle: GPUParticles3D
var _respawn_at := 0.0


func _ready() -> void:
	add_to_group("quest_objects")
	_model = _build_model()
	add_child(_model)
	_click_area.collision_layer = 0
	_click_area.collision_mask = 0
	_click_area.monitoring = false
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	var shape := CollisionShape3D.new()
	shape.shape = sphere
	shape.position.y = 0.5
	_click_area.add_child(shape)
	add_child(_click_area)
	_sparkle = Vfx.motes(Color(1.0, 0.85, 0.4), 10, 0.09, 0.8, Vector3(0.5, 0.3, 0.5))
	_sparkle.position.y = 0.7
	_sparkle.emitting = false
	add_child(_sparkle)


func _process(_delta: float) -> void:
	if not available and Game.time >= _respawn_at:
		available = true
		_model.visible = true
	var player := Game.player
	var wanted := available and player != null and player.quest_log.wants_object(object_id)
	_click_area.collision_layer = Unit.LAYER_CLICKABLE if wanted else 0
	_sparkle.emitting = wanted


## Used up: gone until it respawns.
func use() -> void:
	available = false
	_model.visible = false
	_respawn_at = Game.time + respawn_time
	Vfx.shards(get_parent(), global_position + Vector3.UP * 0.6, GLOOM, 10, 4.0, 0.12)


func _build_model() -> Node3D:
	# a scanned crate with cut gloomshard bristling out of its open top
	var root := Props.crate(0.55)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = GLOOM.darkened(0.3)
	glow.roughness = 0.2
	glow.emission_enabled = true
	glow.emission = GLOOM
	glow.emission_energy_multiplier = 1.6
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 5:
		var shard := MeshInstance3D.new()
		shard.mesh = PlaceholderModel._crystal(rng.randf_range(0.04, 0.07), rng.randf_range(0.25, 0.45))
		shard.material_override = glow
		shard.position = Vector3(rng.randf_range(-0.22, 0.22), 0.95, rng.randf_range(-0.22, 0.22))
		shard.rotation = Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5))
		root.add_child(shard)
	return root
