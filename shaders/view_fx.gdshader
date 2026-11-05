shader_type canvas_item;
render_mode unshaded;
// Sichtstörung (Systemschaden "Sichtsystem", 0.12.0). Wird nur auf den Scheibenflächen gezeichnet (ViewFX:
// Polygone aus dem Cockpitumriss, um die größte Verschiebung verkleinert) – Cockpit und HUD bleiben klar.
// Fotosicher: Verschiebungen sind langsam (< 1,2 Hz) und klein, Schnee und Streifen sind kontrastarm,
// erhalten die mittlere Helligkeit (kein Aufhellen der Fläche) und werden weich ein- und ausgeblendet
// (Stoß 0,3 s, höchstens alle 2,5 s). Keine harten oder regelmäßigen Streifenmuster, kein Flackern ganzer Flächen.
// Zufall über einen Ganzzahl-Hash (PCG): bleibt auch nach langer Spielzeit und auf jeder Grafikkarte
// gleichmäßig verteilt (ein sin()-Hash zerfällt bei großen Argumenten in 32-bit-Genauigkeit zu Mustern).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform vec2 offset = vec2(0.0);   // Schwanken der Außensicht (UV)
uniform float burst = 0.0;         // Hüllkurve des Störungsstoßes 0..1
uniform float kind = 0.0;          // 0 = Schnee, 1 = grüne Streifen
uniform float tear = 0.0;          // Zeilenversatz im Stoß (UV)
uniform float seed = 0.0;
uniform float grain = 2.0;         // Körnung des Schnees (Bildpunkte)
uniform float snow_amount = 0.18;  // Kontrast des Schnees (Spanne um den Mittelwert, auf dunklem Grund)
uniform float stripe_amount = 0.11;  // Grünanteil der Streifen auf dunklem Grund (sRGB)

uint pcg(uint v) {
	uint state = v * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}

float hash3(uint x, uint y, uint z) {
	return float(pcg(x ^ pcg(y ^ pcg(z)))) * (1.0 / 4294967295.0);
}

// weiches 1D-Rauschen (Zeilenversatz, Streifen); salt trennt die beiden Verwendungen
float vnoise(float x, uint salt) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	uint a = uint(int(i) + 1048576);
	uint s = uint(seed * 1000.0);
	return mix(hash3(a, s, salt), hash3(a + 1u, s, salt), f);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = mod(TIME, 1000.0);
	// Zeilenversatz: wenige breite, weich verlaufende Bänder, die langsam wandern (kein Zeilenflimmern)
	float tx = (vnoise(uv.y * 6.0 + t * 0.7, 11u) - 0.5) * 2.0;
	uv.x += tx * tear * burst;
	uv += offset;
	vec3 col = texture(screen_tex, clamp(uv, vec2(0.0005), vec2(0.9995))).rgb;
	float lum = clamp(dot(col, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
	// Schnee: feines, kontrastarmes Rauschen um den Mittelwert, 12 Bilder pro Sekunde. Auf hellem Grund schwächer,
	// damit dort nur wenige Körner um mehr als 10 % der Leuchtdichte springen (auf schwarzem Grund nur dunkelgraue
	// Körner – die mittlere Helligkeit steigt dort um weniger als 1 % der Leuchtdichte).
	uvec2 cell = uvec2(floor(FRAGCOORD.xy / grain));
	uint frame = uint(mod(floor(TIME * 12.0), 65536.0));
	float n = hash3(cell.x, cell.y, frame * 7919u + uint(seed * 1000.0)) - 0.5;
	col += vec3(n * snow_amount * (1.0 - 0.6 * lum) * burst * (1.0 - kind));
	// grüne Störstreifen: zwei bis drei breite, weiche Bänder, die langsam nach unten wandern;
	// sie färben vorhandenes Licht grün um, statt die Fläche aufzuhellen
	float y = SCREEN_UV.y * 5.0 - t * 0.3 + seed;
	float b = smoothstep(0.56, 0.9, vnoise(y * 2.0, 23u)) * burst * kind;
	vec3 green = vec3(lum * 0.6, lum * 1.18 + stripe_amount, lum * 0.66);
	col = mix(col, green, b * 0.62);
	COLOR = vec4(col, 1.0);
}
