class_name PlaceholderModel
extends RefCounted
## Builds simple primitive-shape models until real 3D art exists.
## Meshes go on render layer 2 ("units") so ground decals skip them.
## Models face -Z, Godot's forward direction.

enum Body { HUMANOID, BEAST }

const RENDER_LAYER := 2


static func build(body: Body, main: Color, glow: Color, size := 1.0) -> Node3D:
	var root := beast(main, glow) if body == Body.BEAST else humanoid(main, glow)
	root.scale = Vector3.ONE * size
	return root


## Collision body (radius, height) for a body type.
static func dimensions(body: Body, size: float) -> Vector2:
	return (Vector2(0.55, 1.25) if body == Body.BEAST else Vector2(0.45, 1.95)) * size


## A crystal-backed wolf. Its head is the "weapon" so attacks look like bites.
static func beast(fur: Color, glow: Color) -> Node3D:
	var root := PlaceholderAnimator.new()
	root.name = "Model"
	var dark := fur.darkened(0.3)
	_part(root, _box(0.55, 0.5, 1.2), fur, Vector3(0, 0.75, 0))
	_part(root, _box(0.1, 0.1, 0.5), dark, Vector3(0, 0.88, 0.78), Vector3(30, 0, 0))
	for i in 3:
		_part(root, _crystal(0.09, 0.45), glow, Vector3(0, 1.1, -0.3 + i * 0.3), Vector3(-20, 0, 0), 2.5)
	var head := Node3D.new()
	head.name = "Weapon"
	head.set_meta("swing", 0.5)
	head.position = Vector3(0, 0.95, -0.6)
	root.add_child(head)
	_part(head, _box(0.4, 0.38, 0.45), fur, Vector3(0, 0, -0.15))
	_part(head, _box(0.22, 0.18, 0.3), dark, Vector3(0, -0.07, -0.45))
	for side: float in [-1.0, 1.0]:
		_part(head, _sphere(0.035), glow, Vector3(0.1 * side, 0.05, -0.38), Vector3.ZERO, 3.0)
		_part(head, _crystal(0.06, 0.25), glow, Vector3(0.13 * side, 0.27, -0.05), Vector3(0, 0, -15 * side), 2.5)
		for z: float in [-0.42, 0.42]:
			_part(root, _box(0.14, 0.55, 0.14), dark, Vector3(0.18 * side, 0.28, z))
	return root


static func humanoid(armor: Color, glow: Color, skin := Color(0.86, 0.72, 0.6)) -> Node3D:
	var root := PlaceholderAnimator.new()
	root.name = "Model"
	var dark := armor.darkened(0.35)
	# Legs, belt, torso, cape
	_part(root, _box(0.22, 0.85, 0.25), dark, Vector3(-0.14, 0.425, 0))
	_part(root, _box(0.22, 0.85, 0.25), dark, Vector3(0.14, 0.425, 0))
	_part(root, _box(0.62, 0.12, 0.37), Color(0.35, 0.24, 0.14), Vector3(0, 0.9, 0))
	_part(root, _box(0.6, 0.66, 0.35), armor, Vector3(0, 1.25, 0))
	_part(root, _box(0.56, 1.0, 0.04), glow.darkened(0.55), Vector3(0, 1.05, 0.2))
	# Arms and shoulder pads with crystal spikes, like the concept art
	for side: float in [-1.0, 1.0]:
		_part(root, _box(0.16, 0.62, 0.18), dark, Vector3(0.4 * side, 1.15, 0))
		_part(root, _sphere(0.18), armor.lightened(0.15), Vector3(0.38 * side, 1.52, 0))
		_part(root, _crystal(0.06, 0.32), glow, Vector3(0.42 * side, 1.72, 0), Vector3(0, 0, -20 * side), 2.5)
	# Head with glowing eyes (they show which way the model faces)
	_part(root, _sphere(0.19), skin, Vector3(0, 1.76, 0))
	for side: float in [-1.0, 1.0]:
		_part(root, _sphere(0.035), glow, Vector3(0.07 * side, 1.79, -0.16), Vector3.ZERO, 3.0)
	# Chest rune crystal
	_part(root, _box(0.12, 0.12, 0.05), glow, Vector3(0, 1.32, -0.19), Vector3(0, 0, 45), 2.5)
	# Axe in the right hand
	var weapon := axe(glow)
	weapon.position = Vector3(0.42, 0.9, -0.08)
	root.add_child(weapon)
	return root


## Rune axe: handle along +Y (grip at the origin), blade toward -Z.
static func axe(glow: Color) -> Node3D:
	var weapon := Node3D.new()
	weapon.name = "Weapon"
	_part(weapon, _cylinder(0.03, 1.15), Color(0.35, 0.24, 0.14), Vector3(0, 0.25, 0))
	_part(weapon, _box(0.05, 0.34, 0.32), Color(0.75, 0.78, 0.82), Vector3(0, 0.7, -0.14))
	_part(weapon, _box(0.06, 0.1, 0.1), glow, Vector3(0, 0.7, -0.14), Vector3(45, 0, 0), 2.5)
	return weapon


static func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot_deg := Vector3.ZERO, glow := 0.0) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.position = pos
	mesh_instance.rotation_degrees = rot_deg
	mesh_instance.layers = RENDER_LAYER
	parent.add_child(mesh_instance)
	return mesh_instance


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(x, y, z)
	return mesh


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	return mesh


## A pointed shard: wide at the bottom, sharp at the top.
static func _crystal(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 5
	mesh.rings = 1
	return mesh
