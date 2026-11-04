shader_type spatial;
// Getönter oberer Rand der Kanzel (wie ein Blendstreifen): dunkelt den Himmel oben leicht ab,
// damit die eingeblendeten Anzeigen dort auch vor hellem Himmel lesbar bleiben.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.015, 0.025, 0.035);
uniform float strength = 0.38;

void fragment() {
	float k = 1.0 - smoothstep(0.0, 1.0, UV.y);
	ALBEDO = tint;
	ALPHA = strength * k * k;
}
