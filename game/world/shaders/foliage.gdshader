shader_type spatial;
// Tree crowns and bushes. The mesh stores ambient occlusion in UV.x (dark inside and
// underneath, bright at the sunny tips) and soft, rounded normals; the leaf pattern is
// projected in world space and tinted with each tree's instance color. Crowns sway
// gently in the wind, more toward the top.

uniform sampler2D leaf_texture : filter_linear_mipmap, repeat_enable;
uniform float leaf_scale = 0.55;
uniform float wind_strength = 0.035;
uniform vec2 wind_direction = vec2(0.8, 0.6);
uniform float brightness = 1.15;

varying vec3 world_position;
varying vec3 world_normal;
varying float occlusion;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sway = sin(TIME * 1.2 + origin.x * 0.21 + origin.z * 0.17) + 0.35 * sin(TIME * 2.3 + origin.z * 0.5);
	VERTEX.xz += normalize(wind_direction) * sway * wind_strength * max(VERTEX.y - 1.0, 0.0);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	occlusion = UV.x;
}

void fragment() {
	vec3 w = pow(abs(world_normal), vec3(3.0));
	w /= w.x + w.y + w.z;
	vec3 p = world_position * leaf_scale;
	float leaves = texture(leaf_texture, p.zy).g * w.x + texture(leaf_texture, p.xz).g * w.y + texture(leaf_texture, p.xy).g * w.z;
	// Instance colors are picked in sRGB like every other color in the editor.
	vec3 tint = pow(COLOR.rgb, vec3(2.2));
	ALBEDO = tint * mix(0.55, 1.35, leaves) * occlusion * brightness;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
