class_name QuestObject
extends Node3D
## Something in the world a quest asks the player to use (right-click it): a cache of cut
## gloomshard to smash, a sigil to read... It only sparkles and takes clicks while the
## player has an unfinished quest for it (QuestData.Kind.INTERACT, by object_id); once
## used it is gone for a while, unless it stays (vanishes = false: a carving is read, not
## carried off).

enum Look { GLOOMSHARD_CACHE, ECLIPSE_SIGIL }

const GLOOM := Color(0.62, 0.4, 1.0)
const ECLIPSE := Color(0.55, 0.25, 1.0)

## Which quests count it (QuestData.object_id).
var object_id: StringName
var display_name := ""
## The cast bar while using it, and how long it takes.
var action := "Using"
var use_time := 1.5
var respawn_time := 45.0
var look := Look.GLOOMSHARD_CACHE
var vanishes := true
var available := true

var _model: Node3D
var _click_area := Area3D.new()
var _sparkle: GPUParticles3D
var _respawn_at := 0.0
var _orbit: Node3D


func _ready() -> void:
	add_to_group("quest_objects")
	_model = _sigil_model() if look == Look.ECLIPSE_SIGIL else _cache_model()
	add_child(_model)
	var tall := look == Look.ECLIPSE_SIGIL
	_click_area.collision_layer = 0
	_click_area.collision_mask = 0
	_click_area.monitoring = false
	var sphere := SphereShape3D.new()
	sphere.radius = 1.5 if tall else 1.0
	var shape := CollisionShape3D.new()
	shape.shape = sphere
	shape.position.y = 1.1 if tall else 0.5
	_click_area.add_child(shape)
	add_child(_click_area)
	_sparkle = Vfx.motes(Color(1.0, 0.85, 0.4), 10, 0.09, 0.8, Vector3(0.5, 0.3, 0.5) * (2.0 if tall else 1.0))
	_sparkle.position.y = 1.4 if tall else 0.7
	_sparkle.emitting = false
	add_child(_sparkle)


func _process(delta: float) -> void:
	if not available and Game.time >= _respawn_at:
		available = true
		_model.visible = true
	if _orbit:
		_orbit.rotate_y(delta * 0.4)
	var player := Game.player
	var wanted := available and player != null and player.quest_log.wants_object(object_id)
	_click_area.collision_layer = Unit.LAYER_CLICKABLE if wanted else 0
	_sparkle.emitting = wanted


## Used: smashed and gone until it respawns, or (vanishes = false) left as it is.
func use() -> void:
	if not vanishes:
		Vfx.flash(get_parent(), global_position + Vector3.UP * 1.2, ECLIPSE, 1.2)
		return
	available = false
	_model.visible = false
	_respawn_at = Game.time + respawn_time
	Vfx.shards(get_parent(), global_position + Vector3.UP * 0.6, GLOOM, 10, 4.0, 0.12)


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var glow := StandardMaterial3D.new()
	glow.albedo_color = color.darkened(0.3)
	glow.roughness = 0.2
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = energy
	return glow


## A scanned crate with cut gloomshard bristling out of its open top.
func _cache_model() -> Node3D:
	var root := Props.crate(0.55)
	var glow := _glow(GLOOM, 1.6)
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


## The Eclipse Hand's mark: a dark sun carved on the ground at the foot of a standing stone,
## with fed shards drifting round it in a slow ring and a violet glow.
func _sigil_model() -> Node3D:
	var root := Node3D.new()
	var stone := Props.boulder(1.3, 77)
	for rock: MeshInstance3D in stone.find_children("*", "MeshInstance3D", false, false):
		rock.scale *= Vector3(0.75, 1.7, 0.6)  # a standing stone (the collider stays round)
	stone.position = Vector3(0, 0, -0.9)
	root.add_child(stone)
	var mark := Vfx.decal(self, global_position, ECLIPSE, Vfx.RUNE_CIRCLE, 3.6, 2.5)  # (this sigil never vanishes)
	mark.modulate = ECLIPSE.darkened(0.2)
	_orbit = Node3D.new()
	root.add_child(_orbit)
	var glow := _glow(ECLIPSE, 2.4)
	for i in 6:
		var shard := MeshInstance3D.new()
		shard.mesh = PlaceholderModel._crystal(0.05, 0.3)
		shard.material_override = glow
		var angle := i * TAU / 6.0
		shard.position = Vector3(cos(angle) * 1.3, 0.9 + 0.25 * sin(angle * 2.0), sin(angle) * 1.3)
		shard.rotation = Vector3(0.4, angle, 0.3)
		_orbit.add_child(shard)
	var light := OmniLight3D.new()
	light.light_color = ECLIPSE
	light.light_energy = 1.4
	light.omni_range = 6.0
	light.position = Vector3(0, 1.2, 0)
	root.add_child(light)
	return root
