shader_type sky;
// Painted sky: a soft gradient, a bright sun with a warm halo, and slowly drifting clouds.
// Clouds are left out when Godot renders the sky into the ambient lighting cubemap,
// so the world's lighting stays steady and cheap to update.

uniform vec3 zenith_color : source_color = vec3(0.22, 0.44, 0.8);
uniform vec3 horizon_color : source_color = vec3(0.7, 0.82, 0.92);
uniform vec3 ground_color : source_color = vec3(0.34, 0.38, 0.4);
uniform vec3 cloud_color : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shade : source_color = vec3(0.62, 0.68, 0.8);
uniform sampler2D cloud_texture : filter_linear_mipmap, repeat_enable;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.48;
uniform float cloud_speed = 0.004;

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;
	vec3 color = mix(horizon_color, zenith_color, pow(clamp(up, 0.0, 1.0), 0.5));
	color = mix(color, ground_color, smoothstep(0.0, -0.15, up));
	vec3 sun = LIGHT0_COLOR * LIGHT0_ENERGY;
	float sun_dot = LIGHT0_ENABLED ? max(dot(dir, LIGHT0_DIRECTION), 0.0) : 0.0;
	color += sun * (pow(sun_dot, 80.0) * 0.4 + pow(sun_dot, 6.0) * 0.08);
	color = mix(color, sun * 3.0, smoothstep(0.9993, 0.9996, sun_dot));
	if (!AT_CUBEMAP_PASS && up > 0.0) {
		vec2 uv = dir.xz / (up + 0.15) * 0.22 + TIME * cloud_speed * vec2(1.0, 0.35);
		float density = texture(cloud_texture, uv).r * 0.7 + texture(cloud_texture, uv * 2.6 + 0.31).r * 0.3;
		float edge = 1.0 - cloud_cover;
		float cover = smoothstep(edge, edge + 0.22, density);
		// Thicker toward the sun side means darker undersides: cheap self-shadowing.
		float thick = smoothstep(edge, 1.0, texture(cloud_texture, uv + LIGHT0_DIRECTION.xz * 0.03).r);
		vec3 cloud = mix(cloud_color, cloud_shade, thick * 0.8) + sun * pow(sun_dot, 10.0) * 0.25;
		color = mix(color, cloud, cover * smoothstep(0.0, 0.2, up) * 0.95);
	}
	COLOR = color;
}
