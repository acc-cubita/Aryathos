class_name Zone
extends Node3D
## A playable zone: builds the terrain, decorates it, spawns creatures and places the player.
## Children only build themselves when the zone tells them to, so order is predictable.
## After the world is built, a navigation mesh is baked so creatures can path around obstacles.

@export var zone_name := "Unnamed Zone"
## How close the player must come to a point of interest to discover it.
@export var discover_radius := 20.0

@onready var terrain: Terrain = $Terrain
@onready var decorator: ZoneDecorator = $Decorator
@onready var player: Player = $Player
@onready var player_spawn: Marker3D = $PlayerSpawn
@onready var hud: Hud = $HUD


func _ready() -> void:
	terrain.generate()
	decorator.decorate(terrain)
	if has_node("Grass"):
		($Grass as GrassField).plant(terrain)
	if has_node("Props"):
		for group: PropGroup in $Props.get_children():
			group.build(terrain)
	if has_node("Wardstone"):
		_build_wardstone($Wardstone)
	for exit: Node3D in _children("Exits"):
		exit.global_position.y = terrain.get_height(exit.global_position.x, exit.global_position.z)
	_bake_navigation()
	add_child(CombatVfx.new())
	for spawner: EnemySpawner in _children("Spawners"):
		spawner.spawn(terrain, $Units)
	for spawner: GatherSpawner in _children("GatherSpawners"):
		spawner.spawn(terrain, $Units)
	if has_node("QuestObjectSpawners"):
		for spawner: QuestObjectSpawner in $QuestObjectSpawners.get_children():
			spawner.spawn(terrain, $Units)
	for npc: Npc in _children("NPCs"):
		var spot := npc.global_position
		npc.global_position = Vector3(spot.x, terrain.get_height(spot.x, spot.z) + 0.1, spot.z)
		npc.reset_physics_interpolation()
	var spawn := player_spawn.global_position
	spawn.y = terrain.get_height(spawn.x, spawn.z) + 0.1
	player.spawn_point = spawn
	player.teleport(spawn, player_spawn.rotation.y)
	var map_image := terrain.make_map_image()
	decorator.paint_map(map_image)
	Game.zone = self
	hud.setup(player, zone_name, ImageTexture.create_from_image(map_image))
	if Game.load_game():
		Game.chat("Welcome back, %s." % player.unit_name)
	elif not Game.testing:
		hud.open_character_creation()
	Game.zone_ready.emit()


## Checks a few times a second whether the player reached an undiscovered place.
func _process(_delta: float) -> void:
	if Engine.get_process_frames() % 15 != 0 or player.is_dead:
		return
	for place: Node3D in _children("PointsOfInterest"):
		if player.flat_distance(place.global_position) < discover_radius:
			player.discover(String(place.name))


## Puts the player at Arrivals/<arrival> (the way in from another zone), or at the
## zone's spawn when there is no such marker.
func arrive(arrival: String) -> void:
	var marker: Node3D = get_node_or_null("Arrivals/" + arrival) if arrival != "" else null
	if marker == null:
		marker = player_spawn
	var spot := marker.global_position
	spot.y = terrain.get_height(spot.x, spot.z) + 0.1
	player.teleport(spot, marker.rotation.y)


## The children of an optional group node (none if the zone has no such node).
func _children(group: String) -> Array[Node]:
	return get_node(group).get_children() if has_node(group) else []


## Bakes walkable ground from everything on the world collision layer
## (terrain, trees, rocks, buildings). Steep slopes are left out automatically.
func _bake_navigation() -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = 0.5
	nav_mesh.cell_height = 0.25
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_height = 2.0
	nav_mesh.agent_max_climb = 0.5
	nav_mesh.agent_max_slope = 45.0
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = Unit.LAYER_WORLD
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source, self)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	var region := NavigationRegion3D.new()
	region.name = "Navigation"
	region.navigation_mesh = nav_mesh
	add_child(region)


## The rune pillar at the heart of the camp: a landmark to find your way back.
func _build_wardstone(anchor: Node3D) -> void:
	var base := anchor.global_position
	anchor.global_position = Vector3(base.x, terrain.get_height(base.x, base.z), base.z)
	anchor.add_child(Props.wardstone())
