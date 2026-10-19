class_name Unit
extends CharacterBody3D
## Base class for every living thing: the player, enemies and NPCs.
## Owns health/mana, targeting, ability casting and auto-attack;
## subclasses implement _think() for movement and decisions.

signal damaged(amount: int, source: Unit)
signal died(killer: Unit)
signal revived
signal target_changed(new_target: Unit)
signal cast_started(ability: AbilityData)
signal cast_ended(success: bool)
## A swing or spell went off (drives the attack animation).
signal attacked

enum Faction { PLAYER, HOSTILE, FRIENDLY }

const GRAVITY := 22.0
const GCD := 1.5
## Melee reach, measured between the edges of the two bodies (meters).
const MELEE_RANGE := 1.8
const COMBAT_TIMEOUT := 5.0
const CRIT_CHANCE := 0.08
const LAYER_WORLD := 1
const LAYER_UNITS := 2
const LAYER_CLICKABLE := 4

@export var unit_name := "Unit"
@export var level := 1
@export var faction := Faction.HOSTILE
@export var body_radius := 0.45
@export var body_height := 1.95

## True while this unit's weapon blow (an ability's, AbilityData.is_weapon_blow) lands, for
## those listening to Game.unit_damaged to tell it from a spell.
var landing_blow := false
var max_health := 100
var health := 100
var max_mana := 0
var mana := 0
var is_dead := false
var is_elite := false
var target: Unit = null
var model: Node3D
var click_area: Area3D

var auto_attacking := false
var weapon_min := 2
var weapon_max := 4
var attack_interval := 2.0
## Added to every damage or healing ability before level scaling.
var spell_power := 0

var casting: AbilityData = null
## Length of the current cast (after talents), for cast bars.
var cast_duration := 0.0
var _cast_target: Unit = null
var _cast_end := 0.0
var _cooldowns := {}
var _gcd_end := 0.0
var _next_swing := 0.0
var _last_combat := -100.0
var _last_mana_spent := -100.0
## Fractional health (x) and mana (y) regenerated but not yet applied.
var _regen := Vector2.ZERO


func _ready() -> void:
	add_to_group("units")
	# Units walk on the world but pass through each other, like in WoW.
	collision_layer = LAYER_UNITS
	collision_mask = LAYER_WORLD
	floor_snap_length = 0.5
	_build_body_shape()
	_build_click_area()


func _physics_process(delta: float) -> void:
	_think(delta)
	_keep_above_ground()
	if is_dead:
		return
	_tick_cast()
	_tick_auto_attack()
	_tick_regen(delta)


## Safety net: a unit that somehow ends up under the terrain (a bad teleport,
## a physics glitch) is put back on top instead of falling forever.
func _keep_above_ground() -> void:
	if Game.zone == null:
		return
	var ground := Game.zone.terrain.get_height(global_position.x, global_position.z)
	if global_position.y < ground - 1.5:
		global_position.y = ground + 0.5
		velocity.y = 0.0
		reset_physics_interpolation()


## Movement and decisions; implemented by subclasses.
func _think(_delta: float) -> void:
	pass


# --- Queries ---------------------------------------------------------------

func is_hostile_to(other: Unit) -> bool:
	if other == null or other == self:
		return false
	return (faction == Faction.HOSTILE) != (other.faction == Faction.HOSTILE)


func in_combat() -> bool:
	return Game.time - _last_combat < COMBAT_TIMEOUT


func mark_combat() -> void:
	_last_combat = Game.time


func distance_to_unit(other: Unit) -> float:
	return maxf(0.0, global_position.distance_to(other.global_position) - body_radius - other.body_radius)


func flat_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


## True when `other` is in the front half-circle, like WoW's facing rule.
func is_facing(other: Unit) -> bool:
	var to := other.global_position - global_position
	var forward := -global_transform.basis.z
	return Vector2(to.x, to.z).length_squared() < 0.01 or Vector2(forward.x, forward.z).dot(Vector2(to.x, to.z)) > 0.0


func cooldown_left(ability: AbilityData) -> float:
	return maxf(0.0, float(_cooldowns.get(ability.id, 0.0)) - Game.time)


func gcd_left() -> float:
	return maxf(0.0, _gcd_end - Game.time)


func cast_remaining() -> float:
	return maxf(0.0, _cast_end - Game.time) if casting else 0.0


func set_target(new_target: Unit) -> void:
	if new_target == target:
		return
	target = new_target
	if target == null or target.is_dead or not is_hostile_to(target):
		auto_attacking = false
	target_changed.emit(target)


# --- Abilities -------------------------------------------------------------

## Heals go to a friendly target, or to yourself when there is none.
func ability_target(ability: AbilityData) -> Unit:
	if ability.targeting == AbilityData.Targeting.HOSTILE:
		return target
	if ability.targeting == AbilityData.Targeting.AREA_AROUND_SELF:
		return self
	if target and not target.is_dead and not is_hostile_to(target):
		return target
	return self


## Returns "" when the ability can be used, otherwise the error to show.
func check_ability(ability: AbilityData, on: Unit, starting := true) -> String:
	if is_dead:
		return "You are dead."
	if starting and casting:
		return "Another action is in progress."
	if starting and (cooldown_left(ability) > 0.0 or (ability.triggers_gcd and gcd_left() > 0.0)):
		return "Ability is not ready yet."
	if mana < ability_mana_cost(ability):
		return "Not enough mana."
	if on == null:
		return "You have no target."
	if on.is_dead or (ability.targeting == AbilityData.Targeting.HOSTILE) != is_hostile_to(on):
		return "Invalid target."
	if on != self:
		if distance_to_unit(on) > ability.max_range:
			return "Out of range."
		if ability.targeting == AbilityData.Targeting.HOSTILE and not is_facing(on):
			return "You are facing the wrong way!"
	return ""


func use_ability(ability: AbilityData) -> bool:
	var on := ability_target(ability)
	var error := check_ability(ability, on)
	if error != "":
		_on_ability_error(error)
		return false
	if ability.triggers_gcd:
		_gcd_end = Game.time + GCD
	if ability.starts_auto_attack:
		auto_attacking = true
	cast_duration = ability_cast_time(ability)
	if cast_duration > 0.0:
		casting = ability
		_cast_target = on
		_cast_end = Game.time + cast_duration
		cast_started.emit(ability)
	else:
		_execute(ability, on)
	return true


func interrupt_cast() -> void:
	if casting:
		casting = null
		_cast_target = null
		cast_ended.emit(false)


## Applies an ability's effect; called directly or when a missile arrives.
func apply_ability(ability: AbilityData, on: Unit, amount: int, crit: bool) -> void:
	if not is_instance_valid(on) or on.is_dead:
		return
	if ability.effect == AbilityData.Effect.HEAL:
		on.receive_heal(amount, self, crit)
	else:
		mark_combat()
		landing_blow = ability.is_weapon_blow()
		on.take_damage(amount, self, crit, ability.color)
		landing_blow = false


func _tick_cast() -> void:
	if casting == null or Game.time < _cast_end:
		return
	var ability := casting
	var on := _cast_target
	casting = null
	_cast_target = null
	var error := check_ability(ability, on, false) if is_instance_valid(on) else "Invalid target."
	cast_ended.emit(error == "")
	if error != "":
		_on_ability_error(error)
	else:
		_execute(ability, on)


func _execute(ability: AbilityData, on: Unit) -> void:
	var cost := ability_mana_cost(ability)
	mana -= cost
	if cost > 0:
		_last_mana_spent = Game.time
	var cooldown := ability_cooldown(ability)
	if cooldown > 0.0:
		_cooldowns[ability.id] = Game.time + cooldown
	var crit := randf() < crit_chance()
	var power := (1.0 + 0.1 * (level - 1)) * ability_power(ability)
	var amount := roundi((randi_range(ability.min_amount, ability.max_amount) + spell_power) * power * (1.5 if crit else 1.0))
	attacked.emit()
	if ability.targeting == AbilityData.Targeting.AREA_AROUND_SELF:
		Vfx.nova(get_parent(), global_position, ability.color, ability.radius)
		for node in get_tree().get_nodes_in_group("units"):
			var other := node as Unit
			if not other.is_dead and is_hostile_to(other) and distance_to_unit(other) <= ability.radius:
				apply_ability(ability, other, amount, crit)
	elif ability.projectile_speed > 0.0 and on != self:
		Projectile.launch(self, on, ability, amount, crit)
	else:
		apply_ability(ability, on, amount, crit)


func _tick_auto_attack() -> void:
	if not auto_attacking or casting or Game.time < _next_swing:
		return
	if not is_instance_valid(target) or target.is_dead or not is_hostile_to(target):
		auto_attacking = false
		return
	if distance_to_unit(target) > MELEE_RANGE or not is_facing(target):
		return
	_next_swing = Game.time + attack_interval
	var crit := randf() < crit_chance()
	attacked.emit()
	mark_combat()
	target.take_damage(randi_range(weapon_min, weapon_max) * (2 if crit else 1), self, crit)


func _tick_regen(delta: float) -> void:
	if health < max_health:
		_regen.x += _health_regen() * delta
	if mana < max_mana:
		# Spirit-style regen: much faster after 5 seconds without spending mana.
		_regen.y += max_mana * (0.05 if Game.time - _last_mana_spent > 5.0 else 0.012) * delta
	if _regen.x >= 1.0:
		health = mini(max_health, health + int(_regen.x))
		_regen.x -= int(_regen.x)
	if _regen.y >= 1.0:
		mana = mini(max_mana, mana + int(_regen.y))
		_regen.y -= int(_regen.y)


# --- Damage, healing, death -------------------------------------------------

func take_damage(amount: int, source: Unit, crit := false, color := Color.WHITE) -> void:
	if is_dead:
		return
	if _is_immune():
		Game.unit_evaded.emit(self, source)
		return
	health = maxi(0, health - amount)
	mark_combat()
	damaged.emit(amount, source)
	Game.unit_damaged.emit(self, source, amount, crit, color)
	_on_damaged(amount, source)
	if health == 0:
		die(source)


func receive_heal(amount: int, source: Unit, crit := false) -> void:
	if is_dead:
		return
	health = mini(max_health, health + amount)
	Game.unit_healed.emit(self, source, amount, crit)


func die(killer: Unit) -> void:
	if is_dead:
		return
	is_dead = true
	health = 0
	interrupt_cast()
	auto_attacking = false
	died.emit(killer)
	Game.unit_killed.emit(self, killer)
	_on_died(killer)


func revive(health_fraction := 1.0) -> void:
	is_dead = false
	health = maxi(1, roundi(max_health * health_fraction))
	mana = max_mana
	revived.emit()


# --- Hooks for subclasses ---------------------------------------------------

## Ability numbers after modifiers (talents change these for the player).
func ability_cast_time(ability: AbilityData) -> float:
	return ability.cast_time


func ability_cooldown(ability: AbilityData) -> float:
	return ability.cooldown


func ability_mana_cost(ability: AbilityData) -> int:
	return ability.mana_cost


## Damage or healing multiplier for an ability.
func ability_power(_ability: AbilityData) -> float:
	return 1.0


func crit_chance() -> float:
	return CRIT_CHANCE


func _on_damaged(_amount: int, _source: Unit) -> void:
	pass


func _on_died(_killer: Unit) -> void:
	pass


func _on_ability_error(_text: String) -> void:
	pass


func _is_immune() -> bool:
	return false


## Health regenerated per second.
func _health_regen() -> float:
	return 0.0


# --- Movement helpers for AI ----------------------------------------------

func _move_toward(point: Vector3, speed: float, delta: float) -> void:
	var to := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if to.length() < 0.05:
		_stop()
		return
	var dir := to.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_face(point, delta)


func _stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _face(point: Vector3, delta: float) -> void:
	var to := point - global_position
	if Vector2(to.x, to.z).length_squared() > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-10.0 * delta))


# --- Setup ------------------------------------------------------------------

func _build_body_shape() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = body_radius
	capsule.height = maxf(body_height, body_radius * 2.0)
	var shape := CollisionShape3D.new()
	shape.name = "BodyShape"
	shape.shape = capsule
	shape.position.y = capsule.height * 0.5
	add_child(shape)


## A slightly larger invisible shape that mouse clicks can hit.
func _build_click_area() -> void:
	click_area = Area3D.new()
	click_area.name = "ClickArea"
	click_area.collision_layer = LAYER_CLICKABLE
	click_area.collision_mask = 0
	click_area.monitoring = false
	var cylinder := CylinderShape3D.new()
	cylinder.radius = body_radius + 0.3
	cylinder.height = body_height + 0.3
	var shape := CollisionShape3D.new()
	shape.shape = cylinder
	shape.position.y = cylinder.height * 0.5
	click_area.add_child(shape)
	add_child(click_area)
