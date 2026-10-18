shader_type spatial;
// Splat-mapped terrain with scanned PBR ground (packed by tools/art/terrain_pbr.py).
// Vertex color holds the layer weights painted by terrain.gd:
//   r = dirt (roads, camps), g = sand (shores), b = snow (peaks), a = grass lushness.
// Rock covers steep slopes. Each albedo's alpha is a height, so layers meet with
// natural, uneven edges (pebbles poke through grass, snow settles in hollows).
// *_nrao textures: RG = normal xy (OpenGL), B = roughness, A = ambient occlusion.

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nrao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_nrao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_nrao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Large soft noise that varies colour across the land so the tiling does not show.
uniform sampler2D macro_noise : hint_default_white, filter_linear_mipmap, repeat_enable;

// Texture repeats per meter.
uniform float grass_scale = 0.5;
uniform float dirt_scale = 0.45;
uniform float rock_scale = 0.18;
// The second, larger rock copy (as a share of rock_scale) and the tint of its warmer patches.
uniform float rock_large = 0.22;
uniform vec3 rock_warm : source_color = vec3(1.08, 1.0, 0.9);
uniform vec3 scree_tint : source_color = vec3(0.85, 0.84, 0.82);
uniform float sand_scale = 0.45;
uniform float snow_scale = 0.3;
// Where rock starts and fully covers the ground (1 - normal.y).
uniform vec2 rock_slope = vec2(0.17, 0.33);
uniform vec3 grass_dry : source_color = vec3(1.0, 0.97, 0.8);
uniform vec3 grass_lush : source_color = vec3(0.9, 1.08, 0.9);
uniform float edge_softness = 0.22;
uniform float normal_strength = 1.0;
uniform float macro_scale = 0.01;
uniform float macro_strength = 0.22;

varying vec3 world_position;
varying vec3 world_normal;

struct Ground {
	vec4 albedo;  // rgb + height
	vec3 normal;  // world space
	float rough;
	float ao;
};

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// A packed normal (RG) in the frame of a top-down projection (u = x, v = z, Godot's
// binormal = -Z), turned into a world-space normal around the surface normal.
vec3 top_normal(vec2 rg, vec3 n) {
	vec2 xy = (rg * 2.0 - 1.0) * normal_strength;
	vec3 t = normalize(vec3(1.0, 0.0, 0.0) - n * n.x);
	vec3 b = normalize(cross(n, t));
	return normalize(t * xy.x + b * xy.y + n * sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

// Top-down projection, mixed with a larger copy to hide the repetition at a distance.
Ground planar(sampler2D albedo, sampler2D nrao, float scale) {
	vec2 uv = world_position.xz * scale;
	vec2 uv2 = uv * 0.29 + vec2(0.37, 0.71);
	Ground g;
	g.albedo = mix(texture(albedo, uv), texture(albedo, uv2), 0.3);
	vec4 p = mix(texture(nrao, uv), texture(nrao, uv2), 0.3);
	g.normal = top_normal(p.rg, world_normal);
	g.rough = p.b;
	g.ao = p.a;
	return g;
}

// Projected from three sides so cliffs are not stretched; normals swizzled per side.
Ground triplanar(sampler2D albedo, sampler2D nrao, float scale) {
	vec3 w = pow(abs(world_normal), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec3 p = world_position * scale;
	vec4 px = texture(nrao, p.zy);
	vec4 py = texture(nrao, p.xz);
	vec4 pz = texture(nrao, p.xy);
	vec2 nx = (px.rg * 2.0 - 1.0) * normal_strength;
	vec2 ny = (py.rg * 2.0 - 1.0) * normal_strength;
	vec2 nz = (pz.rg * 2.0 - 1.0) * normal_strength;
	Ground g;
	g.albedo = texture(albedo, p.zy) * w.x + texture(albedo, p.xz) * w.y + texture(albedo, p.xy) * w.z;
	g.normal = normalize(world_normal + vec3(0.0, nx.y, nx.x) * w.x + vec3(ny.x, 0.0, -ny.y) * w.y + vec3(nz.x, nz.y, 0.0) * w.z);
	vec4 m = px * w.x + py * w.y + pz * w.z;
	g.rough = m.b;
	g.ao = m.a;
	return g;
}

// Lays `layer` over `base` by weight t, letting the taller texture win near the edge.
Ground blend(Ground base, Ground layer, float t) {
	float mask = smoothstep(-edge_softness, edge_softness, (t - 0.5) * 2.0 + (layer.albedo.a - base.albedo.a) * 0.7);
	float k = t <= 0.0 ? 0.0 : (t >= 1.0 ? 1.0 : mask);
	Ground g;
	g.albedo = mix(base.albedo, layer.albedo, k);
	g.normal = normalize(mix(base.normal, layer.normal, k));
	g.rough = mix(base.rough, layer.rough, k);
	g.ao = mix(base.ao, layer.ao, k);
	return g;
}

void fragment() {
	float macro = texture(macro_noise, world_position.xz * macro_scale).r;
	float detail = texture(macro_noise, world_position.xz * macro_scale * 5.3 + vec2(0.31, 0.77)).r;
	Ground ground = planar(grass_albedo, grass_nrao, grass_scale);
	// lushness from the painter, plus patches of drier and greener meadow
	float lush = clamp(COLOR.a + (macro - 0.5) * 0.7, 0.0, 1.0);
	ground.albedo.rgb *= mix(grass_dry, grass_lush, lush);
	ground = blend(ground, planar(sand_albedo, sand_nrao, sand_scale), COLOR.g);
	Ground dirt = planar(dirt_albedo, dirt_nrao, dirt_scale);
	// up on the mountains the bare ground is grey scree, not straw-strewn earth
	float dirt_luma = dot(dirt.albedo.rgb, vec3(0.3, 0.59, 0.11));
	dirt.albedo.rgb = mix(dirt.albedo.rgb, vec3(dirt_luma) * scree_tint, smoothstep(7.0, 13.0, world_position.y));
	ground = blend(ground, dirt, COLOR.r);
	float rock_t = smoothstep(rock_slope.x, rock_slope.y, 1.0 - world_normal.y);
	if (rock_t > 0.0) {
		// fine rock mixed with a much larger copy, so a whole mountainside shows big ledges
		Ground rock = triplanar(rock_albedo, rock_nrao, rock_scale);
		Ground ledges = triplanar(rock_albedo, rock_nrao, rock_scale * rock_large);
		rock.albedo = mix(rock.albedo, ledges.albedo, 0.45);
		rock.normal = normalize(rock.normal + ledges.normal - world_normal);
		rock.rough = mix(rock.rough, ledges.rough, 0.45);
		rock.ao = min(rock.ao, ledges.ao);
		// warmer and cooler stone across the range, and faint layered bands
		rock.albedo.rgb *= mix(vec3(0.92, 0.95, 1.0), rock_warm, macro) * (1.0 + 0.07 * sin(world_position.y * 0.9 + detail * 6.0));
		ground = blend(ground, rock, rock_t);
	}
	if (COLOR.b > 0.0) {
		// snow settles on ledges and gentle slopes; steep faces stay bare
		float snow_t = COLOR.b * smoothstep(0.45, 0.75, ground.normal.y);
		ground = blend(ground, planar(snow_albedo, snow_nrao, snow_scale), snow_t);
	}
	// broad light/dark variation breaks up the repeats seen from afar
	ALBEDO = ground.albedo.rgb * (1.0 + (macro - 0.5) * macro_strength * 2.0 + (detail - 0.5) * macro_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(ground.normal, 0.0)).xyz);
	ROUGHNESS = max(ground.rough, 0.6);  // ground never looks wet: keeps the sky's sheen off the grass
	AO = ground.ao;
	AO_LIGHT_AFFECT = 0.25;
	SPECULAR = 0.2;
}
