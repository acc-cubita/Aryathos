class_name AbilityData
extends Resource
## One ability (spell or attack). Add new ones as .tres files in data/abilities/.

enum Effect { DAMAGE, HEAL }
enum Targeting { HOSTILE, FRIENDLY_OR_SELF, AREA_AROUND_SELF }
## How a missile looks: a glowing orb, a flying crystal shard, or a lightning bolt.
enum ProjectileStyle { ORB, SHARD, BOLT }

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
## Shown on the action button while there is no icon texture.
@export var icon_color := Color(0.4, 0.4, 0.8)
@export var icon_glyph := "?"

@export_group("Rules")
@export var effect := Effect.DAMAGE
@export var targeting := Targeting.HOSTILE
@export var cast_time := 0.0
@export var cooldown := 0.0
@export var mana_cost := 0
@export var max_range := 30.0
@export var triggers_gcd := true
@export var starts_auto_attack := false

@export_group("Power")
@export var min_amount := 10
@export var max_amount := 15
@export var color := Color.WHITE
## 0 = lands instantly; otherwise a missile flies to the target at this speed (m/s).
@export var projectile_speed := 0.0
@export var projectile_style := ProjectileStyle.ORB
## AREA_AROUND_SELF only: every enemy this close (meters) is hit.
@export var radius := 0.0


## A blow of the weapon (or claws) in hand: damage dealt at arm's length, no missile, no area.
func is_weapon_blow() -> bool:
	return effect == Effect.DAMAGE and projectile_speed <= 0.0 and radius <= 0.0 and max_range <= 5.0
