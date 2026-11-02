shader_type sky;
// Himmel über der Planetenoberfläche: Farbverlauf, Horizontdunst, Sonne, Sterne (dünne Atmosphäre),
// großer Nachbarplanet/Mond am Himmel.

uniform vec3 top_color : source_color = vec3(0.08, 0.26, 0.6);
uniform vec3 horizon_color : source_color = vec3(0.6, 0.78, 0.95);
uniform vec3 ground_color : source_color = vec3(0.2, 0.2, 0.2);
uniform float star_amount = 0.0;
uniform float sun_size = 0.9994;
uniform float sun_intensity = 1.0;
uniform sampler2D moon_tex : source_color, filter_linear_mipmap, hint_default_black;
uniform bool has_moon = false;
uniform vec3 moon_dir = vec3(-0.5, 0.35, -0.6);
uniform float moon_radius = 0.12;    // Winkelradius (rad)

float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }


// Equirektanguläre Abfrage ohne Mipmap-Naht an der u=0/1-Kante
vec4 tex_equi(sampler2D t, vec2 uv) {
	vec2 uv2 = vec2(fract(uv.x + 0.5) - 0.5, uv.y);
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec2 dx2 = dFdx(uv2);
	vec2 dy2 = dFdy(uv2);
	if (dot(dx2, dx2) + dot(dy2, dy2) < dot(dx, dx) + dot(dy, dy)) {
		dx = dx2;
		dy = dy2;
	}
	return textureGrad(t, uv, dx, dy);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.55));
	col += horizon_color * 0.35 * exp(-max(h, 0.0) * 18.0);
	if (h < 0.0) {
		col = mix(col, ground_color, smoothstep(0.0, -0.08, h));
	}
	if (star_amount > 0.0 && h > 0.0) {
		vec3 p = d * 260.0;
		vec3 cell = floor(p);
		float s = hash3(cell);
		if (s > 0.992) {
			vec3 c = cell + 0.5;
			float b = smoothstep(0.45, 0.0, length(p - c)) * (s - 0.992) * 120.0;
			col += vec3(0.9, 0.95, 1.0) * b * star_amount * smoothstep(0.0, 0.3, h);
		}
	}
	if (has_moon) {
		vec3 md = normalize(moon_dir);
		float ca = dot(d, md);
		float ang = acos(clamp(ca, -1.0, 1.0));
		if (ang < moon_radius) {
			vec3 up = vec3(0.0, 1.0, 0.0);
			vec3 rx = normalize(cross(up, md));
			vec3 ry = cross(md, rx);
			vec2 q = vec2(dot(d - md * ca, rx), dot(d - md * ca, ry)) / sin(moon_radius);
			float r2 = dot(q, q);
			if (r2 < 1.0) {
				vec3 n = normalize(rx * q.x + ry * q.y - md * sqrt(1.0 - r2));
				vec2 uv = vec2(atan(n.x, n.z) / 6.2831853 + 0.5, acos(clamp(n.y, -1.0, 1.0)) / 3.14159265);
				vec3 mc = tex_equi(moon_tex, uv).rgb;
				float lit = LIGHT0_ENABLED ? clamp(dot(-n, LIGHT0_DIRECTION) * -1.0, 0.0, 1.0) : 0.6;
				lit = max(lit, 0.04);
				float edge = smoothstep(1.0, 0.92, r2);
				vec3 moon = mc * lit;
				col = mix(col, moon + col * 0.25, edge * smoothstep(-0.02, 0.05, h));
			}
		}
	}
	if (LIGHT0_ENABLED) {
		float sd = dot(d, LIGHT0_DIRECTION);
		float disc = smoothstep(sun_size - 0.00005, sun_size + 0.00003, sd);
		float halo = pow(max(sd, 0.0), 1800.0) * 1.2 + pow(max(sd, 0.0), 220.0) * 0.18 + pow(max(sd, 0.0), 12.0) * 0.03;
		col += LIGHT0_COLOR * (disc * 25.0 + halo) * sun_intensity;
	}
	COLOR = col;
}
