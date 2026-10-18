class_name FactionData
extends Resource
## A faction the player can earn reputation with. Add new ones as .tres files in data/factions/.

enum Standing { HATED, HOSTILE, UNFRIENDLY, NEUTRAL, FRIENDLY, HONORED, REVERED, EXALTED }

const STANDING_NAMES: Array[String] = [
	"Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted",
]
## Reputation needed for each standing: WoW's ladder, shortened for this prototype.
const THRESHOLDS: Array[int] = [-6000, -3000, -1000, 0, 500, 1500, 3500, 7000]
const STANDING_COLORS: Array[Color] = [
	Color(0.8, 0.13, 0.13), Color(0.9, 0.3, 0.1), Color(0.93, 0.45, 0.1), Color(0.9, 0.8, 0.1),
	Color(0.2, 0.75, 0.2), Color(0.1, 0.8, 0.45), Color(0.1, 0.75, 0.65), Color(0.1, 0.8, 0.85),
]
## Merchants of a faction give this discount at each standing.
const DISCOUNTS: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.05, 0.10, 0.15, 0.20]

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""


static func standing_for(value: int) -> int:
	var standing := 0
	for i in THRESHOLDS.size():
		if value >= THRESHOLDS[i]:
			standing = i
	return standing


## Reputation at the start and at the end of a standing (for progress bars).
static func standing_range(standing: int) -> Vector2i:
	var top := THRESHOLDS[standing + 1] if standing + 1 < THRESHOLDS.size() else THRESHOLDS[standing] + 1000
	return Vector2i(THRESHOLDS[standing], top)
