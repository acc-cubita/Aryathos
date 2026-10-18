class_name CombatVfx
extends Node
## Hit and heal effects for every unit, driven by the Game event bus (added by the zone).

## Sparks for plain weapon blows from creatures (players use their glow colour).
const CLAW_SPARKS := Color(1.0, 0.78, 0.5)
const HEAL_LIGHT := Color(0.4, 1.0, 0.55)


func _ready() -> void:
	Game.unit_damaged.connect(_on_damaged)
	Game.unit_healed.connect(_on_healed)


func _on_damaged(target: Unit, source: Unit, amount: int, crit: bool, color: Color) -> void:
	if not is_instance_valid(target):
		return
	var tint := color
	if color == Color.WHITE:  # a weapon blow, not a spell
		var glow: Variant = source.get("glow_color") if is_instance_valid(source) else null
		tint = glow if glow is Color else CLAW_SPARKS
	var chest := target.global_position + Vector3.UP * target.body_height * 0.6
	var toward := Vector3.UP
	if is_instance_valid(source) and source != target:
		toward = (source.global_position - target.global_position) * Vector3(1, 0, 1)
		toward = (toward.normalized() + Vector3.UP * 0.4).normalized()
	var strength := clampf(0.7 + amount / 40.0, 0.7, 1.6)
	Vfx.impact(get_parent(), chest + toward * 0.3, toward, tint, strength, crit)


func _on_healed(target: Unit, _source: Unit, _amount: int, _crit: bool) -> void:
	if is_instance_valid(target):
		Vfx.heal(get_parent(), target, HEAL_LIGHT)
