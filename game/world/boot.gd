extends Node
## The first scene: opens the zone the saved character is in (a new one starts in
## Game.START_ZONE) behind the loading screen.


func _ready() -> void:
	Game.open_zone.call_deferred(Game.saved_zone())
