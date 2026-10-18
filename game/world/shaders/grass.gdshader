shader_type spatial;
render_mode cull_disabled, world_vertex_coords;
// Grass placed entirely on the GPU. grass_field.gd draws one fixed grid of clumps that
// follows the camera in whole grid steps. Each clump picks a stable random spot, turn and
// size from its world cell, looks up the ground height and how grassy the ground is,
// and bends in the wind. Clumps far from the camera shrink into the ground.

uniform sampler2D height_map : filter_linear;
// r = grass amount, g = lushness (see Terrain.make_grass_texture).
uniform sampler2D grass_map : filter_linear;
// The terrain's grass texture and tints (terrain.gdshader), so blades match the ground.
uniform sampler2D grass_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float grass_scale = 0.5;
uniform vec3 grass_dry : source_color = vec3(1.0, 0.97, 0.8);
uniform vec3 grass_lush : source_color = vec3(0.9, 1.08, 0.9);
uniform vec3 root_shade : source_color = vec3(0.42, 0.47, 0.36);
uniform vec3 tip_tint : source_color = vec3(1.15, 1.12, 0.82);
// How much single blades differ in brightness and hue.
uniform float blade_variation = 0.22;
// Texels per side of the maps (one per meter).
uniform float map_size = 301.0;
uniform float spacing = 0.45;
uniform float fade_start = 24.0;
uniform float fade_end = 32.0;
uniform float wind_strength = 0.16;
uniform vec2 wind_direction = vec2(0.8, 0.6);

varying float tip;
varying float blade;
varying float lushness;
varying vec2 ground_spot;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 cell = floor(origin.xz / spacing + 0.5);
	float r1 = hash(cell);
	float r2 = hash(cell + 17.31);
	float r3 = hash(cell + 41.97);
	float r4 = hash(cell + 73.13);
	vec2 spot = (cell + vec2(r1, r2) - 0.5) * spacing;
	vec2 map_uv = spot / map_size + 0.5;
	float ground = texture(height_map, map_uv).r;
	vec2 grass = texture(grass_map, map_uv).rg;
	float fade = 1.0 - smoothstep(fade_start, fade_end, distance(spot, CAMERA_POSITION_WORLD.xz));
	float size = step(r3, grass.r) * mix(0.5, 1.0, grass.r) * mix(0.75, 1.3, r4) * fade;
	vec3 local = (VERTEX - origin) * size;
	float angle = (r1 + r4) * 6.2832;
	mat2 turn = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle)));
	local.xz = turn * local.xz;
	NORMAL.xz = turn * NORMAL.xz;
	tip = UV.y;
	blade = UV.x;
	float sway = sin(TIME * 1.6 + dot(spot, wind_direction) * 0.3 + r4 * 2.0) * 0.6
			+ sin(TIME * 2.7 + spot.x * 0.8 + spot.y * 0.5) * 0.25 + 0.35;
	local.xz += normalize(wind_direction) * sway * wind_strength * tip * tip * size;
	VERTEX = vec3(spot.x, ground - 0.03, spot.y) + local;
	lushness = grass.g;
	ground_spot = spot;
}

void fragment() {
	// the ground's colour under the clump (a coarse mip, so blades are not speckled)
	vec3 ground = textureLod(grass_texture, ground_spot * grass_scale, 5.0).rgb * mix(grass_dry, grass_lush, lushness);
	vec3 color = ground * (1.0 + (blade - 0.5) * 2.0 * blade_variation);
	color.r *= 1.0 + (fract(blade * 7.31) - 0.5) * blade_variation;  // some blades yellower
	ALBEDO = color * mix(root_shade, tip_tint, tip);
	// mostly lit like the ground, a little by the blade's own facing (and sun shining through)
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(mix(up, NORMAL, 0.35));
	BACKLIGHT = ALBEDO * 0.5 * tip;
	AO = mix(0.55, 1.0, tip);
	AO_LIGHT_AFFECT = 0.5;
	ROUGHNESS = 0.7;
	SPECULAR = 0.25;
}
