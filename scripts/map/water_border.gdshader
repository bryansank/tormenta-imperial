shader_type spatial;

// Stylized water — animated waves, Empires & Allies style
uniform vec4 water_color_deep : source_color = vec4(0.12, 0.30, 0.55, 1.0);
uniform vec4 water_color_shallow : source_color = vec4(0.20, 0.50, 0.70, 1.0);
uniform vec4 foam_color : source_color = vec4(0.85, 0.92, 0.95, 1.0);
uniform float wave_speed : hint_range(0.1, 3.0) = 0.8;
uniform float wave_scale : hint_range(1.0, 20.0) = 6.0;
uniform float foam_width : hint_range(0.5, 8.0) = 3.0;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.15;
uniform vec2 map_center = vec2(0.0, 0.0);
uniform float map_radius = 25.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Gentle wave displacement
	float wave = sin(world_pos.x * 0.8 + TIME * wave_speed) * cos(world_pos.z * 0.6 + TIME * wave_speed * 0.7);
	VERTEX.y += wave * 0.08;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1, 0)), f.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x),
		f.y
	);
}

void fragment() {
	vec2 uv = world_pos.xz;

	// Distance from map edge for foam
	float dist_from_center = length(uv - map_center);
	float edge_factor = smoothstep(map_radius - foam_width, map_radius, dist_from_center);

	// Animated wave pattern
	float wave1 = noise(uv / wave_scale + vec2(TIME * wave_speed * 0.3, TIME * wave_speed * 0.2));
	float wave2 = noise(uv / (wave_scale * 0.7) + vec2(-TIME * wave_speed * 0.2, TIME * wave_speed * 0.35));
	float waves = (wave1 + wave2) * 0.5;

	// Base water color (deeper further from shore)
	vec3 col = mix(water_color_shallow.rgb, water_color_deep.rgb, 1.0 - edge_factor);

	// Wave highlights
	col += vec3(0.05) * smoothstep(0.55, 0.7, waves);

	// Foam near shore
	float foam = smoothstep(0.0, 1.0, edge_factor);
	float foam_pattern = smoothstep(0.4, 0.6, noise(uv * 3.0 + vec2(TIME * 0.5, 0.0)));
	col = mix(col, foam_color.rgb, foam * foam_pattern * 0.6);

	ALBEDO = col;
	ROUGHNESS = roughness_val;
	METALLIC = 0.3;
	SPECULAR = 0.8;
}
