shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;
#include "res://scripts/map/storm_grade.gdshaderinc"

// El canto de la isla (docs/21 §12): la isla es una maqueta, una placa de
// cesped sobre tierra. Por altura: un labio verde arriba, tierra con vetas
// horizontales y el pie mas oscuro. Tonos de ToyPalette: la tierra es WOOD
// oscurecida, el labio el GREEN del cesped en sombra.
uniform vec4 lip_color : source_color = vec4(0.33, 0.55, 0.19, 1.0);
uniform vec4 earth_color : source_color = vec4(0.56, 0.35, 0.20, 1.0);
uniform vec4 earth_dark : source_color = vec4(0.34, 0.21, 0.13, 1.0);
uniform float top_y = 0.0;
uniform float lip_depth = 0.07;

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
	float depth = top_y - world_pos.y;
	float along = world_pos.x + world_pos.z;
	float wob = noise(vec2(along * 0.8, 0.0)) * 0.05;
	vec3 col = mix(earth_color.rgb, earth_dark.rgb, smoothstep(0.1, 0.6, depth));
	float band = sin((depth + wob) * 48.0) * 0.5 + 0.5;
	col *= 0.86 + 0.14 * band;
	col = mix(col, lip_color.rgb, 1.0 - smoothstep(lip_depth - 0.015, lip_depth + 0.015, depth + wob * 0.4));
	ALBEDO = storm_grade(col, 0.85);
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
}
