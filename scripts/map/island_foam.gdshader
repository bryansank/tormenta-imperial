shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
#include "res://scripts/map/storm_grade.gdshaderinc"

// La espuma de la orilla (docs/21 §12): una cinta que sigue la costa exacta.
// UV.y va de la arena (0) al mar (1); UV.x es la distancia recorrida a lo largo
// de la costa. Una franja fija pegada a la arena y lineas que salen hacia el
// mar, rotas por ruido para que no parezcan anillos.
//
// Es `unshaded` (blanca de verdad, se lee desde lejos), asi que la luz de la
// Tormenta no la toca: aqui se enfria, se apaga y pierde opacidad con
// `storm_weight`, o seria lo unico limpio de una isla a oscuras.
uniform vec4 foam_color : source_color = vec4(0.97, 0.99, 1.0, 1.0);
uniform float speed = 0.22;
uniform float opacity : hint_range(0.0, 1.0) = 0.9;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float y = UV.y;
	float x = UV.x;
	float breakup = noise(vec2(x * 1.3, TIME * 0.2));
	// Franja pegada a la arena, con el borde mordido.
	float edge = 1.0 - smoothstep(0.16 + 0.1 * breakup, 0.27 + 0.1 * breakup, y);
	// Lineas que avanzan hacia el mar y se apagan (no en la version sencilla).
	float a = edge;
	if (!simple) {
		float phase = fract(y * 2.2 - TIME * speed + breakup * 0.25);
		float line = smoothstep(0.0, 0.06, phase) * (1.0 - smoothstep(0.06, 0.16, phase));
		line *= step(0.35, noise(vec2(x * 0.9, y * 3.0 - TIME * 0.3)));
		a = max(edge, line * (1.0 - y) * 0.8);
	}
	ALBEDO = storm_grade(foam_color.rgb, 1.0) * (1.0 - 0.35 * storm_weight);
	ALPHA = a * opacity * (1.0 - 0.3 * storm_weight) * (1.0 - smoothstep(0.75, 1.0, y));
}
