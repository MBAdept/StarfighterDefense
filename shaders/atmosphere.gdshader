shader_type spatial;
// Atmosphärenhülle (etwas größere Kugel, Rückseiten), additiver Streulicht-Rand.
render_mode unshaded, blend_add, cull_front, depth_draw_never, shadows_disabled;

uniform vec4 atmo_color : source_color = vec4(0.35, 0.65, 1.0, 1.0);
uniform vec3 sun_dir = vec3(0.5, 0.3, 0.8);
uniform float power = 4.0;
uniform float intensity = 1.6;

varying vec3 world_n;

void vertex() {
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float rim = clamp(dot(-NORMAL, VIEW), 0.0, 1.0);
	float glow = pow(rim, power);
	float lit = smoothstep(-0.35, 0.5, dot(normalize(world_n), normalize(sun_dir)));
	vec3 col = atmo_color.rgb * glow * intensity * (0.08 + lit);
	ALBEDO = col;
	ALPHA = clamp(glow * (0.08 + lit), 0.0, 1.0);
}
