class_name GatherNode
extends Node3D
## A plant (or other resource) in the world. Right-click it to gather it; it
## disappears and grows back after a while. Herbalists see it on the minimap.

const LEAVES := preload("res://world/materials/herb_leaves.tres")
const BLOOM_SHADER := preload("res://world/shaders/herb_bloom.gdshader")
const ATLAS := preload("res://art/textures/foliage/herbs.png")

static var _bloom_materials := {}

var data: GatherNodeData
var available := true

var _model := Node3D.new()
var _card_count := 0
var _bloom_count := 0
var _click_area := Area3D.new()
var _respawn_at := 0.0


func _ready() -> void:
	add_to_group("gather_nodes")
	_build_model()
	add_child(_model)
	_click_area.collision_layer = Unit.LAYER_CLICKABLE
	_click_area.collision_mask = 0
	_click_area.monitoring = false
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8
	var shape := CollisionShape3D.new()
	shape.shape = sphere
	shape.position.y = 0.4
	_click_area.add_child(shape)
	add_child(_click_area)


func harvest() -> void:
	available = false
	_model.visible = false
	_click_area.collision_layer = 0
	_respawn_at = Game.time + data.respawn_time


func _process(_delta: float) -> void:
	if not available and Game.time >= _respawn_at:
		available = true
		_model.visible = true
		_click_area.collision_layer = Unit.LAYER_CLICKABLE


## A rosette of scanned leaves with a few flowering stems: cards from
## art/textures/foliage/herbs.png (2 x 2: two leaves on top, two blooms below). The leaves
## lean toward the herb's leaf colour; the white blooms are dyed its bloom colour and glow.
func _build_model() -> void:
	var rng := RandomNumberGenerator.new()
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tint := Color.WHITE.lerp(data.leaf_color * 1.8, 0.4)
	for i in 9:
		var angle := TAU * i / 9.0 + rng.randf_range(-0.25, 0.25)
		_card(leaves, angle, rng.randf_range(0.5, 1.05), rng.randf_range(0.26, 0.36), 0.7, Vector2(0.5 * (i % 2), 0.0), tint, true)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = leaves.commit()
	mesh_instance.material_override = LEAVES
	_model.add_child(mesh_instance)
	var stem_color := data.leaf_color.darkened(0.35)
	var blooms := SurfaceTool.new()
	blooms.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var angle := TAU * i / 4.0 + rng.randf_range(0.0, 1.0)
		var height := rng.randf_range(0.42, 0.64)
		var top := Vector3(cos(angle) * 0.07, height, sin(angle) * 0.07)
		var stem := PlaceholderModel._part(_model, PlaceholderModel._cylinder(0.008, height), stem_color, top * 0.5)
		stem.basis = Basis(Quaternion(Vector3.UP, top.normalized()))
		# the flower faces up and a little outward
		var face := (Vector3.UP * 2.0 + Vector3(cos(angle), 0, sin(angle))).normalized()
		_bloom(blooms, top, face, rng.randf_range(0.15, 0.2), Vector2(0.5 * (i % 2), 0.5))
	var flowers := MeshInstance3D.new()
	flowers.mesh = blooms.commit()
	flowers.material_override = _bloom_material(data.bloom_color)
	_model.add_child(flowers)


## One leaf card from the base outward at `angle`, `tilt` radians off vertical, its outer
## half drooping; `cell` is the atlas corner (stem at the bottom of the cell).
func _card(tool: SurfaceTool, angle: float, tilt: float, length: float, aspect: float, cell: Vector2, tint: Color, droop: bool) -> void:
	var out := Vector3(cos(angle), 0, sin(angle))
	var dir := (Vector3.UP * cos(tilt) + out * sin(tilt)).normalized()
	var tip_dir := (dir + (out * 0.6 + Vector3.DOWN * 0.5) * (1.0 if droop else 0.0)).normalized()
	var side := out.cross(Vector3.UP).normalized() * length * aspect * 0.5
	var spine: Array[Vector3] = [Vector3(0, 0.02, 0), dir * length * 0.5, dir * length * 0.5 + tip_dir * length * 0.5]
	var normal := side.cross(dir).normalized()
	if normal.y < 0.0:
		normal = -normal
	var rows: Array[int] = []
	for k in 3:
		var v := cell.y + 0.5 * (1.0 - k * 0.5)
		for s: float in [-1.0, 1.0]:
			tool.set_uv(Vector2(cell.x + (0.25 + s * 0.25), v))
			tool.set_uv2(Vector2(0.55 + 0.45 * k * 0.5, randf()))
			tool.set_color(tint)
			tool.set_normal(normal)
			tool.add_vertex(spine[k] + side * s)
	var base := _card_count
	for k in 2:
		var a := base + k * 2
		for index: int in [a, a + 1, a + 2, a + 1, a + 3, a + 2]:
			tool.add_index(index)
	_card_count += 6


## A flat bloom card centred on `at`, facing `face`.
func _bloom(tool: SurfaceTool, at: Vector3, face: Vector3, size: float, cell: Vector2) -> void:
	var right := face.cross(Vector3.FORWARD if absf(face.z) < 0.9 else Vector3.RIGHT).normalized() * size * 0.5
	var up := right.cross(face).normalized() * size * 0.5
	var base := _bloom_count
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		tool.set_uv(cell + (corner * 0.5 + Vector2(0.5, 0.5)) * 0.5)
		tool.set_normal(face)
		tool.add_vertex(at + right * corner.x + up * corner.y)
	for index: int in [0, 1, 2, 0, 2, 3]:
		tool.add_index(base + index)
	_bloom_count += 4


static func _bloom_material(color: Color) -> ShaderMaterial:
	if not _bloom_materials.has(color):
		var material := ShaderMaterial.new()
		material.shader = BLOOM_SHADER
		material.set_shader_parameter("atlas", ATLAS)
		material.set_shader_parameter("bloom_color", color)
		_bloom_materials[color] = material
	return _bloom_materials[color]
