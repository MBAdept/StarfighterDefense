shader_type spatial;
// Explosions-Flipbook als Billboard (8x8 Frames), Frame per Instanz-Uniform.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(8.0, 8.0);
uniform float brightness = 1.7;
instance uniform float frame = 0.0;
instance uniform float alpha_mul = 1.0;
instance uniform float spin = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0);

void vertex() {
	float sc = length(MODEL_MATRIX[0].xyz);
	float c = cos(spin);
	float s = sin(spin);
	VERTEX.xy = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xy;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(sc, 0.0, 0.0, 0.0), vec4(0.0, sc, 0.0, 0.0), vec4(0.0, 0.0, sc, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

vec4 sample_frame(float f, vec2 uv) {
	f = clamp(f, 0.0, grid.x * grid.y - 1.0);
	vec2 cell = vec2(mod(f, grid.x), floor(f / grid.x));
	vec2 inset = clamp(uv, vec2(0.004), vec2(0.996));
	return texture(atlas, (cell + inset) / grid);
}

void fragment() {
	float f0 = floor(frame);
	float fr = fract(frame);
	vec4 a = sample_frame(f0, UV);
	vec4 b = sample_frame(f0 + 1.0, UV);
	vec4 col = mix(a, b, fr);
	ALBEDO = col.rgb * brightness * tint.rgb;
	ALPHA = clamp(col.a * alpha_mul * tint.a, 0.0, 1.0);
}
