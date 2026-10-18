extends Node
## Saves screenshots for visual checks. Run from the project folder:
##   Godot.exe --path game -- --screenshot=<output folder>


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var folder := "res://tests/output"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			folder = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(folder)
	if Game.zone == null:
		await Game.zone_ready
	await get_tree().create_timer(2.0).timeout
	await _shot(folder.path_join("camp.png"))
	Game.zone.hud._graphics.toggle()  # the graphics settings over the camp
	await _shot(folder.path_join("graphics.png"))
	Game.zone.hud._graphics.toggle()
	# Quest view: stand in front of Warden Thalos and talk to him.
	var thalos: Npc = Game.zone.get_node("NPCs/WardenThalos")
	Game.player.teleport(thalos.global_position + Vector3(0, 0.3, 4), 0.0)
	await get_tree().create_timer(0.6).timeout
	Game.player.interact_with(thalos)
	await get_tree().create_timer(0.3).timeout
	await _shot(folder.path_join("quest.png"))
	Game.player.quest_log.accept(Database.quest(&"wolves_at_the_wardstone"), thalos.npc_id)
	# Combat view: target the nearest wolf from 16 m and start casting.
	var player := Game.player
	var wolf: Enemy = null
	for node in get_tree().get_nodes_in_group("enemies"):
		if wolf == null or node.global_position.distance_to(player.global_position) < wolf.global_position.distance_to(player.global_position):
			wolf = node
	var away := (player.global_position - wolf.global_position).normalized()
	var spot := wolf.global_position + Vector3(away.x, 0.0, away.z).normalized() * 16.0
	spot.y = Game.zone.terrain.get_height(spot.x, spot.z) + 0.2
	player.teleport(spot, atan2(away.x, away.z))
	player.set_target(wolf)
	player.use_action_slot(2)
	await get_tree().create_timer(1.6).timeout
	player.use_action_slot(1)
	await get_tree().create_timer(0.9).timeout
	await _shot(folder.path_join("combat.png"))
	# Loot and bags: kill the wolf, open its loot, show the inventory window.
	wolf.take_damage(9999, player)
	wolf.loot_items.append(load("res://data/items/glowing_fang.tres"))
	wolf.loot_items.append(load("res://data/items/shardhide_gloves.tres"))
	for id in ["vale_runner_boots", "scavenger_cap", "matted_pelt", "stormcaller_axe"]:
		player.add_item(load("res://data/items/%s.tres" % id))
	player.equip_from_bag(0)
	player.teleport(wolf.global_position + Vector3(2.5, 0.3, 0), PI * 0.5)
	await get_tree().create_timer(0.5).timeout
	player.interact_with(wolf)
	Input.parse_input_event(_action("toggle_bags"))
	await get_tree().create_timer(0.3).timeout
	await _shot(folder.path_join("bags.png"))
	# Boss: face Grimjaw from 9 m and catch him casting Crystal Roar.
	Input.parse_input_event(_action("toggle_bags"))
	var boss: Enemy = get_tree().get_nodes_in_group("enemies").filter(func(e: Enemy) -> bool: return e.data.id == &"grimjaw")[0]
	var dir := Vector3(0, 0, 1)
	var boss_spot := boss.global_position + dir * 9.0
	boss_spot.y = Game.zone.terrain.get_height(boss_spot.x, boss_spot.z) + 0.3
	player.teleport(boss_spot, 0.0)
	player.set_target(boss)
	boss.engage(player)
	for i in 200:
		if boss.casting:
			break
		await get_tree().physics_frame
	await get_tree().create_timer(0.8).timeout
	await _shot(folder.path_join("boss.png"))
	# Windows: character, spellbook and bags open together, then the world map.
	player.teleport(player.spawn_point, 0.0)
	await get_tree().create_timer(0.5).timeout
	for action in ["toggle_character", "toggle_spellbook", "toggle_bags"]:
		Input.parse_input_event(_action(action))
	await get_tree().create_timer(0.5).timeout
	await _shot(folder.path_join("windows.png"))
	Input.parse_input_event(_action("clear_target"))
	Input.parse_input_event(_action("toggle_map"))
	await get_tree().create_timer(0.5).timeout
	await _shot(folder.path_join("map.png"))
	# Merchant: talk to Quartermaster Bren with some loot in the bags.
	Input.parse_input_event(_action("clear_target"))
	var bren: Npc = Game.zone.get_node("NPCs/QuartermasterBren")
	player.teleport(bren.global_position + Vector3(0, 0.3, 3.5), 0.0)
	player.money = 345
	for id in ["minor_healing_potion", "minor_healing_potion", "minor_healing_potion", "glowing_fang"]:
		player.add_item(load("res://data/items/%s.tres" % id))
	player.place_on_action_bar(load("res://data/items/minor_healing_potion.tres"), 5)
	await get_tree().create_timer(0.5).timeout
	player.interact_with(bren)
	await get_tree().create_timer(0.4).timeout
	await _shot(folder.path_join("merchant.png"))
	# Talents: level 6 with a few points spent.
	Input.parse_input_event(_action("clear_target"))
	while player.level < 6:
		player.gain_xp(Game.xp_to_next_level(player.level))
	for id in ["gathering_storm", "gathering_storm", "thunderous_strikes", "crystal_skin"]:
		player.learn_talent(player.talents.filter(func(t: TalentData) -> bool: return t.id == id)[0])
	await get_tree().create_timer(0.3).timeout
	Input.parse_input_event(_action("toggle_talents"))
	await get_tree().create_timer(0.4).timeout
	await _shot(folder.path_join("talents.png"))
	# Reputation: Friendly with the Watch, then Bren's goods with the faction items.
	Input.parse_input_event(_action("clear_target"))
	player.gain_reputation(Database.faction(&"wardstone_watch"), 650)
	player.gain_reputation(Database.faction(&"azure_concord"), 120)
	var quartermaster: Npc = Game.zone.get_node("NPCs/QuartermasterBren")
	player.teleport(quartermaster.global_position + Vector3(0, 0.3, 3.5), 0.0)
	await get_tree().create_timer(0.5).timeout
	player.interact_with(quartermaster)
	Input.parse_input_event(_action("toggle_reputation"))
	await get_tree().create_timer(0.4).timeout
	await _shot(folder.path_join("reputation.png"))
	# Achievements: discover a place (toast) and open the window.
	Input.parse_input_event(_action("clear_target"))
	player.discover("Silverrun Lake")
	Input.parse_input_event(_action("toggle_achievements"))
	await get_tree().create_timer(0.6).timeout
	await _shot(folder.path_join("achievements.png"))
	# Professions: stand next to a Silverleaf with both professions learned.
	Input.parse_input_event(_action("clear_target"))
	for id in [&"herbalism", &"alchemy"]:
		player.learn_profession(Database.profession(id))
	player.add_item(Database.item(&"silverleaf"), 3)
	player.add_item(Database.item(&"empty_vial"), 2)
	var herb: GatherNode = get_tree().get_nodes_in_group("gather_nodes")[0]
	var herb_spot := herb.global_position + Vector3(0, 0.3, 3.0)
	player.teleport(herb_spot, 0.0)
	await get_tree().create_timer(0.5).timeout
	Input.parse_input_event(_action("toggle_professions"))
	await get_tree().create_timer(0.4).timeout
	await _shot(folder.path_join("professions.png"))
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _action(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event
