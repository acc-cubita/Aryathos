extends Node
## Graphics settings (Esc > Graphics): the window, frame rate and render scale, and the
## quality of anti-aliasing, shadows, ambient occlusion, glow, grass and detail, set from
## a preset (Low to Ultra) or one by one. Applied to the window at start and to each zone
## when it is ready (its sky light, sun and grass); kept in user://settings.cfg [graphics].
## Tests and tools run on the defaults (High) with their own file; --graphics=<Preset>
## starts on a preset, to measure it.

signal changed

## setting: [shown name, option names]
const OPTIONS := {
	"window": ["Window", ["Windowed", "Borderless", "Fullscreen"]],
	"vsync": ["V-Sync", ["Off", "On"]],
	"max_fps": ["Frame limit", ["30", "60", "120", "144", "None"]],
	"fps_counter": ["Frame rate counter", ["Off", "On"]],
	"scale": ["Render scale", ["50%", "60%", "70%", "80%", "90%", "100%"]],
	"aa": ["Anti-aliasing", ["Off", "FXAA", "MSAA 2x", "MSAA 4x", "TAA"]],
	"shadows": ["Shadows", ["Off", "Low", "Medium", "High", "Ultra"]],
	"ao": ["Ambient occlusion", ["Off", "SSAO", "SSAO + bounce light"]],
	"glow": ["Glow", ["Off", "On"]],
	"grass": ["Grass distance", ["Off", "Near", "Medium", "Far"]],
	"detail": ["Model detail", ["Low", "Medium", "High"]],
}
## What a preset sets (the quality settings); the others are left as they are.
const PRESETS := {
	"Low": {"scale": 3, "aa": 1, "shadows": 1, "ao": 0, "glow": 1, "grass": 1, "detail": 0},
	"Medium": {"scale": 5, "aa": 2, "shadows": 2, "ao": 1, "glow": 1, "grass": 2, "detail": 1},
	"High": {"scale": 5, "aa": 3, "shadows": 3, "ao": 2, "glow": 1, "grass": 2, "detail": 2},
	"Ultra": {"scale": 5, "aa": 3, "shadows": 4, "ao": 2, "glow": 1, "grass": 3, "detail": 2},
}
const DEFAULTS := {"window": 0, "vsync": 1, "max_fps": 4, "fps_counter": 0, "scale": 5, "aa": 3, "shadows": 3,
		"ao": 2, "glow": 1, "grass": 2, "detail": 2}
const WINDOW_MODES := [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
const FRAME_LIMITS := [30, 60, 120, 144, 0]
const SCALES := [0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
## Shadows (Low and up): [atlas size, soft filter, sun shadow distance (m), 4 splits]
const SHADOWS := [[], [2048, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, 60.0, false],
		[4096, RenderingServer.SHADOW_QUALITY_SOFT_LOW, 100.0, true],
		[4096, RenderingServer.SHADOW_QUALITY_SOFT_LOW, 140.0, true],
		[8192, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, 200.0, true]]
const GRASS_RADII := [0.0, 18.0, 30.0, 45.0]
## Mesh LOD threshold: higher swaps to simpler meshes sooner.
const LOD_THRESHOLDS := [4.0, 2.0, 1.0]

var settings := DEFAULTS.duplicate()

var _file := "user://settings.cfg"
var _counter := Label.new()


func _ready() -> void:
	if Game.testing:
		_file = "user://settings_test.cfg"
	else:
		var config := ConfigFile.new()
		config.load(_file)
		for key: String in DEFAULTS:
			settings[key] = clampi(int(config.get_value("graphics", key, DEFAULTS[key])), 0, OPTIONS[key][1].size() - 1)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--graphics="):
			settings.merge(PRESETS[arg.get_slice("=", 1)], true)
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_counter.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_counter.offset_left = -90.0
	_counter.offset_right = -8.0
	_counter.offset_top = 4.0
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counter.add_theme_font_size_override("font_size", 14)
	_counter.add_theme_constant_override("outline_size", 4)
	_counter.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(_counter)
	for key: String in settings:
		_apply(key)
	Game.zone_ready.connect(func() -> void:
		for key: String in ["shadows", "ao", "glow", "grass"]:
			_apply(key))


func _process(_delta: float) -> void:
	if _counter.visible and Engine.get_process_frames() % 20 == 0:
		_counter.text = "%d fps" % Engine.get_frames_per_second()


func get_setting(key: String) -> int:
	return settings[key]


## Changes one setting, applies and keeps it.
func set_setting(key: String, value: int) -> void:
	settings[key] = clampi(value, 0, OPTIONS[key][1].size() - 1)
	_apply(key)
	_save()
	changed.emit()


## Sets every quality setting from a preset (PRESETS key).
func use_preset(preset: String) -> void:
	settings.merge(PRESETS[preset], true)
	for key: String in PRESETS[preset]:
		_apply(key)
	_save()
	changed.emit()


## The preset the quality settings match, or "Custom".
func preset_name() -> String:
	for preset: String in PRESETS:
		if (PRESETS[preset] as Dictionary).keys().all(func(key: String) -> bool: return settings[key] == PRESETS[preset][key]):
			return preset
	return "Custom"


func _save() -> void:
	var config := ConfigFile.new()
	config.load(_file)
	for key: String in settings:
		config.set_value("graphics", key, settings[key])
	config.save(_file)


func _apply(key: String) -> void:
	var value: int = settings[key]
	var viewport := get_viewport()
	match key:
		"window":
			if not Game.testing:  # tools keep their window
				DisplayServer.window_set_mode(WINDOW_MODES[value])
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value == 1 else DisplayServer.VSYNC_DISABLED)
		"max_fps":
			Engine.max_fps = FRAME_LIMITS[value]
		"fps_counter":
			_counter.visible = value == 1
		"scale":
			viewport.scaling_3d_scale = SCALES[value]
			# AMD FSR 1 sharpens what is upscaled; at full size plain is the same and cheaper
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if SCALES[value] < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
		"aa":
			viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X,
					Viewport.MSAA_DISABLED][value]
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if value == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
			viewport.use_taa = value == 4
		"detail":
			viewport.mesh_lod_threshold = LOD_THRESHOLDS[value]
		"shadows":
			var spec: Array = SHADOWS[value]
			if value > 0:
				RenderingServer.directional_shadow_atlas_set_size(spec[0], true)
				RenderingServer.directional_soft_shadow_filter_set_quality(spec[1])
			var sun := _zone_node("Sun") as DirectionalLight3D
			if sun:
				sun.shadow_enabled = value > 0
				if value > 0:
					sun.directional_shadow_max_distance = spec[2]
					sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if spec[3] \
							else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		"ao":
			var environment := _environment()
			if environment:
				environment.ssao_enabled = value >= 1
				environment.ssil_enabled = value >= 2
		"glow":
			var environment := _environment()
			if environment:
				environment.glow_enabled = value == 1
		"grass":
			var grass := _zone_node("Grass") as GrassField
			if grass:
				grass.set_radius(GRASS_RADII[value])


func _zone_node(path: String) -> Node:
	return Game.zone.get_node_or_null(path) if is_instance_valid(Game.zone) else null


func _environment() -> Environment:
	var world := _zone_node("WorldEnvironment") as WorldEnvironment
	return world.environment if world else null
