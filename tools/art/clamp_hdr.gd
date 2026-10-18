extends SceneTree
## Prepares a Poly Haven sky HDRI for the game: clamps the sun disc (thousands of times
## brighter than the sky) so the sky's ambient light does not double the DirectionalLight
## sun, and saves it as EXR next to the source. Prints where the sun is.
##   Godot --headless --path game --script ../tools/art/clamp_hdr.gd -- <res:// source.hdr> [max]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var source: String = args[0]
	var limit := float(args[1]) if args.size() > 1 else 40.0
	var img := Image.load_from_file(source)
	img.convert(Image.FORMAT_RGBF)
	var size := img.get_size()
	var data := img.get_data().to_float32_array()
	var brightest := 0.0
	var sun := 0
	for i in range(0, data.size(), 3):
		var l := data[i] + data[i + 1] + data[i + 2]
		if l > brightest:
			brightest = l
			sun = i / 3
		if l > limit * 3.0:
			var k := limit * 3.0 / l
			data[i] *= k
			data[i + 1] *= k
			data[i + 2] *= k
	var out := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBF, data.to_byte_array())
	var target := source.get_basename() + "_clamped.exr"
	out.save_exr(ProjectSettings.globalize_path(target), false)
	var u := float(sun % size.x) / size.x
	var v := float(sun / size.x) / size.y
	print("saved %s; sun at u %.4f v %.4f (elevation %.1f deg)" % [target, u, v, 90.0 - v * 180.0])
	quit()
