class_name GatherSpawner
extends Marker3D
## Scatters gatherable nodes (herbs) around this marker. Move it in the editor.

@export var node_data: GatherNodeData
@export var count := 5
@export var radius := 12.0


func spawn(terrain: Terrain, parent: Node) -> void:
	for i in count:
		var angle := randf() * TAU
		var distance := radius * sqrt(randf())
		var x := global_position.x + cos(angle) * distance
		var z := global_position.z + sin(angle) * distance
		var node := GatherNode.new()
		node.data = node_data
		parent.add_child(node)
		node.global_position = Vector3(x, terrain.get_height(x, z), z)
		node.rotation.y = randf() * TAU
