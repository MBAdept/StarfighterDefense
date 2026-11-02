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

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	// Störstreifen bei schweren Treffern
	if (noise_lines > 0.0) {
		float band = step(0.82, hash(vec2(floor(uv.y * 90.0), floor(TIME * 24.0))));
		uv.x += band * (hash(vec2(TIME, uv.y)) - 0.5) * 0.03 * noise_lines;
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
	col += (hash(FRAGCOORD.xy + fract(TIME) * 100.0) - 0.5) * grain;
	COLOR = vec4(col, 1.0);
}
