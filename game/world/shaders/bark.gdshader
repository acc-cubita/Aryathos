shader_type spatial;
// Tree trunks and branches with scanned bark (art/textures/bark, packed by
// tools/art/terrain_pbr.py: *_nrao = normal xy, roughness, occlusion). Sways with the
// crown (tree_leaves.gdshader) so leaves stay on their branches.

uniform sampler2D bark_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_nrao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wind_strength = 0.05;
uniform vec2 wind_direction = vec2(0.8, 0.6);

float gust(vec3 origin) {
	return sin(TIME * 0.9 + origin.x * 0.13 + origin.z * 0.11) * 0.7 + sin(TIME * 2.1 + origin.z * 0.37) * 0.3;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	VERTEX.xz += normalize(wind_direction) * gust(origin) * wind_strength * max(VERTEX.y - 1.0, 0.0);
}

void fragment() {
	vec4 surface = texture(bark_nrao, UV);
	ALBEDO = texture(bark_albedo, UV).rgb;
	NORMAL_MAP = vec3(surface.rg, 1.0);
	ROUGHNESS = surface.b;
	AO = surface.a;
	AO_LIGHT_AFFECT = 0.3;
	SPECULAR = 0.3;
}
