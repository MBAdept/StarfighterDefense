shader_type canvas_item;
// Planet auf der Systemkarte: texturierte Kugel, beleuchtet von der Sonne (Kartenmitte), Atmosphärensaum.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform vec4 color_a : source_color = vec4(0.2, 0.4, 0.8, 1.0);
uniform vec4 color_b : source_color = vec4(0.3, 0.6, 0.3, 1.0);
uniform vec2 light_dir = vec2(-1.0, 0.0);
uniform vec4 atmo : source_color = vec4(0.4, 0.7, 1.0, 1.0);
uniform float spin = 0.0;
uniform float disc = 0.72;     // Radius der Kugel relativ zur halben Rechteckgröße


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

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) / disc;
	float r = length(p);
	vec3 L = normalize(vec3(light_dir.x, light_dir.y, 0.55));
	if (r > 1.0) {
		float h = smoothstep(1.32, 1.0, r);
		float lit = clamp(dot(normalize(vec3(p, 0.0)), L) * 0.7 + 0.45, 0.0, 1.0);
		COLOR = vec4(atmo.rgb * 1.4, h * h * 0.6 * lit);
	} else {
		vec3 n = vec3(p.x, p.y, sqrt(1.0 - r * r));
		vec2 uv = vec2(atan(n.x, n.z) / 6.2831853 + 0.5 + spin, acos(clamp(-n.y, -1.0, 1.0)) / 3.14159265);
		vec3 base = use_tex ? tex_equi(albedo_tex, uv).rgb : mix(color_a.rgb, color_b.rgb, 0.5 + 0.5 * sin(n.y * 8.0 + n.x * 3.0));
		float ndl = dot(n, L);
		float day = smoothstep(-0.15, 0.35, ndl);
		vec3 col = base * (0.06 + 1.25 * max(ndl, 0.0)) ;
		float fres = pow(1.0 - n.z, 2.5);
		col += atmo.rgb * fres * (0.2 + day) * 0.9;
		float aa = smoothstep(1.0, 0.96, r);
		COLOR = vec4(col, aa);
	}
}
