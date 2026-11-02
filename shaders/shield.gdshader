shader_type spatial;
// Schildblase der Zerstörer: Fresnel-Rand, Hexagon-Muster, Trefferblitz.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 shield_color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform float strength = 0.35;     // Grundsichtbarkeit (Anzahl Schilde)
uniform float hit = 0.0;           // 0..1 Blitz
uniform vec3 hit_dir = vec3(0.0, 0.0, 1.0);

float hexgrid(vec2 p) {
	p *= vec2(1.0, 1.1547);
	p.x += mod(floor(p.y), 2.0) * 0.5;
	vec2 f = abs(fract(p) - 0.5);
	return smoothstep(0.42, 0.5, max(f.x * 1.5 + f.y * 0.5, f.y));
}

varying vec3 obj_n;

void vertex() {
	obj_n = normalize(VERTEX);
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	vec2 uv = vec2(atan(obj_n.z, obj_n.x) * 3.0, obj_n.y * 6.0);
	float hx = hexgrid(uv * 2.2 + vec2(0.0, TIME * 0.15));
	float pulse = 0.85 + 0.15 * sin(TIME * 3.0 + obj_n.y * 8.0);
	float hitspot = pow(clamp(dot(obj_n, normalize(hit_dir)), 0.0, 1.0), 6.0) * hit * 3.0;
	float a = (fres * 1.2 + hx * 0.25 * (fres + 0.2)) * strength * pulse + hit * (0.25 + fres) + hitspot;
	ALBEDO = shield_color.rgb * a * 2.0 + vec3(1.0) * hitspot;
	ALPHA = clamp(a, 0.0, 1.0);
}
