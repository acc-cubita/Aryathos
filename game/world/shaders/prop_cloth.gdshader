shader_type spatial;
render_mode cull_disabled;
// Tent canvas, banners and pennants (world/props.gd): scanned linen dyed by `tint` (see
// prop_surface.gdshaderinc), lit from either side, and rippling in the wind more the
// farther the cloth hangs from where it is tied (UV2.x: 0 at the pole, 1 at the free edge).

#include "res://world/shaders/prop_surface.gdshaderinc"

uniform float sway = 0.0;
uniform float translucency = 0.35;

void vertex() {
	float free = UV2.x;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float wave = sin(TIME * 2.6 - VERTEX.x * 3.2 + VERTEX.y * 1.3 + origin.x) * 0.7 + sin(TIME * 4.1 - VERTEX.x * 5.0 + origin.z) * 0.3;
	VERTEX.z += wave * sway * free;
	object_position = VERTEX;
	object_normal = NORMAL;
}

void fragment() {
	Surface s = prop_surface();
	vec3 n = FRONT_FACING ? s.normal : -s.normal;
	ALBEDO = s.albedo;
	NORMAL = normalize(mat3(VIEW_MATRIX) * (MODEL_NORMAL_MATRIX * n));
	ROUGHNESS = max(s.rough, 0.7);
	AO = s.ao;
	AO_LIGHT_AFFECT = 0.3;
	BACKLIGHT = s.albedo * translucency;
	SPECULAR = 0.2;
}
