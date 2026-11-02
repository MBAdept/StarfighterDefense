shader_type spatial;
// Aufschlagmarke der Bomben: Ring = Trefferradius (bomb_hit_radius), rotierender Strichring, Fadenkreuz.
// lock = 1: eine intakte Stadt liegt im Trefferkreis (grün, schnelleres Pulsieren). Immer sichtbar (kein Tiefentest).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec4 marker_color : source_color = vec4(1.0, 0.72, 0.22, 1.0);
uniform float energy = 2.2;
uniform float lock = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float t = TIME;
	float a = atan(p.y, p.x);
	float ring = smoothstep(0.035, 0.0, abs(r - 0.92));
	float dash = step(0.5, fract(a / 6.2831853 * 16.0 + t * (0.35 + lock * 0.9)));
	float ring2 = smoothstep(0.022, 0.0, abs(r - 0.74)) * dash;
	float cross = (smoothstep(0.022, 0.0, abs(p.x)) + smoothstep(0.022, 0.0, abs(p.y))) * step(r, 0.55) * step(0.16, r);
	float center = smoothstep(0.07, 0.035, r);
	float fill = (1.0 - smoothstep(0.0, 0.92, r)) * 0.18 * lock;
	float pulse = 0.78 + 0.22 * sin(t * (5.0 + lock * 9.0));
	float v = (ring + ring2 * 0.85 + cross * 0.7 + center + fill) * pulse * step(r, 1.0);
	ALBEDO = marker_color.rgb * energy * v;
	ALPHA = clamp(v, 0.0, 1.0) * marker_color.a;
}
