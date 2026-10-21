extends Node
## Automated gameplay check. Run from the project folder:
##   Godot_console.exe --headless --path game -- --smoke-test
## Prints PASS/FAIL per check and exits with code 0 only if all pass.

var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.time_scale = 2.0
	if Game.zone == null:
		await Game.zone_ready
	var player := Game.player
	await _wait(1.0)
	# --only=travel,class: just those check groups (_<name>_checks; ones that stand on their own)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			for group in arg.get_slice("=", 1).split(","):
				var method := "_%s_checks" % group
				if get_method_argument_count(method) == 0:
					await call(method)
				else:
					await call(method, player)
			_finish()
			return
	_check(player.is_on_floor(), "player stands on the terrain")

	var start := player.global_position
	Input.action_press("move_forward")
	await _wait(1.0)
	Input.action_release("move_forward")
	var moved := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	_check(moved > 4.0, "W runs forward (%.1f m in 1 s)" % moved)

	var yaw := player.rotation.y
	Input.action_press("turn_left")
	await _wait(0.5)
	Input.action_release("turn_left")
	_check(player.rotation.y > yaw + 0.5, "A turns left")

	var ground_y := player.global_position.y
	_send_action("jump")
	await _wait(0.25)
	_check(player.global_position.y > ground_y + 0.8, "Space jumps")
	await _wait(1.5)
	_check(player.is_on_floor(), "player lands again")

	_send_action("autorun")
	start = player.global_position
	await _wait(1.0)
	_check(player.global_position.distance_to(start) > 4.0, "autorun moves without holding W")
	_send_action("autorun")

	var spot := player.global_position
	player.teleport(spot - Vector3.UP * 20.0, player.rotation.y)
	await _wait(0.2)
	_check(player.global_position.y > Game.zone.terrain.get_height(spot.x, spot.z) - 1.0, "a character stuck under the ground is put back on top")

	await _navigation_checks()
	await _combat_checks(player)
	await _quest_checks(player)
	await _loot_checks(player)
	await _boss_checks(player)
	await _interface_checks(player)
	await _creation_checks(player)
	_graphics_checks()
	await _merchant_checks(player)
	await _talent_checks(player)
	await _reputation_checks(player)
	await _achievement_checks(player)
	await _profession_checks(player)
	await _save_checks(player)
	await _class_checks(player)
	await _travel_checks(player)

	_finish()


func _finish() -> void:
	print("SMOKE TEST %s" % ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


## The second class (last: it remakes the hero): an Aethermancer made at character creation
## holds the crystal staff, has her class's abilities on the bar and her own talent trees,
## hits with Crystal Lance, learns Starshard from a talent and stays one through a save.
func _class_checks(player: Player) -> void:
	var mage := Database.hero_class(&"aethermancer")
	_check(Database.hero_classes().map(func(c: ClassData) -> StringName: return c.id) == [&"runeknight", &"aethermancer"],
			"two classes to choose, Runeknight first")
	var screen := CharacterCreation.new(player)
	add_child(screen)
	screen.hero_class = mage
	screen.look = {"gender": "female", "face": 1, "hair": 1, "hair_color": 0, "skin": 0, "eyes": 0, "beard": 0}
	_check(screen.create("Ilsa") == "" and player.hero_class == mage, "Create makes an Aethermancer")
	screen.queue_free()
	var wears := func(part: String) -> bool:
		return player.model.find_children("*", "MeshInstance3D", true, false).any(
				func(m: MeshInstance3D) -> bool: return m.visible and String(m.name).ends_with("_" + part))
	_check(wears.call("peasant") and not wears.call("ranger"), "she wears the Aethermancer's clothes, not the ranger's")
	var weapon: Node = player.model.find_child("Weapon", true, false)
	_check(player.equipment.get(ItemData.Slot.WEAPON).id == &"stormcaller_axe" and weapon != null
			and weapon.scene_file_path.ends_with("sword.glb"), "she keeps the better sword she wore (not the staff)")
	var axe_slot := player.bags.find(null)
	player.unequip(ItemData.Slot.WEAPON)
	_check(player.model.find_child("Weapon", true, false) == null, "with no weapon she has empty hands")
	player.equip_from_bag(axe_slot)
	player.bags[axe_slot] = Database.item(&"apprentice_crystal_staff")
	player.bag_counts[axe_slot] = 1
	player.equip_from_bag(axe_slot)
	weapon = player.model.find_child("Weapon", true, false)
	_check(weapon != null and weapon.scene_file_path.ends_with("crystal_staff.glb"), "equipping the crystal staff puts it in her hand")
	var bar := player.action_bar.slice(0, 4).map(func(entry: Resource) -> StringName: return entry.id if entry else &"")
	_check(bar == [&"aether_bolt", &"crystal_lance", &"shardburst", &"crystal_mending"]
			and not player.abilities.any(func(a: AbilityData) -> bool: return a.id == &"rune_strike"),
			"her bar holds Aether Bolt, Crystal Lance, Shardburst and Crystal Mending (no Rune Strike)")
	_check(player.talent_trees == ["Aether", "Crystal", "Warding"] and player.talent_points_free() == player.level - 1
			and player.max_mana > player.max_health, "Aether, Crystal and Warding trees, no talents yet, more mana than health")
	var talent_window: TalentWindow = Game.zone.hud._talents
	_check(talent_window._buttons.keys().any(func(t: TalentData) -> bool: return t.id == &"honed_lance")
			and not talent_window._buttons.keys().any(func(t: TalentData) -> bool: return t.id == &"rune_discipline"),
			"the talent window shows her trees, not the Runeknight's")
	var wolf := _nearest_enemy(player, &"shardfang_wolf")
	_place_facing(player, wolf, 14.0)
	await _wait(0.5)
	player.set_target(wolf)
	var before := wolf.health
	_check(player.use_action_slot(1), "Crystal Lance flies at once")
	await _wait_until(func() -> bool: return wolf.health < before, 4.0)
	_check(wolf.health < before, "the lance hits the wolf")
	player.level = maxi(player.level, 8)
	for id: StringName in [&"honed_lance", &"honed_lance", &"honed_lance", &"crystal_flow", &"crystal_flow", &"shatterpoint"]:
		player.learn_talent(player.talents.filter(func(t: TalentData) -> bool: return t.id == id)[0])
	var starshard: TalentData = player.talents.filter(func(t: TalentData) -> bool: return t.id == &"starshard_talent")[0]
	_check(player.learn_talent(starshard) and player.action_bar.any(func(entry: Resource) -> bool:
			return entry != null and entry.id == &"starshard"), "6 points in Crystal open Starshard, which goes on the bar")
	var saved := player.to_save_data()
	player.set_class(Database.hero_class(&"runeknight"))
	_check(player.hero_class.id == &"runeknight" and player.abilities.size() == 4 and player.talent_trees[1] == "Storm",
			"(a Runeknight again for the moment)")
	_check(not wears.call("peasant") and wears.call("ranger") and not wears.call("hood"),
			"a Runeknight wears the ranger's leathers (hood down)")
	player.load_save_data(saved)
	_check(saved["class"] == "aethermancer" and player.hero_class == mage
			and player.abilities.any(func(a: AbilityData) -> bool: return a.id == &"starshard")
			and player.talent_rank(starshard) == 1, "the save brings back the Aethermancer, her talents and Starshard")


## Zone travel (last: it changes the scene). The road east runs through a pass in the
## mountains; walking into its end saves the character, shows the loading screen and opens
## the Crystal Canyons with the hero at the way in from the vale; the way back leads home.
func _travel_checks(player: Player) -> void:
	var exit: ZoneExit = Game.zone.get_node("Exits/ToCrystalCanyons")
	var map := Game.zone.get_world_3d().navigation_map
	var from := Vector3(78, Game.zone.terrain.get_height(78, 4), 4)
	var path := NavigationServer3D.map_get_path(map, from, exit.global_position, true)
	_check(path.size() > 1 and path[-1].distance_to(exit.global_position) < 6.0, "a path runs from the Gloomshard Camp up the pass")
	var level := player.level
	var hero_class := player.hero_class
	player.teleport(exit.global_position + Vector3.UP * 0.5, 0.0)
	await Game.zone_ready
	var canyons := Game.zone
	var way_in: Node3D = canyons.get_node("Arrivals/FromSilverrunVale")
	_check(canyons.zone_name == "Crystal Canyons" and Game.player.flat_distance(way_in.global_position) < 2.0,
			"walking into the pass opens the Crystal Canyons, the hero at the way in")
	_check(Game.player.level == level and Game.player.hero_class == hero_class, "the hero comes along whole (level, class)")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	_check(saved is Dictionary and saved.get("zone") == "res://world/zones/crystal_canyons.tscn", "the save knows the zone")
	for frame in 3:  # (the zone's frame took seconds: count frames, not time)
		await get_tree().process_frame
	_check(not Game._loading.visible, "the loading screen is gone")
	var foes := {}
	for enemy: Enemy in get_tree().get_nodes_in_group("enemies"):
		foes[enemy.data.id] = foes.get(enemy.data.id, 0) + 1
	_check(foes.get(&"dust_coyote", 0) == 12 and foes.get(&"eclipse_zealot", 0) == 9,
			"dust coyotes run the canyons, Eclipse Zealots hold Duskreach Gorge")
	var thane: Npc = canyons.get_node("NPCs/ThaneDurgan")
	var smith: Npc = canyons.get_node("NPCs/HildeEmberhand")
	_check(thane.quests.has(Database.quest(&"dust_on_the_wind")) and thane.quests.has(Database.quest(&"the_robed_procession"))
			and smith.quests.has(Database.quest(&"hides_for_the_bellows")), "Thane Durgan and Hilde have work for the hero")
	Game.player.teleport(canyons.get_node("Exits/ToSilverrunVale").global_position + Vector3.UP * 0.5, 0.0)
	await Game.zone_ready
	var back: Node3D = Game.zone.get_node_or_null("Arrivals/FromCrystalCanyons")
	_check(Game.zone.zone_name == "Silverrun Vale" and back != null and Game.player.flat_distance(back.global_position) < 2.0,
			"and back to the vale's pass")


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_failures += 1


func _send_action(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _navigation_checks() -> void:
	var map := Game.player.get_world_3d().navigation_map
	_check(NavigationServer3D.map_get_regions(map).size() > 0, "navigation mesh baked")
	# Find a tree trunk out in the open and ask for a path straight through it.
	var terrain: Terrain = Game.zone.terrain
	var trunk: Vector3 = Vector3.INF
	for shape: CollisionShape3D in Game.zone.get_node("Decorator/PropColliders").get_children():
		var p := shape.global_position
		if shape.shape is CylinderShape3D and absf(p.x) < 100 and absf(p.z) < 100 and terrain.get_slope(p.x, p.z) < 0.1:
			trunk = p
			break
	var a := Vector3(trunk.x - 3.0, terrain.get_height(trunk.x - 3.0, trunk.z), trunk.z)
	var b := Vector3(trunk.x + 3.0, terrain.get_height(trunk.x + 3.0, trunk.z), trunk.z)
	var path := NavigationServer3D.map_get_path(map, a, b, true)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	_check(path.size() > 2 and length > 6.05 and path[-1].distance_to(b) < 1.0, "paths walk around a tree (%d points, %.1f m)" % [path.size(), length])


func _combat_checks(player: Player) -> void:
	_check(player.abilities.size() == 4, "4 abilities loaded from data files")
	var wolf := _nearest_enemy(player, &"shardfang_wolf")
	_check(wolf != null, "wolves spawned")
	_place_facing(player, wolf, 14.0)
	await _wait(0.5)
	player.set_target(wolf)
	_check(player.use_action_slot(1), "cast Aether Shard")
	# Re-cast if a slope or another wolf interrupted the first attempt.
	await _wait_until(func() -> bool:
		if player.casting == null and wolf.health == wolf.max_health:
			player.use_action_slot(1)
		return wolf.health < wolf.max_health, 8.0)
	_check(wolf.health < wolf.max_health, "missile hits the wolf")
	var weapon: Node = player.model.find_child("Weapon", true, false)
	_check(weapon.get_parent() == player.model._back_mount, "a spell leaves the axe on the back (WoW: weapons out to fight hand to hand)")
	_check(wolf.state == Enemy.State.CHASE, "wolf fights back")
	var t := 0.0
	while t < 40.0 and not wolf.is_dead and not player.is_dead:
		_face(player, wolf)
		if player.distance_to_unit(wolf) <= Unit.MELEE_RANGE:
			player.use_action_slot(0)
		elif player.casting == null and t > 10.0:  # (more spells only if it never comes to hand:
			player.use_action_slot(1)              # they could kill it before a swing draws the axe)
		await get_tree().physics_frame
		t += get_physics_process_delta_time() * Engine.time_scale
	_check(wolf.is_dead, "wolf killed (%.0f s)" % t)
	_check(weapon.get_parent() == player.model._hand_mount, "fighting hand to hand brought the axe out into the hand")
	# arms and body know each other's surface: held ready, no arm in the body
	var probe := ContactProbe.new()
	player.model._skeleton.add_child(probe)
	await _wait(0.8)
	probe.queue_free()
	_check(player.model._state == "ready_loop" and probe.deepest < 0.04,
			"standing ready, the arms stay out of the body (%.1f cm in)" % [probe.deepest * 100.0])
	_check(wolf.tapped_by == player, "kill credit goes to the player")
	var heard := get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false)
	_check(heard.is_empty() and Audio.played.keys().all(func(k: String) -> bool: return k.ends_with("music")),
			"the fight is silent: no sound effects, only music (%s)" % ", ".join(Audio.played.keys()))

	var healed := [false]
	Game.unit_healed.connect(func(unit: Unit, _s: Unit, _a: int, _c: bool) -> void: healed[0] = healed[0] or unit == player)
	player.set_target(null)
	await _wait(1.6)
	player.use_action_slot(3)
	await _wait(2.5)
	_check(healed[0], "Crystal Mending heals the player")

	var other := _nearest_enemy(player, &"gloomshard_scavenger")
	_place_facing(player, other, 25.0)
	await _wait(0.2)
	player.target_nearest_enemy()
	_check(player.target != null, "Tab selects an enemy in front")

	other.engage(player)
	var home := other.spawn_position
	player.teleport(Vector3(home.x - 90.0, Game.zone.terrain.get_height(home.x - 90.0, home.z) + 0.5, home.z), 0.0)
	await _wait_until(func() -> bool: return other.state == Enemy.State.IDLE, 30.0)
	_check(other.state == Enemy.State.IDLE and other.health == other.max_health, "enemy leashes home and resets (state %d, %.1f m from home, health %d/%d)" % [
			other.state, other.flat_distance(home), other.health, other.max_health])

	player.take_damage(99999, null)
	_check(player.is_dead, "player can die")
	player.release_spirit()
	_check(not player.is_dead and player.global_position.distance_to(player.spawn_point) < 1.0, "Release Spirit revives at the camp")


func _quest_checks(player: Player) -> void:
	_check(player.xp > 0, "killing a wolf gives XP")
	var thalos: Npc = Game.zone.get_node("NPCs/WardenThalos")
	var wolves := Database.quest(&"wolves_at_the_wardstone")
	var light := Database.quest(&"stolen_light")
	var quests := player.quest_log
	_check(quests.state(wolves) == QuestLog.State.AVAILABLE and quests.state(light) == QuestLog.State.UNAVAILABLE, "first quest offered, follow-up locked")
	var talked := [false]
	Game.npc_interacted.connect(func(npc: Npc) -> void: talked[0] = talked[0] or npc == thalos)
	player.teleport(thalos.global_position + Vector3(0, 0.3, 3), 0.0)
	await _wait(0.3)
	player.interact_with(thalos)
	_check(talked[0], "talking to Warden Thalos opens his dialog")

	quests.accept(wolves, thalos.npc_id)
	var level_before := player.level
	for enemy in _alive(&"shardfang_wolf"):
		if quests.state(wolves) == QuestLog.State.ACTIVE:
			enemy.take_damage(9999, player)
	_check(quests.state(wolves) == QuestLog.State.READY, "six wolf kills complete the objective")
	quests.turn_in(wolves)
	_check(quests.state(wolves) == QuestLog.State.DONE and player.level > level_before, "quest reward levels the player up (now level %d)" % player.level)
	_check(player.max_health > 140, "leveling raises max health (%d)" % player.max_health)

	quests.accept(light, thalos.npc_id)
	_check(quests.turn_ins_for(&"magister_ivren").has(light), "Stolen Light is handed in to Magister Ivren")
	for enemy in _alive(&"gloomshard_scavenger"):
		enemy.take_damage(9999, player)
	_check(quests.progress(light) > 0, "scavengers drop Stolen Aether Shards (%d)" % quests.progress(light))
	await _new_quest_checks(player)


## The other kinds of objectives: talk, explore, gather, craft and quest objects.
func _new_quest_checks(player: Player) -> void:
	var quests := player.quest_log
	var supplies := Database.quest(&"concord_supplies")
	quests.accept(supplies, &"thalos")
	_check(quests.state(supplies) == QuestLog.State.READY and quests.turn_ins_for(&"quartermaster_bren").has(supplies),
			"Concord Supplies is ready at once and handed in to Quartermaster Bren")
	quests.turn_in(supplies)

	var eyes := Database.quest(&"eyes_on_the_vale")
	quests.accept(eyes, &"thalos")
	var before := quests.progress(eyes)
	for place: String in eyes.places:
		player.place_discovered.emit(place)  # (discovering for real would spoil the exploration checks)
	_check(quests.state(eyes) == QuestLog.State.READY, "Eyes on the Vale: finding the places completes it (%d found before)" % before)

	var silverleaf := Database.quest(&"silverleaf_for_the_wounded")
	quests.accept(silverleaf, &"herbalist_mira")
	player.gathered.emit(silverleaf.item, 3)
	_check(quests.progress(silverleaf) == 3, "gathering Silverleaf counts for Silverleaf for the Wounded")
	player.gathered.emit(silverleaf.item, 4)
	_check(quests.state(silverleaf) == QuestLog.State.READY, "... and completes it")
	quests.turn_in(silverleaf)
	var brew := Database.quest(&"a_healers_brew")
	quests.accept(brew, &"herbalist_mira")
	player.crafted.emit(brew.item, 3)
	_check(quests.state(brew) == QuestLog.State.READY and quests.turn_ins_for(&"thalos").has(brew), "brewing potions completes A Healer's Brew, handed in to Thalos")

	_check(quests.state(Database.quest(&"cut_to_feed")) == QuestLog.State.UNAVAILABLE, "Cut to Feed waits for Stolen Light")


## The Eclipse Hand: acolytes cast Eclipse Bolts, the sigil behind the den, three quests.
func _eclipse_checks(player: Player) -> void:
	var acolytes := _alive(&"eclipse_acolyte")
	_check(acolytes.size() == 6, "six Eclipse Hand Acolytes stand by the Shardmaw Den (%d)" % acolytes.size())
	var acolyte: Enemy = acolytes[0]
	_place_facing(player, acolyte, 18.0)
	await _wait(0.3)
	acolyte.engage(player)
	await _wait_until(func() -> bool: return acolyte.casting != null, 3.0)
	_check(acolyte.casting != null and acolyte.casting.id == &"eclipse_bolt", "an acolyte casts Eclipse Bolt from range")
	var sigils := get_tree().get_nodes_in_group("quest_objects").filter(func(o: QuestObject) -> bool: return o.object_id == &"eclipse_sigil")
	_check(sigils.size() == 1, "the Eclipse Sigil waits behind the den")
	var quests := player.quest_log
	var sigil_quest := Database.quest(&"the_sigil_in_the_den")
	_check(sigil_quest.requires == Database.quest(&"the_shardmaw") and Database.quest(&"a_name_in_the_dark").turn_in_npc == &"thalos",
			"the Eclipse quests follow The Shardmaw and end with Warden Thalos")
	_check(not quests.wants_object(&"eclipse_sigil"), "the sigil cannot be examined before the quest")


## Cut to Feed (after Stolen Light is handed in): smashing Gloomshard Caches.
func _cache_checks(player: Player) -> void:
	var quests := player.quest_log
	var caches := get_tree().get_nodes_in_group("quest_objects").filter(func(o: QuestObject) -> bool: return o.object_id == &"gloomshard_cache")
	_check(caches.size() >= 4, "Gloomshard Caches stand at the dig site (%d)" % caches.size())
	var cut := Database.quest(&"cut_to_feed")
	quests.accept(cut, &"magister_ivren")
	_check(quests.wants_object(&"gloomshard_cache"), "with Cut to Feed taken the caches can be smashed")
	var cache: QuestObject = caches[0]
	var beside := cache.global_position + Vector3(1.2, 0, 0)
	player.teleport(Vector3(beside.x, Game.zone.terrain.get_height(beside.x, beside.z) + 0.3, beside.z), 0.0)
	await _wait_until(func() -> bool: return player.is_on_floor() and not player.is_moving, 3.0)
	_check(player.use_quest_object(cache), "right-clicking a cache starts smashing it")
	# a scavenger at the dig site may break off the smashing with a blow: start again
	await _wait_until(func() -> bool:
		if player.activity == "" and cache.available and quests.progress(cut) == 0:
			player.use_quest_object(cache)
		return quests.progress(cut) == 1, 15.0)
	_check(quests.progress(cut) == 1 and not cache.available, "a smashed cache counts and is gone")


func _loot_checks(player: Player) -> void:
	var boots: ItemData = load("res://data/items/vale_runner_boots.tres")
	_check(player.equipment.get(ItemData.Slot.WEAPON) != null, "player starts with a weapon equipped")
	_check(player.bags.has(boots), "quest reward item arrives in the bags")
	var health_before := player.max_health
	player.equip_from_bag(player.bags.find(boots))
	_check(player.max_health == health_before + 10, "equipping boots adds their health (+10)")
	player.unequip(ItemData.Slot.FEET)
	_check(player.max_health == health_before, "unequipping removes it again")

	var wolf: Enemy = _alive(&"shardfang_wolf")[0]
	player.teleport(wolf.global_position + Vector3(2, 0.3, 0), 0.0)
	await _wait(0.3)
	wolf.take_damage(9999, player)
	_check(wolf.loot_money >= wolf.data.money_min and wolf.has_loot(), "corpse holds money (%s)" % Game.format_money(wolf.loot_money))
	var opened := [false]
	Game.loot_opened.connect(func(_corpse: Enemy) -> void: opened[0] = true)
	var money_before := player.money
	var free_before := player.bags.count(null)
	var drops := wolf.loot_items.size()
	player.interact_with(wolf)
	_check(player.money > money_before, "looting takes the money")
	_check(opened[0] == (drops > 0), "loot window opens when items dropped (%d items)" % drops)
	for i in drops:
		player.take_loot(wolf, 0)
	_check(player.bags.count(null) == free_before - drops and not wolf.has_loot(), "taking the items empties the corpse")


func _boss_checks(player: Player) -> void:
	var minimap := get_tree().get_first_node_in_group("minimap") as Minimap
	_check(minimap != null and minimap.is_visible_in_tree(), "minimap is on screen")

	var boss: Enemy = _alive(&"grimjaw")[0] if not _alive(&"grimjaw").is_empty() else null
	_check(boss != null and boss.is_elite and boss.level == 4, "Grimjaw the Shardmaw spawned as a level 4 elite")
	_place_facing(player, boss, 6.0)
	await _wait(0.4)
	boss.engage(player)
	await _wait_until(func() -> bool: return boss.casting != null, 20.0)
	_check(boss.casting != null and boss.casting.id == &"crystal_roar", "boss casts Crystal Roar")
	_check(Audio.played.has("music"), "zone music is playing")
	# Step out of range: the roar must fail.
	var away := (player.global_position - boss.global_position).normalized()
	player.teleport(player.global_position + Vector3(away.x, 0, away.z) * 15.0 + Vector3.UP * 0.5, player.rotation.y)
	await _wait_until(func() -> bool: return boss.casting == null, 3.0)
	_check(boss.cooldown_left(boss.data.abilities[1]) == 0.0, "Crystal Roar fizzles when you step out of range")
	await _wait_until(func() -> bool: return Audio.played.has("boss_music"), 2.0)
	_check(Audio.played.has("boss_music"), "Grimjaw's fight brings in his music")
	await _eclipse_checks(player)

	var quests := player.quest_log
	var ivren: Npc = Game.zone.get_node("NPCs/MagisterIvren")
	var light := Database.quest(&"stolen_light")
	var shardmaw := Database.quest(&"the_shardmaw")
	quests.active.filter(func(e: Dictionary) -> bool: return e["quest"] == light)[0]["count"] = light.required
	_check(ivren.quest_marker_text() == "?", "Magister Ivren shows a yellow ? for Stolen Light")
	quests.turn_in(light)
	_check(quests.state(shardmaw) == QuestLog.State.AVAILABLE and ivren.quest_marker_text() == "!", "The Shardmaw unlocks at Magister Ivren")
	await _cache_checks(player)
	quests.accept(shardmaw, ivren.npc_id)
	boss.take_damage(99999, player)
	_check(quests.state(shardmaw) == QuestLog.State.READY, "killing Grimjaw completes The Shardmaw")
	_check(boss.loot_items.has(load("res://data/items/shardmaw_hide.tres")), "Grimjaw always drops Shardmaw Hide Armor")
	_check(quests.turn_ins_for(&"thalos").has(shardmaw), "The Shardmaw is handed in to Warden Thalos")


## Graphics settings: a preset sets the zone's sun, sky light and grass; one change by hand
## makes it Custom; they are kept.
func _graphics_checks() -> void:
	var environment: Environment = Game.zone.get_node("WorldEnvironment").environment
	var sun: DirectionalLight3D = Game.zone.get_node("Sun")
	var grass: GrassField = Game.zone.get_node("Grass")
	_check(Graphics.preset_name() == "High" and environment.ssil_enabled and sun.directional_shadow_max_distance == 140.0
			and grass.radius == 30.0, "the game starts on High graphics (bounce light, 140 m shadows, 30 m grass)")
	Graphics.use_preset("Low")
	_check(not environment.ssao_enabled and sun.directional_shadow_max_distance == 60.0 and grass.radius == 18.0
			and get_viewport().screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA
			and is_equal_approx(get_viewport().scaling_3d_scale, 0.8),
			"Low: no ambient occlusion, 60 m shadows, 18 m grass, FXAA, 80% render scale")
	Graphics.set_setting("grass", 0)
	_check(not grass.visible and Graphics.preset_name() == "Custom", "grass can be turned off (the preset is then Custom)")
	Graphics.use_preset("High")
	_check(grass.visible and grass.radius == 30.0 and environment.ssil_enabled and get_viewport().msaa_3d == Viewport.MSAA_4X
			and is_equal_approx(get_viewport().scaling_3d_scale, 1.0), "High brings it all back")
	var saved := ConfigFile.new()
	saved.load("user://settings_test.cfg")
	_check(saved.get_value("graphics", "grass", -1) == 2 and saved.get_value("graphics", "shadows", -1) == 3,
			"graphics settings are kept")


## Character creation: the look and name a new hero is given, and heroes show one hair style.
func _creation_checks(player: Player) -> void:
	var mira: Npc = Game.zone.get_node("NPCs/HerbalistMira")
	var hairs := func(model: Node) -> Array:
		return model.find_children("*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D) -> bool:
			return m.visible and ["_buns", "_long", "_simpleparted", "_buzzed", "_buzzedfemale"].any(
					func(end: String) -> bool: return String(m.name).ends_with(end)))
	_check(hairs.call(mira.model).size() == 1, "Herbalist Mira shows one hair style, not all of them")
	var old_name := player.unit_name
	var screen := CharacterCreation.new(player)
	add_child(screen)
	screen.look = {"gender": "female", "face": 0, "hair": 2, "hair_color": 2, "skin": 1, "eyes": 5, "beard": 0}
	_check(screen.create("x") != "" and screen.create("Ly ra") != "", "names that are too short or not letters are refused")
	_check(screen.create("seraphine") == "" and player.unit_name == "Seraphine" and player.look.gender == "female",
			"Create names the hero (Seraphine) and gives her the chosen look")
	var shown: Array = hairs.call(player.model)
	_check(shown.size() == 1 and String(shown[0].name).ends_with("_buzzedfemale"), "her chosen short hair is the only one showing")
	var body: MeshInstance3D = player.model.find_children("hero_female", "MeshInstance3D", true, false)[0]
	var eyes: StandardMaterial3D
	for surface in body.mesh.get_surface_count():
		var material := body.get_surface_override_material(surface) as StandardMaterial3D
		if material.resource_name.begins_with("eyes"):
			eyes = material
	_check(eyes != null and eyes.albedo_texture.resource_path.ends_with("/green.png"), "her eyes are the green she chose")
	_check(not get_tree().paused, "the game goes on after Create")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	_check(saved is Dictionary and saved.get("name") == "Seraphine" and (saved.get("look") as Dictionary).get("hair") == 2,
			"the new hero is saved with her name and look")
	player.set_look({"gender": "male", "beard": 1})
	var beards := player.model.find_children("*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D) -> bool:
		return m.visible and "beard" in String(m.name))
	_check(beards.is_empty(), "a male hero chosen beardless wears no beard")
	player.set_look({"gender": "male", "beard": 0})
	beards = player.model.find_children("*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D) -> bool:
		return m.visible and "beard" in String(m.name))
	_check(beards.size() == 1 and String(beards[0].name).ends_with("_beard"), "and with the beard, the one beard")
	player.set_look(CharacterModel.DEFAULT_LOOK)
	player.unit_name = old_name
	screen.queue_free()


func _interface_checks(player: Player) -> void:
	var windows := {}
	for node in get_tree().get_nodes_in_group("game_windows"):
		windows[(node as GameWindow).get_script().get_global_name()] = node
	var keys := {"toggle_bags": "BagWindow", "toggle_character": "CharacterWindow",
		"toggle_spellbook": "SpellbookWindow", "toggle_quest_log": "QuestLogWindow", "toggle_map": "WorldMapWindow"}
	for action: String in keys:
		_send_action(action)
		await _wait(0.25)  # (a slow frame now and then)
		_check(windows[keys[action]].visible, "%s opens the %s" % [Keybinds.label_for(action), keys[action]])
	var character: GameWindow = windows["CharacterWindow"]
	var spellbook: GameWindow = windows["SpellbookWindow"]
	await get_tree().process_frame
	_check(spellbook.position.x > character.position.x + 100, "left-side windows line up next to each other")

	var target := _alive(&"shardfang_wolf")[0]
	player.set_target(target)
	_send_action("clear_target")
	await _wait(0.1)
	var any_open := windows.values().any(func(w: GameWindow) -> bool: return w.visible)
	_check(not any_open and player.target == target, "Esc closes the windows first and keeps the target")

	var surge := player.abilities[2]
	player.place_on_action_bar(surge, 9)
	_check(player.action_bar[9] == surge, "a spell can be placed on button 10")
	player.place_on_action_bar(player.abilities[0], 9, 0)
	_check(player.action_bar[0] == surge and player.action_bar[9] == player.abilities[0], "dragging between buttons swaps them")

	var shardmaw := Database.quest(&"the_shardmaw")
	player.quest_log.abandon(shardmaw)
	_check(player.quest_log.state(shardmaw) == QuestLog.State.AVAILABLE, "an abandoned quest can be picked up again")
	_check(Keybinds.describe("toggle_ui") == "Alt+Z" and Keybinds.label_for("action_11") == "-", "Alt+Z and - / = keys are bound")


func _merchant_checks(player: Player) -> void:
	var heal: ItemData = load("res://data/items/minor_healing_potion.tres")
	var mana_potion: ItemData = load("res://data/items/minor_mana_potion.tres")
	var bren: Npc = Game.zone.get_node("NPCs/QuartermasterBren")
	var merchant: MerchantWindow = get_tree().get_nodes_in_group("game_windows").filter(func(w: Node) -> bool: return w is MerchantWindow)[0]
	var bags: BagWindow = get_tree().get_nodes_in_group("game_windows").filter(func(w: Node) -> bool: return w is BagWindow)[0]
	player.teleport(bren.global_position + Vector3(0, 0.3, 3), 0.0)
	await _wait(0.3)
	player.interact_with(bren)
	await _wait(0.1)
	_check(merchant.is_trading() and bags.visible, "talking to Quartermaster Bren opens his goods and your bags")

	player.money = 100
	var potions_before := player.count_item(heal)
	var bought := player.buy(heal) and player.buy(heal)
	_check(bought and player.money == 50 and player.count_item(heal) == potions_before + 2 and player.bags.count(heal) == 1, "two potions bought for 50c stack in one slot")
	player.add_item(load("res://data/items/matted_pelt.tres"))
	var money_before := player.money
	merchant._sell_junk()
	var junk_left := player.bags.any(func(item: ItemData) -> bool: return item != null and item.quality == ItemData.Quality.POOR)
	_check(not junk_left and player.money > money_before, "Sell All Junk sells every gray item (+%s)" % Game.format_money(player.money - money_before))

	player.buy(mana_potion)
	player.place_on_action_bar(mana_potion, 6)
	player.mana = 0
	_check(player.use_action_slot(6) and player.mana == 80, "a mana potion on the action bar restores 80 mana")
	_check(not player.use_item(heal), "potions share one cooldown")
	money_before = player.money
	var stack := player.count_item(heal)
	player.sell_bag_slot(player.bags.find(heal))
	_check(player.money == money_before + 6 * stack and player.count_item(heal) == 0, "selling a stack pays for every potion in it (%d)" % stack)


func _talent_checks(player: Player) -> void:
	var by_id := {}
	for talent in player.talents:
		by_id[talent.id] = talent
	_check(player.talents.size() == 13 and player.talent_trees.size() == 3, "13 talents in 3 trees loaded")
	player.reset_talents()
	while player.level < 8:
		player.gain_xp(Game.xp_to_next_level(player.level))
	_check(player.talent_points_free() == 7, "level 8 gives 7 talent points")

	var health_before := player.max_health
	player.learn_talent(by_id[&"crystal_skin"])
	_check(player.max_health == roundi(health_before * 1.04), "Crystal Skin adds 4%% health (%d -> %d)" % [health_before, player.max_health])
	_check(not player.learn_talent(by_id[&"thunderous_strikes"]), "row 2 stays locked until 3 points are in the tree")
	player.reset_talents()
	_check(player.max_health == health_before and player.talent_points_free() == 7, "Reset Talents gives every point back")

	var surge: AbilityData = player.abilities[2]
	for i in 3:
		player.learn_talent(by_id[&"gathering_storm"])
	_check(is_equal_approx(player.ability_cooldown(surge), surge.cooldown - 3.0), "Gathering Storm 3/3 cuts Storm Surge cooldown by 3 sec")
	for i in 3:
		player.learn_talent(by_id[&"thunderous_strikes"])
	var nova_talent: TalentData = by_id[&"storm_nova_talent"]
	_check(player.learn_talent(nova_talent) and player.abilities.has(nova_talent.ability) and player.action_bar.has(nova_talent.ability), "Storm Nova is learned and placed on the action bar")

	# Two fresh wolves at the camp, one on each side of the player.
	var spot := player.spawn_point
	var near: Array[Enemy] = []
	for offset: Vector3 in [Vector3(2.5, 0, 0), Vector3(-2.5, 0, 0)]:
		var wolf := Enemy.new()
		wolf.data = load("res://data/enemies/shardfang_wolf.tres")
		wolf.spawn_position = spot + offset
		Game.zone.get_node("Units").add_child(wolf)
		wolf.global_position = wolf.spawn_position
		near.append(wolf)
	player.teleport(spot + Vector3.UP * 0.3, 0.0)
	await _wait(0.6)
	player.mana = player.max_mana
	player.use_ability(nova_talent.ability)
	_check(near.all(func(w: Enemy) -> bool: return w.health < w.max_health or w.is_dead), "Storm Nova hits every enemy around you")
	for wolf in near:
		wolf.queue_free()
	player.reset_talents()
	_check(not player.abilities.has(nova_talent.ability) and not player.action_bar.has(nova_talent.ability), "resetting removes Storm Nova again")


func _reputation_checks(player: Player) -> void:
	var watch := Database.faction(&"wardstone_watch")
	_check(watch != null and Database.factions().size() == 2, "2 factions loaded")
	_check(player.reputation_with(watch) >= 350, "quests and kills gave Wardstone Watch reputation (%d)" % player.reputation_with(watch))
	var scavenger: Enemy = get_tree().get_nodes_in_group("enemies").filter(func(e: Enemy) -> bool: return e.data.id == &"gloomshard_scavenger")[0]
	var before := player.reputation_with(watch)
	player.on_enemy_killed(scavenger)
	_check(player.reputation_with(watch) == before + 10, "killing a Gloomshard Scavenger gives +10 reputation")

	var bren: Npc = Game.zone.get_node("NPCs/QuartermasterBren")
	var mantle: ItemData = Database.item(&"watchkeeper_mantle")
	var heal: ItemData = Database.item(&"minor_healing_potion")
	player.reputation[watch.id] = 0
	player.money = 1000
	_check(not player.buy(mantle, bren) and player.price_for(heal, bren) == 25, "at Neutral: no mantle and full price")
	player.gain_reputation(watch, 500)
	_check(player.standing_with(watch) == FactionData.Standing.FRIENDLY, "500 reputation makes you Friendly")
	_check(player.price_for(heal, bren) == 24 and player.price_for(mantle, bren) == 190, "Friendly gives 5% off at Bren")
	_check(player.buy(mantle, bren) and player.money == 810, "Friendly unlocks the Watchkeeper's Mantle")
	_check(not player.buy(Database.item(&"wardstone_signet"), bren), "the Signet still needs Honored")


func _achievement_checks(player: Player) -> void:
	var tracker := player.achievements
	var by_id := {}
	for achievement in tracker.all():
		by_id[achievement.id] = achievement
	_check(tracker.all().size() == 18, "18 achievements loaded")
	_check(player.discovered.has("Wardstone Post"), "the camp is discovered on arrival")
	for id: StringName in [&"first_steps", &"a_lesson_learned", &"shardmaw_slayer", &"friend_of_the_watch", &"adventurer"]:
		_check(tracker.is_earned(by_id[id]), "earned during the run: %s" % by_id[id].display_name)
	_check(tracker.stat("kill:shardfang_wolf") > 0 and tracker.stat("deaths") >= 1, "statistics count kills and deaths")

	var toasts := [0]
	tracker.earned.connect(func(_a: AchievementData) -> void: toasts[0] += 1)
	var xp_before := player.xp
	var level_before := player.level
	for place: Node3D in Game.zone.get_node("PointsOfInterest").get_children():
		if not player.discovered.has(String(place.name)):
			player.teleport(place.global_position + Vector3.UP * 30.0, 0.0)
			await _wait_until(func() -> bool: return player.discovered.has(String(place.name)), 4.0)
	_check(player.discovered.size() == 6, "all 6 places discovered (%d)" % player.discovered.size())
	_check(player.xp != xp_before or player.level > level_before, "discovering places gives experience")
	_check(tracker.is_earned(by_id[&"explore_silverrun_vale"]) and toasts[0] >= 1, "Explore Silverrun Vale is earned with a toast")
	var expected := 0
	for achievement in tracker.all():
		if tracker.is_earned(achievement):
			expected += achievement.points
	_check(tracker.points() == expected and expected > 0, "achievement points add up (%d)" % expected)
	player.teleport(player.spawn_point, 0.0)


func _profession_checks(player: Player) -> void:
	var herbalism := Database.profession(&"herbalism")
	var alchemy := Database.profession(&"alchemy")
	var mira: Npc = Game.zone.get_node("NPCs/HerbalistMira")
	_check(not player.knows_profession(herbalism) and not player.knows_profession(alchemy), "no professions at the start")
	var herbs := get_tree().get_nodes_in_group("gather_nodes")
	_check(herbs.size() == 27, "27 herbs grow around the vale")
	player.teleport(mira.global_position + Vector3(0, 0.3, 3), 0.0)
	await _wait(0.3)
	var talked := [false]
	Game.npc_interacted.connect(func(npc: Npc) -> void: talked[0] = talked[0] or npc == mira)
	player.interact_with(mira)
	player.learn_profession(herbalism)
	player.learn_profession(alchemy)
	_check(talked[0] and player.profession_skill(herbalism) == 1 and player.profession_skill(alchemy) == 1, "Herbalist Mira teaches Herbalism and Alchemy")

	# Fresh herbs at the camp, so no wandering wolf can interrupt the test.
	var silverleaf := _plant(&"silverleaf", player.spawn_point + Vector3(1.5, 0, 0))
	var stormbloom := _plant(&"stormbloom", player.spawn_point + Vector3(-1.5, 0, 0))
	player.teleport(player.spawn_point + Vector3.UP * 0.3, 0.0)
	await _wait(0.5)
	var leaf_item: ItemData = silverleaf.data.item
	var leaves_before := player.count_item(leaf_item)
	_check(player.gather(silverleaf), "gathering starts a cast bar")
	await _wait(1.8)
	_check(player.count_item(leaf_item) > leaves_before and not silverleaf.available, "gathering gives Silverleaf and the plant disappears")
	_check(player.profession_skill(herbalism) == 2, "an orange herb always raises Herbalism (now 2)")
	_check(not player.gather(stormbloom), "Stormbloom needs Herbalism 30")

	var second := _plant(&"silverleaf", player.spawn_point + Vector3(0, 0, 1.5))
	player.gather(second)
	Input.action_press("move_forward")
	await _wait(0.3)
	Input.action_release("move_forward")
	_check(player.activity == "" and second.available, "moving cancels gathering")

	var recipe := Database.recipe(&"minor_healing_potion")
	var potion: ItemData = recipe.product
	player.money = 100
	player.buy(Database.item(&"empty_vial"))
	player.teleport(player.spawn_point + Vector3.UP * 0.3, 0.0)
	await _wait_until(func() -> bool: return player.is_on_floor() and not player.is_moving, 3.0)
	var potions_before := player.count_item(potion)
	_check(player.craft(recipe), "crafting starts a cast bar")
	await _wait_until(func() -> bool:
		if player.activity == "" and player.count_item(potion) == potions_before:
			player.craft(recipe)  # a blow from something that followed the hero broke it off: again
		return player.count_item(potion) > potions_before, 15.0)
	_check(player.count_item(potion) == potions_before + 1 and player.profession_skill(alchemy) == 2, "Alchemy turns Silverleaf + Empty Vial into a potion and raises the skill")
	_check(player.craft_block_reason(Database.recipe(&"lesser_healing_potion")) != "", "Lesser Healing Potion needs Alchemy 40")
	for node in [silverleaf, stormbloom, second]:
		node.queue_free()


func _plant(id: StringName, at: Vector3) -> GatherNode:
	var node := GatherNode.new()
	node.data = Database.gather_nodes().filter(func(d: GatherNodeData) -> bool: return d.id == id)[0]
	Game.zone.get_node("Units").add_child(node)
	node.global_position = Vector3(at.x, Game.zone.terrain.get_height(at.x, at.z), at.z)
	return node


func _save_checks(player: Player) -> void:
	_check(Game.save_path.ends_with("test.json"), "tests use their own save file")
	var axe: ItemData = load("res://data/items/stormcaller_axe.tres")
	player.money = 4321
	player.add_item(axe)
	player.equip_from_bag(player.bags.find(axe))
	player.add_item(load("res://data/items/minor_healing_potion.tres"), 7)
	player.place_on_action_bar(load("res://data/items/minor_healing_potion.tres"), 8)
	player.learn_talent(player.talents[0])
	player.learn_talent(player.talents[9])
	var snapshot := JSON.stringify(player.to_save_data(), "", false, true)
	_check(Game.save_game() and FileAccess.file_exists(Game.save_path), "the game saves to disk")

	# Scramble the character, then load.
	player.money = 0
	player.reset_talents()
	player.unequip(ItemData.Slot.WEAPON)
	player.action_bar[8] = null
	player.quest_log.load_save_data({})
	player.level = 1
	player.teleport(player.spawn_point, 0.0)
	_check(Game.load_game(), "the save loads")
	var restored := JSON.stringify(player.to_save_data(), "", false, true)
	_check(restored == snapshot, "level, money, bags, gear, action bar, talents, quests and position all come back")
	_check(player.equipment.get(ItemData.Slot.WEAPON) == axe and player.talent_rank(player.talents[0]) == 1, "the loaded gear and talents are the real game items")


func _alive(id: StringName) -> Array[Enemy]:
	var result: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy.data.id == id and not enemy.is_dead:
			result.append(enemy)
	return result


func _nearest_enemy(player: Player, id: StringName) -> Enemy:
	var best: Enemy = null
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy.data.id == id and not enemy.is_dead and enemy.state == Enemy.State.IDLE 				and (best == null or enemy.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
			best = enemy
	return best


func _place_facing(player: Player, enemy: Unit, distance: float) -> void:
	var away := Vector3(player.global_position.x - enemy.global_position.x, 0.0, player.global_position.z - enemy.global_position.z).normalized()
	var spot := enemy.global_position + away * distance
	spot.y = Game.zone.terrain.get_height(spot.x, spot.z) + 0.2
	player.teleport(spot, atan2(away.x, away.z))


func _face(player: Player, enemy: Unit) -> void:
	var to := enemy.global_position - player.global_position
	player.rotation.y = atan2(-to.x, -to.z)


func _wait_until(condition: Callable, timeout: float) -> void:
	var t := 0.0
	while t < timeout and not condition.call():
		await get_tree().physics_frame
		t += get_physics_process_delta_time() * Engine.time_scale


## Reads, last of the skeleton's modifiers (as finally posed), how deep the arms go into the body.
class ContactProbe extends SkeletonModifier3D:
	var deepest := 0.0

	func _process_modification() -> void:
		var contact := get_skeleton().get_node_or_null("BodyContact") as BodyContact
		if contact:
			deepest = maxf(deepest, contact.deepest()[0])
