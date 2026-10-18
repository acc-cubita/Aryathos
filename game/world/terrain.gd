class_name Terrain
extends StaticBody3D
## Procedural heightmap terrain (mesh + matching collision) for a zone.
## Gameplay code only calls get_height() / get_slope(), so this can later be
## replaced by a hand-sculpted terrain without touching anything else.

const GRASS_DARK := Color(0.27, 0.45, 0.22)
const GRASS_LIGHT := Color(0.42, 0.6, 0.3)
const DIRT := Color(0.48, 0.38, 0.26)
const ROCK := Color(0.42, 0.42, 0.46)
const SNOW := Color(0.9, 0.93, 0.98)
const SAND := Color(0.7, 0.64, 0.47)
## Where rock starts and fully covers the ground (1 - normal.y). Keep in sync with terrain.gdshader.
const ROCK_SLOPE := Vector2(0.17, 0.33)

## Side length in meters; one vertex per meter.
@export var size := 300
@export var noise_seed := 1337
@export var hill_height := 7.0
@export var border_height := 42.0
@export var water_level := -1.6
## Circles (x, z, radius) flattened for camps and towns.
@export var flat_areas := PackedVector3Array()
## Circles (x, z, radius) turned into shallow lakes.
@export var lakes := PackedVector3Array()
## Dirt road segments as point pairs: a0, b0, a1, b1, ...
@export var path_segments := PackedVector2Array()
## Splat material (terrain.gdshader) reading the layer weights from vertex colors.
@export var ground_material: Material
@export var water_material: Material

var _count := 0
var _half := 0.0
var _heights := PackedFloat32Array()
var _colors := PackedColorArray()
var _weights := PackedColorArray()
var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()


func generate() -> void:
	_noise.seed = noise_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.008
	_noise.fractal_octaves = 4
	_detail.seed = noise_seed + 1
	_detail.frequency = 0.06
	_detail.fractal_octaves = 2
	# Sharp crests and gullies for the border mountains.
	_ridges.seed = noise_seed + 2
	_ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridges.frequency = 0.011
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridges.fractal_octaves = 5
	_ridges.fractal_gain = 0.45
	_count = size + 1
	_half = size * 0.5
	_heights.resize(_count * _count)
	for z in _count:
		for x in _count:
			_heights[z * _count + x] = _height_function(x - _half, z - _half)
	collision_layer = Unit.LAYER_WORLD
	collision_mask = 0
	_build_mesh()
	_build_collision()
	_build_water()


## Top-down picture of the terrain for the minimap (1 pixel per meter, north up).
## Uses the ground colors with simple hill shading, and paints the lakes blue.
func make_map_image() -> Image:
	var image := Image.create_empty(_count, _count, false, Image.FORMAT_RGBA8)
	var light := Vector3(-0.5, 0.8, -0.4).normalized()
	for z in _count:
		for x in _count:
			var i := z * _count + x
			var color := _colors[i] * (0.65 + 0.45 * maxf(0.0, _normal_at(x, z).dot(light)))
			if _heights[i] < water_level:
				color = Color(0.2, 0.45, 0.65)
			color.a = 1.0
			image.set_pixel(x, z, color)
	return image


## Ground heights as a texture (1 texel per meter), for details placed on the GPU like grass.
func make_height_texture() -> ImageTexture:
	var image := Image.create_from_data(_count, _count, false, Image.FORMAT_RF, _heights.to_byte_array())
	image.convert(Image.FORMAT_RH)
	return ImageTexture.create_from_image(image)


## How grassy the ground is (r) and how lush that grass is (g), 1 texel per meter.
func make_grass_texture() -> ImageTexture:
	var image := Image.create_empty(_count, _count, false, Image.FORMAT_RGBA8)
	for z in _count:
		for x in _count:
			var w := _weights[z * _count + x]
			var rock := smoothstep(ROCK_SLOPE.x, ROCK_SLOPE.y, 1.0 - _normal_at(x, z).y)
			var bare := maxf(maxf(w.r, w.g), maxf(w.b, rock))
			var patches := clampf(_detail.get_noise_2d(x * 0.9 + 77.0, z * 0.9) * 1.4 + 0.6, 0.15, 1.0)
			image.set_pixel(x, z, Color((1.0 - smoothstep(0.2, 0.55, bare)) * patches, w.a, 0.0, 1.0))
	return ImageTexture.create_from_image(image)


## Vertices per side of the height and grass textures.
func map_resolution() -> int:
	return _count


func get_height(x: float, z: float) -> float:
	var fx := clampf(x + _half, 0.0, _count - 1.001)
	var fz := clampf(z + _half, 0.0, _count - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * _count + ix
	var top := lerpf(_heights[i], _heights[i + 1], tx)
	var bottom := lerpf(_heights[i + _count], _heights[i + _count + 1], tx)
	return lerpf(top, bottom, tz)


## 0 = flat, 1 = vertical.
func get_slope(x: float, z: float) -> float:
	var dx := get_height(x + 1.0, z) - get_height(x - 1.0, z)
	var dz := get_height(x, z + 1.0) - get_height(x, z - 1.0)
	return 1.0 - Vector3(-dx, 2.0, -dz).normalized().y


## What the ground at (x, z) is, for footsteps: "snow", "rock", "sand", "dirt" or "grass".
func surface_at(x: float, z: float) -> String:
	var dx := get_height(x + 1.0, z) - get_height(x - 1.0, z)
	var dz := get_height(x, z + 1.0) - get_height(x, z - 1.0)
	var normal := Vector3(-dx, 2.0, -dz).normalized()
	var weights := _weights_at(x, z, get_height(x, z), normal)
	if weights.b > 0.5:
		return "snow"
	if 1.0 - normal.y > ROCK_SLOPE.y:
		return "rock"
	if weights.g > 0.5:
		return "sand"
	if weights.r > 0.45:
		return "dirt"
	return "grass"


func distance_to_path(x: float, z: float) -> float:
	var point := Vector2(x, z)
	var best := INF
	for i in range(0, path_segments.size() - 1, 2):
		var closest := Geometry2D.get_closest_point_to_segment(point, path_segments[i], path_segments[i + 1])
		best = minf(best, point.distance_to(closest))
	return best


## Rolling hills (always above water), border mountains, lakes and flat camps.
func _height_function(x: float, z: float) -> float:
	var h := _base_height(x, z) + _detail.get_noise_2d(x, z) * 0.5
	# Mountains along the zone edge close the zone in, like WoW zone borders: a rising
	# wall carved into crests and gullies by ridged noise, highest along the far edge.
	var edge := maxf(absf(x), absf(z)) / _half + _noise.get_noise_2d(z * 2.0, x * 2.0) * 0.06
	var m := smoothstep(0.7, 0.97, edge)
	if m > 0.0:
		var ridge := _ridges.get_noise_2d(x, z) * 0.5 + 0.5
		h += border_height * (m * (0.7 + 0.2 * _detail.get_noise_2d(x * 0.3, z * 0.3)) + m * m * (ridge - 0.4) * 0.8)
		# layered rock: uneven ledges and steep risers about every 3.5 m of height
		var layer := (h + _noise.get_noise_2d(x * 3.0 + 900.0, z * 3.0) * 2.5) / 3.5
		var ledges := (floorf(layer) + smoothstep(0.35, 0.95, layer - floorf(layer))) * 3.5
		h += (ledges - layer * 3.5) * smoothstep(0.2, 0.6, m) * 0.55
	for lake: Vector3 in lakes:
		var t := 1.0 - smoothstep(lake.z * 0.5, lake.z, Vector2(x - lake.x, z - lake.y).length())
		h = lerpf(h, water_level - 1.4, t)
	for area: Vector3 in flat_areas:
		var t := 1.0 - smoothstep(area.z, area.z * 1.8, Vector2(x - area.x, z - area.y).length())
		h = lerpf(h, _base_height(area.x, area.y), t)
	return h


func _base_height(x: float, z: float) -> float:
	return (_noise.get_noise_2d(x, z) * 0.5 + 0.5) * hill_height


func _color_at(x: float, z: float, h: float, normal: Vector3) -> Color:
	var n := _detail.get_noise_2d(x * 1.7, z * 1.7) * 0.5 + 0.5
	var color := GRASS_DARK.lerp(GRASS_LIGHT, n)
	if h < water_level + 0.8:
		color = color.lerp(SAND, clampf((water_level + 0.8 - h) / 0.8, 0.0, 1.0))
	var road := distance_to_path(x, z)
	if road < 3.5:
		color = color.lerp(DIRT, (1.0 - smoothstep(1.5, 3.5, road)) * 0.9)
	for area: Vector3 in flat_areas:
		var d := Vector2(x - area.x, z - area.y).length()
		if d < area.z:
			color = color.lerp(DIRT, (1.0 - smoothstep(area.z * 0.4, area.z, d)) * 0.7)
	color = color.lerp(ROCK, smoothstep(0.18, 0.38, 1.0 - normal.y))
	return color.lerp(SNOW, smoothstep(24.0, 32.0, h + n * 5.0))


## Layer weights for the splat shader: r = dirt, g = sand, b = snow, a = grass lushness.
func _weights_at(x: float, z: float, h: float, normal: Vector3) -> Color:
	var n := _detail.get_noise_2d(x * 1.7, z * 1.7) * 0.5 + 0.5
	var lush := clampf(_noise.get_noise_2d(x * 2.5 + 400.0, z * 2.5) * 0.8 + 0.5, 0.0, 1.0)
	lush *= 1.0 - smoothstep(10.0, 22.0, h) * 0.8  # dry alpine grass higher up
	var sand := clampf((water_level + 0.8 - h) / 0.8, 0.0, 1.0)
	var dirt := 1.0 - smoothstep(1.2, 3.5, distance_to_path(x, z))
	for area: Vector3 in flat_areas:
		var d := Vector2(x - area.x, z - area.y).length()
		dirt = maxf(dirt, (1.0 - smoothstep(area.z * 0.4, area.z, d)) * 0.75)
	# stony bare ground where the mountain grass thins out below the rock
	var scree := smoothstep(ROCK_SLOPE.x - 0.1, ROCK_SLOPE.x, 1.0 - normal.y) * smoothstep(4.0, 12.0, h)
	dirt = maxf(dirt, scree * (0.75 + 0.25 * n))
	var snow := smoothstep(24.0, 32.0, h + n * 5.0)
	return Color(dirt, sand, snow, lush)


func _normal_at(x: int, z: int) -> Vector3:
	var left := _heights[z * _count + maxi(x - 1, 0)]
	var right := _heights[z * _count + mini(x + 1, _count - 1)]
	var up := _heights[maxi(z - 1, 0) * _count + x]
	var down := _heights[mini(z + 1, _count - 1) * _count + x]
	return Vector3(left - right, 2.0, up - down).normalized()


func _build_mesh() -> void:
	var n := _count
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	_weights.resize(n * n)
	for z in n:
		for x in n:
			var i := z * n + x
			var normal := _normal_at(x, z)
			vertices[i] = Vector3(x - _half, _heights[i], z - _half)
			normals[i] = normal
			colors[i] = _color_at(x - _half, z - _half, _heights[i], normal)
			_weights[i] = _weights_at(x - _half, z - _half, _heights[i], normal)
	var indices := PackedInt32Array()
	indices.resize((n - 1) * (n - 1) * 6)
	var k := 0
	for z in n - 1:
		for x in n - 1:
			var a := z * n + x
			var c := a + n
			# Godot treats clockwise triangles as front faces.
			indices[k] = a
			indices[k + 1] = a + 1
			indices[k + 2] = c
			indices[k + 3] = a + 1
			indices[k + 4] = c + 1
			indices[k + 5] = c
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = _weights
	_colors = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	if ground_material:
		mesh_instance.material_override = ground_material
	else:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = GRASS_DARK
		mesh_instance.material_override = plain
	add_child(mesh_instance)


func _build_collision() -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = _count
	shape.map_depth = _count
	shape.map_data = _heights
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	add_child(collision)
	# Invisible walls inside the border mountains, in case a gully is gentle enough to climb.
	for side in 4:
		var wall := BoxShape3D.new()
		wall.size = Vector3(size, 300.0, 2.0)
		var border := CollisionShape3D.new()
		border.name = "Border%d" % side
		border.shape = wall
		border.rotation.y = side * PI * 0.5
		border.position = Vector3(0, 100, _half * 0.95).rotated(Vector3.UP, side * PI * 0.5)
		add_child(border)


func _build_water() -> void:
	var material := water_material
	if material == null:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = Color(0.18, 0.42, 0.62, 0.72)
		plain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material = plain
	for lake: Vector3 in lakes:
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE * lake.z * 2.0
		var water := MeshInstance3D.new()
		water.name = "Water"
		water.mesh = plane
		water.material_override = material
		water.position = Vector3(lake.x, water_level, lake.y)
		add_child(water)
