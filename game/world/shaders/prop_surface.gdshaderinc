// Shared by prop.gdshader and prop_cloth.gdshader. A scanned surface (art/textures/props_pbr
// or art/textures/bark, packed by tools/art/terrain_pbr.py: *_nrao = normal xy, roughness,
// occlusion) projected from three sides in the prop's own space, so it stays put on the prop
// and needs no UVs. The textures' grain runs along U; `grain_axis` lays it along a prop axis.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrao_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
// Texture repeats per meter.
uniform float scale = 1.0;
// The prop axis the grain follows: 0 = X, 1 = Y (poles), 2 = Z (rails).
uniform int grain_axis = 1;

varying vec3 object_position;
varying vec3 object_normal;

struct Surface {
	vec3 albedo;
	vec3 normal;  // prop space
	float rough;
	float ao;
};

float component(vec3 v, int i) {
	return i == 0 ? v.x : (i == 1 ? v.y : v.z);
}

vec3 unit(int i) {
	return i == 0 ? vec3(1.0, 0.0, 0.0) : (i == 1 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0));
}

// One projection along axis `a`, weighted by w: U runs along the grain where the grain lies
// in this plane, and the normal map bends the surface along the same two axes.
void project(int a, float w, inout vec4 albedo, inout vec4 maps, inout vec3 bend) {
	if (w < 0.001) {
		return;
	}
	int u = grain_axis != a ? grain_axis : (a + 1) % 3;
	int v = 3 - a - u;
	vec2 uv = vec2(component(object_position, u), -component(object_position, v)) * scale;
	vec4 m = texture(nrao_texture, uv);
	albedo += texture(albedo_texture, uv) * w;
	maps += m * w;
	vec2 xy = m.rg * 2.0 - 1.0;
	bend += (unit(u) * xy.x + unit(v) * xy.y) * w;
}

Surface prop_surface() {
	vec3 n = normalize(object_normal);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec4 albedo = vec4(0.0);
	vec4 maps = vec4(0.0);
	vec3 bend = vec3(0.0);
	project(0, w.x, albedo, maps, bend);
	project(1, w.y, albedo, maps, bend);
	project(2, w.z, albedo, maps, bend);
	Surface s;
	s.albedo = albedo.rgb * tint;
	s.normal = normalize(n + bend);
	s.rough = maps.b;
	s.ao = maps.a;
	return s;
}
