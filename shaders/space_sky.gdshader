shader_type sky;
// Weltraumhimmel: Panorama (equirektangulär) + Sonne mit Halo; prozeduraler Sternenfallback.

uniform sampler2D panorama : source_color, filter_linear, hint_default_black;
uniform bool use_panorama = false;
uniform float pano_energy = 1.0;
uniform vec3 tint = vec3(1.0);
uniform float sun_size = 0.9997;      // cos des Sonnenradius
uniform float sun_intensity = 1.0;
uniform vec3 nebula_a = vec3(0.10, 0.25, 0.35);
uniform vec3 nebula_b = vec3(0.30, 0.10, 0.35);

float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1,0,0)), f.x), mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x), mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z);
}

vec3 procedural(vec3 d) {
	vec3 col = vec3(0.004, 0.006, 0.014);
	float n = noise3(d * 2.5) * 0.6 + noise3(d * 5.0) * 0.3 + noise3(d * 11.0) * 0.1;
	col += nebula_a * pow(n, 3.0) * 0.5 + nebula_b * pow(1.0 - n, 4.0) * 0.25;
	for (int i = 0; i < 3; i++) {
		float sc = 180.0 + float(i) * 170.0;
		vec3 p = d * sc;
		vec3 cell = floor(p);
		float h = hash3(cell + float(i) * 13.0);
		if (h > 0.985) {
			vec3 c = cell + 0.5 + (vec3(hash3(cell + 1.0), hash3(cell + 2.0), hash3(cell + 3.0)) - 0.5) * 0.6;
			float dist = length(p - c);
			float b = smoothstep(0.35, 0.0, dist) * (h - 0.985) * 60.0;
			vec3 sc_col = mix(vec3(0.7, 0.8, 1.0), vec3(1.0, 0.85, 0.65), hash3(cell + 5.0));
			col += sc_col * b;
		}
	}
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col;
	if (use_panorama) {
		vec2 uv = vec2(atan(d.x, -d.z) / 6.2831853 + 0.5, acos(clamp(d.y, -1.0, 1.0)) / 3.14159265);
		col = textureLod(panorama, uv, 0.0).rgb * pano_energy * tint;
	} else {
		col = procedural(d);
	}
	if (LIGHT0_ENABLED) {
		float sd = dot(d, LIGHT0_DIRECTION);
		float disc = smoothstep(sun_size - 0.00004, sun_size + 0.00002, sd);
		float halo = pow(max(sd, 0.0), 2600.0) * 2.0 + pow(max(sd, 0.0), 420.0) * 0.22 + pow(max(sd, 0.0), 30.0) * 0.025;
		col += LIGHT0_COLOR * (disc * 40.0 + halo) * sun_intensity;
	}
	COLOR = col;
}
