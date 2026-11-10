shader_type spatial;
// Planetenoberfläche: prozedurale Färbung (Noise), Wasser/Lava je Planettyp, Retro-Raster mit
// Distanzabfall (vermittelt Geschwindigkeit und Perspektive).
// [0.14.4] Gelände (PlanetTerrain): felsige Hänge, Schnee auf Höhen, Seen in Senken, Feinrelief über die
// Normalen, ebene Plätze um die Städte mit Straßen (Helion: Felder bzw. Bewässerungskreise) oder leuchtenden
// Adern (Feindwelten). Alles statisch – keine Blink- oder Flackereffekte (Fotosicherheit).
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 ground_a : source_color = vec3(0.16, 0.3, 0.13);
uniform vec3 ground_b : source_color = vec3(0.36, 0.31, 0.21);
uniform vec3 rock_color : source_color = vec3(0.34, 0.32, 0.29);
uniform vec3 grid_color : source_color = vec3(0.3, 0.9, 1.0);
uniform vec3 accent : source_color = vec3(1.0, 0.25, 0.6);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float grid_strength = 0.55;
uniform float grid_size = 40.0;
uniform float lava = 0.0;
uniform float water = 0.0;
uniform float water_level = -3.2;
uniform vec3 water_color : source_color = vec3(0.04, 0.2, 0.38);
uniform float snow = 0.0;
uniform float snow_height = 170.0;
uniform int style = 0;
uniform float area = 640.0;
uniform float bump = 2.2;
uniform vec4 cities[24];      // x, z, Platzradius, intakt (1) / zerstört (0)
uniform int city_count = 0;
uniform vec4 roads[32];       // Strecke x0, z0, x1, z1
uniform vec2 road_alive[32];  // Endpunkte intakt (1) / zerstört (0) – Adern erlöschen zur Ruine hin
uniform int road_count = 0;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 p = wpos.xz;
	float hgt = wpos.y;
	float cam_d = length(wpos - INV_VIEW_MATRIX[3].xyz);
	float n1 = texture(noise_tex, p * 0.00055).r;
	float n2 = texture(noise_tex, p * 0.0031 + vec2(0.37, 0.11)).r;
	float n3 = texture(noise_tex, p * 0.021 + vec2(0.71, 0.53)).r;
	float n4 = texture(noise_tex, p * 0.11).r;
	float hn = n1 * 0.65 + n2 * 0.35;
	vec3 col = mix(ground_a, ground_b, smoothstep(0.38, 0.66, hn));
	col *= 0.78 + 0.32 * n3 + 0.12 * (n4 - 0.5);

	// Feinrelief: Normale aus dem Rauschen geneigt (nur Licht, keine Geometrie), in der Ferne ausgeblendet
	float nx = texture(noise_tex, (p + vec2(1.6, 0.0)) * 0.021 + vec2(0.71, 0.53)).r;
	float nz = texture(noise_tex, (p + vec2(0.0, 1.6)) * 0.021 + vec2(0.71, 0.53)).r;
	float bfade = 1.0 - smoothstep(250.0, 900.0, cam_d);
	vec3 wn = normalize(wnorm + vec3(n3 - nx, 0.0, n3 - nz) * bump * bfade);

	// Hänge felsig, Täler etwas dunkler, Höhen mit Schnee
	float slope = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	float rockm = smoothstep(0.16, 0.4, slope + (n3 - 0.5) * 0.14);
	col = mix(col, rock_color * (0.78 + 0.4 * n3), rockm);
	col *= 1.0 + 0.06 * clamp(hgt / 4.0, -1.0, 1.0) * (1.0 - rockm);
	if (snow > 0.0) {
		float sm = smoothstep(snow_height - 50.0, snow_height + 40.0, hgt + (n2 - 0.5) * 80.0);
		sm *= 1.0 - smoothstep(0.45, 0.7, slope);
		col = mix(col, vec3(0.9, 0.94, 1.0) * (0.92 + 0.12 * n3), sm * snow);
	}
	float rough = 0.92;
	float spec = 0.25;
	vec3 emis = vec3(0.0);

	// --- Stadtumfeld (nur im Einsatzgebiet), in Durchgängen, damit keine Stadt die Plätze anderer übermalt:
	//     1. Maske aller Plätze und Brandflecken, 2. Umfeld (Felder/Kreise/Wurzeln) außerhalb dieser Maske,
	//     3. Straßen bzw. Adern, 4. Plätze, Ringe, Brandflecken obenauf.
	float near_city = 1e6;
	if (length(p) < area + 700.0 && city_count > 0) {
		float plaza_any = 0.0;
		for (int i = 0; i < city_count; i++) {
			vec4 c = cities[i];
			float d = distance(p, c.xy);
			near_city = min(near_city, d);
			plaza_any = max(plaza_any, 1.0 - smoothstep(c.z + 0.5, c.z + 4.0, d));
			if (c.w < 0.5) {
				plaza_any = max(plaza_any, 1.0 - smoothstep(c.z * 0.6, c.z + 22.0, d + (n3 - 0.5) * 18.0));
			}
		}
		float free_m = 1.0 - plaza_any;
		for (int i = 0; i < city_count; i++) {
			vec4 c = cities[i];
			vec2 q = p - c.xy;
			float d = length(q);
			if (d > c.z + 130.0) {
				continue;
			}
			float rot = hash21(c.xy) * 6.2832;
			if (style == 0) {
				// Felder: gedrehtes Raster rund um die Stadt, Töne je Feld, Furchen, Hecken an den Rändern
				vec2 r2 = vec2(q.x * cos(rot) - q.y * sin(rot), q.x * sin(rot) + q.y * cos(rot));
				vec2 cell = floor(r2 / vec2(26.0, 18.0));
				float tone = hash21(cell + c.xy * 0.01);
				vec2 fpos = fract(r2 / vec2(26.0, 18.0));
				float edge = min(min(fpos.x, 1.0 - fpos.x) * 26.0, min(fpos.y, 1.0 - fpos.y) * 18.0);
				// Feldtöne nahe an den Bodenfarben (kein hartes Schachbrett): Grün, reifes Feld, Brache
				vec3 fcol = mix(ground_a * 1.15, mix(ground_a, vec3(0.5, 0.45, 0.22), 0.6), smoothstep(0.5, 0.6, tone));
				fcol = mix(fcol, ground_b * 1.05, smoothstep(0.8, 0.86, tone));
				fcol *= (0.9 + 0.1 * n3) * (0.93 + 0.07 * sin(r2.x * 2.2));
				float fm = smoothstep(c.z + 2.0, c.z + 8.0, d) * (1.0 - smoothstep(c.z + 90.0, c.z + 125.0, d + (n2 - 0.5) * 40.0));
				fm *= step(0.18, tone) * free_m;
				col = mix(col, fcol, fm * 0.7);
				col = mix(col, ground_a * 0.55, fm * (1.0 - smoothstep(0.0, 1.3, edge)) * 0.8);
			} else if (style == 1) {
				// Bewässerungskreise (Wüste): grüne Kreise mit Ringen um die Stadt
				for (int k = 0; k < 4; k++) {
					float a = rot + float(k) * 1.5708 + 0.4;
					vec2 cc = c.xy + vec2(cos(a), sin(a)) * (c.z + 42.0);
					float dd = length(p - cc);
					float cm = (1.0 - smoothstep(25.0, 27.0, dd)) * free_m;
					vec3 ccol = vec3(0.26, 0.38, 0.13) * (0.85 + 0.15 * sin(dd * 1.4));
					col = mix(col, ccol, cm * 0.9);
				}
			} else if (style == 3) {
				// Feindwelten: radiales Wurzelmuster um die Stadt (erlischt mit der Stadt)
				float ang = atan(q.y, q.x);
				float roots = 1.0 - smoothstep(0.0, 0.08, abs(sin(ang * 7.0 + d * 0.035 + rot)));
				float rm = roots * smoothstep(c.z, c.z + 6.0, d) * (1.0 - smoothstep(c.z + 40.0, c.z + 95.0, d)) * free_m;
				col = mix(col, rock_color * 0.6, rm * 0.7);
				emis += accent * rm * 0.35 * c.w;
			}
		}
		// Straßen (Helion) bzw. Adern (Feindwelten); Adern erlöschen zu zerstörten Städten hin
		for (int i = 0; i < road_count; i++) {
			vec4 rd = roads[i];
			vec2 pa = p - rd.xy;
			vec2 ba = rd.zw - rd.xy;
			float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
			float sd = length(pa - ba * h);
			if (style == 3) {
				float core = 1.0 - smoothstep(0.6, 1.6, sd);
				float glow = 1.0 - smoothstep(1.5, 7.0, sd);
				float alive = mix(road_alive[i].x, road_alive[i].y, smoothstep(0.15, 0.85, h));
				col = mix(col, rock_color * 0.4, glow * 0.6);
				emis += accent * (core * 1.1 + glow * 0.18) * alive * (1.0 - plaza_any * 0.7);
			} else {
				float road = 1.0 - smoothstep(2.4, 3.2, sd);
				float shoulder = 1.0 - smoothstep(3.2, 5.0, sd);
				vec3 rcol = style == 1 ? vec3(0.62, 0.5, 0.36) : vec3(0.19, 0.19, 0.2);
				col = mix(col, rcol * 1.25, shoulder * 0.35);
				col = mix(col, rcol * (0.9 + 0.1 * n4), road);
				rough = mix(rough, 0.8, road);
			}
		}
		// Plätze (eben, gepflastert bzw. dunkel glänzend), Ringe und Brandflecken obenauf
		for (int i = 0; i < city_count; i++) {
			vec4 c = cities[i];
			vec2 q = p - c.xy;
			float d = length(q);
			if (d > c.z + 25.0) {
				continue;
			}
			float pm = 1.0 - smoothstep(c.z - 1.5, c.z + 0.5, d);
			vec3 pcol = style == 3 ? rock_color * 0.45 : mix(ground_b, vec3(0.45, 0.45, 0.47), 0.65);
			float tiles = 0.94 + 0.06 * step(0.5, fract(q.x / 4.0)) * step(0.5, fract(q.y / 4.0));
			col = mix(col, pcol * tiles, pm);
			float ring = 1.0 - smoothstep(0.0, 0.9, abs(d - c.z));
			col = mix(col, style == 3 ? accent * 0.4 : vec3(0.68, 0.68, 0.66), ring * 0.7);
			if (style == 3) {
				emis += accent * ring * 0.5 * c.w;
				rough = mix(rough, 0.35, pm);
			}
			if (c.w < 0.5) {
				// zerstörte Stadt: verbrannter Platz
				float burn = 1.0 - smoothstep(c.z * 0.6, c.z + 22.0, d + (n3 - 0.5) * 18.0);
				col = mix(col, vec3(0.05, 0.04, 0.035), burn * 0.85);
			}
		}
	}

	// Seen in Senken (nie auf den Stadtplätzen – dort ist der Boden eben bei y = 0)
	if (water > 0.0) {
		float wm = 1.0 - smoothstep(water_level - 0.35, water_level + 0.25, hgt + (n3 - 0.5) * 0.25);
		col = mix(col, water_color * (0.85 + 0.25 * n3), wm);
		rough = mix(rough, 0.2, wm);
		spec = mix(spec, 0.6, wm);
		wn = normalize(mix(wn, wnorm, wm));
	}
	if (lava > 0.0) {
		float crack = 1.0 - smoothstep(0.0, 0.035, abs(n2 - 0.5));
		crack *= smoothstep(0.3, 0.6, n1);
		crack *= smoothstep(45.0, 70.0, near_city);   // keine Lava an den Städten
		emis += vec3(1.0, 0.32, 0.05) * crack * lava * (2.0 + 1.5 * sin(TIME * 1.5 + n3 * 10.0));
		col = mix(col, vec3(0.05, 0.02, 0.01), crack * 0.6);
	}
	// Retro-Raster (auf steilen Hängen schwächer)
	vec2 gp = p / grid_size;
	vec2 gd = abs(fract(gp - 0.5) - 0.5) / max(fwidth(gp), vec2(0.0001));
	float line = 1.0 - min(min(gd.x, gd.y), 1.0);
	float fade = exp(-cam_d / 520.0) * (1.0 - rockm * 0.6);
	emis += grid_color * line * grid_strength * fade;
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = emis;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
