class_name ZoneExit
extends Area3D
## A way out of the zone (a mountain pass, a road's end). Walking into it takes the player
## to `target_zone`, arriving at that zone's Arrivals/<arrival> marker. The destination's
## name floats over the way.

@export_file("*.tscn") var target_zone := ""
@export var arrival := ""
@export var radius := 6.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = Unit.LAYER_UNITS
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 12.0
	var body := CollisionShape3D.new()
	body.shape = shape
	body.position.y = 4.0
	add_child(body)
	var sign_text := Label3D.new()
	sign_text.text = target_zone.get_file().get_basename().capitalize()
	sign_text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_text.font_size = 64
	sign_text.pixel_size = 0.01
	sign_text.modulate = Color(1.0, 0.85, 0.45)
	sign_text.outline_size = 12
	sign_text.position.y = 4.0
	sign_text.visibility_range_end = 60.0
	add_child(sign_text)
	body_entered.connect(func(entered: Node3D) -> void:
		var hero := entered as Player
		if hero and not hero.is_dead:
			Game.travel(target_zone, arrival))
