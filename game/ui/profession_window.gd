class_name ProfessionWindow
extends GameWindow
## Professions (K): your skill in each profession. For crafting professions it
## lists every recipe, colored by difficulty, with its reagents and a Create button.

var _player: Player
var _list := VBoxContainer.new()


func _init() -> void:
	super("Professions")


func setup(player: Player) -> void:
	_player = player
	_list.add_theme_constant_override("separation", 8)
	_list.custom_minimum_size.x = 430
	content.add_child(_list)
	player.professions_changed.connect(refresh)
	player.inventory_changed.connect(func() -> void:
		if visible:
			refresh())


func refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	var known := Database.professions().filter(func(p: ProfessionData) -> bool: return _player.knows_profession(p))
	if known.is_empty():
		var hint := Hud.make_label("You have not learned a profession yet.\nVisit Herbalist Mira at the Wardstone.", 14, Color(0.8, 0.8, 0.8))
		_list.add_child(hint)
		return
	for profession: ProfessionData in known:
		var skill := _player.profession_skill(profession)
		_list.add_child(Hud.make_label(profession.display_name, 17, Hud.GOLD))
		var bar := StatBar.new(Color(0.2, 0.45, 0.85), 16, 11)
		bar.show_values(skill, profession.max_skill, "Skill  %d / %d" % [skill, profession.max_skill])
		_list.add_child(bar)
		if profession.kind == ProfessionData.Kind.CRAFTING:
			for recipe in Database.recipes():
				if recipe.profession == profession:
					_list.add_child(_recipe_row(recipe, skill))
		else:
			for node in Database.gather_nodes():
				if node.profession == profession:
					var color := ProfessionData.DIFFICULTY_COLORS[ProfessionData.difficulty(skill, node.required_skill)] if skill >= node.required_skill else Color(0.8, 0.25, 0.2)
					_list.add_child(Hud.make_label("  %s  (skill %d)" % [node.display_name, node.required_skill], 13, color))


func _recipe_row(recipe: RecipeData, skill: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var icon := ItemSlot.new(40)
	icon.item = recipe.product
	icon.count = recipe.product_count
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	var learned := skill >= recipe.required_skill
	var color := ProfessionData.DIFFICULTY_COLORS[ProfessionData.difficulty(skill, recipe.required_skill)] if learned else Color(0.8, 0.25, 0.2)
	text.add_child(Hud.make_label(recipe.product.display_name + ("" if learned else "  (requires %d)" % recipe.required_skill), 14, color))
	var parts := PackedStringArray()
	for i in recipe.reagents.size():
		parts.append("%s %d/%d" % [recipe.reagents[i].display_name, _player.count_item(recipe.reagents[i]), recipe.reagent_counts[i]])
	text.add_child(Hud.make_label(", ".join(parts), 12, Color(0.8, 0.8, 0.8)))
	row.add_child(text)
	var create := Button.new()
	create.text = "Create"
	create.focus_mode = Control.FOCUS_NONE
	create.disabled = _player.craft_block_reason(recipe) != ""
	create.pressed.connect(_player.craft.bind(recipe))
	row.add_child(create)
	return row
