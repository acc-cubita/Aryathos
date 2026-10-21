class_name CombatVfx
extends Node
## Hit and heal effects for every unit, driven by the Game event bus (added by the zone).
## Only spells flash where they land: weapon blows (a swing's or an ability's) show nothing.

const HEAL_LIGHT := Color(0.4, 1.0, 0.55)


func _ready() -> void:
	Game.unit_damaged.connect(_on_damaged)
	Game.unit_healed.connect(_on_healed)


func _on_damaged(target: Unit, source: Unit, amount: int, crit: bool, color: Color) -> void:
	if not is_instance_valid(target):
		return
	if color.is_equal_approx(Color.WHITE) or (is_instance_valid(source) and source.landing_blow):
		return
	var chest := target.global_position + Vector3.UP * target.body_height * 0.6
	var toward := Vector3.UP
	if is_instance_valid(source) and source != target:
		toward = (source.global_position - target.global_position) * Vector3(1, 0, 1)
		toward = (toward.normalized() + Vector3.UP * 0.4).normalized()
	var strength := clampf(0.7 + amount / 40.0, 0.7, 1.6)
	Vfx.impact(get_parent(), chest + toward * 0.3, toward, color, strength, crit)


func _on_healed(target: Unit, _source: Unit, _amount: int, _crit: bool) -> void:
	if is_instance_valid(target):
		Vfx.heal(get_parent(), target, HEAL_LIGHT)
