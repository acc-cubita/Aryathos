class_name SoundWindow
extends GameWindow
## Sound (from the game menu): volume sliders for everything and for the music.
## Changes are heard at once and kept (Audio saves them).

const SLIDERS := [["Master", "Everything"], ["Music", "Music"]]


func _init() -> void:
	super("Sound", Side.CENTER)


func setup() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	for entry: Array in SLIDERS:
		var bus: String = entry[0]
		grid.add_child(Hud.make_label(entry[1], 15, Color.WHITE))
		var slider := HSlider.new()
		slider.custom_minimum_size = Vector2(220, 20)
		slider.min_value = 0.0
		slider.max_value = 100.0
		slider.step = 5.0
		slider.focus_mode = Control.FOCUS_NONE
		slider.value = Audio.get_volume(bus) * 100.0
		var percent := Hud.make_label("%d%%" % slider.value, 15, Hud.GOLD)
		percent.custom_minimum_size = Vector2(48, 0)
		slider.value_changed.connect(func(value: float) -> void:
			Audio.set_volume(bus, value / 100.0)
			percent.text = "%d%%" % value)
		grid.add_child(slider)
		grid.add_child(percent)
	content.add_child(grid)
