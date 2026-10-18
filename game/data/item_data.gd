class_name ItemData
extends Resource
## An item: junk, armor, a weapon or a consumable (potion). Add new ones as
## .tres files in data/items/.

enum Quality { POOR, COMMON, UNCOMMON, RARE, EPIC }
enum UseEffect { NONE, HEAL, RESTORE_MANA }
enum Slot { NONE, WEAPON, HEAD, CHEST, HANDS, LEGS, FEET, NECK, SHOULDERS, BACK, WRIST, WAIST, FINGER, TRINKET, OFF_HAND }

## WoW quality colors: gray, white, green, blue, purple.
const QUALITY_COLORS: Array[Color] = [
	Color(0.62, 0.62, 0.62), Color(1, 1, 1), Color(0.12, 1, 0), Color(0, 0.44, 0.87), Color(0.64, 0.21, 0.93),
]
const SLOT_NAMES: Array[String] = [
	"", "Main Hand", "Head", "Chest", "Hands", "Legs", "Feet",
	"Neck", "Shoulders", "Back", "Wrist", "Waist", "Finger", "Trinket", "Off Hand",
]

@export var id: StringName
@export var display_name := ""
@export_multiline var flavor_text := ""
@export var quality := Quality.COMMON
@export var slot := Slot.NONE
@export var icon: Texture2D
## Shown in item slots while there is no icon texture.
@export var icon_color := Color(0.5, 0.5, 0.5)
@export var icon_glyph := "?"

@export_group("Stats")
@export var health_bonus := 0
@export var mana_bonus := 0
@export var spell_power := 0
## Weapons only.
@export var min_damage := 0
@export var max_damage := 0

@export_group("Trade")
## Copper a merchant pays for one; 0 = merchants will not buy it.
@export var sell_price := 0
## Copper it costs at a merchant.
@export var buy_price := 0
## How many fit in one bag slot.
@export var max_stack := 1
## Merchants only sell this to players with at least this standing with the faction.
@export var required_faction: FactionData
@export var required_standing: FactionData.Standing = FactionData.Standing.NEUTRAL

@export_group("Use")
@export var use_effect := UseEffect.NONE
@export var use_amount := 0
@export var use_cooldown := 0.0
## Items in the same group share a cooldown (like all potions in WoW). Empty = the item's id.
@export var cooldown_group: StringName


func is_usable() -> bool:
	return use_effect != UseEffect.NONE


func cooldown_key() -> StringName:
	return cooldown_group if cooldown_group != &"" else id


func quality_color() -> Color:
	return QUALITY_COLORS[quality]


## Tooltip lines after the name (slot, damage, stats, flavor text).
func detail_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if slot != Slot.NONE:
		lines.append(SLOT_NAMES[slot])
	if slot == Slot.WEAPON:
		lines.append("%d - %d Damage" % [min_damage, max_damage])
	if health_bonus:
		lines.append("+%d Health" % health_bonus)
	if mana_bonus:
		lines.append("+%d Mana" % mana_bonus)
	if spell_power:
		lines.append("+%d Spell Power" % spell_power)
	if use_effect == UseEffect.HEAL:
		lines.append("Use: Restores %d health." % use_amount)
	elif use_effect == UseEffect.RESTORE_MANA:
		lines.append("Use: Restores %d mana." % use_amount)
	if flavor_text != "":
		lines.append("\"%s\"" % flavor_text)
	if required_faction:
		lines.append("Requires %s - %s" % [required_faction.display_name, FactionData.STANDING_NAMES[required_standing]])
	if sell_price > 0:
		lines.append("Sell price: %s" % Game.format_money(sell_price))
	return lines
