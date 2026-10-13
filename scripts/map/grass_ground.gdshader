shader_type spatial;
render_mode specular_schlick_ggx;
#include "res://scripts/map/storm_grade.gdshaderinc"

// El cesped de la isla (docs/21 §12): diorama de juguete, verdes calidos y
// saturados con tres tonos, calvas de tierra, manchas secas y flores sueltas.
// Todo en coordenadas de mundo: no hay costura ni textura que descargar.
uniform vec4 grass_color_1 : source_color = vec4(0.42, 0.66, 0.22, 1.0);
uniform vec4 grass_color_2 : source_color = vec4(0.33, 0.57, 0.18, 1.0);
uniform vec4 grass_color_3 : source_color = vec4(0.25, 0.46, 0.15, 1.0);
uniform vec4 dry_color : source_color = vec4(0.66, 0.68, 0.30, 1.0);
uniform vec4 dirt_color : source_color = vec4(0.58, 0.44, 0.28, 1.0);
uniform float noise_scale : hint_range(1.0, 50.0) = 14.0;
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.5;
uniform float flower_density : hint_range(0.0, 0.3) = 0.06;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.9;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	// Fundido de quinto grado: con el cubico las celdas del ruido se leian
	// como facetas rectas en las manchas grandes.
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Cada octava girada ~37 grados: el ruido de valor alineado con los ejes
// dejaba manchas cuadradas que se leian como una rejilla.
const mat2 OCTAVE_ROT = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));

// Tres octavas escritas a mano (sin bucle: igual en cualquier GPU vieja).
float fbm(vec2 p) {
	float val = 0.5 * noise(p);
	p = OCTAVE_ROT * p * 2.13;
	val += 0.25 * noise(p);
	p = OCTAVE_ROT * p * 2.13;
	val += 0.125 * noise(p);
	return val / 0.875;
}

void fragment() {
	// Girada tambien la base: ninguna mancha sigue las calles de la rejilla.
	vec2 uv = OCTAVE_ROT * world_pos.xz;

	// Grandes manchas de dos verdes y una sombra mas oscura. En la version
	// completa el dominio se dobla con dos ruidos lentos: sin eso el ruido de
	// valor deja manchas de lados rectos, como facetas.
	vec2 puv = uv;
	if (!simple) {
		puv += (vec2(noise(uv * 0.08), noise(uv * 0.08 + vec2(17.0, 5.0))) - 0.5) * 9.0;
	}
	float n1 = fbm(puv / noise_scale);
	vec3 col = mix(grass_color_1.rgb, grass_color_2.rgb, smoothstep(0.38, 0.62, n1));
	// La sombra y las zonas secas (amarillentas), solo en la version completa.
	if (!simple) {
		float dark = fbm(puv / (noise_scale * 0.6) + vec2(37.0, 11.0));
		col = mix(col, grass_color_3.rgb, smoothstep(0.55, 0.75, dark) * 0.7);
		float dry = fbm(puv / (noise_scale * 1.7) + vec2(-21.0, 64.0));
		col = mix(col, dry_color.rgb, smoothstep(0.6, 0.78, dry) * 0.45);
	}

	// Calvas de tierra: pocas, de borde suave.
	float dirt = fbm(uv / 5.0 + vec2(91.0, -13.0));
	float dirt_m = smoothstep(0.74, 0.8, dirt) * dirt_amount;
	col = mix(col, dirt_color.rgb, dirt_m);

	// Matas: un grano fino de luz y sombra, como cesped de maqueta.
	if (!simple) {
		float tuft = noise(uv * 3.1) * 0.6 + noise(uv * 7.3) * 0.4;
		col *= 0.9 + 0.18 * tuft;
	}

	// Flores sueltas: una por celda de 0.7 unidades, en pocas celdas.
	vec2 cell = floor(uv / 0.7);
	float pick = hash(cell + vec2(3.0, 7.0));
	if (pick < flower_density * (1.0 - dirt_m)) {
		vec2 centre = (cell + 0.25 + 0.5 * vec2(hash(cell + 1.3), hash(cell + 5.1))) * 0.7;
		float d = length(uv - centre);
		float aa = fwidth(d) + 0.001;
		float petal = 1.0 - smoothstep(0.07 - aa, 0.07 + aa, d);
		float kind = hash(cell + vec2(11.0, 2.0));
		vec3 flower = kind < 0.4 ? vec3(0.98, 0.96, 0.9) : (kind < 0.75 ? vec3(1.0, 0.82, 0.25) : vec3(0.95, 0.5, 0.62));
		col = mix(col, flower, petal);
	}

	ALBEDO = storm_grade(col, 0.85);
	ROUGHNESS = roughness_val;
	SPECULAR = 0.2;
	METALLIC = 0.0;
}
