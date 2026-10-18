shader_type spatial;
// Camp props built from simple shapes (world/props.gd): wood, planks, bark and carved
// stone with scanned surfaces (see prop_surface.gdshaderinc).

#include "res://world/shaders/prop_surface.gdshaderinc"

void vertex() {
	object_position = VERTEX;
	object_normal = NORMAL;
}

void fragment() {
	Surface s = prop_surface();
	ALBEDO = s.albedo;
	NORMAL = normalize(mat3(VIEW_MATRIX) * (MODEL_NORMAL_MATRIX * s.normal));
	ROUGHNESS = s.rough;
	AO = s.ao;
	AO_LIGHT_AFFECT = 0.3;
	SPECULAR = 0.3;
}
