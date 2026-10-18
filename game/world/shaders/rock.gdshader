shader_type spatial;
// Boulders and carved stone. Rock texture projected from three sides, tinted by the
// instance color, with moss creeping over the faces that look up.

uniform sampler2D rock_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_scale = 0.35;
uniform float moss_scale = 0.4;
// 0 = no moss, 1 = moss on every upward face.
uniform float moss_amount : hint_range(0.0, 1.0) = 0.55;
uniform vec3 moss_tint : source_color = vec3(0.75, 0.9, 0.62);

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 w = pow(abs(world_normal), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec3 p = world_position * rock_scale;
	vec4 rock = texture(rock_texture, p.zy) * w.x + texture(rock_texture, p.xz) * w.y + texture(rock_texture, p.xy) * w.z;
	vec3 moss = texture(moss_texture, world_position.xz * moss_scale).rgb * moss_tint;
	float up = world_normal.y + (rock.a - 0.5) * 0.4;
	float moss_mask = smoothstep(1.0 - moss_amount * 0.6, 1.05 - moss_amount * 0.45, up) * step(0.01, moss_amount);
	ALBEDO = mix(rock.rgb * pow(COLOR.rgb, vec3(2.2)), moss, moss_mask);
	ROUGHNESS = 0.9;
	SPECULAR = 0.3;
}
