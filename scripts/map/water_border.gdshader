shader_type spatial;
render_mode specular_schlick_ggx;
#include "res://scripts/map/storm_grade.gdshaderinc"

// El mar alrededor de la isla (docs/21 §12): azul de juguete (el SKY de
// ToyPalette, mas hondo lejos y mas turquesa junto a la costa), con ondas que
// se mueven solo en el fragmento (el plano no tiene vertices que desplazar) y
// reflejos suaves del cielo.
//
// La distancia a la costa es la de un rectangulo redondeado (island_half,
// island_radius) que IslandGenerator ajusta a la isla de la partida; la
// ondulacion real de la costa la pone la espuma, que si sigue el borde exacto.
//
// Las ondas son solo senos (cuatro trenes, uno con la fase doblada por otro
// seno lento): el ruido de valor derivado por diferencias dejaba en el agua un
// mosaico de cuadros y rombos. Sin ruido ni hash: mas barato, ademas.
uniform vec4 water_color_deep : source_color = vec4(0.10, 0.34, 0.58, 1.0);
uniform vec4 water_color_shallow : source_color = vec4(0.28, 0.68, 0.76, 1.0);
uniform vec2 island_half = vec2(46.0, 46.0);
uniform float island_radius = 10.0;
// Isla irregular (2026-10-12): la distancia a la linea del agua sale de una
// textura pequena (un texel por celda, filtrado lineal) que IslandGenerator
// hace una vez por partida. coast_rect: origen (xy) y tamano (zw) en mundo.
uniform bool use_coast_map = false;
uniform sampler2D coast_map : filter_linear, repeat_disable;
uniform vec4 coast_rect = vec4(-80.0, -80.0, 160.0, 160.0);
uniform float coast_map_range = 24.0;
uniform float shallow_width : hint_range(1.0, 30.0) = 9.0;
uniform float wave_speed : hint_range(0.0, 3.0) = 0.6;
uniform float wave_strength : hint_range(0.0, 3.0) = 0.9;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.22;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Altura de la ola en [0, 1]: trenes de senos en direcciones distintas; el
// ultimo dobla su fase con otro seno lento para que no se lea una cuadricula.
float waves(vec2 p, float t) {
	float h = sin(dot(p, vec2(0.46, 0.19)) + t * 1.1) * 0.38;
	h += sin(dot(p, vec2(-0.21, 0.53)) + t * 0.8) * 0.28;
	h += sin(dot(p, vec2(0.71, -0.43)) - t * 1.5) * 0.14;
	h += sin(dot(p, vec2(0.13, 0.37)) + 2.0 * sin(p.x * 0.09 - p.y * 0.05 + t * 0.2)) * 0.2;
	return h * 0.5 + 0.5;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME * wave_speed;
	float d = sd_round_box(p, island_half, island_radius);
	if (use_coast_map) {
		vec2 cuv = (p - coast_rect.xy) / coast_rect.zw;
		bool inside = cuv.x >= 0.0 && cuv.y >= 0.0 && cuv.x <= 1.0 && cuv.y <= 1.0;
		d = inside ? texture(coast_map, cuv).r * coast_map_range : coast_map_range;
	}
	float shallow = 1.0 - smoothstep(0.0, shallow_width, d);
	vec3 col = mix(water_color_deep.rgb, water_color_shallow.rgb, shallow * shallow);

	// Ondas: pendiente de la altura como mapa de normales, y lineas claras de
	// juguete sobre las crestas. La version sencilla deja el agua lisa: solo
	// el degradado de hondo a turquesa (sigue leyendose como agua).
	if (!simple) {
		float h = waves(p, t);
		float hx = waves(p + vec2(0.3, 0.0), t);
		float hz = waves(p + vec2(0.0, 0.3), t);
		NORMAL_MAP = normalize(vec3((h - hx) * wave_strength + 0.5, (h - hz) * wave_strength + 0.5, 1.0));
		NORMAL_MAP_DEPTH = 1.0;
		float crest = smoothstep(0.80, 0.86, h) * (1.0 - smoothstep(0.86, 0.94, h));
		col = mix(col, vec3(0.86, 0.95, 1.0), crest * (0.10 + 0.30 * shallow));
	}

	// Con la Tormenta: agua de pizarra, y menos brillo (el cielo ya no es azul).
	// De noche, ademas, mas apagada: agua azul bajo luna azul salia chillona.
	col = mix(col, vec3(dot(col, vec3(0.299, 0.587, 0.114))), 0.35 * night_weight) * (1.0 - 0.2 * night_weight);
	ALBEDO = storm_grade(col, 0.9);
	ROUGHNESS = mix(roughness_val, 0.45, storm_weight);
	SPECULAR = 0.5;
	METALLIC = 0.0;
}
