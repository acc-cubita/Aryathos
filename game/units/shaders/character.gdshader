shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
// Hand-painted character (WoW style): the baked painting already holds its own
// shading, so scene light only modulates it; a small self-lit share keeps the
// palette true under the blue sky ambient, plus a soft rim to lift silhouettes.

uniform sampler2D paint : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D glow : source_color, filter_linear_mipmap;
uniform float glow_energy = 2.5;
uniform float self_lit = 0.22;
uniform vec3 rim_color : source_color = vec3(0.6, 0.72, 0.9);
uniform float rim_strength = 0.12;

void fragment() {
	vec3 color = texture(paint, UV).rgb;
	ALBEDO = color;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = texture(glow, UV).rgb * glow_energy + color * self_lit + rim_color * rim * rim_strength;
}
