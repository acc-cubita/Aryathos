class_name CharacterWindow
extends GameWindow
## Character info (C): equipment slots around a 3D preview of the character
## (drag it to turn), weapons below, stats at the bottom. Click worn gear to take it off.

const LEFT: Array[ItemData.Slot] = [
	ItemData.Slot.HEAD, ItemData.Slot.NECK, ItemData.Slot.SHOULDERS,
	ItemData.Slot.BACK, ItemData.Slot.CHEST, ItemData.Slot.WRIST,
]
const RIGHT: Array[ItemData.Slot] = [
	ItemData.Slot.HANDS, ItemData.Slot.WAIST, ItemData.Slot.LEGS,
	ItemData.Slot.FEET, ItemData.Slot.FINGER, ItemData.Slot.TRINKET,
]
const BOTTOM: Array[ItemData.Slot] = [ItemData.Slot.WEAPON, ItemData.Slot.OFF_HAND]
const SHORT_NAMES := {
	ItemData.Slot.SHOULDERS: "Shldr", ItemData.Slot.FINGER: "Ring",
	ItemData.Slot.TRINKET: "Trink", ItemData.Slot.WEAPON: "Main", ItemData.Slot.OFF_HAND: "Off",
}

var _player: Player
var _slots := {}
var _stats := Hud.make_label("", 13, Color(0.95, 0.92, 0.85))
var _model_pivot := Node3D.new()


func _init() -> void:
	super("Character")


func setup(player: Player) -> void:
	_player = player
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.add_child(_slot_column(LEFT))
	body.add_child(_build_preview())
	body.add_child(_slot_column(RIGHT))
	content.add_child(body)
	var weapons := HBoxContainer.new()
	weapons.alignment = BoxContainer.ALIGNMENT_CENTER
	for slot in BOTTOM:
		weapons.add_child(_slot(slot))
	content.add_child(weapons)
	content.add_child(_stats)
	player.inventory_changed.connect(refresh)
	refresh()


func refresh() -> void:
	for slot: ItemData.Slot in _slots:
		(_slots[slot] as ItemSlot).item = _player.equipment.get(slot)


func _process(_delta: float) -> void:
	if not visible:
		return
	var p := _player
	set_title("%s  -  Level %d %s Runeknight" % [p.unit_name, p.level, p.race])
	var dps := (p.weapon_min + p.weapon_max) * 0.5 / p.attack_interval
	_stats.text = "Health  %d / %d          Mana  %d / %d\nDamage  %d - %d          Speed  %.2f          DPS  %.1f\nSpell Power  %d          Critical Strike  %d%%" % [
		p.health, p.max_health, p.mana, p.max_mana, p.weapon_min, p.weapon_max,
		p.attack_interval, dps, p.spell_power, roundi(p.crit_chance() * 100)]


func _slot(slot: ItemData.Slot) -> ItemSlot:
	var item_slot := ItemSlot.new()
	item_slot.placeholder = SHORT_NAMES.get(slot, ItemData.SLOT_NAMES[slot])
	item_slot.clicked.connect(_player.unequip.bind(slot))
	_slots[slot] = item_slot
	return item_slot


func _slot_column(slots: Array[ItemData.Slot]) -> VBoxContainer:
	var column := VBoxContainer.new()
	for slot in slots:
		column.add_child(_slot(slot))
	return column


## A small separate 3D world showing the character, like WoW's paper doll.
func _build_preview() -> Control:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(200, 300)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 25, 0)
	viewport.add_child(light)
	_model_pivot.rotation.y = PI
	_model_pivot.add_child(CharacterModel.create_hero(_player.look, _player.glow_color))
	_player.look_changed.connect(func() -> void:
		for old in _model_pivot.get_children():
			old.queue_free()
		_model_pivot.add_child(CharacterModel.create_hero(_player.look, _player.glow_color)))
	viewport.add_child(_model_pivot)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.05, 3.4)
	camera.fov = 40.0
	viewport.add_child(camera)
	container.gui_input.connect(func(event: InputEvent) -> void:
		var motion := event as InputEventMouseMotion
		if motion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_model_pivot.rotation.y += motion.relative.x * 0.01)
	return container
