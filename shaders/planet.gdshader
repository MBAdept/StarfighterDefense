shader_type spatial;
// Planetenkugel aus dem All: equirektanguläre Albedo, Wolkenschicht, Nachtlichter, Atmosphärenrand.
render_mode unshaded, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D clouds_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D emission_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_clouds = true;
uniform bool has_emission = false;
uniform vec3 sun_dir = vec3(0.5, 0.3, 0.8);        // Weltraumrichtung zur Sonne
uniform vec4 atmo_color : source_color = vec4(0.35, 0.65, 1.0, 1.0);
uniform vec4 night_lights : source_color = vec4(1.0, 0.75, 0.4, 1.0);
uniform float night_light_strength = 0.0;
uniform sampler2D night_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_speed = 0.004;
uniform float spin = 0.0;
uniform vec4 fallback_a : source_color = vec4(0.2, 0.4, 0.8, 1.0);
uniform vec4 fallback_b : source_color = vec4(0.3, 0.6, 0.3, 1.0);
uniform bool use_fallback = false;

varying vec3 obj_n;
varying vec3 world_n;

void vertex() {
	obj_n = normalize(VERTEX);
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


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

vec2 equi(vec3 n, float rot) {
	float u = atan(n.x, -n.z) / 6.2831853 + 0.5 + rot;
	float v = acos(clamp(n.y, -1.0, 1.0)) / 3.14159265;
	return vec2(u, v);
}

void fragment() {
	vec2 uv = equi(obj_n, spin);
	vec3 base;
	if (use_fallback) {
		float b = sin(obj_n.y * 9.0 + sin(obj_n.x * 4.0) * 2.0) * 0.5 + 0.5;
		base = mix(fallback_a.rgb, fallback_b.rgb, b);
	} else {
		base = tex_equi(albedo_tex, uv).rgb;
	}
	vec3 L = normalize(sun_dir);
	float ndl = dot(normalize(world_n), L);
	float day = smoothstep(-0.12, 0.25, ndl);
	vec3 col = base * (0.03 + 0.95 * max(ndl, 0.0) * day + 0.04 * day);
	if (has_clouds) {
		float c = tex_equi(clouds_tex, equi(obj_n, spin + TIME * cloud_speed)).a;
		col = mix(col, vec3(0.92, 0.95, 1.0) * (0.03 + 0.9 * max(ndl, 0.0)), c * 0.62);
	}
	if (has_emission) {
		vec3 e = tex_equi(emission_tex, uv).rgb;
		col += e * (1.0 - day * 0.6) * 1.8;
	}
	if (night_light_strength > 0.0) {
		float land = smoothstep(0.02, 0.12, base.g - base.b * 0.55) * smoothstep(0.75, 0.55, base.b);
		float cl = texture(night_noise, uv * vec2(6.0, 3.0)).r;
		float fine = texture(night_noise, uv * vec2(48.0, 24.0)).r;
		float lights = smoothstep(0.6, 0.82, cl) * pow(smoothstep(0.5, 0.85, fine), 2.0);
		col += night_lights.rgb * lights * land * (1.0 - day) * night_light_strength * 0.3;
	}
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col += atmo_color.rgb * fres * (0.1 + 1.0 * smoothstep(-0.3, 0.6, ndl));
	ALBEDO = col;
}
