shader_type spatial;
// Scanned boulders and cliff faces (game/art/rocks, made by tools/art/blender/rocks.py):
// the scan's own colour and baked normals (*_nrao: normal xy, roughness, occlusion).
// Cliff skirts (UV2.x = 1), pushed back into the hill, take the terrain's rock instead of
// the scan. The colour is pulled toward one stone tone so every set matches the terrain
// rock, the instance colour varies it, and snow settles on ledges above the snow line.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D nrao_texture : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_scale = 0.18;
uniform float snow_scale = 0.3;
uniform float saturation = 0.75;
uniform vec3 stone_tone : source_color = vec3(0.6, 0.58, 0.55);
uniform float tone_amount : hint_range(0.0, 1.0) = 0.3;
// Snow starts at snow_line.x and covers the ledges from snow_line.y (meters), as on the terrain.
uniform vec2 snow_line = vec2(24.0, 32.0);

varying vec3 world_position;
varying vec3 world_normal;
varying vec3 world_tangent;
varying vec3 world_binormal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	world_tangent = normalize((MODEL_MATRIX * vec4(TANGENT, 0.0)).xyz);
	world_binormal = normalize((MODEL_MATRIX * vec4(BINORMAL, 0.0)).xyz);
}

vec3 unpack(vec2 rg) {
	vec2 xy = rg * 2.0 - 1.0;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

void fragment() {
	vec4 maps = texture(nrao_texture, UV);
	vec3 albedo = texture(albedo_texture, UV).rgb;
	vec3 t = unpack(maps.rg);
	vec3 n = normalize(world_tangent * t.x + world_binormal * t.y + world_normal * t.z);
	float rough = maps.b;
	float ao = maps.a;
	float skirt = UV2.x;
	if (skirt > 0.0) {
		vec3 w = pow(abs(world_normal), vec3(4.0));
		w /= w.x + w.y + w.z;
		vec3 p = world_position * rock_scale;
		vec4 rock = texture(rock_albedo, p.zy) * w.x + texture(rock_albedo, p.xz) * w.y + texture(rock_albedo, p.xy) * w.z;
		vec4 rm = texture(rock_nrao, p.zy) * w.x + texture(rock_nrao, p.xz) * w.y + texture(rock_nrao, p.xy) * w.z;
		albedo = mix(albedo, rock.rgb, skirt);
		n = normalize(mix(n, world_normal, skirt));
		rough = mix(rough, rm.b, skirt);
		ao = mix(ao, rm.a, skirt);
	}
	float luma = dot(albedo, vec3(0.3, 0.59, 0.11));
	albedo = mix(vec3(luma), albedo, saturation);
	albedo = mix(albedo, stone_tone * luma / dot(stone_tone, vec3(0.3, 0.59, 0.11)), tone_amount);
	albedo *= COLOR.rgb;
	float wobble = sin(world_position.x * 0.21) * sin(world_position.z * 0.17) * 3.0;
	float snow = smoothstep(snow_line.x, snow_line.y, world_position.y + wobble) * smoothstep(0.55, 0.8, n.y);
	if (snow > 0.0) {
		albedo = mix(albedo, texture(snow_albedo, world_position.xz * snow_scale).rgb, snow);
		n = normalize(mix(n, world_normal, snow * 0.6));
		rough = mix(rough, 0.75, snow);
	}
	ALBEDO = albedo;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = max(rough, 0.55);
	AO = ao;
	AO_LIGHT_AFFECT = 0.3;
	SPECULAR = 0.3;
}
