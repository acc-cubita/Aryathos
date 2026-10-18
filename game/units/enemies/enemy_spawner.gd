class_name EnemySpawner
extends Marker3D
## Places a group of creatures around this marker.
## Move it in the editor to design where packs live.

@export var enemy_data: EnemyData
@export var count := 4
@export var radius := 10.0


func spawn(terrain: Terrain, parent: Node) -> void:
	for i in count:
		var angle := TAU * i / count + randf_range(-0.4, 0.4)
		var distance := radius * sqrt(randf_range(0.1, 1.0))
		var x := global_position.x + cos(angle) * distance
		var z := global_position.z + sin(angle) * distance
		var enemy := Enemy.new()
		enemy.data = enemy_data
		enemy.spawn_position = Vector3(x, terrain.get_height(x, z) + 0.1, z)
		parent.add_child(enemy)
		enemy.global_position = enemy.spawn_position
		enemy.rotation.y = randf() * TAU
		enemy.reset_physics_interpolation()
