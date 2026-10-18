class_name Enemy
extends Unit
## A hostile creature driven by a simple WoW-style state machine:
## idle (wander) -> chase and attack -> evade back home -> dead -> respawn.

enum State { IDLE, CHASE, EVADE, DEAD }

const EVADE_SPEED := 1.4
const EVADE_TIMEOUT := 10.0
## Give up a chase after this long without landing or taking a hit (target unreachable).
const GIVE_UP_TIME := 10.0

var data: EnemyData
var state := State.IDLE
var spawn_position := Vector3.ZERO
## The unit that hit first gets the kill credit (WoW "tapping").
var tapped_by: Unit = null
## What the corpse holds for the player who tapped it.
var loot_items: Array[ItemData] = []
var loot_money := 0

var _wander_target := Vector3.ZERO
var _next_wander := 0.0
var _respawn_at := 0.0
var _decay_at := 0.0
var _evade_until := 0.0
var _sparkle: MeshInstance3D
var _path := PackedVector3Array()
var _path_index := 0
var _path_goal := Vector3.INF
var _repath_at := 0.0


func _ready() -> void:
	faction = Faction.HOSTILE
	unit_name = data.display_name
	is_elite = data.is_elite
	var size := PlaceholderModel.dimensions(data.body, data.model_scale)
	body_radius = size.x
	body_height = size.y
	_roll_stats()
	super()
	add_to_group("enemies")
	if data.character != "":
		model = CharacterModel.create(data.character, data.glow_color, data.weapon)
	elif data.beast != "":
		model = BeastModel.create(data.beast, data.glow_color, data.model_scale)
	elif data.model_scene:
		model = data.model_scene.instantiate()
	else:
		model = PlaceholderModel.build(data.body, data.main_color, data.glow_color, data.model_scale)
	add_child(model)
	_sparkle = _make_sparkle()
	add_child(_sparkle)
	_wander_target = spawn_position
	_next_wander = Game.time + randf_range(2.0, 8.0)


func _roll_stats() -> void:
	level = randi_range(data.min_level, data.max_level)
	var bonus := level - data.min_level
	max_health = data.base_health + data.health_per_level * bonus
	health = max_health
	weapon_min = data.min_damage + bonus
	weapon_max = data.max_damage + bonus
	attack_interval = data.attack_interval


func _think(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	match state:
		State.IDLE:
			_tick_idle(delta)
		State.CHASE:
			_tick_chase(delta)
		State.EVADE:
			_tick_evade(delta)
		State.DEAD:
			_tick_dead()
	move_and_slide()


## Starts a fight with `attacker` and calls nearby kin for help.
func engage(attacker: Unit) -> void:
	if state != State.IDLE or attacker == null or attacker.is_dead:
		return
	state = State.CHASE
	mark_combat()
	set_target(attacker)
	auto_attacking = true
	_next_swing = Game.time + 0.4
	for node in get_tree().get_nodes_in_group("enemies"):
		var kin := node as Enemy
		if kin != self and kin.data.id == data.id and kin.state == State.IDLE \
				and kin.global_position.distance_to(global_position) <= data.social_radius:
			kin.engage(attacker)


func _tick_idle(delta: float) -> void:
	var player := Game.player
	if player and not player.is_dead and is_hostile_to(player):
		# Like WoW, creatures notice you from further away when you are lower level.
		var radius := clampf(data.aggro_radius - (player.level - level), 3.0, data.aggro_radius * 1.5)
		if global_position.distance_to(player.global_position) <= radius:
			engage(player)
			return
	if data.wander_radius > 0.0 and Game.time >= _next_wander:
		_next_wander = Game.time + randf_range(5.0, 11.0)
		var angle := randf() * TAU
		_wander_target = spawn_position + Vector3(cos(angle), 0.0, sin(angle)) * randf() * data.wander_radius
	if flat_distance(_wander_target) > 0.6:
		_navigate(_wander_target, data.wander_speed if data.wander_speed > 0.0 else data.move_speed * 0.35, delta)
	else:
		_stop()


func _tick_chase(delta: float) -> void:
	if not is_instance_valid(target) or target.is_dead or flat_distance(spawn_position) > data.leash_radius 			or Game.time - _last_combat > GIVE_UP_TIME:
		_start_evade()
		return
	target.mark_combat()
	if casting:
		# Stand still and keep facing the target while casting.
		_stop()
		_face(target.global_position, delta)
		return
	for ability in data.abilities:
		if check_ability(ability, target) == "":
			use_ability(ability)
			return
	if distance_to_unit(target) > MELEE_RANGE * 0.75:
		_navigate(target.global_position, data.move_speed, delta)
	else:
		_stop()
		_face(target.global_position, delta)


func _start_evade() -> void:
	state = State.EVADE
	interrupt_cast()
	set_target(null)
	tapped_by = null
	health = max_health
	_evade_until = Game.time + EVADE_TIMEOUT


func _tick_evade(delta: float) -> void:
	# home, or as near as the navigation mesh gets to it (a spawn hard against a rock)
	var home := spawn_position
	if _path_goal == spawn_position and not _path.is_empty():
		home = _path[_path.size() - 1]
	if flat_distance(home) < 0.8 or Game.time > _evade_until:
		if Game.time > _evade_until:
			global_position = spawn_position
			reset_physics_interpolation()
		state = State.IDLE
		_stop()
		_wander_target = spawn_position
		_next_wander = Game.time + randf_range(3.0, 8.0)
		return
	_navigate(spawn_position, data.move_speed * EVADE_SPEED, delta)


## Walks toward `point` along the navigation mesh, around trees and rocks.
## The path is refreshed twice a second or when the goal moves.
## Falls back to a straight line when there is no navigation mesh yet.
func _navigate(point: Vector3, speed: float, delta: float) -> void:
	if Game.time >= _repath_at or _path_goal.distance_to(point) > 1.5:
		_repath_at = Game.time + randf_range(0.4, 0.6)
		_path_goal = point
		_path = NavigationServer3D.map_get_path(get_world_3d().navigation_map, global_position, point, true)
		_path_index = 1
	while _path_index < _path.size() and flat_distance(_path[_path_index]) < 0.7:
		_path_index += 1
	_move_toward(_path[_path_index] if _path_index < _path.size() else point, speed, delta)


func has_loot() -> bool:
	return is_dead and model.visible and (loot_money > 0 or not loot_items.is_empty())


func _tick_dead() -> void:
	_stop()
	_sparkle.visible = has_loot()
	_sparkle.rotate_y(0.05)
	if model.visible and Game.time >= _decay_at:
		# The corpse fades away; it can no longer be clicked.
		model.visible = false
		click_area.collision_layer = 0
		if Game.player and Game.player.target == self:
			Game.player.set_target(null)
	if Game.time >= _respawn_at:
		global_position = spawn_position
		reset_physics_interpolation()
		_roll_stats()
		tapped_by = null
		state = State.IDLE
		revive()
		model.visible = true
		click_area.collision_layer = LAYER_CLICKABLE


func _on_damaged(_amount: int, source: Unit) -> void:
	if source == null:
		return
	if tapped_by == null:
		tapped_by = source
	if state == State.IDLE:
		engage(source)


func _on_died(_killer: Unit) -> void:
	state = State.DEAD
	loot_items.clear()
	loot_money = 0
	if tapped_by is Player:
		_roll_loot()
		(tapped_by as Player).on_enemy_killed(self)
	set_target(null)
	_stop()
	_respawn_at = Game.time + data.respawn_time
	_decay_at = Game.time + minf(15.0, data.respawn_time * 0.5)


func _is_immune() -> bool:
	return state == State.EVADE


func _roll_loot() -> void:
	loot_money = randi_range(data.money_min, data.money_max)
	for i in data.loot_items.size():
		if i < data.loot_chances.size() and randf() < data.loot_chances[i]:
			loot_items.append(data.loot_items[i])


## A small spinning gold gem over corpses that still hold loot.
func _make_sparkle() -> MeshInstance3D:
	var gem := SphereMesh.new()
	gem.radius = 0.14
	gem.height = 0.28
	gem.radial_segments = 4
	gem.rings = 2
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.85, 0.3)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.8, 0.2)
	material.emission_energy_multiplier = 4.0
	var sparkle := MeshInstance3D.new()
	sparkle.mesh = gem
	sparkle.material_override = material
	sparkle.position.y = body_height + 0.4
	sparkle.layers = PlaceholderModel.RENDER_LAYER
	sparkle.visible = false
	return sparkle
