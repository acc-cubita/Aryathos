class_name Vfx
extends RefCounted
## Spell and hit effects, built in code: additive glowing particles and sprites
## (combat/vfx_glow.gdshader, bloomed by the environment's glow), glow decals projected
## on the ground (art/vfx/*.png) and short flashes of light. Every effect frees itself.

const GLOW_SHADER := preload("res://combat/vfx_glow.gdshader")
const RUNE_CIRCLE := preload("res://art/vfx/rune_circle.png")
const SHOCKWAVE := preload("res://art/vfx/shockwave.png")
## Ground decals skip unit models, so a circle under a caster does not paint its legs.
const DECAL_MASK := 0xFFFFF ^ PlaceholderModel.RENDER_LAYER

static var _dot: Texture2D
static var _fade: GradientTexture1D
static var _shrink: CurveTexture


## Additive glow material. billboard: 0 as modelled, 1 faces the camera, 2 stretched along Y.
static func glow_material(tint: Color, texture: Texture2D = null, billboard := 0, energy := 2.5) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GLOW_SHADER
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("energy", energy)
	material.set_shader_parameter("billboard", billboard)
	if texture:
		material.set_shader_parameter("tex", texture)
	return material


## Soft round spot, white with a hot centre.
static func dot() -> Texture2D:
	if _dot == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.22, Color(1, 1, 1, 0.75))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 64
		texture.height = 64
		_dot = texture
	return _dot


# ---------------------------------------------------------------- particles

## A glowing particle emitter; `streak` particles stretch along their flight (sparks).
static func emitter(tint: Color, amount: int, lifetime: float, size: float, streak := false) -> GPUParticles3D:
	if _fade == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.6, Color(1, 1, 1, 0.7))
		_fade = GradientTexture1D.new()
		_fade.gradient = gradient
		var curve := Curve.new()
		curve.add_point(Vector2(0, 1))
		curve.add_point(Vector2(1, 0.15))
		_shrink = CurveTexture.new()
		_shrink.curve = curve
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24))
	var process := ParticleProcessMaterial.new()
	process.color = tint
	process.color_ramp = _fade
	process.scale_curve = _shrink
	process.particle_flag_align_y = streak
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(size * 0.16, size) if streak else Vector2(size, size)
	quad.material = glow_material(Color.WHITE, dot(), 2 if streak else 1)
	particles.draw_pass_1 = quad
	return particles


## Fires an emitter once at `at` and frees it when its particles are gone.
static func burst(parent: Node, at: Vector3, particles: GPUParticles3D) -> void:
	particles.one_shot = true
	if particles.explosiveness == 0.0:
		particles.explosiveness = 1.0
	particles.finished.connect(particles.queue_free)
	_place(parent, particles, at)
	particles.emitting = true


## Stops a continuous emitter, leaves its last particles where they are, then frees it.
static func release(particles: GPUParticles3D) -> void:
	if not is_instance_valid(particles) or not particles.is_inside_tree():
		return
	particles.emitting = false
	var world := particles.get_tree().current_scene
	if world and particles.get_parent() != world:
		particles.reparent(world)
	particles.get_tree().create_timer(particles.lifetime + 0.1).timeout.connect(particles.queue_free)


static func sparks(parent: Node, at: Vector3, tint: Color, amount := 20, speed := 6.0, size := 0.32, toward := Vector3.ZERO) -> void:
	var particles := emitter(tint, amount, 0.42, size, true)
	var process := particles.process_material as ParticleProcessMaterial
	process.direction = toward.normalized() if toward != Vector3.ZERO else Vector3.UP
	process.spread = 75.0 if toward != Vector3.ZERO else 180.0
	process.initial_velocity_min = speed * 0.45
	process.initial_velocity_max = speed
	process.gravity = Vector3(0, -7, 0)
	process.damping_min = 3.0
	process.damping_max = 6.0
	burst(parent, at, particles)


## Glowing crystal splinters flying off and tumbling down.
static func shards(parent: Node, at: Vector3, tint: Color, count := 8, speed := 5.0, size := 0.14) -> void:
	var particles := emitter(tint, count, 0.75, size)
	var crystal := PlaceholderModel._crystal(size * 0.3, size)
	crystal.material = glow_material(Color.WHITE, null, 0, 1.6)
	particles.draw_pass_1 = crystal
	var process := particles.process_material as ParticleProcessMaterial
	process.particle_flag_align_y = true
	process.direction = Vector3.UP
	process.spread = 80.0
	process.initial_velocity_min = speed * 0.5
	process.initial_velocity_max = speed
	process.gravity = Vector3(0, -12, 0)
	process.scale_min = 0.6
	process.scale_max = 1.3
	burst(parent, at, particles)


## Soft motes drifting up, e.g. healing light; one-shot unless `continuous`.
static func motes(tint: Color, amount: int, size: float, rise: float, extents: Vector3, lifetime := 1.1) -> GPUParticles3D:
	var particles := emitter(tint, amount, lifetime, size)
	var process := particles.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	process.direction = Vector3.UP
	process.spread = 15.0
	process.initial_velocity_min = rise * 0.5
	process.initial_velocity_max = rise
	process.gravity = Vector3(0, rise * 0.4, 0)
	return particles


# ---------------------------------------------------------------- sprites, decals, lights

## A bright sprite that swells and fades, with a matching flash of light.
static func flash(parent: Node, at: Vector3, tint: Color, size := 1.0, duration := 0.25, light := 2.0) -> void:
	var quad := QuadMesh.new()
	var sprite := MeshInstance3D.new()
	sprite.mesh = quad
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := glow_material(tint, dot(), 1, 3.0)
	sprite.material_override = material
	_place(parent, sprite, at)
	sprite.scale = Vector3.ONE * size * 0.35
	var tween := sprite.create_tween().set_parallel()
	tween.tween_property(sprite, "scale", Vector3.ONE * size, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(material, "shader_parameter/tint", Color(tint, 0.0), duration).set_ease(Tween.EASE_IN)
	if light > 0.0:
		var lamp := OmniLight3D.new()
		lamp.light_color = tint
		lamp.light_energy = light
		lamp.omni_range = 2.5 + size * 2.0
		sprite.add_child(lamp)
		tween.tween_property(lamp, "light_energy", 0.0, duration)
	tween.chain().tween_callback(sprite.queue_free)


## A glow texture projected on the ground around `at` (feet height).
static func decal(parent: Node, at: Vector3, tint: Color, texture: Texture2D, size: float, energy := 3.0) -> Decal:
	var ground := Decal.new()
	ground.texture_albedo = texture
	ground.texture_emission = texture
	ground.emission_energy = energy
	ground.modulate = tint
	ground.albedo_mix = 0.3
	ground.size = Vector3(size, 3.0, size)
	ground.upper_fade = 0.3
	ground.lower_fade = 0.3
	ground.cull_mask = DECAL_MASK
	_place(parent, ground, at)
	return ground


## A ring decal sweeping out from `at` to `radius`, fading as it goes.
static func shockwave(parent: Node, at: Vector3, tint: Color, radius: float, duration := 0.55, energy := 4.0) -> void:
	var wave := decal(parent, at, tint, SHOCKWAVE, 0.6, energy)
	var tween := wave.create_tween().set_parallel()
	tween.tween_property(wave, "size", Vector3(radius * 2.0, 3.0, radius * 2.0), duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(wave, "modulate:a", 0.0, duration * 0.7).set_delay(duration * 0.3)
	tween.chain().tween_callback(wave.queue_free)


## A glowing ring that expands from `at` out to `radius` and fades away.
static func ring(parent: Node, at: Vector3, color: Color, radius: float, duration := 0.45) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	var material := glow_material(Color(color, 0.8), null, 0, 2.0)
	var mesh := MeshInstance3D.new()
	mesh.mesh = torus
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_place(parent, mesh, at + Vector3.UP * 0.4)
	mesh.scale = Vector3(0.3, 0.6, 0.3)
	var tween := mesh.create_tween().set_parallel()
	tween.tween_property(mesh, "scale", Vector3(radius, 1.0, radius), duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(material, "shader_parameter/tint", Color(color, 0.0), duration)
	tween.chain().tween_callback(mesh.queue_free)


# ---------------------------------------------------------------- composed effects

## Something got hit: a flash and sparks thrown back toward the attacker; crits also shatter crystal.
static func impact(parent: Node, at: Vector3, toward: Vector3, tint: Color, strength := 1.0, crit := false) -> void:
	var s := strength * (1.5 if crit else 1.0)
	flash(parent, at, tint, 0.8 * s, 0.2, 1.2 * s)
	sparks(parent, at, tint, roundi(14 * s), 5.5 * s, 0.3 * s, toward)
	if crit:
		shards(parent, at, tint, 9, 4.5)
		flash(parent, at, Color(1, 1, 1), 0.5, 0.12, 0.0)


## Storm Nova and other blasts around the caster.
static func nova(parent: Node, at: Vector3, tint: Color, radius: float) -> void:
	shockwave(parent, at, tint, radius, 0.5, 5.0)
	flash(parent, at + Vector3.UP * 1.0, tint, 2.0, 0.3, 4.0)
	var particles := emitter(tint, 64, 0.55, 0.5, true)
	var process := particles.process_material as ParticleProcessMaterial
	process.direction = Vector3.RIGHT
	process.spread = 180.0
	process.flatness = 0.85
	process.initial_velocity_min = radius * 1.4
	process.initial_velocity_max = radius * 2.0
	process.damping_min = radius
	process.damping_max = radius * 1.5
	burst(parent, at + Vector3.UP * 0.6, particles)


## Healing light: a soft pulse on the ground and motes rising around the body.
static func heal(parent: Node, unit: Unit, tint: Color) -> void:
	var at := unit.global_position
	shockwave(parent, at, tint, 1.1, 0.7, 3.0)
	var particles := motes(tint, 28, 0.22, 1.6, Vector3(0.35, unit.body_height * 0.4, 0.35))
	particles.explosiveness = 0.5
	burst(parent, at + Vector3.UP * unit.body_height * 0.45, particles)
	flash(parent, at + Vector3.UP * unit.body_height * 0.6, tint, 1.0, 0.4, 1.5)


## A crackling bolt from `from` to `to`, flickering out.
static func lightning(parent: Node, from: Vector3, to: Vector3, tint: Color, duration := 0.3) -> void:
	var bolt := Node3D.new()
	_place(parent, bolt, Vector3.ZERO)
	var material := glow_material(tint, null, 0, 4.0)
	var path := _bolt_path(from, to, 10, 0.09)
	_bolt_segments(bolt, path, material, 0.045)
	for branch in 2:  # forks off the main bolt
		var start: Vector3 = path[randi_range(2, path.size() - 3)]
		var off := (to - from).normalized().rotated(Vector3.UP, randf_range(-1.2, 1.2)) + Vector3(0, randf_range(-0.6, 0.3), 0)
		_bolt_segments(bolt, _bolt_path(start, start + off.normalized() * randf_range(0.5, 1.1), 4, 0.12), material, 0.025)
	flash(parent, to, tint, 1.1, 0.25, 3.0)
	flash(parent, from, tint, 0.5, 0.15, 0.0)
	var tween := bolt.create_tween()
	tween.tween_property(material, "shader_parameter/tint", Color(tint, 0.25), duration * 0.25)
	tween.tween_property(material, "shader_parameter/tint", Color(tint, 1.0), duration * 0.15)
	tween.tween_property(material, "shader_parameter/tint", Color(tint, 0.0), duration * 0.6)
	tween.tween_callback(bolt.queue_free)


## Jagged points from `from` to `to`, wandering most in the middle.
static func _bolt_path(from: Vector3, to: Vector3, steps: int, jitter: float) -> Array[Vector3]:
	var axis := (to - from)
	var side := axis.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var up := side.cross(axis).normalized()
	var points: Array[Vector3] = [from]
	for i in range(1, steps):
		var t := float(i) / steps
		var wander := axis.length() * jitter * sin(PI * t)
		points.append(from + axis * t + side * randf_range(-wander, wander) + up * randf_range(-wander, wander))
	points.append(to)
	return points


static func _bolt_segments(root: Node3D, path: Array[Vector3], material: Material, width: float) -> void:
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var box := BoxMesh.new()
		box.size = Vector3(width, width, a.distance_to(b) + width)
		var segment := MeshInstance3D.new()
		segment.mesh = box
		segment.material_override = material
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(segment)
		var up := Vector3.UP if absf((b - a).normalized().y) < 0.95 else Vector3.RIGHT
		segment.look_at_from_position((a + b) * 0.5, b, up)
		segment.reset_physics_interpolation()


# ---------------------------------------------------------------- casting

## Ground rune circle + rising motes under a caster for as long as the cast lasts (see end_aura).
static func cast_aura(unit: Unit, tint: Color) -> Node3D:
	var aura := Node3D.new()
	aura.name = "CastAura"
	_place(unit, aura, unit.global_position)
	var circle := decal(aura, unit.global_position, Color(tint, 0.0), RUNE_CIRCLE, 2.6, 3.5)
	var spin := circle.create_tween().set_loops()
	spin.tween_property(circle, "rotation:y", TAU, 7.0).from(0.0)
	circle.create_tween().tween_property(circle, "modulate:a", 0.9, 0.3)
	var particles := motes(tint, 22, 0.16, 1.1, Vector3(0.7, 0.05, 0.7), 1.0)
	_place(aura, particles, unit.global_position + Vector3.UP * 0.1)
	particles.emitting = true
	return aura


static func end_aura(aura: Node3D) -> void:
	for child in aura.get_children():
		if child is GPUParticles3D:
			(child as GPUParticles3D).emitting = false
		elif child is Decal:
			child.create_tween().tween_property(child, "modulate:a", 0.0, 0.3)
	aura.get_tree().create_timer(1.1).timeout.connect(aura.queue_free)


## Shows a cast aura under `unit` while it casts (any model; call once per unit).
static func follow_casts(unit: Unit) -> void:
	var current: Array[Node3D] = [null]
	var stop := func(_arg: Variant = null) -> void:
		if is_instance_valid(current[0]):
			end_aura(current[0])
		current[0] = null
	unit.cast_started.connect(func(ability: AbilityData) -> void:
		stop.call()
		current[0] = cast_aura(unit, ability.color))
	unit.cast_ended.connect(stop)


## Glow drifting off a casting hand; switch it with `emitting`, recolour with set_tint().
static func hand_glow() -> GPUParticles3D:
	var particles := emitter(Color.WHITE, 26, 0.55, 0.13)
	var process := particles.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.07
	process.direction = Vector3.UP
	process.spread = 40.0
	process.initial_velocity_min = 0.15
	process.initial_velocity_max = 0.45
	process.gravity = Vector3(0, 0.6, 0)
	particles.emitting = false
	return particles


static func set_tint(particles: GPUParticles3D, tint: Color) -> void:
	(particles.process_material as ParticleProcessMaterial).color = tint


static func _place(parent: Node, node: Node3D, at: Vector3) -> void:
	parent.add_child(node)
	node.global_position = at
	node.reset_physics_interpolation()
