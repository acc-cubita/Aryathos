shader_type spatial;
render_mode cull_disabled;
// Tree crowns, bushes and conifer sprays: alpha-tested cards carrying scanned leaves or
// needle sprays (art/textures/foliage, made by tools/art/foliage_cards.py; meshes by
// tools/art/blender/trees.py). UV2 = (shade, phase): shade darkens the inside and
// underside of the crown, phase staggers each card's flutter. The instance colour tints
// each tree a little differently. Card normals point out of the crown on both sides,
// so a crown shades as one leafy volume and glows where the sun shines through it.

uniform sampler2D leaf_atlas : source_color, filter_linear_mipmap_anisotropic;
uniform float alpha_cutoff = 0.42;
uniform vec3 shade_dark : source_color = vec3(0.32, 0.38, 0.3);
uniform float translucency = 0.55;
uniform float wind_strength = 0.05;
uniform float flutter = 0.03;
uniform vec2 wind_direction = vec2(0.8, 0.6);

varying float shade;

// Slow sway of the whole tree, stronger higher up (bark.gdshader moves the same way).
float gust(vec3 origin) {
	return sin(TIME * 0.9 + origin.x * 0.13 + origin.z * 0.11) * 0.7 + sin(TIME * 2.1 + origin.z * 0.37) * 0.3;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float height = max(VERTEX.y - 1.0, 0.0);
	VERTEX.xz += normalize(wind_direction) * gust(origin) * wind_strength * height;
	VERTEX += NORMAL * sin(TIME * 5.0 + UV2.y * 40.0 + origin.x) * flutter * min(height, 3.0);
	shade = UV2.x;
}

void fragment() {
	vec4 leaf = texture(leaf_atlas, UV);
	ALBEDO = leaf.rgb * COLOR.rgb * mix(shade_dark, vec3(1.0), shade);
	ALPHA = leaf.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ALPHA_ANTIALIASING_EDGE = 0.25;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(leaf_atlas, 0));
	// two-sided cards keep the crown's outward normal on their back too
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	BACKLIGHT = ALBEDO * translucency;
	AO = mix(0.55, 1.0, shade);
	AO_LIGHT_AFFECT = 0.2;
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
}
