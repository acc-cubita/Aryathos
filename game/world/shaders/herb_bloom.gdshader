shader_type spatial;
render_mode cull_disabled;
// Herb blooms on gather nodes (world/gather_node.gd): white petal cards from
// art/textures/foliage/herbs.png dyed in the herb's colour and glowing softly, so
// herbalists can spot them across a meadow. The golden stamens keep their colour.

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 bloom_color : source_color = vec3(1.0);
uniform float glow = 1.2;
uniform float alpha_cutoff = 0.45;

void fragment() {
	vec4 tex = texture(atlas, UV);
	float petal = smoothstep(0.55, 0.8, tex.b / max(tex.r, 0.01));
	ALBEDO = mix(tex.rgb, tex.rgb * bloom_color, petal);
	EMISSION = ALBEDO * glow * petal;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ALPHA_ANTIALIASING_EDGE = 0.25;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(atlas, 0));
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	BACKLIGHT = ALBEDO * 0.4;
	ROUGHNESS = 0.6;
	SPECULAR = 0.3;
}
