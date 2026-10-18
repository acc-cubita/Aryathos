class_name RockLibrary
extends RefCounted
## Scanned boulders and cliff faces made by tools/art/blender/rocks.py: each
## art/rocks/<set>.glb holds meshes piece_0, piece_1, ... and
## world/materials/rocks/<set>.tres draws them.

static var _cache := {}


## Every piece of a set, in order.
static func pieces(set_name: String) -> Array[Mesh]:
	if not _cache.has(set_name):
		var scene := (load("res://art/rocks/%s.glb" % set_name) as PackedScene).instantiate()
		var found := scene.find_children("piece_*", "MeshInstance3D", true, false)
		found.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
		var meshes: Array[Mesh] = []
		for node: MeshInstance3D in found:
			meshes.append(node.mesh)
		scene.free()
		_cache[set_name] = meshes
	return _cache[set_name]


static func material(set_name: String) -> Material:
	return load("res://world/materials/rocks/%s.tres" % set_name)
