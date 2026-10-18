class_name NatureMeshes
extends RefCounted
## Procedural stylized meshes for the world: pines, broadleaf trees, bushes and boulders.
## Crowns store ambient occlusion in UV.x for foliage.gdshader (0 = dark, 1 = sunlit)
## and use rounded normals so they shade softly, like painted foliage.
## Trunks are UV-mapped for the bark texture (u around, v up; one repeat per 2 m).


## A pine about 8 m tall: [trunk, crown].
static func pine(seed_value: int) -> Array[Mesh]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var height := rng.randf_range(7.0, 9.0)
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(trunk, [Vector3(0, -0.3, 0), Vector3(0, height * 0.85, 0)], [0.32, 0.06], 7)
	var crown := SurfaceTool.new()
	crown.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tiers := rng.randi_range(5, 6)
	for k in tiers:
		var t := float(k) / (tiers - 1)
		var base := Vector3(rng.randf_range(-0.1, 0.1), lerpf(1.6, height - 2.1, t), rng.randf_range(-0.1, 0.1))
		_pine_tier(crown, rng, base, lerpf(2.4, 0.75, t) * rng.randf_range(0.9, 1.1), lerpf(2.6, 2.1, t), lerpf(0.72, 1.0, t))
	var meshes: Array[Mesh] = [trunk.commit(), crown.commit()]
	return meshes


## A round-crowned broadleaf tree about 6.5 m tall: [trunk with branches, crown].
static func broadleaf(seed_value: int) -> Array[Mesh]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := _noise(seed_value)
	var height := rng.randf_range(3.0, 3.7)
	var lean := Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35))
	var top := Vector3(lean.x, height, lean.z)
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(trunk, [Vector3(0, -0.3, 0), Vector3(0, 0.5, 0), lean * 0.4 + Vector3.UP * height * 0.55, top], [0.62, 0.38, 0.3, 0.2], 8)
	for b in 3:
		var angle := b * TAU / 3.0 + rng.randf_range(-0.5, 0.5)
		var start := lean * 0.6 + Vector3.UP * height * rng.randf_range(0.7, 0.92)
		var end := start + Vector3(cos(angle), 0.9, sin(angle)).normalized() * rng.randf_range(1.4, 1.9)
		_tube(trunk, [start, end], [0.13, 0.04], 5)
	var crown := SurfaceTool.new()
	crown.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := top + Vector3.UP * 1.4
	_blob(crown, noise, center, 2.0, center, 3.0)
	var blobs := rng.randi_range(5, 6)
	for b in blobs:
		var angle := b * TAU / blobs + rng.randf_range(-0.4, 0.4)
		var offset := Vector3(cos(angle), rng.randf_range(-0.35, 0.6), sin(angle)) * rng.randf_range(1.3, 1.7)
		_blob(crown, noise, center + offset, rng.randf_range(1.1, 1.5), center, 3.0)
	var meshes: Array[Mesh] = [trunk.commit(), crown.commit()]
	return meshes


## A low leafy bush about 1 m tall.
static func bush(seed_value: int) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := _noise(seed_value)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, 0.45, 0)
	for b in rng.randi_range(2, 3):
		var offset := Vector3(rng.randf_range(-0.45, 0.45), rng.randf_range(-0.05, 0.15), rng.randf_range(-0.45, 0.45))
		_blob(tool, noise, center + offset, rng.randf_range(0.5, 0.75), center, 1.0)
	return tool.commit()


## A lumpy, faceted boulder about 1 m across (like a unit SphereMesh) with a flat bottom.
static func boulder(seed_value: int) -> Mesh:
	var noise := _noise(seed_value)
	var sphere := SphereMesh.new()
	sphere.radial_segments = 9
	sphere.rings = 6
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, indices.size(), 3):
		var points: Array[Vector3] = []
		for k in 3:
			var v := vertices[indices[i + k]]
			var p := v * (1.0 + noise.get_noise_3dv(v * 1.6) * 0.45)
			p.y = maxf(p.y * 0.72, -0.25)
			points.append(p)
		# Flat shading: one normal per face gives the chiseled, hand-made look.
		var normal := (points[2] - points[0]).cross(points[1] - points[0]).normalized()
		if normal.dot(points[0] + points[1] + points[2]) < 0.0:
			normal = -normal
		for p in points:
			tool.set_normal(normal)
			tool.add_vertex(p)
	return tool.commit()


static func _noise(seed_value: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.9
	noise.fractal_octaves = 2
	return noise


## One drooping, star-shaped layer of pine branches.
static func _pine_tier(tool: SurfaceTool, rng: RandomNumberGenerator, base: Vector3, radius: float, height: float, light: float) -> void:
	var points := rng.randi_range(9, 11)
	var apex := base + Vector3.UP * height
	var under := base + Vector3.UP * height * 0.3
	var spin := rng.randf() * TAU
	var ring: Array[Vector3] = []
	var shade: Array[float] = []
	for i in points * 2:
		var angle := spin + i * PI / points
		var tip := i % 2 == 0
		var r := radius * (rng.randf_range(0.92, 1.08) if tip else 0.7)
		var y := -radius * 0.22 if tip else 0.12
		ring.append(base + Vector3(cos(angle) * r, y, sin(angle) * r))
		shade.append((0.95 if tip else 0.72) * light)
	for i in ring.size():
		var j := (i + 1) % ring.size()
		var up_a := _rounded(ring[i], base)
		var up_b := _rounded(ring[j], base)
		_triangle(tool, [apex, ring[i], ring[j]], [Vector3.UP, up_a, up_b], [light * 1.05, shade[i], shade[j]], Vector3.UP)
		_triangle(tool, [under, ring[j], ring[i]], [Vector3.DOWN, up_b, up_a], [light * 0.3, shade[j] * 0.6, shade[i] * 0.6], Vector3.DOWN)


## A noisy sphere of leaves. Normals point away from the whole crown so it shades as one.
static func _blob(tool: SurfaceTool, noise: FastNoiseLite, center: Vector3, radius: float, crown_center: Vector3, crown_size: float) -> void:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 12
	sphere.rings = 7
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		var v := vertices[index] / 0.5
		var p := center + v * radius * (1.0 + noise.get_noise_3dv(center + v * radius) * 0.22)
		var away := (p - crown_center).normalized()
		var normal := (away * 0.65 + normals[index] * 0.35).normalized()
		var height := clampf((p.y - crown_center.y + crown_size * 0.6) / (crown_size * 1.2), 0.0, 1.0)
		var outer := clampf((p - crown_center).length() / crown_size, 0.0, 1.0)
		tool.set_normal(normal)
		tool.set_uv(Vector2(lerpf(0.42, 1.05, height * 0.6 + outer * 0.4), 0.0))
		tool.add_vertex(p)


## A tapered tube along a path of points (trunks, branches).
static func _tube(tool: SurfaceTool, path: Array[Vector3], radii: Array[float], sides: int) -> void:
	var rings: Array[PackedVector3Array] = []
	var ring_normals: Array[PackedVector3Array] = []
	var heights: Array[float] = []
	var travelled := 0.0
	for k in path.size():
		var along := (path[mini(k + 1, path.size() - 1)] - path[maxi(k - 1, 0)]).normalized()
		var side := along.cross(Vector3.FORWARD if absf(along.z) < 0.9 else Vector3.RIGHT).normalized()
		var other := along.cross(side)
		if k > 0:
			travelled += path[k].distance_to(path[k - 1])
		heights.append(travelled)
		var ring := PackedVector3Array()
		var normals := PackedVector3Array()
		for s in sides + 1:
			var angle := s * TAU / sides
			var out := side * cos(angle) + other * sin(angle)
			ring.append(path[k] + out * radii[k])
			normals.append(out)
		rings.append(ring)
		ring_normals.append(normals)
	for k in path.size() - 1:
		for s in sides:
			var u0 := float(s) / sides * 2.0
			var u1 := float(s + 1) / sides * 2.0
			var v0 := heights[k] * 0.5
			var v1 := heights[k + 1] * 0.5
			var outward := ring_normals[k][s] + ring_normals[k][s + 1]
			_textured_triangle(tool, [rings[k][s], rings[k][s + 1], rings[k + 1][s]], [ring_normals[k][s], ring_normals[k][s + 1], ring_normals[k + 1][s]], [Vector2(u0, v0), Vector2(u1, v0), Vector2(u0, v1)], outward)
			_textured_triangle(tool, [rings[k][s + 1], rings[k + 1][s + 1], rings[k + 1][s]], [ring_normals[k][s + 1], ring_normals[k + 1][s + 1], ring_normals[k + 1][s]], [Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)], outward)


## Pushes a crown point's normal outward and up, for soft rounded shading.
static func _rounded(point: Vector3, axis_point: Vector3) -> Vector3:
	var out := Vector3(point.x - axis_point.x, 0.0, point.z - axis_point.z).normalized()
	return (out * 0.75 + Vector3.UP * 0.65).normalized()


## Adds a triangle facing `outward` (Godot draws clockwise triangles as front faces).
static func _triangle(tool: SurfaceTool, points: Array[Vector3], normals: Array[Vector3], shades: Array[float], outward: Vector3) -> void:
	var uvs: Array[Vector2] = [Vector2(shades[0], 0.0), Vector2(shades[1], 0.0), Vector2(shades[2], 0.0)]
	_textured_triangle(tool, points, normals, uvs, outward)


static func _textured_triangle(tool: SurfaceTool, points: Array[Vector3], normals: Array[Vector3], uvs: Array[Vector2], outward: Vector3) -> void:
	var order := [0, 1, 2]
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(outward) > 0.0:
		order = [0, 2, 1]
	for i: int in order:
		tool.set_normal(normals[i])
		tool.set_uv(uvs[i])
		tool.add_vertex(points[i])
