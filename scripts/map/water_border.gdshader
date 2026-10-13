shader_type spatial;
render_mode specular_schlick_ggx;

// El mar alrededor de la isla (docs/21 §12): azul de juguete, mas claro y
// turquesa junto a la costa, con ondas que se mueven solo en el fragmento (el
// plano no tiene vertices que desplazar) y reflejos del cielo.
//
// La distancia a la costa es la de un rectangulo redondeado (island_half,
// island_radius) que IslandGenerator ajusta a la isla de la partida; la
// ondulacion real de la costa la pone la espuma, que si sigue el borde exacto.
uniform vec4 water_color_deep : source_color = vec4(0.06, 0.30, 0.55, 1.0);
uniform vec4 water_color_shallow : source_color = vec4(0.16, 0.64, 0.72, 1.0);
uniform vec2 island_half = vec2(46.0, 46.0);
uniform float island_radius = 10.0;
uniform float shallow_width : hint_range(1.0, 30.0) = 10.0;
uniform float wave_speed : hint_range(0.0, 3.0) = 0.6;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.12;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

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

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float waves(vec2 p, float t) {
	return noise(p * 0.35 + vec2(t * 0.11, t * 0.07)) * 0.6
		+ noise(p * 0.8 - vec2(t * 0.09, -t * 0.13)) * 0.4;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME * wave_speed;
	float d = sd_round_box(p, island_half, island_radius);
	float shallow = 1.0 - smoothstep(0.0, shallow_width, d);
	vec3 col = mix(water_color_deep.rgb, water_color_shallow.rgb, shallow * shallow);

	// Ondas: pendiente del ruido como mapa de normales.
	float h = waves(p, t);
	float hx = waves(p + vec2(0.25, 0.0), t);
	float hz = waves(p + vec2(0.0, 0.25), t);
	NORMAL_MAP = normalize(vec3((h - hx) * 2.2 + 0.5, (h - hz) * 2.2 + 0.5, 1.0));
	NORMAL_MAP_DEPTH = 1.0;

	// Lineas claras de juguete sobre las crestas, mas cerca de la costa.
	float crest = smoothstep(0.62, 0.7, h) * (1.0 - smoothstep(0.7, 0.8, h));
	col = mix(col, vec3(0.85, 0.95, 1.0), crest * (0.12 + 0.25 * shallow));

	ALBEDO = col;
	ROUGHNESS = roughness_val;
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
