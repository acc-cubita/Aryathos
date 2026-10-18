class_name BagWindow
extends GameWindow
## The backpack (B): 16 slots and your money. Click gear to equip it, click a
## potion to drink it, or sell either while a merchant is open. Drag potions onto
## the action bar.

var _player: Player
var _slots: Array[ItemSlot] = []
var _free := Hud.make_label("", 13, Color(0.8, 0.8, 0.8))
var _money := HBoxContainer.new()
## Set by the HUD: while trading, clicking a bag slot sells it.
var merchant: MerchantWindow


func _init() -> void:
	super("Backpack", Side.RIGHT)


func setup(player: Player) -> void:
	_player = player
	var grid := GridContainer.new()
	grid.columns = 4
	for i in Player.BAG_SIZE:
		var slot := ItemSlot.new()
		slot.drag_source = true
		slot.clicked.connect(_on_slot_clicked.bind(i))
		grid.add_child(slot)
		_slots.append(slot)
	content.add_child(grid)
	var footer := HBoxContainer.new()
	_free.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_free)
	footer.add_child(_money)
	content.add_child(footer)
	player.inventory_changed.connect(refresh)
	refresh()


func refresh() -> void:
	for i in _slots.size():
		_slots[i].item = _player.bags[i]
		_slots[i].count = _player.bag_counts[i]
	_free.text = "%d free" % _player.bags.count(null)
	for child in _money.get_children():
		child.queue_free()
	add_coins(_money, _player.money)


func _on_slot_clicked(index: int) -> void:
	if merchant and merchant.is_trading():
		_player.sell_bag_slot(index)
	else:
		_player.use_bag_slot(index)


## Money the WoW way: amounts followed by gold, silver and copper coin letters.
static func add_coins(box: HBoxContainer, copper: int) -> void:
	var coins := [[copper / 10000, "g", Color(1, 0.82, 0)], [copper / 100 % 100, "s", Color(0.8, 0.82, 0.88)], [copper % 100, "c", Color(0.85, 0.5, 0.25)]]
	for coin: Array in coins:
		if coin[0] > 0 or (coin[1] == "c" and copper == 0):
			box.add_child(Hud.make_label("%d" % coin[0], 14, Color.WHITE))
			box.add_child(Hud.make_label(coin[1] + " ", 14, coin[2]))
