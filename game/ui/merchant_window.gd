class_name MerchantWindow
extends GameWindow
## A merchant's goods (opens when you right-click a vendor NPC, together with
## your bags). Click a row to buy; click items in your bags to sell them.

const CLOSE_DISTANCE := 8.0

var _player: Player
var _bags: BagWindow
var _npc: Npc
var _rows := VBoxContainer.new()


func _init() -> void:
	super("Merchant")


func setup(player: Player, bags: BagWindow) -> void:
	_player = player
	_bags = bags
	_rows.add_theme_constant_override("separation", 6)
	content.add_child(_rows)
	var sell_junk := Button.new()
	sell_junk.text = "Sell All Junk"
	sell_junk.focus_mode = Control.FOCUS_NONE
	sell_junk.pressed.connect(_sell_junk)
	content.add_child(sell_junk)
	content.add_child(Hud.make_label("Click items in your bags to sell them.", 12, Color(0.65, 0.65, 0.65)))
	Game.npc_interacted.connect(_on_npc_interacted)
	player.reputation_changed.connect(func() -> void:
		if is_trading():
			_show_goods())


func is_trading() -> bool:
	return visible and _npc != null


func _on_npc_interacted(npc: Npc) -> void:
	if npc.vendor_items.is_empty():
		return
	_npc = npc
	set_title(npc.unit_name)
	_show_goods()
	visible = true
	if not _bags.visible:
		_bags.toggle()


## One row per item: icon, name (and faction requirement), price after discount.
func _show_goods() -> void:
	for child in _rows.get_children():
		child.queue_free()
	for item in _npc.vendor_items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var slot := ItemSlot.new(40)
		slot.item = item
		slot.clicked.connect(_player.buy.bind(item, _npc))
		row.add_child(slot)
		var names := VBoxContainer.new()
		names.custom_minimum_size.x = 200
		names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		names.add_theme_constant_override("separation", 0)
		names.add_child(Hud.make_label(item.display_name, 14, item.quality_color()))
		if item.required_faction:
			var met := _player.standing_with(item.required_faction) >= item.required_standing
			names.add_child(Hud.make_label("Requires %s" % FactionData.STANDING_NAMES[item.required_standing], 11, Color(0.3, 1, 0.4) if met else Color(1, 0.3, 0.25)))
		row.add_child(names)
		var price := HBoxContainer.new()
		price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		BagWindow.add_coins(price, _player.price_for(item, _npc))
		row.add_child(price)
		_rows.add_child(row)


func _process(_delta: float) -> void:
	if visible and (_npc == null or _player.is_dead or _player.global_position.distance_to(_npc.global_position) > CLOSE_DISTANCE):
		visible = false
		_npc = null


## Sells every gray (poor quality) item in the bags.
func _sell_junk() -> void:
	for i in Player.BAG_SIZE:
		var item := _player.bags[i]
		if item and item.quality == ItemData.Quality.POOR:
			_player.sell_bag_slot(i)
