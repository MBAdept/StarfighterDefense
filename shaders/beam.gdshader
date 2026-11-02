shader_type spatial;
// Bombardement-Strahl (Zylinder, Y-Achse): pulsierende Energie, additiv.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 beam_color : source_color = vec4(1.0, 0.3, 0.15, 1.0);
uniform float intensity = 1.0;

void fragment() {
	float edge = 1.0 - abs(UV.x - 0.5) * 2.0;
	edge = pow(clamp(edge, 0.0, 1.0), 1.5);
	float flow = 0.6 + 0.4 * sin(UV.y * 60.0 + TIME * 22.0);
	float flick = 0.85 + 0.15 * sin(TIME * 47.0);
	float core = pow(edge, 6.0);
	vec3 col = beam_color.rgb * edge * flow * flick + vec3(1.0, 0.9, 0.8) * core;
	float fade_ends = smoothstep(0.0, 0.05, UV.y) * smoothstep(1.0, 0.92, UV.y);
	ALBEDO = col * intensity * 2.5 * fade_ends;
	ALPHA = clamp(edge * intensity * fade_ends, 0.0, 1.0);
}
