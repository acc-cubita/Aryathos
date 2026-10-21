class_name CharacterCreation
extends Control
## The character creation screen of a new game: race (Arkanor for now; the Covenant's other
## races are shown as still to come), class (every ClassData), gender, hair, hair colour,
## face, eyes, skin, beard and a name, with the hero turning in a preview (drag to turn it,
## scroll to zoom; choosing a face or eyes moves in on the face). The game waits (paused)
## until Create; then the hero takes the class, the name and the look and is saved.

signal created

## [name, playable, description]
const RACES := [
	["Arkanor", true, "Tall, long-lived and noble, silver-haired even in youth. They carve Aether into runes on their arms and their long runeblades, and raised the first Wardstones."],
	["Sylvari / Luminar", false, "Graceful guardians of cosmic light and sacred forests."],
	["Arkanite Mechanists", false, "Engineers who fuse their own bodies with crystal-powered machines."],
	["Valenar", false, "Resilient humans: the political and martial backbone of the Covenant."],
]
const NAMES := {
	"male": ["Aldren", "Thaeron", "Vorian", "Eldric", "Haldor", "Corvan", "Ithran", "Maelor", "Torvald",
			"Brannoc", "Kaelen", "Aric", "Soren", "Varek", "Orrin", "Hadrik"],
	"female": ["Aelira", "Seraphine", "Ilsa", "Vaelis", "Lyra", "Maeve", "Eirwen", "Ysolde", "Thessa",
			"Nimra", "Orla", "Kaelith", "Sarai", "Liora", "Brynja", "Edda"],
}
const PANEL_WIDTH := 360.0
## The preview camera's full-body spot; the face spot follows the hero's head as it moves
## (EYES up the head bone from the neck, FACE_DISTANCE in front).
const FULL_VIEW := Vector3(0, 1.05, 3.6)
const EYES := Vector3(0, 0.09, 0)
const FACE_DISTANCE := 1.0

var look := CharacterModel.DEFAULT_LOOK.duplicate()

var hero_class: ClassData

var _player: Player
var _class_buttons := {}
var _class_text: Label
var _pivot := Node3D.new()
var _name := LineEdit.new()
var _error := Hud.make_label("", 14, Color(1, 0.4, 0.35))
var _values := {}
var _gender_buttons := {}
var _beard_row: Control
var _camera := Camera3D.new()
var _face_view := Vector3(0, 1.6, FACE_DISTANCE)
var _skeleton: Skeleton3D  # the previewed hero's
var _zoom := 0.0  # 0 the whole hero, 1 the face
var _zoom_to := 0.0


func _init(player: Player) -> void:
	_player = player
	hero_class = player.hero_class
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS  # it runs while the game waits
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


## Shows the screen and holds the game until a character is created.
func open() -> void:
	visible = true
	get_tree().paused = true
	_name.text = _random_name()
	_refresh()


## Makes the character: `name` checked, the look given to the hero, the game saved.
## Returns "" or why the name was refused.
func create(hero_name: String) -> String:
	var clean := hero_name.strip_edges()
	if clean.length() < 2 or clean.length() > 16:
		return "A name has 2 to 16 letters."
	if not RegEx.create_from_string("^[A-Za-z][A-Za-z']*$").search(clean):
		return "Only letters (and ') in a name."
	_player.unit_name = clean.substr(0, 1).to_upper() + clean.substr(1).to_lower()
	if _player.hero_class != hero_class:
		_player.set_class(hero_class)
	_player.set_look(look)
	Game.save_game()
	visible = false
	get_tree().paused = false
	Game.chat("Welcome to Aryathos, %s." % _player.unit_name)
	created.emit()
	return ""


func _process(delta: float) -> void:
	_zoom = move_toward(_zoom, _zoom_to, delta * 2.5)
	if is_instance_valid(_skeleton):
		var head := _skeleton.get_bone_global_pose(_skeleton.find_bone("Head"))
		var face := _skeleton.to_global(head * EYES) - _pivot.global_position
		_face_view = _face_view.lerp(face + Vector3(0, 0, FACE_DISTANCE), minf(delta * 4.0, 1.0))
	_camera.position = FULL_VIEW.lerp(_face_view, smoothstep(0.0, 1.0, _zoom))


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.035, 0.05, 0.97)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var page := VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 12)
	page.offset_left = 28.0
	page.offset_top = 20.0
	page.offset_right = -28.0
	page.offset_bottom = -20.0
	add_child(page)
	var title := Hud.make_label("Create your Champion", 30, Hud.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(title)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 20)
	page.add_child(row)
	row.add_child(_race_panel())
	row.add_child(_preview())
	row.add_child(_look_panel())
	page.add_child(_name_row())


func _panel(heading: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(Hud.make_label(heading, 20, Hud.GOLD))
	return box


func _wrapped(text: String, color := Color(0.85, 0.85, 0.85)) -> Label:
	var label := Hud.make_label(text, 14, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = PANEL_WIDTH - 20.0
	return label


func _race_panel() -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", Hud.panel_style())
	frame.custom_minimum_size.x = PANEL_WIDTH
	var box := _panel("Radiant Covenant")
	frame.add_child(box)
	box.add_child(Hud.make_label("Race", 16, Color.WHITE))
	var description := _wrapped(RACES[0][2])
	for race: Array in RACES:
		var button := Button.new()
		button.text = race[0] if race[1] else "%s  (to come)" % race[0]
		button.disabled = not race[1]
		button.toggle_mode = true
		button.button_pressed = race[1]
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = race[2]
		box.add_child(button)
	box.add_child(description)
	box.add_child(Hud.make_label("Class", 16, Color.WHITE))
	for each in Database.hero_classes():
		var button := Button.new()
		button.text = each.display_name
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void:
			hero_class = each
			_zoom_to = 0.0
			_refresh())
		_class_buttons[each] = button
		box.add_child(button)
	_class_text = _wrapped("")
	box.add_child(_class_text)
	return frame


func _look_panel() -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", Hud.panel_style())
	frame.custom_minimum_size.x = PANEL_WIDTH
	var box := _panel("Appearance")
	frame.add_child(box)
	var genders := HBoxContainer.new()
	for gender: String in ["male", "female"]:
		var button := Button.new()
		button.text = gender.capitalize()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void:
			if look.gender != gender:
				look.gender = gender
				look.face = 0
				look.hair = 0
				look.beard = 0
				_name.text = _random_name()
			_zoom_to = 0.0
			_refresh())
		_gender_buttons[gender] = button
		genders.add_child(button)
	box.add_child(genders)
	box.add_child(_option_row("Face", "face", func() -> Array: return CharacterModel.LOOKS[look.gender].face, 1.0))
	box.add_child(_option_row("Eyes", "eyes", func() -> Array: return CharacterModel.EYE_COLORS, 1.0))
	box.add_child(_option_row("Hair", "hair", func() -> Array: return CharacterModel.LOOKS[look.gender].hair, 0.55))
	box.add_child(_option_row("Hair colour", "hair_color", func() -> Array: return CharacterModel.HAIR_COLORS, 0.55))
	box.add_child(_option_row("Skin", "skin", func() -> Array: return CharacterModel.SKIN_TONES))
	_beard_row = _option_row("Beard", "beard", func() -> Array: return CharacterModel.LOOKS[look.gender].beard, 0.75)
	box.add_child(_beard_row)
	return frame


## "Hair   <  Ponytail  >": the arrows step through options() (each [shown name, ...]) and
## bring the preview camera to `zoom` (0 the whole hero, 1 the face).
func _option_row(title: String, key: String, options: Callable, zoom := 0.0) -> Control:
	var line := HBoxContainer.new()
	var label := Hud.make_label(title, 15, Color.WHITE)
	label.custom_minimum_size.x = 110.0
	line.add_child(label)
	var value := Hud.make_label("", 15, Hud.GOLD)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.custom_minimum_size.x = 150.0
	for step in [-1, 1]:
		var button := Button.new()
		button.text = " < " if step < 0 else " > "
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void:
			var count: int = (options.call() as Array).size()
			look[key] = posmod(int(look[key]) + step, count)
			_zoom_to = zoom
			_refresh())
		line.add_child(button)
		if step < 0:
			line.add_child(value)
	_values[key] = [value, options]
	return line


func _preview() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(container)
	var hint := Hud.make_label("Drag to turn  -  scroll to zoom", 13, Color(0.6, 0.62, 0.66))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.52, 0.58)
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 30, 0)
	key.light_energy = 1.3
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 200, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.6, 0.75, 1.0)
	viewport.add_child(rim)
	_pivot.rotation.y = PI
	viewport.add_child(_pivot)
	_camera.position = FULL_VIEW
	_camera.fov = 36.0
	viewport.add_child(_camera)
	container.gui_input.connect(func(event: InputEvent) -> void:
		var motion := event as InputEventMouseMotion
		if motion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_pivot.rotation.y += motion.relative.x * 0.01
		var wheel := event as InputEventMouseButton
		if wheel and wheel.pressed and wheel.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_to = clampf(_zoom_to + (0.2 if wheel.button_index == MOUSE_BUTTON_WHEEL_UP else -0.2), 0.0, 1.0))
	return column


func _name_row() -> Control:
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 10)
	line.add_child(Hud.make_label("Name", 16, Color.WHITE))
	_name.custom_minimum_size = Vector2(220, 36)
	_name.max_length = 16
	_name.text_submitted.connect(func(_text: String) -> void: _on_create())
	line.add_child(_name)
	var dice := Button.new()
	dice.text = "Random"
	dice.focus_mode = Control.FOCUS_NONE
	dice.pressed.connect(func() -> void: _name.text = _random_name())
	line.add_child(dice)
	var make := Button.new()
	make.text = "Create Character"
	make.custom_minimum_size = Vector2(200, 40)
	make.focus_mode = Control.FOCUS_NONE
	make.pressed.connect(_on_create)
	line.add_child(make)
	line.add_child(_error)
	return line


func _on_create() -> void:
	_error.text = create(_name.text)


func _refresh() -> void:
	for gender: String in _gender_buttons:
		(_gender_buttons[gender] as Button).button_pressed = look.gender == gender
	_beard_row.visible = (CharacterModel.LOOKS[look.gender].beard as Array).size() > 1
	for key: String in _values:
		var entry: Array = _values[key]
		var options: Array = (entry[1] as Callable).call()
		look[key] = clampi(int(look.get(key, 0)), 0, options.size() - 1)
		(entry[0] as Label).text = options[look[key]][0]
	for old in _pivot.get_children():
		old.queue_free()
	for each: ClassData in _class_buttons:
		(_class_buttons[each] as Button).set_pressed_no_signal(each == hero_class)
	_class_text.text = hero_class.description
	var hero := CharacterModel.create_hero(look.merged({"outfit": hero_class.outfit}), hero_class.glow_color,
			hero_class.starting_weapon.weapon_model)
	_pivot.add_child(hero)
	_skeleton = hero.find_children("*", "Skeleton3D", true, false)[0]


func _random_name() -> String:
	return (NAMES[look.gender] as Array).pick_random()
