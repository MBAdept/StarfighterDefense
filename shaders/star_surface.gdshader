shader_type spatial;
// Sternoberfläche beim Schnelltanken (Helion bzw. Vorrhal): langsam wallende Granulation, Randverdunkelung,
// einzelne dunkle Flecken. Bewusst ruhig animiert – helles, großes Bild ohne Flackern (Fotosensibilität).
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform vec3 core_color : source_color = vec3(1.0, 0.93, 0.74);
uniform vec3 limb_color : source_color = vec3(1.0, 0.46, 0.12);
uniform float energy = 2.6;
uniform float speed = 0.035;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * noise3(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

void fragment() {
	vec3 n = normalize(lpos);
	float t = TIME * speed;
	float g = fbm(n * 7.0 + vec3(t, -t * 0.7, t * 0.4));
	float g2 = fbm(n * 21.0 - vec3(t * 1.3, t * 0.5, -t));
	float mu = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float limb = pow(mu, 0.5);
	vec3 col = mix(limb_color, core_color, limb);
	col *= 0.72 + 0.38 * g + 0.14 * g2;
	// Sonnenflecken (ruhig, keine schnellen Helligkeitswechsel)
	col *= 1.0 - 0.4 * smoothstep(0.66, 0.8, fbm(n * 3.0 + vec3(11.0) + vec3(t * 0.2)));
	ALBEDO = col * energy * (0.55 + 0.45 * limb);
}
