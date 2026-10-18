class_name Player
extends Unit
## The player character with WoW-style controls:
## W/S run and backpedal, A/D turn (or strafe while right mouse is held),
## Q/E strafe, Space jump, R/NumLock autorun, both mouse buttons run forward.
## Combat: click or Tab to target, 1-6 use abilities, right-click attacks.
## Right-click (or F) talks to NPCs and loots corpses. Kills and quests give XP;
## gear in the equipment slots adds to the character's stats.

signal leveled_up(new_level: int)
signal inventory_changed
signal talents_changed
signal reputation_changed
signal money_looted(amount: int)
signal item_used(item: ItemData)
signal place_discovered(place: String)
signal professions_changed
signal gathered(item: ItemData, count: int)
signal crafted(item: ItemData, count: int)
## The hero's look changed (its model was made again).
signal look_changed
## Gathering and crafting use a cast bar like spells do.
signal activity_started(text: String)
signal activity_ended(success: bool)

const RUN_SPEED := 7.0
## Backing off is a measured walk backwards (CharacterModel.BACK_*).
const BACKPEDAL_SPEED := 2.8
## With walking on (/ like WoW): a brisk walk, forward or back.
const WALK_SPEED := 1.6
const TURN_SPEED := PI
const JUMP_VELOCITY := 8.0
const TAB_TARGET_RANGE := 40.0
const ACTION_SLOTS := 12
const INTERACT_RANGE := 6.0
const BAG_SIZE := 16
const GATHER_RANGE := 4.0

@export var race := "Arkanor"
## The hero's class (data/classes): abilities, talent trees, starting weapon, glow, and
## how health and mana grow.
@export var hero_class: ClassData
## How the hero looks (gender, hair, beard, colours): see CharacterModel.LOOKS.
var look := CharacterModel.DEFAULT_LOOK.duplicate()
@export var armor_color := Color(0.55, 0.6, 0.7)
## The class's glow (swing arcs, casting hands).
var glow_color := Color(0.3, 0.7, 1.0)
## Every ability the character knows (the spellbook): the class's, and any a talent taught.
var abilities: Array[AbilityData] = []
## Names of the class's talent trees (TalentData.tree indexes into this).
var talent_trees: Array[String] = []
var talents: Array[TalentData] = []
## Points needed in a tree before each next row opens.
const POINTS_PER_TIER := 3

## What sits on each action bar button: an AbilityData, a usable ItemData (potion)
## or null. Starts with the known abilities.
var action_bar: Array[Resource] = []
var autorun := false
## Walking instead of running (toggled with /).
var walking := false
var is_moving := false
## Forward/back input this frame (-1..1); the camera uses it to swing behind.
var forward_input := 0.0
var spawn_point := Vector3.ZERO
var xp := 0
var quest_log: QuestLog
var achievements: AchievementLog
## Names of the places (points of interest) this character has found.
var discovered: Array[String] = []
## Bag slots; null = empty.
var bags: Array[ItemData] = []
## How many of the item sit in each bag slot (stacks, e.g. 5 potions).
var bag_counts := PackedInt32Array()
## ItemData.Slot -> ItemData.
var equipment := {}
## Copper coins.
var money := 0

var _jump_queued := false
var _ring: Decal
## Cooldown group -> game time when items in that group can be used again.
var _item_cooldowns := {}
## Talent id -> rank learned.
var _talent_ranks := {}
## Faction id -> reputation points (0 = the start of Neutral).
var reputation := {}
## Profession id -> skill (1..max).
var professions := {}
## What is being gathered or crafted right now ("" = nothing).
var activity := ""
var activity_duration := 0.0
var _activity_end := 0.0
var _activity_done: Callable

@onready var camera_rig: CameraRig = $CameraRig


func _ready() -> void:
	faction = Faction.PLAYER
	bags.resize(BAG_SIZE)
	bag_counts.resize(BAG_SIZE)
	action_bar.resize(ACTION_SLOTS)
	_take_class(hero_class)
	for i in mini(abilities.size(), ACTION_SLOTS):
		action_bar[i] = abilities[i]
	if hero_class.starting_weapon:
		equipment[ItemData.Slot.WEAPON] = hero_class.starting_weapon
	_apply_level_stats()
	health = max_health
	mana = max_mana
	quest_log = QuestLog.new(self)
	achievements = AchievementLog.new(self)
	super()
	model = make_model()
	add_child(model)
	_ring = _make_target_ring()
	add_child(_ring)
	camera_rig.clicked.connect(_on_world_clicked)
	Game.player = self


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		_jump_queued = true
	elif event.is_action_pressed("autorun"):
		autorun = not autorun
	elif event.is_action_pressed("toggle_walk"):
		set_walking(not walking)
	elif event.is_action_pressed("move_forward") or event.is_action_pressed("move_back"):
		autorun = false
	elif event.is_action_pressed("interact"):
		interact_with(target)
	elif event.is_action_pressed("target_nearest"):
		target_nearest_enemy()
	elif event.is_action_pressed("clear_target"):
		if casting:
			interrupt_cast()
		elif activity != "":
			cancel_activity()
		elif target:
			set_target(null)
		else:
			Game.menu_requested.emit()
	else:
		for i in ACTION_SLOTS:
			if event.is_action_pressed("action_%d" % (i + 1)):
				use_action_slot(i)


func _process(_delta: float) -> void:
	_update_target_ring()


func _think(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if is_dead:
		_stop()
		move_and_slide()
		is_moving = false
		return

	var turn := Input.get_axis("turn_right", "turn_left")
	var strafe := Input.get_axis("strafe_left", "strafe_right")
	if camera_rig.is_steering():
		# Right mouse held: the mouse steers, so A/D strafe instead of turning.
		strafe = clampf(strafe - turn, -1.0, 1.0)
	elif turn != 0.0:
		var amount := turn * TURN_SPEED * delta
		rotation.y += amount
		camera_rig.follow_character_turn(amount)

	forward_input = Input.get_axis("move_back", "move_forward")
	if autorun or camera_rig.both_buttons_held():
		forward_input = 1.0
	var local := Vector3(strafe, 0.0, -forward_input)
	if local.length() > 1.0:
		local = local.normalized()
	var speed := WALK_SPEED if walking else (RUN_SPEED if forward_input >= 0.0 else BACKPEDAL_SPEED)
	var wish := Basis(Vector3.UP, rotation.y) * local * speed

	# Like WoW, there is no air control: momentum is kept until landing.
	if is_on_floor():
		velocity.x = wish.x
		velocity.z = wish.z
		if _jump_queued:
			velocity.y = JUMP_VELOCITY
	_jump_queued = false
	move_and_slide()
	is_moving = wish.length_squared() > 0.01 or not is_on_floor()
	if is_moving and casting:
		interrupt_cast()
	if is_moving and activity != "":
		cancel_activity()
	_tick_activity()


func set_walking(on: bool) -> void:
	walking = on


# --- Combat -----------------------------------------------------------------

func use_action_slot(index: int) -> bool:
	if index < 0 or index >= ACTION_SLOTS:
		return false
	var entry := action_bar[index]
	if entry is AbilityData:
		return use_ability(entry)
	if entry is ItemData:
		return use_item(entry)
	return false


## Puts an ability or potion on a button. When it was dragged from another
## button, whatever was on the target moves to that button (a swap).
func place_on_action_bar(entry: Resource, slot: int, from_slot := -1) -> void:
	var previous := action_bar[slot]
	action_bar[slot] = entry
	if from_slot >= 0 and from_slot != slot:
		action_bar[from_slot] = previous


func use_ability(ability: AbilityData) -> bool:
	if ability_cast_time(ability) > 0.0 and is_moving and not is_dead:
		_on_ability_error("You can't do that while moving.")
		return false
	return super(ability)


func in_ability_range(ability: AbilityData) -> bool:
	var on := ability_target(ability)
	return on == null or on == self or distance_to_unit(on) <= ability.max_range


## Tab: cycles through living enemies in front of the camera, nearest first.
func target_nearest_enemy() -> void:
	var look := -camera_rig.camera.global_transform.basis.z
	var candidates: Array[Unit] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var unit := node as Unit
		var to := unit.global_position - global_position
		if unit.is_dead or to.length() > TAB_TARGET_RANGE:
			continue
		if Vector2(look.x, look.z).normalized().dot(Vector2(to.x, to.z).normalized()) < 0.3:
			continue
		candidates.append(unit)
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position))
	var next := (candidates.find(target) + 1) % candidates.size()
	set_target(candidates[next])


## The unit under the mouse, or null.
func pick_unit(screen_position: Vector2) -> Unit:
	var area := _pick_area(screen_position)
	return area.get_parent() as Unit if area else null


## The herb (or other gatherable) under the mouse, or null.
func pick_gather_node(screen_position: Vector2) -> GatherNode:
	var area := _pick_area(screen_position)
	return area.get_parent() as GatherNode if area else null


## The quest object under the mouse (only ones a quest wants can be clicked), or null.
func pick_quest_object(screen_position: Vector2) -> QuestObject:
	var area := _pick_area(screen_position)
	return area.get_parent() as QuestObject if area else null


func _pick_area(screen_position: Vector2) -> Area3D:
	var camera := camera_rig.camera
	var from := camera.project_ray_origin(screen_position)
	var query := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(screen_position) * 300.0, LAYER_WORLD | LAYER_CLICKABLE)
	query.collide_with_areas = true
	query.exclude = [click_area.get_rid(), get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).get("collider") as Area3D


## Left click selects (empty ground clears the target); right click also attacks.
func _on_world_clicked(button: int, at: Vector2) -> void:
	var unit := pick_unit(at)
	if button == MOUSE_BUTTON_LEFT or unit:
		set_target(unit)
	if button == MOUSE_BUTTON_RIGHT and unit:
		if unit.is_dead or not is_hostile_to(unit):
			interact_with(unit)
		else:
			auto_attacking = true
	elif button == MOUSE_BUTTON_RIGHT:
		var node := pick_gather_node(at)
		if node:
			gather(node)
		else:
			var thing := pick_quest_object(at)
			if thing:
				use_quest_object(thing)


## Talk to an NPC or loot a corpse.
func interact_with(unit: Unit) -> void:
	var npc := unit as Npc
	var corpse := unit as Enemy
	if is_dead or not (npc or (corpse and corpse.has_loot())):
		return
	if distance_to_unit(unit) > INTERACT_RANGE:
		_on_ability_error("You are too far away.")
		return
	if npc:
		npc.interact(self)
		return
	if corpse.loot_money > 0:
		money += corpse.loot_money
		Game.chat("You loot %s." % Game.format_money(corpse.loot_money), Game.CHAT_LOOT)
		money_looted.emit(corpse.loot_money)
		corpse.loot_money = 0
		inventory_changed.emit()
	if corpse.has_loot():
		Game.loot_opened.emit(corpse)


# --- Inventory and equipment ----------------------------------------------------

## How many more of an item fit in the bags.
func room_for(item: ItemData) -> int:
	var room := 0
	for i in BAG_SIZE:
		if bags[i] == null:
			room += item.max_stack
		elif bags[i] == item:
			room += item.max_stack - bag_counts[i]
	return room


## Adds to existing stacks first, then to empty slots. Fails (adding nothing) when it does not fit.
func add_item(item: ItemData, count := 1) -> bool:
	if room_for(item) < count:
		_on_ability_error("Inventory is full.")
		return false
	for pass_index in 2:
		for i in BAG_SIZE:
			if count == 0:
				break
			var stacking := pass_index == 0 and bags[i] == item
			if stacking or (pass_index == 1 and bags[i] == null):
				var moved := mini(count, item.max_stack - bag_counts[i])
				bags[i] = item
				bag_counts[i] += moved
				count -= moved
	inventory_changed.emit()
	return true


## How many of an item are in the bags, over all stacks.
func count_item(item: ItemData) -> int:
	var total := 0
	for i in BAG_SIZE:
		if bags[i] == item:
			total += bag_counts[i]
	return total


## Takes `count` of an item out of the bags, from any stacks.
func remove_item(item: ItemData, count: int) -> void:
	for i in range(BAG_SIZE - 1, -1, -1):
		if count > 0 and bags[i] == item:
			var taken := mini(count, bag_counts[i])
			bag_counts[i] -= taken
			count -= taken
			if bag_counts[i] == 0:
				bags[i] = null
	inventory_changed.emit()


func remove_from_slot(index: int, count := 1) -> void:
	bag_counts[index] -= count
	if bag_counts[index] <= 0:
		bags[index] = null
		bag_counts[index] = 0
	inventory_changed.emit()


## Clicking a bag slot: drink a potion, or put on a piece of gear.
func use_bag_slot(index: int) -> void:
	var item := bags[index]
	if item == null:
		return
	if item.is_usable():
		use_item(item)
	elif item.slot != ItemData.Slot.NONE:
		equip_from_bag(index)


func item_cooldown_left(item: ItemData) -> float:
	return maxf(0.0, float(_item_cooldowns.get(item.cooldown_key(), 0.0)) - Game.time)


## Uses one of a consumable from the bags (from the bags or an action button).
func use_item(item: ItemData) -> bool:
	var index := bags.find(item)
	if is_dead or not item.is_usable():
		return false
	if index < 0:
		_on_ability_error("You don't have any %s." % item.display_name)
		return false
	if item_cooldown_left(item) > 0.0:
		_on_ability_error("Item is not ready yet.")
		return false
	match item.use_effect:
		ItemData.UseEffect.HEAL:
			receive_heal(item.use_amount, self)
		ItemData.UseEffect.RESTORE_MANA:
			mana = mini(max_mana, mana + item.use_amount)
			Game.mana_restored.emit(self, item.use_amount)
	_item_cooldowns[item.cooldown_key()] = Game.time + item.use_cooldown
	remove_from_slot(index)
	item_used.emit(item)
	return true


# --- Merchants ----------------------------------------------------------------

## What an item costs from this seller, after the faction discount.
func price_for(item: ItemData, seller: Npc = null) -> int:
	if seller == null or seller.reputation_faction == null:
		return item.buy_price
	return roundi(item.buy_price * (1.0 - FactionData.DISCOUNTS[standing_with(seller.reputation_faction)]))


func buy(item: ItemData, seller: Npc = null) -> bool:
	if item.required_faction and standing_with(item.required_faction) < item.required_standing:
		_on_ability_error("Requires %s with %s." % [FactionData.STANDING_NAMES[item.required_standing], item.required_faction.display_name])
		return false
	var price := price_for(item, seller)
	if money < price:
		_on_ability_error("You don't have enough money.")
		return false
	if not add_item(item):
		return false
	money -= price
	inventory_changed.emit()
	return true


## Sells the whole stack in a bag slot.
func sell_bag_slot(index: int) -> void:
	var item := bags[index]
	if item == null:
		return
	if item.sell_price <= 0:
		_on_ability_error("The merchant doesn't want that item.")
		return
	var earned := item.sell_price * bag_counts[index]
	money += earned
	Game.chat("You sold %s for %s." % [item.display_name, Game.format_money(earned)], Game.CHAT_LOOT)
	remove_from_slot(index, bag_counts[index])


func take_loot(corpse: Enemy, index: int) -> void:
	if index < corpse.loot_items.size() and add_item(corpse.loot_items[index]):
		Game.chat("You receive loot: [%s]." % corpse.loot_items[index].display_name, Game.CHAT_LOOT)
		corpse.loot_items.remove_at(index)


## Equips the item in a bag slot; whatever was worn there goes back into that bag slot.
func equip_from_bag(index: int) -> void:
	var item := bags[index]
	if item == null or item.slot == ItemData.Slot.NONE or is_dead:
		return
	bags[index] = equipment.get(item.slot)
	bag_counts[index] = 1 if bags[index] else 0
	equipment[item.slot] = item
	_apply_level_stats()
	_show_weapon()
	inventory_changed.emit()


func unequip(slot: ItemData.Slot) -> void:
	if not equipment.has(slot) or is_dead:
		return
	var free := bags.find(null)
	if free < 0:
		_on_ability_error("Inventory is full.")
		return
	bags[free] = equipment[slot]
	bag_counts[free] = 1
	equipment.erase(slot)
	_apply_level_stats()
	_show_weapon()
	inventory_changed.emit()


func _gear_total(stat: StringName) -> int:
	var total := 0
	for item: ItemData in equipment.values():
		total += int(item.get(stat))
	return total


# --- Experience and levels ---------------------------------------------------

func on_enemy_killed(enemy: Enemy) -> void:
	if enemy.data.reputation_faction:
		gain_reputation(enemy.data.reputation_faction, enemy.data.reputation_on_kill)
	var amount := Game.kill_xp(enemy.level, level, enemy.is_elite)
	if amount > 0:
		Game.chat("%s dies, you gain %d experience." % [enemy.unit_name, amount], Game.CHAT_XP)
		gain_xp(amount)


func gain_xp(amount: int) -> void:
	if level >= Game.MAX_LEVEL:
		return
	xp += amount
	while level < Game.MAX_LEVEL and xp >= Game.xp_to_next_level(level):
		xp -= Game.xp_to_next_level(level)
		level += 1
		_apply_level_stats()
		health = max_health
		mana = max_mana
		Game.system_message.emit("Level %d!" % level, Color(1.0, 0.82, 0.0))
		Game.chat("Congratulations, you have reached level %d!" % level)
		Game.chat("You have %d unspent talent point%s. Press N to open your talents." % [talent_points_free(), "" if talent_points_free() == 1 else "s"])
		leveled_up.emit(level)
	if level >= Game.MAX_LEVEL:
		xp = 0


## Level and gear decide the stats. Without a weapon you fight with your fists.
func _apply_level_stats() -> void:
	var health_bonus := 1.0 + talent_value(TalentData.Effect.MAX_HEALTH) / 100.0
	var mana_bonus := 1.0 + talent_value(TalentData.Effect.MAX_MANA) / 100.0
	var weapon_bonus := 1.0 + talent_value(TalentData.Effect.WEAPON_DAMAGE) / 100.0
	max_health = roundi((hero_class.base_health + hero_class.health_per_level * (level - 1)
			+ _gear_total(&"health_bonus")) * health_bonus)
	max_mana = roundi((hero_class.base_mana + hero_class.mana_per_level * (level - 1)
			+ _gear_total(&"mana_bonus")) * mana_bonus)
	spell_power = _gear_total(&"spell_power")
	var weapon: ItemData = equipment.get(ItemData.Slot.WEAPON)
	weapon_min = roundi(((weapon.min_damage if weapon else 2) + (level - 1)) * weapon_bonus)
	weapon_max = roundi(((weapon.max_damage if weapon else 4) + 2 * (level - 1)) * weapon_bonus)
	attack_interval = 2.4
	health = mini(health, max_health)
	mana = mini(mana, max_mana)


# --- Gathering and crafting -------------------------------------------------------

## Starts a cast-bar action that finishes by calling `on_done`. Moving, taking
## damage or Esc cancels it.
func start_activity(text: String, duration: float, on_done: Callable) -> bool:
	if is_dead:
		return false
	if casting or activity != "":
		_on_ability_error("Another action is in progress.")
		return false
	if is_moving:
		_on_ability_error("You can't do that while moving.")
		return false
	activity = text
	activity_duration = duration
	_activity_end = Game.time + duration
	_activity_done = on_done
	activity_started.emit(text)
	return true


func activity_remaining() -> float:
	return maxf(0.0, _activity_end - Game.time) if activity != "" else 0.0


func cancel_activity() -> void:
	if activity != "":
		activity = ""
		activity_ended.emit(false)


func _tick_activity() -> void:
	if activity != "" and Game.time >= _activity_end:
		var done := _activity_done
		activity = ""
		activity_ended.emit(true)
		done.call()


func knows_profession(profession: ProfessionData) -> bool:
	return professions.has(profession.id)


func profession_skill(profession: ProfessionData) -> int:
	return int(professions.get(profession.id, 0))


func learn_profession(profession: ProfessionData) -> void:
	if knows_profession(profession):
		return
	professions[profession.id] = 1
	Game.chat("You have learned %s." % profession.display_name, Game.CHAT_SYSTEM)
	professions_changed.emit()


func gather(node: GatherNode) -> bool:
	var data := node.data
	if not node.available or is_dead:
		return false
	if not knows_profession(data.profession):
		_on_ability_error("Requires %s." % data.profession.display_name)
		return false
	if profession_skill(data.profession) < data.required_skill:
		_on_ability_error("Requires %s (%d)." % [data.profession.display_name, data.required_skill])
		return false
	if flat_distance(node.global_position) > GATHER_RANGE:
		_on_ability_error("You are too far away.")
		return false
	return start_activity(data.profession.display_name, data.gather_time, _finish_gather.bind(node))


func _finish_gather(node: GatherNode) -> void:
	if not node.available:
		return
	var data := node.data
	var amount := randi_range(data.min_count, data.max_count)
	if add_item(data.item, amount):
		node.harvest()
		Game.chat("You receive loot: [%s] x%d." % [data.item.display_name, amount], Game.CHAT_LOOT)
		gathered.emit(data.item, amount)
		_raise_skill(data.profession, data.required_skill)


## Uses a quest object (a short cast bar); the quest moves on when it finishes.
func use_quest_object(thing: QuestObject) -> bool:
	if not thing.available or is_dead or not quest_log.wants_object(thing.object_id):
		return false
	if flat_distance(thing.global_position) > GATHER_RANGE:
		_on_ability_error("You are too far away.")
		return false
	return start_activity(thing.action, thing.use_time, func() -> void:
		if thing.available and quest_log.use_object(thing.object_id):
			thing.use())


## "" when the recipe can be made right now, otherwise why not.
func craft_block_reason(recipe: RecipeData) -> String:
	if not knows_profession(recipe.profession):
		return "Requires %s." % recipe.profession.display_name
	if profession_skill(recipe.profession) < recipe.required_skill:
		return "Requires %s (%d)." % [recipe.profession.display_name, recipe.required_skill]
	for i in recipe.reagents.size():
		if count_item(recipe.reagents[i]) < recipe.reagent_counts[i]:
			return "Missing reagents."
	return ""


func craft(recipe: RecipeData) -> bool:
	var reason := craft_block_reason(recipe)
	if reason != "":
		_on_ability_error(reason)
		return false
	return start_activity(recipe.product.display_name, recipe.craft_time, _finish_craft.bind(recipe))


func _finish_craft(recipe: RecipeData) -> void:
	var reason := craft_block_reason(recipe)
	if reason == "" and room_for(recipe.product) < recipe.product_count:
		reason = "Inventory is full."
	if reason != "":
		_on_ability_error(reason)
		return
	for i in recipe.reagents.size():
		remove_item(recipe.reagents[i], recipe.reagent_counts[i])
	add_item(recipe.product, recipe.product_count)
	Game.chat("You create: [%s]." % recipe.product.display_name, Game.CHAT_LOOT)
	crafted.emit(recipe.product, recipe.product_count)
	_raise_skill(recipe.profession, recipe.required_skill)


## Orange recipes/herbs always raise the skill, yellow and green sometimes, gray never.
func _raise_skill(profession: ProfessionData, required: int) -> void:
	var skill := profession_skill(profession)
	if skill >= profession.max_skill:
		return
	if randf() < ProfessionData.SKILL_UP_CHANCE[ProfessionData.difficulty(skill, required)]:
		professions[profession.id] = skill + 1
		Game.chat("Your skill in %s has increased to %d." % [profession.display_name, skill + 1], Color(0.4, 0.6, 1))
		professions_changed.emit()


# --- Exploration ----------------------------------------------------------------

## First visit to a place: a WoW-style "Discovered" message and some experience.
func discover(place: String) -> void:
	if discovered.has(place):
		return
	discovered.append(place)
	var amount := 20 + 10 * level
	Game.system_message.emit("Discovered: %s" % place, Color(1, 0.85, 0.35))
	Game.chat("Discovered %s: %d experience gained." % [place, amount], Game.CHAT_XP)
	gain_xp(amount)
	place_discovered.emit(place)


# --- Reputation -----------------------------------------------------------------

func reputation_with(faction: FactionData) -> int:
	return int(reputation.get(faction.id, 0))


func standing_with(faction: FactionData) -> int:
	return FactionData.standing_for(reputation_with(faction))


func gain_reputation(faction: FactionData, amount: int) -> void:
	if faction == null or amount == 0:
		return
	var before := standing_with(faction)
	reputation[faction.id] = reputation_with(faction) + amount
	Game.chat("Reputation with %s %s by %d." % [faction.display_name, "increased" if amount > 0 else "decreased", absi(amount)], Game.CHAT_REPUTATION)
	var after := standing_with(faction)
	if after != before:
		var text := "You are now %s with %s." % [FactionData.STANDING_NAMES[after], faction.display_name]
		Game.system_message.emit(text, FactionData.STANDING_COLORS[after])
		Game.chat(text, Game.CHAT_REPUTATION)
	reputation_changed.emit()


# --- Saving ---------------------------------------------------------------------

## A new look (character creation, a loaded save): the model is made again.
func set_look(new_look: Dictionary) -> void:
	look = CharacterModel.DEFAULT_LOOK.duplicate()
	for key: String in look:  # (a save brings numbers back as floats)
		if new_look.has(key):
			look[key] = String(new_look[key]) if key == "gender" else int(new_look[key])
	_remake_model()
	look_changed.emit()


## A new hero's class (character creation): its abilities on the action bar, its weapon
## in hand (instead of the old class's), no talents; the model is made again.
func set_class(data: ClassData) -> void:
	reset_talents()
	var old_weapon: ItemData = hero_class.starting_weapon if hero_class else null
	_take_class(data)
	action_bar.fill(null)
	for i in mini(abilities.size(), ACTION_SLOTS):
		action_bar[i] = abilities[i]
	if not equipment.has(ItemData.Slot.WEAPON) or equipment[ItemData.Slot.WEAPON] == old_weapon:
		equipment[ItemData.Slot.WEAPON] = data.starting_weapon
	_apply_level_stats()
	health = max_health
	mana = max_mana
	_remake_model()
	inventory_changed.emit()
	talents_changed.emit()
	look_changed.emit()


## The hero's model as they look now, holding the weapon they wear (previews make one too).
func make_model() -> CharacterModel:
	return CharacterModel.create_hero(look.merged({"outfit": hero_class.outfit}), glow_color, _weapon_model())


## What the hero holds: the worn weapon's model, or nothing (fists).
func _weapon_model() -> String:
	var weapon: ItemData = equipment.get(ItemData.Slot.WEAPON)
	return weapon.weapon_model if weapon else ""


## After the weapon changed (equipping, loading): the model is made again if it looks different.
func _show_weapon() -> void:
	if model != null and model.weapon_key != _weapon_model():
		_remake_model()
		look_changed.emit()


## Takes on a class's abilities, talent trees and glow; talents, gear and the bar stay.
func _take_class(data: ClassData) -> void:
	hero_class = data
	abilities = data.abilities.duplicate()
	talent_trees = data.talent_trees.duplicate()
	talents = data.talents.duplicate()
	glow_color = data.glow_color


func _remake_model() -> void:
	if model != null:
		model.queue_free()
		remove_child(model)
	model = make_model()
	add_child(model)


## Everything about the character that should survive closing the game.
## Items, abilities and quests are stored by id (see Database).
func to_save_data() -> Dictionary:
	var bag_data := []
	for i in BAG_SIZE:
		bag_data.append({"id": String(bags[i].id), "count": bag_counts[i]} if bags[i] else null)
	var gear := {}
	for slot: int in equipment:
		gear[str(slot)] = String((equipment[slot] as ItemData).id)
	var bar := []
	for entry in action_bar:
		if entry is AbilityData:
			bar.append({"ability": String(entry.id)})
		elif entry is ItemData:
			bar.append({"item": String(entry.id)})
		else:
			bar.append(null)
	var ranks := {}
	for id: StringName in _talent_ranks:
		ranks[String(id)] = _talent_ranks[id]
	var standing := {}
	for id: StringName in reputation:
		standing[String(id)] = reputation[id]
	var skills := {}
	for id: StringName in professions:
		skills[String(id)] = professions[id]
	# A dead character comes back at the camp, half healed.
	var where := spawn_point if is_dead else global_position
	return {
		"version": 1, "name": unit_name, "class": String(hero_class.id), "look": look.duplicate(), "level": level, "xp": xp, "money": money,
		"health": maxi(health, max_health / 2) if is_dead else health, "mana": mana,
		"position": [where.x, where.y, where.z], "yaw": rotation.y,
		"bags": bag_data, "equipment": gear, "action_bar": bar, "talents": ranks, "reputation": standing,
		"quests": quest_log.to_save_data(),
		"discovered": discovered.duplicate(),
		"professions": skills,
		"achievements": achievements.to_save_data(),
	}


func load_save_data(data: Dictionary) -> void:
	unit_name = String(data.get("name", unit_name))
	reset_talents()  # the old class's taught abilities go before its talent list does
	var saved_class := Database.hero_class(StringName(data.get("class", "runeknight")))
	_take_class(saved_class if saved_class else hero_class)
	set_look(data["look"] if data.get("look") is Dictionary else look)
	level = clampi(int(data.get("level", 1)), 1, Game.MAX_LEVEL)
	xp = int(data.get("xp", 0))
	money = int(data.get("money", 0))
	var bag_data: Array = data.get("bags", [])
	for i in BAG_SIZE:
		var entry: Variant = bag_data[i] if i < bag_data.size() else null
		var item := Database.item(StringName(entry["id"])) if entry is Dictionary else null
		bags[i] = item
		bag_counts[i] = int(entry["count"]) if item else 0
	equipment.clear()
	var gear: Dictionary = data.get("equipment", {})
	for key: String in gear:
		var item := Database.item(StringName(gear[key]))
		if item:
			equipment[int(key)] = item
	_show_weapon()
	reset_talents()
	var ranks: Dictionary = data.get("talents", {})
	for talent in talents:
		_talent_ranks[talent.id] = mini(int(ranks.get(String(talent.id), 0)), talent.max_rank)
		if _talent_ranks[talent.id] == 0:
			_talent_ranks.erase(talent.id)
		elif talent.effect == TalentData.Effect.LEARN_ABILITY and not abilities.has(talent.ability):
			abilities.append(talent.ability)
	_talent_ranks = _sorted_like(_talent_ranks, ranks)
	var bar: Array = data.get("action_bar", [])
	for i in ACTION_SLOTS:
		var entry: Variant = bar[i] if i < bar.size() else null
		action_bar[i] = null
		if entry is Dictionary and entry.has("ability"):
			action_bar[i] = Database.ability(StringName(entry["ability"]))
		elif entry is Dictionary and entry.has("item"):
			action_bar[i] = Database.item(StringName(entry["item"]))
	_apply_level_stats()
	health = clampi(int(data.get("health", max_health)), 1, max_health)
	mana = clampi(int(data.get("mana", max_mana)), 0, max_mana)
	reputation.clear()
	var standing: Dictionary = data.get("reputation", {})
	for key: String in standing:
		reputation[StringName(key)] = int(standing[key])
	quest_log.load_save_data(data.get("quests", {}))
	discovered.assign(data.get("discovered", []))
	professions.clear()
	var skills: Dictionary = data.get("professions", {})
	for key: String in skills:
		professions[StringName(key)] = int(skills[key])
	professions_changed.emit()
	achievements.load_save_data(data.get("achievements", {}))
	var where: Array = data.get("position", [])
	if where.size() == 3:
		teleport(Vector3(where[0], where[1], where[2]), float(data.get("yaw", 0.0)))
	inventory_changed.emit()
	talents_changed.emit()
	reputation_changed.emit()


## Keeps talent ranks in the order they were saved, so saving again gives the same file.
func _sorted_like(learned: Dictionary, saved: Dictionary) -> Dictionary:
	var ordered := {}
	for key: String in saved:
		if learned.has(StringName(key)):
			ordered[StringName(key)] = learned[StringName(key)]
	return ordered


# --- Talents --------------------------------------------------------------------

## One point per level from level 2, like WoW Classic's level 10+.
func talent_points_total() -> int:
	return maxi(0, level - 1)


func talent_points_free() -> int:
	var spent := 0
	for rank: int in _talent_ranks.values():
		spent += rank
	return talent_points_total() - spent


func talent_rank(talent: TalentData) -> int:
	return int(_talent_ranks.get(talent.id, 0))


func points_in_tree(tree: int) -> int:
	var total := 0
	for talent in talents:
		if talent.tree == tree:
			total += talent_rank(talent)
	return total


## "" when the next rank can be learned, otherwise why not.
func talent_block_reason(talent: TalentData) -> String:
	if talent_rank(talent) >= talent.max_rank:
		return "Fully learned."
	var needed := (talent.tier - 1) * POINTS_PER_TIER
	if points_in_tree(talent.tree) < needed:
		return "Requires %d points in %s." % [needed, talent_trees[talent.tree]]
	if talent_points_free() <= 0:
		return "No talent points left."
	return ""


func learn_talent(talent: TalentData) -> bool:
	var reason := talent_block_reason(talent)
	if reason != "":
		_on_ability_error(reason)
		return false
	_talent_ranks[talent.id] = talent_rank(talent) + 1
	if talent.effect == TalentData.Effect.LEARN_ABILITY and not abilities.has(talent.ability):
		abilities.append(talent.ability)
		var free := action_bar.find(null)
		if free >= 0:
			action_bar[free] = talent.ability
		Game.chat("You have learned a new ability: %s." % talent.ability.display_name)
	_apply_level_stats()
	talents_changed.emit()
	return true


func reset_talents() -> void:
	for talent in talents:
		if talent.effect == TalentData.Effect.LEARN_ABILITY and talent_rank(talent) > 0:
			abilities.erase(talent.ability)
			for i in ACTION_SLOTS:
				if action_bar[i] == talent.ability:
					action_bar[i] = null
	_talent_ranks.clear()
	_apply_level_stats()
	talents_changed.emit()


## Total bonus from learned talents with this effect. With an ability, talents
## for that ability and talents for "all abilities" (no ability set) both count.
func talent_value(effect: TalentData.Effect, ability: AbilityData = null) -> float:
	var total := 0.0
	for talent in talents:
		if talent.effect == effect and (talent.ability == null or talent.ability == ability):
			total += talent.value_per_rank * talent_rank(talent)
	return total


func ability_cast_time(ability: AbilityData) -> float:
	return maxf(0.0, ability.cast_time - talent_value(TalentData.Effect.ABILITY_CAST_TIME, ability))


func ability_cooldown(ability: AbilityData) -> float:
	return maxf(0.0, ability.cooldown - talent_value(TalentData.Effect.ABILITY_COOLDOWN, ability))


func ability_mana_cost(ability: AbilityData) -> int:
	return roundi(ability.mana_cost * (1.0 - talent_value(TalentData.Effect.ABILITY_MANA, ability) / 100.0))


func ability_power(ability: AbilityData) -> float:
	if ability.effect == AbilityData.Effect.HEAL:
		return 1.0 + talent_value(TalentData.Effect.HEALING) / 100.0
	return 1.0 + talent_value(TalentData.Effect.ABILITY_DAMAGE, ability) / 100.0


func crit_chance() -> float:
	return CRIT_CHANCE + talent_value(TalentData.Effect.CRIT) / 100.0


func release_spirit() -> void:
	if is_dead:
		teleport(spawn_point, rotation.y)
		revive(0.5)


## Instantly moves the player (spawn, teleport) without visual smoothing streaks.
func teleport(to: Vector3, yaw: float) -> void:
	global_position = to
	rotation.y = yaw
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	camera_rig.snap_behind()


func _on_ability_error(text: String) -> void:
	Game.error_message.emit(text)


func _on_died(_killer: Unit) -> void:
	autorun = false
	cancel_activity()


## Like in WoW, getting hit stops gathering and crafting.
func _on_damaged(_amount: int, _source: Unit) -> void:
	cancel_activity()


func _health_regen() -> float:
	return 0.0 if in_combat() else max_health * 0.03


# --- Target ring ------------------------------------------------------------

## A glowing circle painted on the ground under the current target.
func _make_target_ring() -> Decal:
	var size := 128
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - size * 0.5 + 0.5, y - size * 0.5 + 0.5).length() / (size * 0.5)
			var alpha := clampf(1.0 - absf(d - 0.86) / 0.09, 0.0, 1.0) + (0.12 if d < 0.86 else 0.0)
			image.set_pixel(x, y, Color(1, 1, 1, minf(alpha, 1.0)))
	var decal := Decal.new()
	decal.texture_albedo = ImageTexture.create_from_image(image)
	decal.texture_emission = decal.texture_albedo
	decal.emission_energy = 1.5
	decal.cull_mask = LAYER_WORLD
	decal.top_level = true
	decal.visible = false
	return decal


func _update_target_ring() -> void:
	_ring.visible = target != null and target.model.visible
	if not _ring.visible:
		return
	_ring.global_position = target.get_global_transform_interpolated().origin + Vector3.UP
	var diameter := (target.body_radius + 0.45) * 2.0
	_ring.size = Vector3(diameter, 4.0, diameter)
	if target.is_dead:
		_ring.modulate = Color(0.55, 0.55, 0.55)
	elif is_hostile_to(target):
		_ring.modulate = Color(1.0, 0.2, 0.15)
	else:
		_ring.modulate = Color(0.3, 1.0, 0.35)
