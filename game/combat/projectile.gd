class_name Projectile
extends Node3D
## A homing spell missile. Like WoW spells it always reaches its target;
## the effect lands on arrival. Looks by AbilityData.projectile_style: a glowing orb,
## a spinning crystal shard trailing sparkles, or a lightning bolt that strikes at once.

var _source: Unit
var _target: Unit
var _ability: AbilityData
var _amount := 0
var _crit := false
var _body: Node3D
var _trail: GPUParticles3D
var _spin := 0.0


static func launch(source: Unit, target: Unit, ability: AbilityData, amount: int, crit: bool) -> void:
	var missile := Projectile.new()
	missile._source = source
	missile._target = target
	missile._ability = ability
	missile._amount = amount
	missile._crit = crit
	source.get_parent().add_child(missile)
	missile.global_position = source.global_position + Vector3.UP * source.body_height * 0.7 - source.global_transform.basis.z * 0.6
	missile.reset_physics_interpolation()
	match ability.projectile_style:
		AbilityData.ProjectileStyle.SHARD:
			missile._build_shard()
		AbilityData.ProjectileStyle.BOLT:
			Vfx.lightning(source.get_parent(), missile.global_position, missile._aim(), ability.color)
		_:
			missile._build_orb()


func _build_orb() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.32
	_body = MeshInstance3D.new()
	(_body as MeshInstance3D).mesh = mesh
	(_body as MeshInstance3D).material_override = Vfx.glow_material(_ability.color, null, 0, 3.0)
	add_child(_body)
	_add_glow(0.9, 1.5)


## An elongated crystal pointing where it flies, spinning, in a halo with a sparkling trail.
func _build_shard() -> void:
	var crystal := PlaceholderModel._crystal(0.09, 0.55)
	var shard := MeshInstance3D.new()
	shard.mesh = crystal
	shard.material_override = Vfx.glow_material(_ability.color, null, 0, 2.2)
	shard.rotation.x = -PI / 2  # crystal's long axis (Y) along the flight (-Z)
	shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body = Node3D.new()
	_body.add_child(shard)
	add_child(_body)
	_add_glow(0.75, 2.0)


func _add_glow(halo: float, light_energy: float) -> void:
	var sprite := MeshInstance3D.new()
	sprite.mesh = QuadMesh.new()
	sprite.scale = Vector3.ONE * halo
	sprite.material_override = Vfx.glow_material(_ability.color, Vfx.dot(), 1, 2.0)
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sprite)
	var light := OmniLight3D.new()
	light.light_color = _ability.color
	light.light_energy = light_energy
	light.omni_range = 3.0
	add_child(light)
	_trail = Vfx.emitter(_ability.color, 40, 0.4, 0.22)
	var process := _trail.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.08
	process.spread = 180.0
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.5
	add_child(_trail)
	_trail.emitting = true


func _aim() -> Vector3:
	return _target.global_position + Vector3.UP * _target.body_height * 0.55


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_target) or _target.is_dead:
		_finish()
		return
	var aim := _aim()
	var to := aim - global_position
	var step := _ability.projectile_speed * delta
	if to.length() <= step:
		if is_instance_valid(_source):
			_source.apply_ability(_ability, _target, _amount, _crit)
		_finish()
		return
	global_position += to.normalized() * step
	if _body and to.length() > 0.01:
		_spin += delta * 9.0
		_body.look_at(aim, Vector3.UP if absf(to.normalized().y) < 0.95 else Vector3.RIGHT)
		_body.rotate_object_local(Vector3.FORWARD, _spin)


## The sparkle trail stays behind and fades instead of vanishing with the missile.
func _finish() -> void:
	if _trail:
		Vfx.release(_trail)
		_trail = null
	queue_free()
