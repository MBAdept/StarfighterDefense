shader_type spatial;
// Prozeduraler Feuerball (Fallback/Ergänzung zum Flipbook): Billboard mit Noise-Textur.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
instance uniform float age = 0.0;     // 0..1
instance uniform float seed = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0, 0.55, 0.2, 1.0);

void vertex() {
	float sc = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(sc, 0.0, 0.0, 0.0), vec4(0.0, sc, 0.0, 0.0), vec4(0.0, 0.0, sc, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float n = texture(noise_tex, vec2(ang / 6.2831 + seed, r * 0.6 - age * 0.8 + seed * 3.0)).r;
	float n2 = texture(noise_tex, p * 0.35 + vec2(seed, age * 0.3)).r;
	float edge = 1.0 - smoothstep(0.35 + 0.45 * n, 0.95, r + age * 0.35);
	float core = smoothstep(0.75, 0.0, r + age * 0.9) * (1.0 - age);
	vec3 hot = vec3(1.0, 0.95, 0.8);
	vec3 col = mix(tint.rgb, hot, core) * (0.6 + n2);
	float a = edge * (1.0 - age) * (0.65 + 0.35 * n);
	ALBEDO = col * a * 3.0;
	ALPHA = clamp(a, 0.0, 1.0);
}
