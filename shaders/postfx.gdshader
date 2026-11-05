shader_type canvas_item;
// Nachbearbeitung über der 3D-Szene: Vignette, dezente Scanlines (Retro), chromatische
// Aberration und Farbblitz bei Treffern, feines Filmkorn.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float vignette = 0.42;
uniform float scanlines = 0.035;
uniform float aberration = 0.0;
uniform vec4 flash_color = vec4(1.0, 0.2, 0.1, 0.0);
uniform float grain = 0.018;
uniform float noise_lines = 0.0;

// Ganzzahl-Hash (PCG): gleichmäßig auf jeder Grafikkarte und auch nach langer Spielzeit (ein sin()-Hash zerfällt
// bei großen Argumenten in 32-bit-Genauigkeit zu regelmäßigen Mustern)
uint pcg(uint v) {
	uint state = v * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}
float hash3(uint x, uint y, uint z) { return float(pcg(x ^ pcg(y ^ pcg(z)))) * (1.0 / 4294967295.0); }

void fragment() {
	vec2 uv = SCREEN_UV;
	// Störstreifen bei schweren Treffern – fotosicher: Muster wechselt nur dreimal pro Sekunde, kleiner Versatz
	if (noise_lines > 0.0) {
		uint k = uint(mod(floor(TIME * 3.0), 65536.0));
		uint row = uint(floor(uv.y * 60.0));
		float band = step(0.86, hash3(row, k, 3u));
		uv.x += band * (hash3(k, row, 5u) - 0.5) * 0.012 * noise_lines;
	}
	vec2 d = uv - 0.5;
	float ab = 0.0006 + aberration * 0.01;
	vec3 col;
	col.r = texture(screen_tex, uv + d * ab).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - d * ab).b;
	float v = 1.0 - vignette * smoothstep(0.15, 0.85, length(d * vec2(1.0, 0.85)) * 1.25);
	col *= v;
	col *= 1.0 - scanlines * (0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159));
	col = mix(col, flash_color.rgb, flash_color.a);
	col += (hash3(uint(FRAGCOORD.x), uint(FRAGCOORD.y), uint(mod(floor(TIME * 60.0), 65536.0))) - 0.5) * grain;
	COLOR = vec4(col, 1.0);
}
