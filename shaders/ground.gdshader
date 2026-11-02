shader_type spatial;
// Planetenoberfläche: prozedurale Färbung (Noise), Wasser/Lava je Planettyp, Retro-Raster mit
// Distanzabfall (vermittelt Geschwindigkeit und Perspektive).
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 ground_a : source_color = vec3(0.16, 0.3, 0.13);
uniform vec3 ground_b : source_color = vec3(0.36, 0.31, 0.21);
uniform vec3 grid_color : source_color = vec3(0.3, 0.9, 1.0);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float grid_strength = 0.55;
uniform float grid_size = 40.0;
uniform float lava = 0.0;
uniform float water = 0.0;
uniform vec3 water_color : source_color = vec3(0.04, 0.2, 0.38);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float n1 = texture(noise_tex, p * 0.00055).r;
	float n2 = texture(noise_tex, p * 0.0031 + vec2(0.37, 0.11)).r;
	float n3 = texture(noise_tex, p * 0.021 + vec2(0.71, 0.53)).r;
	float n4 = texture(noise_tex, p * 0.11).r;
	float h = n1 * 0.65 + n2 * 0.35;
	vec3 col = mix(ground_a, ground_b, smoothstep(0.38, 0.66, h));
	col *= 0.78 + 0.32 * n3 + 0.12 * (n4 - 0.5);
	float rough = 0.92;
	float spec = 0.25;
	vec3 emis = vec3(0.0);
	if (water > 0.0) {
		float wm = smoothstep(water + 0.03, water - 0.03, h + (n3 - 0.5) * 0.05);
		col = mix(col, water_color * (0.85 + 0.25 * n3), wm);
		rough = mix(rough, 0.08, wm);
		spec = mix(spec, 0.9, wm);
	}
	if (lava > 0.0) {
		float crack = 1.0 - smoothstep(0.0, 0.035, abs(n2 - 0.5));
		crack *= smoothstep(0.3, 0.6, n1);
		emis += vec3(1.0, 0.32, 0.05) * crack * lava * (2.0 + 1.5 * sin(TIME * 1.5 + n3 * 10.0));
		col = mix(col, vec3(0.05, 0.02, 0.01), crack * 0.6);
	}
	// Retro-Raster
	vec2 gp = p / grid_size;
	vec2 gd = abs(fract(gp - 0.5) - 0.5) / max(fwidth(gp), vec2(0.0001));
	float line = 1.0 - min(min(gd.x, gd.y), 1.0);
	float dist = length(wpos - INV_VIEW_MATRIX[3].xyz);
	float fade = exp(-dist / 520.0);
	emis += grid_color * line * grid_strength * fade;
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = emis;
}
