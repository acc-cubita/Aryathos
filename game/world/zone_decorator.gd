class_name ZoneDecorator
extends Node3D
## Scatters trees, rocks and glowing crystal clusters over the terrain.
## Uses MultiMesh so hundreds of props stay cheap to draw.

const CRYSTAL_BLUE := Color(0.35, 0.7, 1.0)
const CRYSTAL_VIOLET := Color(0.62, 0.45, 1.0)
## Mesh variants per kind; each variant is one MultiMesh, so a few keep the forest varied.
const VARIANTS := 3
## Trees and bushes are split into square chunks this wide, so the ones out of view
## (behind the camera, outside a shadow cascade) are culled instead of drawn with the rest.
const CHUNK := 60.0
## Scanned boulder sets (RockLibrary); every piece is its own variant.
const BOULDER_SETS: Array[String] = ["boulders_a", "boulders_b"]
## Scanned cliff faces and the scales they are placed at (the scans are 3-10 m across):
## cliff_c is near vertical and goes on the steepest ground.
const CLIFFS := {"cliff_a": Vector2(1.6, 3.0), "cliff_b": Vector2(2.0, 3.4), "cliff_c": Vector2(1.1, 2.0)}

@export var decor_seed := 7
@export var tree_count := 380
@export var bush_count := 220
@export var rock_count := 120
@export var cliff_count := 130
@export var crystal_cluster_count := 26
## Share of valley trees that are broadleaf (the rest, and all mountain trees, are pines).
@export_range(0.0, 1.0) var broadleaf_share := 0.45
## Share of broadleaf trees already in autumn colours.
@export_range(0.0, 1.0) var autumn_share := 0.1
## Circles (x, z, radius) kept free of props, e.g. camps.
@export var clear_areas := PackedVector3Array()
## Circles (x, z, radius) where most crystal clusters gather.
@export var crystal_areas := PackedVector3Array()
@export_group("Materials")
## Broadleaf crowns and bushes (summer leaves), autumn crowns, conifer needles.
@export var leaf_material: Material
@export var autumn_leaf_material: Material
@export var needle_material: Material
## Broadleaf and conifer bark.
@export var bark_material: Material
@export var pine_bark_material: Material

var _terrain: Terrain
var _rng := RandomNumberGenerator.new()
var _colliders: StaticBody3D
var _map_marks: Array[Vector4] = []
## Circles (x, z, radius) already taken by cliffs and boulders.
var _blocked: Array[Vector3] = []


func decorate(terrain: Terrain) -> void:
	_terrain = terrain
	_rng.seed = decor_seed
	_colliders = StaticBody3D.new()
	_colliders.name = "PropColliders"
	_colliders.collision_layer = Unit.LAYER_WORLD
	_colliders.collision_mask = 0
	add_child(_colliders)
	_scatter_cliffs()
	_scatter_rocks()
	_scatter_trees()
	_scatter_bushes()
	_scatter_crystals()


func _scatter_trees() -> void:
	# [kind][variant] -> transforms / colors; kind 0 = pine, 1 = broadleaf, 2 = broadleaf in autumn.
	var transforms := [[[], [], []], [[], [], []], [[], [], []]]
	var colors := [[[], [], []], [[], [], []], [[], [], []]]
	for i in tree_count:
		# Every third tree may climb the border mountains for a forested skyline.
		var spread := 0.97 if i % 3 == 0 else 0.88
		var p := _random_ground_point(spread, 0.45, 1.5)
		if not p.is_finite():
			continue
		var on_mountain := maxf(absf(p.x), absf(p.z)) > _terrain.size * 0.5 * 0.8
		var kind := 1 if not on_mountain and _rng.randf() < broadleaf_share else 0
		if kind == 1 and _rng.randf() < autumn_share:
			kind = 2
		var variant := _rng.randi() % VARIANTS
		var s := _rng.randf_range(0.75, 1.2)
		transforms[kind][variant].append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), p))
		# the textures carry the colour; tints only vary each tree a little
		var tint := _rng.randf()
		match kind:
			0: colors[kind][variant].append(Color(0.82, 0.9, 0.84).lerp(Color(1.0, 1.02, 0.94), tint))
			1: colors[kind][variant].append(Color(0.86, 0.95, 0.84).lerp(Color(1.06, 1.05, 0.9), tint))
			_: colors[kind][variant].append(Color(0.95, 0.88, 0.86).lerp(Color(1.08, 1.0, 0.92), tint))
		_map_marks.append(Vector4(p.x, p.z, (1.6 if kind == 0 else 2.4) * s, 0))
		_add_cylinder_collider(p, (0.3 if kind == 0 else 0.36) * s, 3.0 * s)
	var crowns: Array[Material] = [needle_material, leaf_material, autumn_leaf_material]
	var barks: Array[Material] = [pine_bark_material, bark_material, bark_material]
	for kind in 3:
		for variant in VARIANTS:
			var meshes := TreeLibrary.meshes("pine" if kind == 0 else "broadleaf", variant)
			var label: String = ["Pine", "Broadleaf", "Autumn"][kind] + str(variant)
			var placed: Array[Transform3D] = []
			placed.assign(transforms[kind][variant])
			var tints: Array[Color] = []
			tints.assign(colors[kind][variant])
			_add_chunked(label + "Trunks", meshes[0], placed, [], barks[kind])
			_add_chunked(label + "Crowns", meshes[1], placed, tints, crowns[kind])


func _scatter_bushes() -> void:
	var transforms: Array[Array] = [[], []]
	var colors: Array[Array] = [[], []]
	for i in bush_count:
		var p := _random_ground_point(0.9, 0.5, 0.5)
		if not p.is_finite():
			continue
		var s := _rng.randf_range(0.7, 1.3)
		var variant := i % 2
		transforms[variant].append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.1), s)), p - Vector3.UP * 0.05))
		colors[variant].append(Color(0.85, 0.93, 0.82).lerp(Color(1.05, 1.04, 0.9), _rng.randf()))
	for variant in 2:
		var meshes := TreeLibrary.meshes("bush", variant)
		var placed: Array[Transform3D] = []
		placed.assign(transforms[variant])
		var tints: Array[Color] = []
		tints.assign(colors[variant])
		_add_chunked("BushStems" + str(variant), meshes[0], placed, [], bark_material)
		_add_chunked("Bushes" + str(variant), meshes[1], placed, tints, leaf_material)


## Scanned cliff faces on the steep border mountains, turned to look down the slope.
## Their skirts reach back into the hill, so they read as rock breaking out of it.
func _scatter_cliffs() -> void:
	var half := _terrain.size * 0.5
	var transforms := {}
	var colors := {}
	for set_name: String in CLIFFS:
		transforms[set_name] = [] as Array[Transform3D]
		colors[set_name] = [] as Array[Color]
	for i in cliff_count:
		for attempt in 40:
			var x := _rng.randf_range(-half, half) * 0.96
			var z := _rng.randf_range(-half, half) * 0.96
			var slope := _terrain.get_slope(x, z)
			if maxf(absf(x), absf(z)) < half * 0.66 or slope < 0.2 or slope > 0.75:
				continue
			var set_name: String = "cliff_c" if slope > 0.4 and _rng.randf() < 0.6 else ["cliff_a", "cliff_b"][_rng.randi() % 2]
			var scale_range: Vector2 = CLIFFS[set_name]
			var s := _rng.randf_range(scale_range.x, scale_range.y)
			var box := RockLibrary.pieces(set_name)[0].get_aabb()
			var r := box.size.x * s * 0.4
			if not _is_free(x, z, r):
				continue
			var down := Vector2(_terrain.get_height(x - 1.0, z) - _terrain.get_height(x + 1.0, z), _terrain.get_height(x, z - 1.0) - _terrain.get_height(x, z + 1.0))
			# the hill must rise behind the face, or it would stand on a crest like a lone pillar
			var behind := Vector2(x, z) - down.normalized() * box.size.z * s * 0.6
			if _terrain.get_height(behind.x, behind.y) < _terrain.get_height(x, z) + box.size.y * s * 0.3:
				continue
			var basis := Basis(Vector3.UP, atan2(down.x, down.y) + _rng.randf_range(-0.3, 0.3)).scaled(Vector3.ONE * s)
			transforms[set_name].append(Transform3D(basis, Vector3(x, _terrain.get_height(x, z) - 0.4 * s, z)))
			var grey := _rng.randf_range(0.85, 1.05)
			colors[set_name].append(Color(grey, grey, grey))
			_blocked.append(Vector3(x, z, r))
			break
	for set_name: String in CLIFFS:
		_add_chunked(set_name.capitalize().replace(" ", ""), RockLibrary.pieces(set_name)[0], transforms[set_name], colors[set_name], RockLibrary.material(set_name))


func _scatter_rocks() -> void:
	var meshes: Array[Mesh] = []
	var materials: Array[Material] = []
	for set_name in BOULDER_SETS:
		for mesh in RockLibrary.pieces(set_name):
			meshes.append(mesh)
			materials.append(RockLibrary.material(set_name))
	var transforms: Array[Array] = []
	var colors: Array[Array] = []
	for mesh in meshes:
		transforms.append([] as Array[Transform3D])
		colors.append([] as Array[Color])
	for i in rock_count:
		var p := _random_ground_point(0.93, 0.6, 1.0)
		if not p.is_finite():
			continue
		var k := _rng.randi() % meshes.size()
		var s := _rng.randf_range(0.6, 1.5)
		var size := meshes[k].get_aabb().size * s
		var r := maxf(size.x, size.z) * 0.5
		# sit on the lowest ground under the rock, so no side floats over a slope
		var ground := p.y
		for side in 4:
			var a := side * PI * 0.5
			ground = minf(ground, _terrain.get_height(p.x + cos(a) * r * 0.7, p.z + sin(a) * r * 0.7))
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.15), s))
		transforms[k].append(Transform3D(basis, Vector3(p.x, ground - 0.05 * s, p.z)))
		var grey := _rng.randf_range(0.85, 1.05)
		colors[k].append(Color(grey, grey, grey))
		_blocked.append(Vector3(p.x, p.z, r * 0.8))
		if r > 0.8:
			var shape := CollisionShape3D.new()
			var sphere := SphereShape3D.new()
			sphere.radius = r * 0.8
			shape.shape = sphere
			shape.position = Vector3(p.x, ground + size.y * 0.25, p.z)
			_colliders.add_child(shape)
	for k in meshes.size():
		var placed: Array[Transform3D] = []
		placed.assign(transforms[k])
		var tints: Array[Color] = []
		tints.assign(colors[k])
		_add_chunked("Boulder%d" % k, meshes[k], placed, tints, materials[k])


func _scatter_crystals() -> void:
	var blue: Array[Transform3D] = []
	var violet: Array[Transform3D] = []
	for i in crystal_cluster_count:
		var center := Vector3.INF
		if i < crystal_cluster_count * 0.7 and not crystal_areas.is_empty():
			var area := crystal_areas[i % crystal_areas.size()]
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * area.z
			var x := area.x + cos(a) * r
			var z := area.y + sin(a) * r
			center = Vector3(x, _terrain.get_height(x, z), z)
		else:
			center = _random_ground_point(0.85, 0.4, 1.0)
		if not center.is_finite():
			continue
		_map_marks.append(Vector4(center.x, center.z, 1.2, 1))
		var is_violet := i % 4 == 0
		var list := violet if is_violet else blue
		for shard in _rng.randi_range(3, 6):
			var offset := Vector3(_rng.randf_range(-0.8, 0.8), -0.2, _rng.randf_range(-0.8, 0.8))
			var tilt := Basis.from_euler(Vector3(_rng.randf_range(-0.45, 0.45), _rng.randf() * TAU, _rng.randf_range(-0.45, 0.45)))
			var s := _rng.randf_range(0.6, 1.8)
			list.append(Transform3D(tilt * Basis.from_scale(Vector3(s, s * _rng.randf_range(1.0, 1.8), s)), center + offset))
		if i % 2 == 0:
			var light := OmniLight3D.new()
			light.light_color = CRYSTAL_VIOLET if is_violet else CRYSTAL_BLUE
			light.light_energy = 1.2
			light.omni_range = 5.0
			light.position = center + Vector3.UP * 1.2
			add_child(light)
	var shard_mesh := PlaceholderModel._crystal(0.28, 1.6)
	_add_multimesh("CrystalsBlue", shard_mesh, blue, [], _glow_material(CRYSTAL_BLUE))
	_add_multimesh("CrystalsViolet", shard_mesh, violet, [], _glow_material(CRYSTAL_VIOLET))


## Draws trees (dark green) and crystal clusters (cyan) onto the minimap picture.
func paint_map(image: Image) -> void:
	var half := _terrain.size * 0.5
	for mark in _map_marks:
		var color := Color(0.12, 0.27, 0.14) if mark.w == 0 else Color(0.5, 0.85, 1.0)
		var r := ceili(mark.z)
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var px := roundi(mark.x + half) + dx
				var pz := roundi(mark.y + half) + dz
				if dx * dx + dz * dz <= mark.z * mark.z and px >= 0 and pz >= 0 and px < image.get_width() and pz < image.get_height():
					image.set_pixel(px, pz, color)


## Random walkable spot, or Vector3.INF if none was found.
## `spread` is the fraction of the zone used (1 = up to the very edge).
func _random_ground_point(spread: float, max_slope: float, clearance: float) -> Vector3:
	var half := _terrain.size * 0.5 * spread
	for attempt in 30:
		var x := _rng.randf_range(-half, half)
		var z := _rng.randf_range(-half, half)
		if not _is_clear(x, z, clearance):
			continue
		var h := _terrain.get_height(x, z)
		if h < _terrain.water_level + 0.4 or _terrain.get_slope(x, z) > max_slope:
			continue
		return Vector3(x, h, z)
	return Vector3.INF


func _is_clear(x: float, z: float, clearance: float) -> bool:
	for area: Vector3 in clear_areas:
		if Vector2(x - area.x, z - area.y).length() < area.z + clearance:
			return false
	return _terrain.distance_to_path(x, z) > 3.5 + clearance and _is_free(x, z, clearance)


## True if a circle of `radius` here misses every cliff and boulder placed so far.
func _is_free(x: float, z: float, radius: float) -> bool:
	for taken in _blocked:
		if Vector2(x - taken.x, z - taken.y).length() < taken.z + radius:
			return false
	return true


func _add_cylinder_collider(at: Vector3, radius: float, height: float) -> void:
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	var shape := CollisionShape3D.new()
	shape.shape = cylinder
	shape.position = at + Vector3.UP * height * 0.5
	_colliders.add_child(shape)


## One MultiMesh per CHUNK of ground the instances stand on.
func _add_chunked(node_name: String, mesh: Mesh, transforms: Array[Transform3D], colors: Array[Color], material: Material) -> void:
	var chunks := {}
	for i in transforms.size():
		var key := Vector2i(floori(transforms[i].origin.x / CHUNK), floori(transforms[i].origin.z / CHUNK))
		if not chunks.has(key):
			chunks[key] = [[] as Array[Transform3D], [] as Array[Color]]
		chunks[key][0].append(transforms[i])
		if not colors.is_empty():
			chunks[key][1].append(colors[i])
	for key: Vector2i in chunks:
		_add_multimesh("%s_%d_%d" % [node_name, key.x, key.y], mesh, chunks[key][0], chunks[key][1], material)


func _add_multimesh(node_name: String, mesh: Mesh, transforms: Array[Transform3D], colors: Array[Color], material: Material) -> void:
	if transforms.is_empty() or mesh == null:
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = not colors.is_empty()
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		if multimesh.use_colors:
			multimesh.set_instance_color(i, colors[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	add_child(instance)


func _glow_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.2
	return material
