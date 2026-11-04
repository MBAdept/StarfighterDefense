shader_type canvas_item;
// HUD-Symbolik als gebündeltes Licht ("collimated"): kräftige Kerne werden normal gemischt
// (bleiben auch vor hellem Himmel lesbar), schwache Halos werden überwiegend addiert (Leuchten).
// Optional begrenzt eine Maske die Symbolik auf das Combiner-Glas (Viereck in Bildschirm-
// koordinaten, folgt dem nachfedernden Glas) und spart das davorliegende Mittelpult aus.
render_mode blend_premul_alpha;

uniform bool use_mask = false;
uniform vec2 view_size = vec2(1920.0, 1080.0);
// Glas: Ecken im Uhrzeigersinn (oben links, oben rechts, unten rechts, unten links)
uniform vec2 g0 = vec2(0.0, 0.0);
uniform vec2 g1 = vec2(1920.0, 0.0);
uniform vec2 g2 = vec2(1920.0, 1080.0);
uniform vec2 g3 = vec2(0.0, 1080.0);
// Mittelpult (verdeckt den unteren Glasrand), ebenfalls im Uhrzeigersinn
uniform vec2 s0 = vec2(-10.0, -10.0);
uniform vec2 s1 = vec2(-9.0, -10.0);
uniform vec2 s2 = vec2(-9.0, -9.0);
uniform vec2 s3 = vec2(-10.0, -9.0);
uniform float feather = 14.0;
uniform float intensity = 1.0;      // Flackern bei schweren Treffern
uniform float halo_add = 0.7;       // 0 = alles gemischt, 1 = Halos rein additiv
uniform float boot = 1.0;           // Einschalt-Sweep beim Szenenstart (0 → 1), 1 = fertig
uniform vec3 boot_color : source_color = vec3(0.55, 1.0, 0.7);

// Abstand zur Kante a→b, positiv auf der Innenseite (Uhrzeigersinn in y-unten-Koordinaten)
float edge_dist(vec2 p, vec2 a, vec2 b) {
	vec2 e = b - a;
	vec2 n = normalize(vec2(-e.y, e.x));
	return dot(p - a, n);
}

float quad_dist(vec2 p, vec2 a, vec2 b, vec2 c, vec2 d) {
	return min(min(edge_dist(p, a, b), edge_dist(p, b, c)), min(edge_dist(p, c, d), edge_dist(p, d, a)));
}

void fragment() {
	vec4 col = COLOR;
	float m = 1.0;
	if (use_mask) {
		vec2 p = SCREEN_UV * view_size;
		m = smoothstep(0.0, feather, quad_dist(p, g0, g1, g2, g3));
		m *= 1.0 - smoothstep(-3.0, 3.0, quad_dist(p, s0, s1, s2, s3));
	}
	float a = clamp(col.a * m * intensity, 0.0, 1.0);
	float cover = mix(1.0 - halo_add, 1.0, smoothstep(0.22, 0.7, col.a));
	// dunkle Kontrastsäume werden gemischt (dunkeln ab), nicht addiert
	cover = mix(1.0, cover, smoothstep(0.02, 0.12, max(col.r, max(col.g, col.b))));
	COLOR = vec4(col.rgb * a, a * cover);
	if (boot < 1.0) {
		// von oben nach unten aufblenden, an der Sweep-Kante ein heller Streifen (additiv)
		float edge = boot * 1.12;
		float y = SCREEN_UV.y;
		float reveal = 1.0 - smoothstep(edge - 0.05, edge, y);
		COLOR *= reveal;
		float band = exp(-pow((y - edge) * 38.0, 2.0)) * (1.0 - boot) * m;
		COLOR.rgb += boot_color * band * 0.35;
	}
}
