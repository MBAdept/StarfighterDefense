shader_type canvas_item;
// Sprungpunkt zum Feindsystem: kleine Spiralgalaxie (vorerst deaktiviert = entsättigt).

uniform float active = 0.0;
uniform float highlight = 0.0;
uniform vec3 arm_active = vec3(1.0, 0.35, 0.45);   // Armfarbe (0.14.0: blau-violett für das zweite Feindsystem)
uniform float spin = 1.0;                           // Drehsinn/-tempo

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 p = (UV * 2.0 - 1.0);
	p = mat2(vec2(1.0, 0.0), vec2(0.0, 1.6)) * p;   // geneigte Scheibe
	float r = length(p);
	float a = atan(p.y, p.x) - TIME * 0.12 * spin;
	float arms = 0.5 + 0.5 * cos(2.0 * (a - log(r + 0.001) * 2.6));
	arms = pow(arms, 3.0);
	float disc = exp(-r * 3.2);
	float core = exp(-r * 14.0);
	vec2 sp = floor(UV * 90.0);
	float stars = step(0.985, hash(sp)) * smoothstep(0.9, 0.2, r);
	vec3 arm_col = mix(vec3(0.75, 0.3, 1.0), arm_active, active);
	vec3 col = arm_col * arms * disc * 1.6 + vec3(1.0, 0.85, 0.7) * core * 2.0 + vec3(0.9, 0.8, 1.0) * stars * 0.8;
	float alpha = clamp(arms * disc * 1.4 + core * 2.0 + stars * 0.6, 0.0, 1.0) * smoothstep(1.0, 0.75, r);
	float grey = dot(col, vec3(0.3, 0.5, 0.2));
	col = mix(vec3(grey) * vec3(0.8, 0.8, 1.0), col, 0.35 + 0.65 * max(active, highlight));
	COLOR = vec4(col, alpha);
}
