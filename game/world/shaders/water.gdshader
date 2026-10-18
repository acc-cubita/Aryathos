shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;
// Lake surface: turquoise in the shallows, deep blue further out, soft foam where
// it meets the shore, and two ripple normal maps drifting in different directions.

uniform vec3 shallow_color : source_color = vec3(0.3, 0.68, 0.66);
uniform vec3 deep_color : source_color = vec3(0.05, 0.2, 0.36);
uniform vec3 foam_color : source_color = vec3(0.92, 0.97, 1.0);
// Meters of water before it looks fully deep.
uniform float depth_fade = 2.2;
uniform float foam_width = 0.45;
uniform float ripple_scale = 0.07;
uniform vec2 ripple_speed = vec2(0.018, 0.012);
uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	float water_depth = max(VERTEX.z - scene.z / scene.w, 0.0);
	float deep = clamp(water_depth / depth_fade, 0.0, 1.0);
	vec2 uv = world_position.xz * ripple_scale;
	vec3 ripples = mix(texture(ripple_a, uv + TIME * ripple_speed).rgb,
			texture(ripple_b, uv * 1.6 - TIME * ripple_speed.yx).rgb, 0.5);
	NORMAL_MAP = ripples;
	NORMAL_MAP_DEPTH = 0.5;
	float wave = sin(TIME * 1.4 + world_position.x * 0.7 + world_position.z * 0.5) * 0.08;
	float foam = 1.0 - smoothstep(0.0, foam_width, water_depth + wave);
	ALBEDO = mix(mix(shallow_color, deep_color, deep), foam_color, foam * 0.75);
	ALPHA = clamp(mix(0.5, 0.94, deep) + foam * 0.35, 0.0, 1.0);
	ROUGHNESS = 0.05;
	SPECULAR = 0.6;
}
