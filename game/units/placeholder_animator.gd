class_name PlaceholderAnimator
extends Node3D
## Tiny procedural animations for placeholder models: walk bob, attack swing,
## hit flinch and falling over on death. Will be replaced by an AnimationTree
## once real rigged models exist.

var _unit: Unit
var _weapon: Node3D
var _base_scale := Vector3.ONE
var _walk_phase := 0.0
var _attack := 0.0
var _hit := 0.0
var _death_tween: Tween


func _ready() -> void:
	_unit = get_parent() as Unit
	_weapon = get_node_or_null("Weapon")
	_base_scale = scale
	if _unit == null:
		return
	_unit.attacked.connect(func() -> void: _attack = 1.0)
	_unit.damaged.connect(func(_amount: int, _source: Unit) -> void: _hit = 1.0)
	_unit.died.connect(_on_died)
	_unit.revived.connect(_on_revived)
	Vfx.follow_casts(_unit)


func _process(delta: float) -> void:
	if _unit == null or _unit.is_dead:
		return
	var speed := Vector2(_unit.velocity.x, _unit.velocity.z).length()
	if speed > 0.3 and _unit.is_on_floor():
		_walk_phase += delta * (4.0 + speed * 1.4)
		position.y = absf(sin(_walk_phase)) * 0.07
	else:
		position.y = lerpf(position.y, 0.0, 1.0 - exp(-10.0 * delta))
	_attack = maxf(0.0, _attack - delta * 3.5)
	_hit = maxf(0.0, _hit - delta * 6.0)
	var swing := sin(_attack * PI)
	position.z = -swing * 0.2
	if _weapon:
		_weapon.rotation.x = -swing * float(_weapon.get_meta("swing", 1.6))
	scale = _base_scale * Vector3(1.0 + _hit * 0.05, 1.0 - _hit * 0.1, 1.0 + _hit * 0.05)


func _on_died(_killer: Unit) -> void:
	scale = _base_scale
	position.z = 0.0
	_death_tween = create_tween().set_parallel()
	_death_tween.tween_property(self, "rotation:z", PI * 0.5, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_death_tween.tween_property(self, "position:y", _unit.body_radius * 0.5, 0.6)


func _on_revived() -> void:
	if _death_tween:
		_death_tween.kill()
	rotation = Vector3.ZERO
	position = Vector3.ZERO
