shader_type canvas_item;
// Hyperraumsprung: radial auseinanderlaufende Sternstreifen, Tunnelleuchten und Weißblitz.
// intensity 0..1 (Streifenlänge/Tempo), flash 0..1 (Weißblende), fade 0..1 (Gesamtdeckkraft)

uniform float intensity = 0.0;
uniform float flash = 0.0;
uniform float fade = 0.0;
uniform float aspect = 1.7778;
uniform vec3 tint = vec3(0.55, 0.8, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float layer(vec2 uv, float sectors, float seed, float t) {
	float r = length(uv);
	float a = atan(uv.y, uv.x) / 6.2831853 + 0.5;
	float sa = a * sectors;
	float id = floor(sa);
	float h1 = hash(vec2(id, seed));
	float h2 = hash(vec2(id, seed + 13.7));
	float h3 = hash(vec2(id, seed + 41.1));
	float af = abs(fract(sa) - 0.5);
	float width = mix(0.05, 0.22, h3);
	float line = smoothstep(width, 0.0, af);
	float speed = 0.35 + h2 * 0.9;
	float head = fract(h1 + t * speed) * 1.6;
	float len = mix(0.01, 0.75, intensity) * (0.4 + h3);
	float d = head - r;
	float s = smoothstep(len, 0.0, d) * step(0.0, d) * smoothstep(0.0, 0.03, d + 0.03);
	s *= smoothstep(0.02, 0.25, r);
	return line * s * (0.4 + h2);
}

void fragment() {
	vec2 uv = (UV - 0.5) * vec2(aspect, 1.0);
	float t = TIME * (0.6 + intensity * 2.4);
	float s = layer(uv, 180.0, 1.0, t) + layer(uv, 310.0, 7.0, t * 1.3) * 0.7 + layer(uv, 90.0, 3.0, t * 0.8) * 0.9;
	float r = length(uv);
	vec3 col = tint * s * (1.2 + 2.0 * intensity);
	// Tunnelglühen
	col += tint * 0.35 * intensity * smoothstep(0.9, 0.0, r) * (0.6 + 0.4 * sin(r * 40.0 - TIME * 30.0));
	col += vec3(1.0) * pow(smoothstep(0.5, 0.0, r), 2.0) * intensity * 0.8;
	float a = clamp(max(s, intensity * 0.55) * fade, 0.0, 1.0);
	col = mix(col, vec3(1.0, 1.0, 1.0), flash);
	a = max(a, flash);
	// Hintergrund abdunkeln, damit die Streifen tragen
	vec3 bg = vec3(0.0, 0.01, 0.03);
	float bga = fade * intensity * 0.85;
	vec3 outc = mix(bg, col, clamp(s + flash + intensity * 0.3, 0.0, 1.0));
	COLOR = vec4(outc, clamp(max(a, bga), 0.0, 1.0));
}
