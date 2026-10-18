class_name TreeLibrary
extends RefCounted
## Tree, pine and bush meshes made by tools/art/blender/trees.py: each
## art/trees/<kind>_<n>.glb holds a "trunk" and a "leaves" mesh.

static var _cache := {}


## [trunk, leaves] of one variant (either may be null if the model has none).
static func meshes(kind: String, variant: int) -> Array[Mesh]:
	var key := "%s_%d" % [kind, variant]
	if not _cache.has(key):
		var scene := (load("res://art/trees/%s.glb" % key) as PackedScene).instantiate()
		var parts: Array[Mesh] = [null, null]
		for node: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			parts[0 if String(node.name).begins_with("trunk") else 1] = node.mesh
		scene.free()
		_cache[key] = parts
	return _cache[key]
