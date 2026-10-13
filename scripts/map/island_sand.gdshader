shader_type spatial;
render_mode specular_schlick_ggx;

// La playa (docs/21 §12): arena calida con grano, mas oscura y mojada donde
// la toca el agua (por altura: la playa baja hacia el mar) y algun guijarro.
uniform vec4 sand_color : source_color = vec4(0.93, 0.81, 0.57, 1.0);
uniform vec4 sand_dark : source_color = vec4(0.84, 0.70, 0.47, 1.0);
uniform vec4 wet_color : source_color = vec4(0.66, 0.56, 0.40, 1.0);
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
	col *= 0.94 + 0.1 * noise(uv * 9.0);
	// Mojada en la franja que lame el agua.
	float wet = 1.0 - smoothstep(water_y, water_y + 0.16, world_pos.y);
	col = mix(col, wet_color.rgb, wet * 0.85);
	// Guijarros.
	vec2 cell = floor(uv / 0.9);
	if (hash(cell) < 0.05) {
		vec2 c = (cell + 0.3 + 0.4 * vec2(hash(cell + 2.0), hash(cell + 4.0))) * 0.9;
		float d = length(uv - c);
		col = mix(col, vec3(0.55, 0.52, 0.48), 1.0 - smoothstep(0.06, 0.09, d));
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.35, wet);
	SPECULAR = 0.25;
}
