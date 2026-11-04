shader_type spatial;
// Combiner-Glas des Head-Up-Displays: kaum sichtbare Scheibe. Vormultipliziertes Alpha:
// ALPHA dunkelt die Welt dahinter leicht ab (getönte Beschichtung), ALBEDO addiert schwache
// Reflexe (Himmelsschimmer oben, zwei schmale Glanzstreifen, hell gefasste Glaskanten).
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.16, 0.1, 0.2);
uniform float tint_alpha = 0.13;
uniform vec3 reflect_color : source_color = vec3(0.6, 0.82, 0.9);
uniform float reflection = 0.036;
uniform float edge_light = 0.22;
uniform vec3 coating : source_color = vec3(0.2, 0.75, 0.4);   // grünlicher Schimmer der Beschichtung
uniform float coating_glow = 0.03;

void fragment() {
	vec2 uv = UV;
	float top = pow(clamp(1.0 - uv.y, 0.0, 1.0), 5.0);
	float s = uv.x * 0.92 - uv.y * 0.42;
	float streak = exp(-pow((s - 0.1) * 10.0, 2.0));
	float streak2 = exp(-pow((s - 0.25) * 34.0, 2.0));
	float streak3 = exp(-pow((s - 0.72) * 22.0, 2.0)) * 0.5;
	float d = min(min(uv.x, 1.0 - uv.x), min(uv.y * 0.6, 1.0 - uv.y));
	float edge = smoothstep(0.01, 0.0, d);
	float r = top * 0.7 + streak * 0.55 + streak2 * 0.6 + streak3;
	float low = smoothstep(0.55, 1.0, uv.y) * (1.0 - smoothstep(0.0, 0.25, abs(uv.x - 0.5) - 0.2));
	ALBEDO = tint * tint_alpha + reflect_color * (reflection * r + edge * edge_light) + coating * coating_glow * low;
	ALPHA = clamp(tint_alpha + edge * 0.3, 0.0, 1.0);
}
