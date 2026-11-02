shader_type canvas_item;
// Zentralgestirn der Karte: heller Kern, pulsierende Korona mit Strahlen.

uniform vec4 core_color : source_color = vec4(1.0, 0.92, 0.7, 1.0);
uniform vec4 corona_color : source_color = vec4(1.0, 0.6, 0.2, 1.0);

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float core = smoothstep(0.24, 0.2, r);
	float rays = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		rays += pow(abs(sin(a * (5.0 + fi * 3.0) + TIME * (0.15 + fi * 0.07) + fi)), 12.0) * (0.35 - fi * 0.06);
	}
	float glow = exp(-r * 4.5) * 1.2 + exp(-r * 12.0) * 1.5;
	float corona = (glow + rays * exp(-r * 3.2) * 0.9) * (0.92 + 0.08 * sin(TIME * 2.0));
	vec3 col = mix(corona_color.rgb, core_color.rgb, clamp(core + exp(-r * 9.0), 0.0, 1.0));
	float alpha = clamp(core + corona, 0.0, 1.0) * smoothstep(1.0, 0.6, r);
	COLOR = vec4(col * (1.0 + core * 1.5), alpha);
}
