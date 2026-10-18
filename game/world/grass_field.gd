class_name GrassField
extends MultiMeshInstance3D
## Grass around the camera. One fixed grid of blade clumps follows the camera in
## whole grid steps; grass.gdshader places every clump on the ground, so each always
## lands on the same spot of the world and nothing visibly swims or pops.

## How far from the camera grass is drawn (it fades out over the last few meters).
@export var radius := 30.0
@export var spacing := 0.42
@export var blades_per_clump := 11
@export var grass_seed := 5


func plant(terrain: Terrain) -> void:
	var shader := material_override as ShaderMaterial
	shader.set_shader_parameter("height_map", terrain.make_height_texture())
	shader.set_shader_parameter("grass_map", terrain.make_grass_texture())
	shader.set_shader_parameter("map_size", float(terrain.map_resolution()))
	shader.set_shader_parameter("spacing", spacing)
	_build_grid()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Grass out to `distance` from the camera (0: none); the graphics settings' grass distance.
func set_radius(distance: float) -> void:
	radius = distance
	visible = distance > 0.0
	if visible and material_override:
		_build_grid()


func _build_grid() -> void:
	var shader := material_override as ShaderMaterial
	shader.set_shader_parameter("fade_start", radius * 0.73)
	shader.set_shader_parameter("fade_end", radius)
	var cells := ceili(radius / spacing)
	var grid := MultiMesh.new()
	grid.transform_format = MultiMesh.TRANSFORM_3D
	grid.mesh = _clump_mesh()
	grid.instance_count = (cells * 2 + 1) * (cells * 2 + 1)
	var i := 0
	for z in range(-cells, cells + 1):
		for x in range(-cells, cells + 1):
			grid.set_instance_transform(i, Transform3D(Basis(), Vector3(x * spacing, 0.0, z * spacing)))
			i += 1
	multimesh = grid
	# The shader moves the clumps up to the ground, so cull with a box that covers any height.
	custom_aabb = AABB(Vector3(-radius - 2.0, -20.0, -radius - 2.0), Vector3(radius * 2.0 + 4.0, 120.0, radius * 2.0 + 4.0))


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera and multimesh:
		var at := camera.global_position
		global_position = Vector3(snappedf(at.x, spacing), 0.0, snappedf(at.z, spacing))


## A tuft of thin, tapered blades that bend over toward their tips. UV.y runs from 0
## at the root to 1 at the tip; UV.x is a random number per blade (colour variation).
func _clump_mesh() -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = grass_seed
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in blades_per_clump:
		var angle := rng.randf() * TAU
		var root := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.0, 0.2)
		var facing := rng.randf() * TAU
		var side := Vector3(cos(facing), 0.0, sin(facing))
		# blades lean outward from the clump and curl over a little more near the tip
		var lean := (root.normalized() if root.length() > 0.01 else side) * rng.randf_range(0.05, 0.22) 				+ Vector3(-side.z, 0.0, side.x) * rng.randf_range(-0.08, 0.08)
		var height := rng.randf_range(0.22, 0.55)
		var width := rng.randf_range(0.007, 0.013)
		var shade := rng.randf()
		var rows: Array[float] = [0.0, 0.35, 0.7, 1.0]
		var points: Array[Vector3] = []
		for t in rows:
			var bend := lean * t * t
			var half := width * (1.0 - t * 0.85)
			var center := root + bend + Vector3.UP * height * t * (1.0 - 0.12 * t * t)
			if t < 1.0:
				points.append(center - side * half)
				points.append(center + side * half)
			else:
				points.append(center)
		var tips: Array[float] = [0.0, 0.0, 0.35, 0.35, 0.7, 0.7, 1.0]
		for index: int in [0, 1, 2, 1, 3, 2, 2, 3, 4, 3, 5, 4, 4, 5, 6]:
			tool.set_uv(Vector2(shade, tips[index]))
			tool.set_normal(Vector3(-side.z, 0.35, side.x).normalized())  # facing out of the blade
			tool.add_vertex(points[index])
	return tool.commit()
