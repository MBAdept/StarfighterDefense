shader_type spatial;
// Bildschirm eines Multifunktionsdisplays im Cockpit: selbstleuchtender Inhalt (SubViewport-Textur),
// leichte Randabschattung, entspiegeltes Deckglas mit schwachem Glanz.
render_mode unshaded, cull_back, shadows_disabled;
stencil_mode write, compare_always, 1;   // Cockpit: verdeckt die Aufschlagmarke (siehe bomb_marker)

uniform sampler2D screen_tex : source_color, filter_linear, repeat_disable;
uniform float brightness = 1.25;
uniform vec3 glass_tint : source_color = vec3(0.012, 0.02, 0.024);
uniform float sheen = 0.035;
uniform float flicker = 0.0;

void fragment() {
	vec3 c = texture(screen_tex, UV).rgb;
	vec2 d = abs(UV - 0.5) * 2.0;
	float vig = 1.0 - 0.28 * pow(max(d.x, d.y), 5.0);
	float s = UV.x * 0.8 + UV.y * 0.45;
	float gloss = sheen * (exp(-pow((s - 0.32) * 9.0, 2.0)) + 0.5 * exp(-pow((s - 0.5) * 30.0, 2.0)));
	float lines = 1.0 - 0.06 * step(0.5, fract(UV.y * 120.0));
	ALBEDO = glass_tint + c * brightness * vig * lines * (1.0 - flicker) + vec3(gloss);
}
