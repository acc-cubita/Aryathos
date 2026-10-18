shader_type spatial;
// Additive glow for spell and hit effects: texture alpha x vertex/particle colour x tint,
// pushed above 1 so the environment's glow blooms it.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D tex : source_color, hint_default_white, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float energy = 2.5;
// 0 = as modelled, 1 = faces the camera (particles), 2 = stretched along its Y axis
// (particles aligned to their velocity: sparks, streaks) and turned toward the camera
uniform int billboard = 0;

void vertex() {
	if (billboard == 1) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(MAIN_CAM_INV_VIEW_MATRIX[0], MAIN_CAM_INV_VIEW_MATRIX[1], MAIN_CAM_INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
				vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
				vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	} else if (billboard == 2) {
		vec3 y = MODEL_MATRIX[1].xyz;
		vec3 to_cam = normalize(MAIN_CAM_INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz);
		vec3 x = normalize(cross(y, to_cam)) * length(MODEL_MATRIX[0].xyz);
		vec3 z = normalize(cross(x, y));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(x, 0.0), vec4(y, 0.0), vec4(z, 0.0), MODEL_MATRIX[3]);
	}
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = COLOR.rgb * tint.rgb * t.rgb * energy;
	ALPHA = clamp(COLOR.a * tint.a * t.a, 0.0, 1.0);
}
