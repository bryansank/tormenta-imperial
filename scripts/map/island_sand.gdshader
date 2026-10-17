shader_type spatial;
render_mode specular_schlick_ggx;
#include "res://scripts/map/storm_grade.gdshaderinc"

// La playa (docs/21 §12): arena calida con grano, mas oscura y mojada donde
// la toca el agua (por altura: la playa baja hacia el mar) y algun guijarro.
// Tonos entre CREAM y BRASS de ToyPalette. Al pie del canto (UV.y = 0, el borde
// del cesped) una franja oscura hace de sombra de contacto: ancla la placa de
// cesped sobre la arena sin pedirle nada al SSAO, que en Mobile no existe.
uniform vec4 sand_color : source_color = vec4(0.94, 0.83, 0.61, 1.0);
uniform vec4 sand_dark : source_color = vec4(0.86, 0.72, 0.50, 1.0);
uniform vec4 wet_color : source_color = vec4(0.62, 0.53, 0.40, 1.0);
uniform float contact_width : hint_range(0.0, 0.5) = 0.14;
uniform float contact_dark : hint_range(0.0, 1.0) = 0.38;
uniform float water_y = -0.5;

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

void fragment() {
	vec2 uv = world_pos.xz;
	float n = noise(uv * 0.4) * 0.6 + noise(uv * 1.7) * 0.4;
	vec3 col = mix(sand_color.rgb, sand_dark.rgb, smoothstep(0.35, 0.75, n));
	if (!simple) {
		col *= 0.94 + 0.1 * noise(uv * 9.0);
	}
	// Mojada en la franja que lame el agua.
	float wet = 1.0 - smoothstep(water_y, water_y + 0.16, world_pos.y);
	col = mix(col, wet_color.rgb, wet * 0.85);
	// Guijarros.
	vec2 cell = floor(uv / 0.9);
	if (!simple && hash(cell) < 0.05) {
		vec2 c = (cell + 0.3 + 0.4 * vec2(hash(cell + 2.0), hash(cell + 4.0))) * 0.9;
		float d = length(uv - c);
		col = mix(col, vec3(0.55, 0.52, 0.48), 1.0 - smoothstep(0.06, 0.09, d));
	}
	// Sombra de contacto al pie del canto.
	col *= 1.0 - contact_dark * (1.0 - smoothstep(0.0, contact_width, UV.y));
	ALBEDO = storm_grade(col, 0.85);
	ROUGHNESS = mix(0.95, 0.35, wet);
	SPECULAR = 0.25;
}
