class_name Props
extends RefCounted
## Camp props: scanned CC0 models (art/props, Poly Haven) for chests, barrels and the fire
## pit, and simple shapes with scanned surfaces (prop.gdshader, prop_cloth.gdshader) for
## tents, banners, fences, carts and the wardstone.
## Each prop is a Node3D holding its meshes and, for solid props, a StaticBody3D on
## the world layer, so the player bumps into it and the navigation bake routes
## creatures around it. PropGroup places them from markers in the zone scene.

const WOOD := preload("res://world/materials/wood.tres")
const CANVAS := preload("res://world/materials/canvas.tres")
const BARK := preload("res://world/materials/bark.tres")
const STONE := preload("res://world/materials/stone.tres")
const PLANKS := preload("res://world/materials/planks.tres")
const ROPE := Color(0.62, 0.56, 0.45)
const RUNE := Color(0.35, 0.75, 1.0)
const BONE := Color(0.86, 0.82, 0.72)
const IRON := Color(0.22, 0.22, 0.25)

## Cloth colors per camp style.
## The linen texture is pale, so these dye it: tents in natural canvas, banners in the
## camp's colour with a trim.
const STYLES := {
	"watch": {"tent": Color(1.0, 0.97, 0.9), "canvas": Color(0.45, 0.6, 1.0), "trim": Color(1.0, 0.82, 0.45)},
	"gloomshard": {"tent": Color(0.62, 0.56, 0.58), "canvas": Color(0.62, 0.5, 0.58), "trim": Color(0.7, 0.5, 1.0)},
}

static var _materials := {}


## Builds one prop. `data` holds the marker's metadata (e.g. size, radius, from, to).
static func build(kind: String, style: String, data: Dictionary, terrain: Terrain, at: Vector3) -> Node3D:
	match kind:
		"Tent":
			return tent(style)
		"Campfire":
			return campfire()
		"Crate":
			return crate(data.get("size", 0.9))
		"Barrel":
			return barrel()
		"Banner":
			return banner(style)
		"FenceArc":
			return fence_arc(terrain, at, data.get("radius", 10.0), data.get("from", 0.0), data.get("to", 90.0))
		"Cart":
			return cart()
		"Boulder":
			return boulder(data.get("size", 2.0), data.get("seed", 5))
		"Bones":
			return bones()
	push_warning("Unknown prop kind: " + kind)
	return Node3D.new()


## A ridge tent of sagging canvas, 2.9 m wide and 3.4 m deep, opening toward +Z: two
## poles and a ridge pole, the hem pegged down and guy ropes at both ends.
static func tent(style: String) -> Node3D:
	var root := Node3D.new()
	var colors: Dictionary = STYLES[style]
	var half_width := 1.45
	var depth := 1.7
	var ridge := 2.3
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 6
	var cols := 10
	var count := 0
	for side: float in [-1.0, 1.0]:
		var outward := Vector3(side * ridge, half_width, 0.0).normalized()
		for i in rows + 1:
			var t := float(i) / rows
			for j in cols + 1:
				var u := float(j) / cols
				# slack canvas dips between the ridge and the pegged hem, most mid-tent
				var dip := 0.08 * sin(PI * t) * (0.55 + 0.45 * sin(PI * u))
				var p := Vector3(side * half_width * t, lerpf(ridge, 0.04, t), lerpf(-depth, depth, u)) - outward * dip
				p.z -= (u - 0.5) * 0.12 * sin(PI * t)
				tool.add_vertex(p)
		for i in rows:
			for j in cols:
				var a := count + i * (cols + 1) + j
				var b := a + cols + 1
				var order := [a, a + 1, b, a + 1, b + 1, b] if side > 0.0 else [a, b, a + 1, a + 1, b, b + 1]
				for k: int in order:
					tool.add_index(k)
		count += (rows + 1) * (cols + 1)
	# closed back wall; the front is two flaps tied back from a shadowed doorway
	var walls := [
		[Vector3(0, ridge, -depth), Vector3(half_width, 0.04, -depth), Vector3(-half_width, 0.04, -depth)],
		[Vector3(0, ridge, depth), Vector3(-half_width, 0.04, depth), Vector3(-0.55, 0.04, depth + 0.05)],
		[Vector3(0, ridge, depth), Vector3(0.55, 0.04, depth + 0.05), Vector3(half_width, 0.04, depth)],
	]
	for wall: Array in walls:
		for p: Vector3 in wall:
			tool.add_vertex(p)
		for k in 3:
			tool.add_index(count + k)
		count += 3
	tool.generate_normals()
	_add_mesh(root, tool.commit(), _tinted(CANVAS, colors["tent"]))
	var door := SurfaceTool.new()
	door.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tri(door, Vector3(0, ridge * 0.92, depth - 0.25), Vector3(0.7, 0.0, depth - 0.25), Vector3(-0.7, 0.0, depth - 0.25))
	_add_mesh(root, door.commit(), _plain(Color(0.05, 0.045, 0.04)))
	for z: float in [-depth - 0.04, depth + 0.04]:
		_add_mesh(root, _cylinder(0.05, 0.06, ridge + 0.3), WOOD, Vector3(0, (ridge + 0.3) * 0.5, z))
		# a guy rope from the pole top to a peg beyond the tent
		var peg := Vector3(0, 0.0, z + signf(z) * 1.4)
		_rope(root, Vector3(0, ridge + 0.2, z), peg)
		_add_mesh(root, _cylinder(0.025, 0.02, 0.3, 5), WOOD, peg + Vector3.UP * 0.1, Vector3(-signf(z) * 20.0, 0, 0))
	_add_mesh(root, _cylinder(0.045, 0.045, depth * 2.0 + 0.3), WOOD, Vector3(0, ridge + 0.02, 0), Vector3(90, 0, 0))
	for x: float in [-half_width, half_width]:
		for z: float in [-depth, depth]:
			_add_mesh(root, _cylinder(0.02, 0.015, 0.25, 5), WOOD, Vector3(x * 1.03, 0.08, z))
	# a small pennant in the camp's trim colour, fluttering from the front pole
	var pennant := SurfaceTool.new()
	pennant.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Vector3 in [Vector3(0, ridge + 0.32, 0), Vector3(0.55, ridge + 0.2, 0), Vector3(0, ridge + 0.06, 0)]:
		pennant.set_uv2(Vector2(p.x / 0.55, 0.0))
		pennant.set_normal(Vector3.BACK)
		pennant.add_vertex(p)
	_add_mesh(root, pennant.commit(), _cloth(colors["trim"], 0.08), Vector3(0, 0, depth + 0.05))
	_solid(root, _box_shape(Vector3(half_width * 1.7, ridge * 0.8, depth * 2.0)), Vector3(0, ridge * 0.4, 0))
	return root


## A ring of fire-blackened stones (scanned) around crossed logs, with flames, a
## flickering light and rising sparks.
static func campfire() -> Node3D:
	var root := Node3D.new()
	_scanned(root, "stone_fire_pit", 1.1)
	for i in 3:
		var log_piece := _add_mesh(root, _cylinder(0.09, 0.11, 1.1), BARK, Vector3(0, 0.25, 0), Vector3(62, i * 120, 0))
		log_piece.position += log_piece.basis.y * 0.15
	root.add_child(_flames())
	var crackle := AudioStreamPlayer3D.new()  # tools/art/audio_pack.py
	crackle.stream = load("res://audio/ambience/fire.wav")
	crackle.bus = "Ambience"
	crackle.unit_size = 2.5
	crackle.max_distance = 22.0
	crackle.volume_db = -6.0
	crackle.position = Vector3(0, 0.4, 0)
	crackle.ready.connect(func() -> void: crackle.play(randf() * 20.0))  # campfires out of step
	root.add_child(crackle)
	var light := FireLight.new()
	light.light_color = Color(1.0, 0.62, 0.3)
	light.omni_range = 9.0
	light.position = Vector3(0, 1.0, 0)
	root.add_child(light)
	_solid(root, _cylinder_shape(0.9, 0.6), Vector3(0, 0.3, 0))
	return root


## An iron-bound supply chest (scanned), about `size` * 1.4 m long.
static func crate(size: float) -> Node3D:
	var root := Node3D.new()
	var box := _scanned(root, "wooden_crate_01", size * 1.7)
	_solid(root, _box_shape(box.size), box.get_center())
	return root


## A coopered barrel (scanned), 1 m tall.
static func barrel() -> Node3D:
	var root := Node3D.new()
	var box := _scanned(root, "wine_barrel_01", 1.15)
	_solid(root, _cylinder_shape(box.size.x * 0.5, box.size.y), box.get_center())
	return root


## A tall pole with a cloth banner in the camp's colours, stirring in the wind.
static func banner(style: String) -> Node3D:
	var root := Node3D.new()
	var colors: Dictionary = STYLES[style]
	_add_mesh(root, _cylinder(0.06, 0.08, 4.2), WOOD, Vector3(0, 2.1, 0))
	_add_mesh(root, _cylinder(0.04, 0.04, 1.2), WOOD, Vector3(0, 3.9, 0), Vector3(0, 0, 90))
	# the cloth hangs from the crossbar: a long panel ending in a point, a trim band
	# along the top and a diamond emblem, all rippling together
	var panel := func(y: float) -> float: return 0.5 if y > 2.3 else 0.5 * (y - 1.95) / 0.35
	var band := func(_y: float) -> float: return 0.5
	var diamond := func(y: float) -> float: return 0.18 - absf(y - 3.05) * 0.6
	_add_mesh(root, _hanging_cloth(panel, 3.85, 1.95, 0.05), _cloth(colors["canvas"], 0.1))
	_add_mesh(root, _hanging_cloth(band, 3.85, 3.7, 0.058), _cloth(colors["trim"], 0.1))
	_add_mesh(root, _hanging_cloth(diamond, 3.35, 2.75, 0.058), _cloth(colors["trim"], 0.1))
	_solid(root, _cylinder_shape(0.15, 4.2), Vector3(0, 2.1, 0))
	return root


## Cloth hanging from a crossbar at y = 3.85, from y = top down to y = bottom in the
## plane z, `half_width.call(y)` to each side, finely divided so it can ripple. UV2.x says
## how far down it hangs (prop_cloth.gdshader moves the lower cloth more).
static func _hanging_cloth(half_width: Callable, top: float, bottom: float, z: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 10
	var cols := 6
	for i in rows + 1:
		var y := lerpf(top, bottom, float(i) / rows)
		var w := maxf(half_width.call(y), 0.0)
		for j in cols + 1:
			tool.set_uv2(Vector2((3.85 - y) / 1.9, 0.0))
			tool.set_normal(Vector3.BACK)
			tool.add_vertex(Vector3(lerpf(-w, w, float(j) / cols), y, z))
	for i in rows:
		for j in cols:
			var a := i * (cols + 1) + j
			var b := a + cols + 1
			for k: int in [a, a + 1, b, a + 1, b + 1, b]:
				tool.add_index(k)
	return tool.commit()


## A post-and-rail fence along a circle around `center`, from one angle to another
## (degrees, measured from +X toward +Z). Posts follow the ground.
static func fence_arc(terrain: Terrain, center: Vector3, radius: float, from_deg: float, to_deg: float) -> Node3D:
	var root := Node3D.new()
	var body := StaticBody3D.new()
	body.collision_layer = Unit.LAYER_WORLD
	body.collision_mask = 0
	root.add_child(body)
	var steps := maxi(1, ceili(deg_to_rad(absf(to_deg - from_deg)) * radius / 2.4))
	var posts: Array[Vector3] = []
	for i in steps + 1:
		var angle := deg_to_rad(lerpf(from_deg, to_deg, float(i) / steps))
		var x := center.x + cos(angle) * radius
		var z := center.z + sin(angle) * radius
		posts.append(Vector3(cos(angle) * radius, terrain.get_height(x, z) - center.y, sin(angle) * radius))
	for post in posts:
		_add_mesh(root, _cylinder(0.09, 0.11, 1.5, 6), BARK, post + Vector3.UP * 0.6, Vector3(0, randf() * 360.0, 0))
	for i in steps:
		var a := posts[i]
		var b := posts[i + 1]
		var length := a.distance_to(b)
		var middle := (a + b) * 0.5
		var turn := Basis.looking_at(b - a, Vector3.UP)
		for height: float in [0.55, 1.05]:
			var rail := _add_mesh(root, _box(Vector3(0.08, 0.12, length)), _grained(WOOD, 2), middle + Vector3.UP * height)
			rail.basis = turn
		var shape := CollisionShape3D.new()
		shape.shape = _box_shape(Vector3(0.3, 1.4, length))
		shape.transform = Transform3D(turn, middle + Vector3.UP * 0.7)
		body.add_child(shape)
	return root


## A mine cart heaped with glowing crystal ore.
static func cart() -> Node3D:
	var root := Node3D.new()
	_add_mesh(root, _box(Vector3(1.0, 0.7, 1.6)), PLANKS, Vector3(0, 0.75, 0))
	for x: float in [-0.56, 0.56]:
		for z: float in [-0.5, 0.5]:
			_add_mesh(root, _cylinder(0.28, 0.28, 0.1, 10), _plain(IRON, 0.5), Vector3(x, 0.3, z), Vector3(0, 0, 90))
	for i in 5:
		var shard := _add_mesh(root, PlaceholderModel._crystal(0.16, 0.7), _glow(RUNE), Vector3(randf_range(-0.3, 0.3), 1.2, randf_range(-0.5, 0.5)))
		shard.rotation = Vector3(randf_range(-0.5, 0.5), randf() * TAU, randf_range(-0.5, 0.5))
	_solid(root, _box_shape(Vector3(1.2, 1.1, 1.7)), Vector3(0, 0.55, 0))
	return root


## One of the scanned boulders (picked by seed), about `size` meters across.
static func boulder(size: float, seed_value: int) -> Node3D:
	var root := Node3D.new()
	var set_name: String = ZoneDecorator.BOULDER_SETS[seed_value % 2]
	var pieces := RockLibrary.pieces(set_name)
	var mesh := pieces[seed_value % pieces.size()]
	var rock := _add_mesh(root, mesh, RockLibrary.material(set_name), Vector3(0, -0.1, 0), Vector3(0, seed_value * 47, 0))
	var footprint := maxf(mesh.get_aabb().size.x, mesh.get_aabb().size.z)
	rock.scale = Vector3(1.0, 1.4, 1.0) * size / footprint
	_solid(root, _sphere_shape(size * 0.45), Vector3(0, size * 0.15, 0))
	return root


## A half-buried rib cage with a spine: what is left of Grimjaw's last meal.
static func bones() -> Node3D:
	var root := Node3D.new()
	var material := _plain(BONE)
	_add_mesh(root, _cylinder(0.07, 0.07, 2.4, 6), material, Vector3(0, 0.05, 0), Vector3(90, 0, 0))
	for i in 5:
		var rib := TorusMesh.new()
		rib.inner_radius = 0.5 - i * 0.05
		rib.outer_radius = 0.58 - i * 0.05
		_add_mesh(root, rib, material, Vector3(0, -0.05, -0.8 + i * 0.4), Vector3(90, 0, 0))
	var skull := _add_mesh(root, _sphere(0.28), material, Vector3(0.15, 0.12, 1.45))
	skull.scale = Vector3(1.0, 0.8, 1.3)
	return root


## The rune pillar at the heart of the Wardstone camp.
static func wardstone() -> Node3D:
	var root := Node3D.new()
	_add_mesh(root, _cylinder(2.2, 2.4, 0.4, 8), STONE, Vector3(0, 0.2, 0))
	_add_mesh(root, _cylinder(1.45, 1.6, 0.35, 8), STONE, Vector3(0, 0.55, 0))
	_add_mesh(root, _box(Vector3(1.1, 5.0, 1.1)), STONE, Vector3(0, 3.2, 0))
	_add_mesh(root, _cylinder(0.0, 0.82, 0.7, 4), STONE, Vector3(0, 6.05, 0), Vector3(0, 45, 0))
	for side in 4:
		var strip := _add_mesh(root, _box(Vector3(0.12, 3.2, 0.04)), _glow(RUNE, 2.5), Vector3.ZERO)
		strip.rotation.y = side * PI * 0.5
		strip.position = strip.basis.z * 0.56 + Vector3.UP * 3.3
	var crystal := _add_mesh(root, PlaceholderModel._crystal(0.45, 1.6), _glow(RUNE, 3.0), Vector3(0, 7.4, 0))
	crystal.create_tween().set_loops().tween_property(crystal, "rotation:y", TAU, 6.0).from(0.0)
	var light := OmniLight3D.new()
	light.light_color = RUNE
	light.light_energy = 2.0
	light.omni_range = 12.0
	light.position = Vector3(0, 7.0, 0)
	root.add_child(light)
	_solid(root, _box_shape(Vector3(1.3, 6.0, 1.3)), Vector3(0, 3.0, 0))
	_solid(root, _cylinder_shape(2.2, 0.7), Vector3(0, 0.35, 0))
	return root


## Flickers like firelight.
class FireLight extends OmniLight3D:
	var _time := randf() * 10.0

	func _process(delta: float) -> void:
		_time += delta
		light_energy = 1.7 + sin(_time * 11.0) * 0.18 + sin(_time * 23.0 + 1.3) * 0.12


static func _flames() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.22
	process.direction = Vector3.UP
	process.spread = 12.0
	process.initial_velocity_min = 0.7
	process.initial_velocity_max = 1.3
	process.gravity = Vector3(0, 0.6, 0)
	process.scale_min = 0.6
	process.scale_max = 1.0
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0.15))
	var scale_texture := CurveTexture.new()
	scale_texture.curve = shrink
	process.scale_curve = scale_texture
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([Color(1, 0.92, 0.55, 1), Color(1, 0.5, 0.12, 0.9), Color(0.5, 0.08, 0.02, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	var falloff := Gradient.new()
	falloff.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	dot.gradient = falloff
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = dot
	var quad := QuadMesh.new()
	quad.size = Vector2(0.65, 0.65)
	quad.material = material
	var particles := GPUParticles3D.new()
	particles.amount = 30
	particles.lifetime = 0.75
	particles.process_material = process
	particles.draw_pass_1 = quad
	particles.position.y = 0.25
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


static func _add_mesh(parent: Node3D, mesh: Mesh, material: Material, pos := Vector3.ZERO, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.rotation_degrees = rot_deg
	parent.add_child(instance)
	return instance


static func _solid(parent: Node3D, shape: Shape3D, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Unit.LAYER_WORLD
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = pos
	body.add_child(collision)
	parent.add_child(body)


## Two triangles; the winding makes the front face the side the corners turn clockwise from.
static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(tool, a, b, c)
	_tri(tool, a, c, d)


static func _tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (c - a).cross(b - a).normalized()
	for p in [a, b, c]:
		tool.set_normal(normal)
		tool.add_vertex(p)


## Instances one of the scanned props (art/props/<name>/<name>.gltf), scaled by `factor`,
## and returns its bounds in the prop's space.
static func _scanned(parent: Node3D, model: String, factor: float) -> AABB:
	var scene: Node3D = (load("res://art/props/%s/%s.gltf" % [model, model]) as PackedScene).instantiate()
	scene.scale = Vector3.ONE * factor
	parent.add_child(scene)
	var box := AABB()
	for node: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var part: AABB = node.transform * node.mesh.get_aabb()
		box = part if box.size == Vector3.ZERO else box.merge(part)
	return Transform3D.IDENTITY.scaled(Vector3.ONE * factor) * box


## A thin rope between two points.
static func _rope(parent: Node3D, from: Vector3, to: Vector3) -> void:
	var rope := _add_mesh(parent, _cylinder(0.012, 0.012, from.distance_to(to), 4), _plain(ROPE), (from + to) * 0.5)
	rope.basis = Basis(Quaternion(Vector3.UP, (to - from).normalized()))


## A copy of a scanned-surface material with other shader parameters, shared per combination.
static func _variant(base: ShaderMaterial, parameters: Dictionary) -> Material:
	var key := "%s/%s" % [base.resource_path, parameters]
	if not _materials.has(key):
		var material: ShaderMaterial = base.duplicate()
		for parameter: String in parameters:
			material.set_shader_parameter(parameter, parameters[parameter])
		_materials[key] = material
	return _materials[key]


static func _tinted(base: ShaderMaterial, color: Color) -> Material:
	return _variant(base, {"tint": color})


## Wood whose grain runs along another axis of the piece (0 = X, 1 = Y, 2 = Z).
static func _grained(base: ShaderMaterial, axis: int) -> Material:
	return _variant(base, {"grain_axis": axis})


## Dyed canvas that ripples by up to `sway` meters at its free edge.
static func _cloth(color: Color, sway := 0.0) -> Material:
	return _variant(CANVAS, {"tint": color, "sway": sway})


static func _plain(color: Color, metallic := 0.0) -> Material:
	var key := "plain/%s/%s" % [color.to_html(), metallic]
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.metallic = metallic
		material.roughness = 0.8
		_materials[key] = material
	return _materials[key]


static func _glow(color: Color, energy := 2.2) -> Material:
	var key := "glow/%s/%s" % [color.to_html(), energy]
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = energy
		_materials[key] = material
	return _materials[key]


static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _cylinder(top: float, bottom: float, height: float, sides := 8) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return mesh


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	return mesh


static func _box_shape(size: Vector3) -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return shape


static func _cylinder_shape(radius: float, height: float) -> CylinderShape3D:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	return shape


static func _sphere_shape(radius: float) -> SphereShape3D:
	var shape := SphereShape3D.new()
	shape.radius = radius
	return shape
